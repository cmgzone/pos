import 'dart:convert';
import 'dart:developer' as developer;

import '../services/openrouter_service.dart';
import 'spreadsheet_import_reader.dart';

class CloudSpreadsheetImportPlanner {
  static const _maxPreviewRows = 30;
  static const _maxPreviewColumns = 18;
  static const _maxCellLength = 120;

  static Future<SpreadsheetImportPlan> buildPlan({
    required List<List<String>> rows,
    required String? fileName,
    required String importType,
    required String importLabel,
    required Map<String, List<String>> columnAliases,
    required SpreadsheetImportPlan Function() localPlanBuilder,
  }) async {
    SpreadsheetImportPlan? localPlan;
    Object? localError;

    try {
      localPlan = localPlanBuilder();
    } catch (error) {
      localError = error;
    }

    final cloudEnabled = await _cloudAiEnabled();
    if (!cloudEnabled) {
      return _fallbackPlan(
        localPlan: localPlan,
        localError: localError,
        warning:
            'Cloud AI is not connected or enabled, so Piki used the local import check.',
      );
    }

    try {
      final response = await OpenRouterService.chat(
        includeBusinessContext: false,
        consumeQuota: true,
        messages: [
          {
            'role': 'user',
            'content': _buildPrompt(
              rows: rows,
              fileName: fileName,
              importType: importType,
              importLabel: importLabel,
              columnAliases: columnAliases,
              localPlan: localPlan,
              localError: localError,
            ),
          },
        ],
      );
      return _planFromResponse(
        response,
        rows: rows,
        fileName: fileName,
        importType: importType,
        importLabel: importLabel,
        columnAliases: columnAliases,
        localPlan: localPlan,
      );
    } catch (_) {
      return _fallbackPlan(
        localPlan: localPlan,
        localError: localError,
        warning:
            'Cloud AI review was unavailable, so Piki used the local import check.',
      );
    }
  }

  static Future<bool> _cloudAiEnabled() async {
    if (OpenRouterService.isEnabled) {
      return true;
    }
    try {
      return await OpenRouterService.refreshConfig();
    } catch (_) {
      return false;
    }
  }

  static SpreadsheetImportPlan _fallbackPlan({
    required SpreadsheetImportPlan? localPlan,
    required Object? localError,
    required String warning,
  }) {
    if (localPlan != null) {
      return localPlan.copyWith(
        warnings: _dedupe([...localPlan.warnings, warning]),
      );
    }
    if (localError is Exception) {
      throw localError;
    }
    throw Exception(
      localError?.toString().replaceFirst('Exception: ', '') ??
          'Piki could not read the import file.',
    );
  }

  static String _buildPrompt({
    required List<List<String>> rows,
    required String? fileName,
    required String importType,
    required String importLabel,
    required Map<String, List<String>> columnAliases,
    required SpreadsheetImportPlan? localPlan,
    required Object? localError,
  }) {
    final allowedFields = columnAliases.keys
        .map(SpreadsheetImportReader.normalizeHeader)
        .where((field) => field.isNotEmpty)
        .toList();
    final payload = {
      'fileName': fileName,
      'importType': importType,
      'importLabel': importLabel,
      'allowedFields': allowedFields,
      'fieldAliases': {
        for (final entry in columnAliases.entries)
          SpreadsheetImportReader.normalizeHeader(entry.key): entry.value,
      },
      'localPlan': localPlan == null
          ? null
          : {
              'headerIndex': localPlan.headerIndex,
              'rawHeaders': localPlan.rawHeaders,
              'mappedColumns': localPlan.mappedColumns,
              'ignoredColumns': localPlan.ignoredColumns,
              'warnings': localPlan.warnings,
            },
      'localError': localError?.toString().replaceFirst('Exception: ', ''),
      'previewRows': _previewRows(rows),
    };

    return '''
You are Piki cloud AI helping a POS app import a messy spreadsheet.

Decide which preview row is the real header row and map spreadsheet columns to POS import fields.
Return JSON only. Do not use markdown.

JSON schema:
{
  "headerIndex": 0,
  "mappings": [
    {
      "index": 0,
      "rawHeader": "Item Name",
      "field": "name",
      "confidence": 0.95,
      "reason": "short reason"
    }
  ],
  "warnings": ["short warning for the cashier"]
}

Rules:
- headerIndex is zero-based and must point to a row in previewRows.
- field must be one of allowedFields exactly.
- Omit irrelevant columns instead of inventing fields.
- Prefer SKU, barcode, ID, date, amount, price, quantity, customer, phone, category, and note columns when relevant to $importLabel.
- If the sheet has titles, notes, totals, or blank rows above the table, choose the actual table header row.
- Use confidence below 0.60 only when uncertain; the app may ignore weak mappings.
- Do not change values or create import rows. Only map columns.

INPUT:
${jsonEncode(payload)}
''';
  }

  static SpreadsheetImportPlan _planFromResponse(
    String response, {
    required List<List<String>> rows,
    required String? fileName,
    required String importType,
    required String importLabel,
    required Map<String, List<String>> columnAliases,
    required SpreadsheetImportPlan? localPlan,
  }) {
    final parsed = _extractJsonMap(response);
    if (parsed == null) {
      throw const FormatException('Cloud AI did not return valid JSON');
    }

    final headerIndex =
        _readInt(parsed['headerIndex'] ?? parsed['header_index']) ??
        localPlan?.headerIndex ??
        SpreadsheetImportReader.firstHeaderIndex(rows);
    if (headerIndex < 0 || headerIndex >= rows.length) {
      throw const FormatException('Cloud AI returned an invalid header row');
    }

    final allowedFields = columnAliases.keys
        .map(SpreadsheetImportReader.normalizeHeader)
        .where((field) => field.isNotEmpty)
        .toSet();
    final mappings = <int, String>{};
    if (localPlan != null && localPlan.headerIndex == headerIndex) {
      mappings.addAll(_localColumnMappings(localPlan, allowedFields));
    }
    mappings.addAll(
      _cloudColumnMappings(
        parsed,
        rawHeaders: rows[headerIndex],
        allowedFields: allowedFields,
      ),
    );

    if (mappings.isEmpty) {
      throw const FormatException('Cloud AI did not map any import columns');
    }

    final warnings = _dedupe([
      'Review the cloud AI mapping before importing. It can make mistakes with unclear spreadsheets.',
      ..._readWarnings(parsed),
      if (importType.trim().isNotEmpty)
        'Cloud AI import type: ${importType.trim()}.',
    ]);

    return SpreadsheetImportReader.buildPlanFromColumnMappings(
      rows: rows,
      fileName: fileName,
      headerIndex: headerIndex,
      columnMappings: mappings,
      importLabel: importLabel,
      warnings: warnings,
    );
  }

  static Map<int, String> _localColumnMappings(
    SpreadsheetImportPlan plan,
    Set<String> allowedFields,
  ) {
    final mappings = <int, String>{};
    for (var index = 0; index < plan.rawHeaders.length; index += 1) {
      final rawHeader = plan.rawHeaders[index];
      final mapped = SpreadsheetImportReader.normalizeHeader(
        plan.mappedColumns[rawHeader] ?? '',
      );
      if (allowedFields.contains(mapped)) {
        mappings[index] = mapped;
      }
    }
    return mappings;
  }

  static Map<int, String> _cloudColumnMappings(
    Map<String, dynamic> parsed, {
    required List<String> rawHeaders,
    required Set<String> allowedFields,
  }) {
    final mappings = <int, String>{};
    final rawMappings =
        parsed['mappings'] ?? parsed['columns'] ?? parsed['mappedColumns'];

    if (rawMappings is List) {
      for (final item in rawMappings) {
        if (item is! Map) continue;
        final field = _readField(item, allowedFields);
        if (field == null) continue;
        final confidence = _readDouble(item['confidence'] ?? item['score']);
        if (confidence != null && confidence < 0.55) continue;

        final index =
            _readInt(
              item['index'] ?? item['columnIndex'] ?? item['column_index'],
            ) ??
            _indexForRawHeader(
              rawHeaders,
              item['rawHeader'] ?? item['header'] ?? item['name'],
            );
        if (index == null || index < 0 || index >= rawHeaders.length) {
          continue;
        }
        mappings[index] = field;
      }
      return mappings;
    }

    if (rawMappings is Map) {
      for (final entry in rawMappings.entries) {
        final field = SpreadsheetImportReader.normalizeHeader(
          entry.value?.toString() ?? '',
        );
        if (!allowedFields.contains(field)) continue;
        final index =
            int.tryParse(entry.key.toString()) ??
            _indexForRawHeader(rawHeaders, entry.key);
        if (index == null || index < 0 || index >= rawHeaders.length) {
          continue;
        }
        mappings[index] = field;
      }
    }
    return mappings;
  }

  static String? _readField(Map<dynamic, dynamic> item, Set<String> allowed) {
    final raw = item['field'] ?? item['canonical'] ?? item['target'];
    final field = SpreadsheetImportReader.normalizeHeader(
      raw?.toString() ?? '',
    );
    if (field == 'ignore' || field == 'ignored' || field == 'none') {
      return null;
    }
    return allowed.contains(field) ? field : null;
  }

  static int? _indexForRawHeader(List<String> rawHeaders, Object? raw) {
    final normalized = SpreadsheetImportReader.normalizeHeader(
      raw?.toString() ?? '',
    );
    if (normalized.isEmpty) return null;
    for (var index = 0; index < rawHeaders.length; index += 1) {
      if (SpreadsheetImportReader.normalizeHeader(rawHeaders[index]) ==
          normalized) {
        return index;
      }
    }
    return null;
  }

  static List<Map<String, Object>> _previewRows(List<List<String>> rows) {
    final limit = rows.length < _maxPreviewRows ? rows.length : _maxPreviewRows;
    final preview = <Map<String, Object>>[];
    for (var index = 0; index < limit; index += 1) {
      final row = rows[index];
      final cells = row
          .take(_maxPreviewColumns)
          .map((cell) => _limitCell(cell.trim()))
          .toList();
      preview.add({'index': index, 'cells': cells});
    }
    return preview;
  }

  static String _limitCell(String value) {
    if (value.length <= _maxCellLength) return value;
    return '${value.substring(0, _maxCellLength - 3)}...';
  }

  static Map<String, dynamic>? _extractJsonMap(String raw) {
    for (final candidate in _jsonCandidates(raw)) {
      try {
        final parsed = jsonDecode(candidate);
        if (parsed is Map) {
          return Map<String, dynamic>.from(parsed);
        }
        } catch (_) {
        try {
          final parsed = jsonDecode(_repairCommonJsonIssues(candidate));
          if (parsed is Map) {
            return Map<String, dynamic>.from(parsed);
          }
        } catch (e, st) {
          developer.log(
            'Failed to parse JSON candidate: $candidate',
            error: e,
            stackTrace: st,
            name: 'CloudSpreadsheetImportPlanner',
          );
        }
      }
    }
    return null;
  }

  static Iterable<String> _jsonCandidates(String raw) sync* {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return;

    yield trimmed;

    final unfenced = _stripMarkdownFence(trimmed);
    if (unfenced != trimmed) {
      yield unfenced;
    }

    for (final candidate in _balancedJsonObjects(trimmed)) {
      yield candidate;
    }
  }

  static String _stripMarkdownFence(String raw) {
    final match = RegExp(
      r'^```(?:json)?\s*([\s\S]*?)\s*```$',
      caseSensitive: false,
    ).firstMatch(raw.trim());
    return match?.group(1)?.trim() ?? raw;
  }

  static Iterable<String> _balancedJsonObjects(String raw) sync* {
    var depth = 0;
    var start = -1;
    var inString = false;
    var escaped = false;

    for (var i = 0; i < raw.length; i += 1) {
      final char = raw[i];
      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (char == '\\') {
          escaped = true;
        } else if (char == '"') {
          inString = false;
        }
        continue;
      }

      if (char == '"') {
        inString = true;
      } else if (char == '{') {
        if (depth == 0) {
          start = i;
        }
        depth += 1;
      } else if (char == '}' && depth > 0) {
        depth -= 1;
        if (depth == 0 && start >= 0) {
          yield raw.substring(start, i + 1);
          start = -1;
        }
      }
    }
  }

  static String _repairCommonJsonIssues(String raw) {
    final normalized = _stripMarkdownFence(raw)
        .replaceAll('\uFEFF', '')
        .replaceAll('\u201c', '"')
        .replaceAll('\u201d', '"')
        .trim();
    return normalized
        .replaceAllMapped(RegExp(r',\s*([}\]])'), (match) => match.group(1)!)
        .replaceAllMapped(
          RegExp(r'([{\[,]\s*)([A-Za-z_][A-Za-z0-9_-]*)\s*:'),
          (match) => '${match.group(1)}"${match.group(2)}":',
        );
  }

  static int? _readInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString().trim() ?? '');
  }

  static double? _readDouble(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString().trim() ?? '');
  }

  static List<String> _readWarnings(Map<String, dynamic> parsed) {
    final raw = parsed['warnings'];
    if (raw is! List) return const [];
    return raw
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .take(5)
        .toList();
  }

  static List<String> _dedupe(List<String> values) {
    final seen = <String>{};
    final result = <String>[];
    for (final value in values) {
      final trimmed = value.trim();
      if (trimmed.isEmpty || !seen.add(trimmed)) {
        continue;
      }
      result.add(trimmed);
    }
    return result;
  }
}
