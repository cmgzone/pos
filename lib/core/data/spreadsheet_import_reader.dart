import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:excel/excel.dart' as xl;
import 'package:file_picker/file_picker.dart';
import 'package:xml/xml.dart' as xml;

class SpreadsheetFileRows {
  final List<List<String>> rows;
  final String fileName;
  final Uint8List? bytes;
  final String extension;
  final String? mimeType;
  final String? extractedText;

  const SpreadsheetFileRows({
    required this.rows,
    required this.fileName,
    this.bytes,
    this.extension = '',
    this.mimeType,
    this.extractedText,
  });
}

class SpreadsheetImportPlan {
  final List<List<String>> rows;
  final String? fileName;
  final int headerIndex;
  final List<String> rawHeaders;
  final List<String> headers;
  final Map<String, String> mappedColumns;
  final List<String> ignoredColumns;
  final List<String> warnings;
  final int dataRowCount;
  final List<Map<String, String>> sampleRows;

  const SpreadsheetImportPlan({
    required this.rows,
    required this.fileName,
    required this.headerIndex,
    required this.rawHeaders,
    required this.headers,
    required this.mappedColumns,
    required this.ignoredColumns,
    required this.warnings,
    required this.dataRowCount,
    required this.sampleRows,
  });

  int get headerRowNumber => headerIndex + 1;

  SpreadsheetImportPlan copyWith({
    List<List<String>>? rows,
    String? fileName,
    int? headerIndex,
    List<String>? rawHeaders,
    List<String>? headers,
    Map<String, String>? mappedColumns,
    List<String>? ignoredColumns,
    List<String>? warnings,
    int? dataRowCount,
    List<Map<String, String>>? sampleRows,
  }) {
    return SpreadsheetImportPlan(
      rows: rows ?? this.rows,
      fileName: fileName ?? this.fileName,
      headerIndex: headerIndex ?? this.headerIndex,
      rawHeaders: rawHeaders ?? this.rawHeaders,
      headers: headers ?? this.headers,
      mappedColumns: mappedColumns ?? this.mappedColumns,
      ignoredColumns: ignoredColumns ?? this.ignoredColumns,
      warnings: warnings ?? this.warnings,
      dataRowCount: dataRowCount ?? this.dataRowCount,
      sampleRows: sampleRows ?? this.sampleRows,
    );
  }
}

class _HeaderCandidate {
  final int index;
  final List<String> rawHeaders;
  final List<String> headers;
  final Map<String, String> mappedColumns;
  final List<String> ignoredColumns;
  final List<String> warnings;
  final int score;
  final int dataRowCount;

  const _HeaderCandidate({
    required this.index,
    required this.rawHeaders,
    required this.headers,
    required this.mappedColumns,
    required this.ignoredColumns,
    required this.warnings,
    required this.score,
    required this.dataRowCount,
  });
}

class _XlsxSheetRows {
  final String name;
  final List<List<String>> rows;

  const _XlsxSheetRows({required this.name, required this.rows});
}

class _XlsxSheetEntry {
  final String name;
  final String path;

  const _XlsxSheetEntry({required this.name, required this.path});
}

class SpreadsheetImportReader {
  static const supportedExtensions = ['xlsx', 'csv'];
  static const productImportExtensions = [
    'xlsx',
    'csv',
    'tsv',
    'pdf',
    'txt',
    'json',
    'docx',
    'png',
    'jpg',
    'jpeg',
    'webp',
  ];
  static const documentImportExtensions = productImportExtensions;

  static bool isSpreadsheetExtension(String extension) {
    return const {'xlsx', 'csv', 'tsv'}.contains(extension.toLowerCase());
  }

  static Future<SpreadsheetFileRows?> pickRows({
    required String dialogTitle,
    List<String> allowedExtensions = supportedExtensions,
  }) async {
    final picked = await FilePicker.platform.pickFiles(
      dialogTitle: dialogTitle,
      type: FileType.custom,
      allowedExtensions: allowedExtensions,
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) {
      return null;
    }

    final file = picked.files.single;
    final extension = extensionFor(file.name, file.path);
    final bytes = file.bytes ?? await _readFileBytes(file.path);
    if (bytes == null || bytes.isEmpty) {
      throw Exception('Could not read the selected file.');
    }

    final rows = switch (extension) {
      'csv' => readCsvRows(bytes),
      'tsv' => readTsvRows(bytes),
      'xlsx' => readExcelRows(bytes),
      _ => <List<String>>[],
    };
    final extractedText = switch (extension) {
      'xlsx' => readExcelWorkbookText(bytes),
      'csv' ||
      'tsv' ||
      'txt' ||
      'json' => utf8.decode(bytes, allowMalformed: true),
      _ => null,
    };
    return SpreadsheetFileRows(
      rows: rows,
      fileName: file.name,
      bytes: bytes,
      extension: extension,
      mimeType: _mimeTypeForExtension(extension),
      extractedText: extractedText,
    );
  }

  static int firstHeaderIndex(List<List<String>> rows) {
    return rows.indexWhere((row) => row.any((cell) => cell.trim().isNotEmpty));
  }

  static SpreadsheetImportPlan buildPlan({
    required List<List<String>> rows,
    required Map<String, List<String>> columnAliases,
    String? fileName,
    List<String> requiredAny = const [],
    List<String> requiredAll = const [],
    String importLabel = 'import',
  }) {
    if (rows.isEmpty) {
      throw Exception('The import file is empty.');
    }

    final maxScan = rows.length < 30 ? rows.length : 30;
    _HeaderCandidate? best;
    for (var index = 0; index < maxScan; index += 1) {
      final rawRow = rows[index];
      if (rawRow.every((cell) => cell.trim().isEmpty)) {
        continue;
      }
      final candidate = _scoreHeaderCandidate(
        rows: rows,
        index: index,
        columnAliases: columnAliases,
        requiredAny: requiredAny,
        requiredAll: requiredAll,
      );
      if (best == null || candidate.score > best.score) {
        best = candidate;
      }
    }

    final candidate = best;
    if (candidate == null || candidate.score <= 0) {
      throw Exception('The import file does not contain a usable header row.');
    }

    final sampleRows = <Map<String, String>>[];
    for (var index = candidate.index + 1; index < rows.length; index += 1) {
      final row = rows[index];
      if (row.every((cell) => cell.trim().isEmpty)) {
        continue;
      }
      sampleRows.add(rowMap(candidate.headers, row));
      if (sampleRows.length >= 3) {
        break;
      }
    }

    final warnings = <String>[
      ...candidate.warnings,
      if (candidate.index > 0)
        'Piki AI used row ${candidate.index + 1} as the header and skipped ${candidate.index} note row${candidate.index == 1 ? '' : 's'} above it.',
      if (candidate.ignoredColumns.isNotEmpty)
        'Ignored ${candidate.ignoredColumns.length} column${candidate.ignoredColumns.length == 1 ? '' : 's'} that did not look relevant for $importLabel.',
    ];

    return SpreadsheetImportPlan(
      rows: rows,
      fileName: fileName,
      headerIndex: candidate.index,
      rawHeaders: candidate.rawHeaders,
      headers: candidate.headers,
      mappedColumns: candidate.mappedColumns,
      ignoredColumns: candidate.ignoredColumns,
      warnings: warnings,
      dataRowCount: candidate.dataRowCount,
      sampleRows: sampleRows,
    );
  }

  static SpreadsheetImportPlan buildPlanFromColumnMappings({
    required List<List<String>> rows,
    required Map<int, String> columnMappings,
    String? fileName,
    required int headerIndex,
    required String importLabel,
    List<String> warnings = const [],
  }) {
    if (rows.isEmpty) {
      throw Exception('The import file is empty.');
    }
    if (headerIndex < 0 || headerIndex >= rows.length) {
      throw Exception('Piki cloud AI returned an invalid header row.');
    }

    final rawHeaders = rows[headerIndex].map((cell) => cell.trim()).toList();
    final headers = <String>[];
    final mappedColumns = <String, String>{};
    final ignoredColumns = <String>[];
    final mappingWarnings = <String>[];

    for (var index = 0; index < rawHeaders.length; index += 1) {
      final rawHeader = rawHeaders[index];
      final normalized = normalizeHeader(rawHeader);
      if (normalized.isEmpty) {
        headers.add('');
        continue;
      }

      final mapped = normalizeHeader(columnMappings[index] ?? '');
      if (mapped.isEmpty) {
        headers.add(normalized);
        ignoredColumns.add(rawHeader);
        continue;
      }

      headers.add(mapped);
      mappedColumns[rawHeader.isEmpty ? 'Column ${index + 1}' : rawHeader] =
          mapped;
      if (mapped != normalized) {
        mappingWarnings.add('Cloud AI mapped "$rawHeader" to "$mapped".');
      }
    }

    final sampleRows = <Map<String, String>>[];
    for (var index = headerIndex + 1; index < rows.length; index += 1) {
      final row = rows[index];
      if (row.every((cell) => cell.trim().isEmpty)) {
        continue;
      }
      sampleRows.add(rowMap(headers, row));
      if (sampleRows.length >= 3) {
        break;
      }
    }

    final dataRowCount = _countDataRowsAfter(rows, headerIndex);
    return SpreadsheetImportPlan(
      rows: rows,
      fileName: fileName,
      headerIndex: headerIndex,
      rawHeaders: rawHeaders,
      headers: headers,
      mappedColumns: mappedColumns,
      ignoredColumns: ignoredColumns,
      warnings: _dedupe([
        'Piki cloud AI reviewed this spreadsheet before import.',
        ...mappingWarnings,
        ...warnings,
        if (headerIndex > 0)
          'Piki cloud AI used row ${headerIndex + 1} as the header and skipped $headerIndex note row${headerIndex == 1 ? '' : 's'} above it.',
        if (ignoredColumns.isNotEmpty)
          'Ignored ${ignoredColumns.length} column${ignoredColumns.length == 1 ? '' : 's'} that did not look relevant for $importLabel.',
      ]),
      dataRowCount: dataRowCount,
      sampleRows: sampleRows,
    );
  }

  static List<List<String>> readExcelRows(Uint8List bytes) {
    try {
      final book = xl.Excel.decodeBytes(bytes);
      if (book.tables.isEmpty) {
        return const [];
      }
      final sheet = book.tables.values.firstWhere(
        (table) =>
            table.rows.any((row) => row.any((cell) => cell?.value != null)),
        orElse: () => book.tables.values.first,
      );
      return sheet.rows
          .map((row) => row.map((cell) => _excelCellText(cell?.value)).toList())
          .toList();
    } catch (_) {
      final sheets = _readXlsxSheetsFromArchive(bytes);
      if (sheets.isEmpty) {
        return const [];
      }
      return sheets
          .firstWhere(
            (sheet) =>
                sheet.rows.any((row) => row.any((cell) => cell.isNotEmpty)),
            orElse: () => sheets.first,
          )
          .rows;
    }
  }

  static String readExcelWorkbookText(Uint8List bytes) {
    try {
      final book = xl.Excel.decodeBytes(bytes);
      if (book.tables.isEmpty) {
        return '';
      }
      return _workbookPreviewText(
        book.tables.entries.map(
          (entry) => _XlsxSheetRows(
            name: entry.key,
            rows: entry.value.rows
                .map(
                  (row) =>
                      row.map((cell) => _excelCellText(cell?.value)).toList(),
                )
                .toList(),
          ),
        ),
      );
    } catch (_) {
      return _workbookPreviewText(_readXlsxSheetsFromArchive(bytes));
    }
  }

  static String _workbookPreviewText(Iterable<_XlsxSheetRows> sheets) {
    final buffer = StringBuffer();
    for (final sheet in sheets) {
      final rows = sheet.rows
          .where((row) => row.any((cell) => cell.trim().isNotEmpty))
          .toList();
      if (rows.isEmpty) continue;

      if (buffer.isNotEmpty) {
        buffer.writeln();
      }
      buffer.writeln('Sheet: ${sheet.name}');
      final rowLimit = rows.length < 160 ? rows.length : 160;
      for (var index = 0; index < rowLimit; index += 1) {
        final cells = rows[index]
            .take(24)
            .map((cell) => _limitPreviewCell(cell.trim()))
            .join(' | ');
        buffer.writeln('Row ${index + 1}: $cells');
      }
      if (rows.length > rowLimit) {
        buffer.writeln('... ${rows.length - rowLimit} more row(s)');
      }
    }
    return buffer.toString().trim();
  }

  static List<_XlsxSheetRows> _readXlsxSheetsFromArchive(Uint8List bytes) {
    final archive = ZipDecoder().decodeBytes(bytes, verify: false);
    final sharedStrings = _readXlsxSharedStrings(archive);
    final sheetEntries = _readXlsxSheetEntries(archive);
    final sheets = <_XlsxSheetRows>[];

    if (sheetEntries.isNotEmpty) {
      for (final entry in sheetEntries) {
        final content = _archiveText(archive, entry.path);
        if (content == null) continue;
        sheets.add(
          _XlsxSheetRows(
            name: entry.name,
            rows: _readXlsxSheetRows(content, sharedStrings),
          ),
        );
      }
      return sheets;
    }

    final worksheetFiles =
        archive.files
            .where((file) => file.name.startsWith('xl/worksheets/'))
            .where((file) => file.name.toLowerCase().endsWith('.xml'))
            .toList()
          ..sort((a, b) => a.name.compareTo(b.name));
    for (var index = 0; index < worksheetFiles.length; index += 1) {
      sheets.add(
        _XlsxSheetRows(
          name: 'Sheet ${index + 1}',
          rows: _readXlsxSheetRows(
            utf8.decode(
              worksheetFiles[index].content as List<int>,
              allowMalformed: true,
            ),
            sharedStrings,
          ),
        ),
      );
    }
    return sheets;
  }

  static List<String> _readXlsxSharedStrings(Archive archive) {
    final content = _archiveText(archive, 'xl/sharedStrings.xml');
    if (content == null || content.trim().isEmpty) {
      return const <String>[];
    }
    final document = xml.XmlDocument.parse(content);
    return _descendantElements(document, 'si').map((item) {
      return _descendantElements(
        item,
        't',
      ).map((text) => text.innerText).join();
    }).toList();
  }

  static List<_XlsxSheetEntry> _readXlsxSheetEntries(Archive archive) {
    final workbook = _archiveText(archive, 'xl/workbook.xml');
    final relationships = _archiveText(archive, 'xl/_rels/workbook.xml.rels');
    if (workbook == null || relationships == null) {
      return const <_XlsxSheetEntry>[];
    }

    final targetById = <String, String>{};
    final relDocument = xml.XmlDocument.parse(relationships);
    for (final rel in _descendantElements(relDocument, 'Relationship')) {
      final id = rel.getAttribute('Id')?.trim();
      final target = rel.getAttribute('Target')?.trim();
      if (id == null || id.isEmpty || target == null || target.isEmpty) {
        continue;
      }
      targetById[id] = _normalizeXlsxPath(target);
    }

    final entries = <_XlsxSheetEntry>[];
    final workbookDocument = xml.XmlDocument.parse(workbook);
    for (final sheet in _descendantElements(workbookDocument, 'sheet')) {
      final name = sheet.getAttribute('name')?.trim();
      final relationshipId = sheet.attributes
          .where((attribute) => attribute.name.local == 'id')
          .map((attribute) => attribute.value.trim())
          .where((value) => value.isNotEmpty)
          .firstOrNull;
      final path = targetById[relationshipId];
      if (path == null || path.isEmpty) {
        continue;
      }
      entries.add(
        _XlsxSheetEntry(
          name: name == null || name.isEmpty
              ? 'Sheet ${entries.length + 1}'
              : name,
          path: path,
        ),
      );
    }
    return entries;
  }

  static List<List<String>> _readXlsxSheetRows(
    String sheetXml,
    List<String> sharedStrings,
  ) {
    final document = xml.XmlDocument.parse(sheetXml);
    final rows = <List<String>>[];
    for (final rowElement in _descendantElements(document, 'row')) {
      final row = <String>[];
      var nextColumn = 0;
      for (final cell in _childElements(rowElement, 'c')) {
        final columnIndex = _xlsxColumnIndex(
          cell.getAttribute('r'),
          fallback: nextColumn,
        );
        while (row.length < columnIndex) {
          row.add('');
        }
        row.add(_xlsxCellValue(cell, sharedStrings));
        nextColumn = columnIndex + 1;
      }
      rows.add(row);
    }
    return rows;
  }

  static String _xlsxCellValue(
    xml.XmlElement cell,
    List<String> sharedStrings,
  ) {
    final type = cell.getAttribute('t')?.trim();
    if (type == 'inlineStr') {
      return _descendantElements(
        cell,
        't',
      ).map((text) => text.innerText).join();
    }

    final value =
        _firstElement(_childElements(cell, 'v'))?.innerText.trim() ?? '';
    if (value.isEmpty) {
      return '';
    }
    if (type == 's') {
      final index = int.tryParse(value);
      if (index != null && index >= 0 && index < sharedStrings.length) {
        return sharedStrings[index].trim();
      }
    }
    if (type == 'b') {
      return value == '1' ? 'true' : 'false';
    }
    return _formatNumericText(value);
  }

  static Iterable<xml.XmlElement> _descendantElements(
    xml.XmlNode node,
    String localName,
  ) {
    return node.descendants.whereType<xml.XmlElement>().where(
      (element) => element.name.local == localName,
    );
  }

  static Iterable<xml.XmlElement> _childElements(
    xml.XmlElement node,
    String localName,
  ) {
    return node.childElements.where(
      (element) => element.name.local == localName,
    );
  }

  static xml.XmlElement? _firstElement(Iterable<xml.XmlElement> elements) {
    final iterator = elements.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }

  static String? _archiveText(Archive archive, String path) {
    final file = archive.findFile(path);
    if (file == null) {
      return null;
    }
    return utf8.decode(file.content as List<int>, allowMalformed: true);
  }

  static String _normalizeXlsxPath(String target) {
    final clean = target.replaceAll('\\', '/');
    if (clean.startsWith('/')) {
      return clean.substring(1);
    }
    if (clean.startsWith('xl/')) {
      return clean;
    }
    return 'xl/$clean';
  }

  static int _xlsxColumnIndex(String? cellReference, {required int fallback}) {
    if (cellReference == null || cellReference.isEmpty) {
      return fallback;
    }
    var column = 0;
    var foundLetter = false;
    for (final codeUnit in cellReference.codeUnits) {
      final upper = codeUnit >= 97 && codeUnit <= 122
          ? codeUnit - 32
          : codeUnit;
      if (upper < 65 || upper > 90) {
        break;
      }
      foundLetter = true;
      column = (column * 26) + (upper - 64);
    }
    return foundLetter ? column - 1 : fallback;
  }

  static String _formatNumericText(String value) {
    final number = double.tryParse(value);
    if (number == null) {
      return value.trim();
    }
    return _formatExcelNumber(number);
  }

  static String _excelCellText(xl.CellValue? value) {
    if (value == null) {
      return '';
    }
    return switch (value) {
      xl.TextCellValue() => value.value.toString().trim(),
      xl.IntCellValue() => value.value.toString(),
      xl.DoubleCellValue() => _formatExcelNumber(value.value),
      xl.BoolCellValue() => value.value ? 'true' : 'false',
      xl.FormulaCellValue() => value.formula.trim(),
      _ => value.toString().trim(),
    };
  }

  static String _formatExcelNumber(double value) {
    if (value.isFinite && value == value.roundToDouble()) {
      return value.round().toString();
    }
    return value.toString();
  }

  static String _limitPreviewCell(String value) {
    if (value.length <= 120) {
      return value;
    }
    return '${value.substring(0, 117)}...';
  }

  static List<List<String>> readCsvRows(Uint8List bytes) {
    var content = utf8.decode(bytes, allowMalformed: true);
    // Strip UTF-8 BOM if present so the first header is not corrupted.
    if (content.startsWith('\uFEFF')) {
      content = content.substring(1);
    }
    final separator = _detectCsvSeparator(content);
    final rows = <List<String>>[];
    var row = <String>[];
    final buffer = StringBuffer();
    var inQuotes = false;

    for (var index = 0; index < content.length; index += 1) {
      final char = content[index];
      final next = index + 1 < content.length ? content[index + 1] : '';

      if (char == '"') {
        if (inQuotes && next == '"') {
          buffer.write('"');
          index += 1;
        } else {
          inQuotes = !inQuotes;
        }
        continue;
      }

      if (char == separator && !inQuotes) {
        row.add(buffer.toString().trim());
        buffer.clear();
        continue;
      }

      if ((char == '\n' || char == '\r') && !inQuotes) {
        if (char == '\r' && next == '\n') {
          index += 1;
        }
        row.add(buffer.toString().trim());
        buffer.clear();
        rows.add(row);
        row = <String>[];
        continue;
      }

      buffer.write(char);
    }

    if (buffer.isNotEmpty || row.isNotEmpty) {
      row.add(buffer.toString().trim());
      rows.add(row);
    }
    return rows;
  }

  static List<List<String>> readTsvRows(Uint8List bytes) {
    var content = utf8.decode(bytes, allowMalformed: true);
    if (content.startsWith('\uFEFF')) {
      content = content.substring(1);
    }
    return content
        .split(RegExp(r'\r?\n'))
        .where((line) => line.trim().isNotEmpty)
        .map((line) => line.split('\t').map((cell) => cell.trim()).toList())
        .toList();
  }

  static String _detectCsvSeparator(String content) {
    // Look at the first non-empty line and count unquoted commas vs semicolons.
    final firstLine = content
        .split('\n')
        .firstWhere((line) => line.trim().isNotEmpty, orElse: () => '');
    if (firstLine.isEmpty) return ',';
    final commas = _countUnquoted(firstLine, ',');
    final semicolons = _countUnquoted(firstLine, ';');
    return semicolons > commas ? ';' : ',';
  }

  static int _countUnquoted(String line, String separator) {
    var count = 0;
    var inQuotes = false;
    for (var i = 0; i < line.length; i += 1) {
      final char = line[i];
      if (char == '"') {
        // Handle escaped quotes.
        if (inQuotes && i + 1 < line.length && line[i + 1] == '"') {
          i += 1;
          continue;
        }
        inQuotes = !inQuotes;
      } else if (char == separator && !inQuotes) {
        count += 1;
      }
    }
    return count;
  }

  static List<String> normalizeHeaders(List<String> row) {
    return row
        .map(
          (header) => header
              .trim()
              .toLowerCase()
              .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
              .replaceAll(RegExp(r'^_+|_+$'), ''),
        )
        .toList();
  }

  static String normalizeHeader(String header) {
    return header
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
  }

  static Map<String, String> rowMap(List<String> headers, List<String> row) {
    final values = <String, String>{};
    for (var index = 0; index < headers.length; index += 1) {
      final header = headers[index];
      if (header.isEmpty) continue;
      values[header] = index < row.length ? row[index].trim() : '';
    }
    return values;
  }

  static bool hasAnyHeader(List<String> headers, List<String> candidates) {
    return candidates.any(headers.contains);
  }

  static String? readText(Map<String, String> row, List<String> keys) {
    for (final key in keys) {
      final value = row[key]?.trim();
      if (value != null && value.isNotEmpty) {
        return value;
      }
    }
    return null;
  }

  static bool hasAnyValue(Map<String, String> row, List<String> keys) {
    return readText(row, keys) != null;
  }

  static double? readMoney(Map<String, String> row, List<String> keys) {
    final raw = readText(row, keys);
    if (raw == null) return null;
    final normalized = raw.replaceAll(RegExp(r'[^0-9.\-]'), '');
    if (normalized.isEmpty || normalized == '-' || normalized == '.') {
      return null;
    }
    return double.tryParse(normalized);
  }

  static bool? readBool(Map<String, String> row, List<String> keys) {
    final raw = readText(row, keys);
    if (raw == null) return null;
    final normalized = raw.trim().toLowerCase();
    if (['1', 'true', 'yes', 'y', 'on'].contains(normalized)) {
      return true;
    }
    if (['0', 'false', 'no', 'n', 'off'].contains(normalized)) {
      return false;
    }
    return null;
  }

  static DateTime? readDate(Map<String, String> row, List<String> keys) {
    final raw = readText(row, keys);
    if (raw == null) return null;
    return parseDate(raw);
  }

  static DateTime? parseDate(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    final iso = DateTime.tryParse(trimmed);
    if (iso != null) return iso;

    final parts = trimmed.split(RegExp(r'[\/\-.]'));
    if (parts.length >= 3) {
      final first = int.tryParse(parts[0]);
      final second = int.tryParse(parts[1]);
      final third = int.tryParse(parts[2].split(RegExp(r'\s+')).first);
      if (first != null && second != null && third != null) {
        if (parts[0].length == 4) {
          // YYYY/MM/DD or YYYY-MM-DD
          return _safeDate(first, second, third);
        }
        if (first > 12) {
          // Day is clearly first: DD/MM/YYYY
          return _safeDate(third, second, first);
        }
        if (second > 12) {
          // Month is clearly first: MM/DD/YYYY
          return _safeDate(third, first, second);
        }
        // Ambiguous: prefer DD/MM/YYYY for the app's primary East-African market.
        return _safeDate(third, second, first);
      }
    }

    final excelSerial = double.tryParse(trimmed);
    if (excelSerial != null && excelSerial > 59) {
      return DateTime(1899, 12, 30).add(Duration(days: excelSerial.floor()));
    }
    return null;
  }

  static String extensionFor(String name, String? path) {
    final source = path?.trim().isNotEmpty == true ? path! : name;
    final index = source.lastIndexOf('.');
    if (index < 0 || index == source.length - 1) {
      return '';
    }
    return source.substring(index + 1).toLowerCase();
  }

  static Future<Uint8List?> _readFileBytes(String? path) async {
    if (path == null || path.trim().isEmpty) {
      return null;
    }
    return File(path).readAsBytes();
  }

  static String _mimeTypeForExtension(String extension) {
    return switch (extension.toLowerCase()) {
      'xlsx' =>
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'csv' => 'text/csv',
      'tsv' => 'text/tab-separated-values',
      'pdf' => 'application/pdf',
      'json' => 'application/json',
      'docx' =>
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'png' => 'image/png',
      'jpg' || 'jpeg' => 'image/jpeg',
      'webp' => 'image/webp',
      _ => 'text/plain',
    };
  }

  static DateTime? _safeDate(int year, int month, int day) {
    if (year < 1900 || month < 1 || month > 12 || day < 1 || day > 31) {
      return null;
    }
    return DateTime(year, month, day);
  }

  static _HeaderCandidate _scoreHeaderCandidate({
    required List<List<String>> rows,
    required int index,
    required Map<String, List<String>> columnAliases,
    required List<String> requiredAny,
    required List<String> requiredAll,
  }) {
    final rawHeaders = rows[index].map((cell) => cell.trim()).toList();
    final headers = <String>[];
    final mappedColumns = <String, String>{};
    final ignoredColumns = <String>[];
    final warnings = <String>[];
    var score = 0;

    for (final rawHeader in rawHeaders) {
      final normalized = normalizeHeader(rawHeader);
      if (normalized.isEmpty) {
        headers.add('');
        continue;
      }
      final match = _matchHeader(normalized, columnAliases);
      if (match == null) {
        headers.add(normalized);
        ignoredColumns.add(rawHeader);
        score -= 1;
        continue;
      }

      headers.add(match);
      mappedColumns[rawHeader] = match;
      score += 10;
      if (match != normalized) {
        warnings.add('Mapped "$rawHeader" to "$match".');
      }
    }

    final matched = mappedColumns.values.toSet();
    if (requiredAny.isNotEmpty &&
        requiredAny.any((key) => matched.contains(key))) {
      score += 18;
    }
    if (requiredAll.isNotEmpty) {
      final allPresent = requiredAll.every((key) => matched.contains(key));
      score += allPresent ? 28 : -22;
    }

    final dataRowCount = _countDataRowsAfter(rows, index);
    score += dataRowCount > 0 ? 6 : -12;
    score += dataRowCount > 5 ? 4 : dataRowCount;

    return _HeaderCandidate(
      index: index,
      rawHeaders: rawHeaders,
      headers: headers,
      mappedColumns: mappedColumns,
      ignoredColumns: ignoredColumns,
      warnings: warnings,
      score: score,
      dataRowCount: dataRowCount,
    );
  }

  static String? _matchHeader(
    String normalized,
    Map<String, List<String>> columnAliases,
  ) {
    for (final entry in columnAliases.entries) {
      final canonical = normalizeHeader(entry.key);
      if (normalized == canonical) {
        return canonical;
      }
    }

    String? bestKey;
    var bestScore = 0;
    for (final entry in columnAliases.entries) {
      final canonical = normalizeHeader(entry.key);
      final aliases = {
        canonical,
        ...entry.value.map(normalizeHeader),
      }.where((value) => value.isNotEmpty);

      for (final alias in aliases) {
        final score = _headerSimilarityScore(normalized, alias);
        if (score > bestScore) {
          bestScore = score;
          bestKey = canonical;
        }
      }
    }
    return bestScore >= 72 ? bestKey : null;
  }

  static int _headerSimilarityScore(String left, String right) {
    if (left == right) return 100;
    final compactLeft = left.replaceAll('_', '');
    final compactRight = right.replaceAll('_', '');
    if (compactLeft == compactRight) return 98;
    if (compactLeft.length >= 4 &&
        compactRight.length >= 4 &&
        (compactLeft.contains(compactRight) ||
            compactRight.contains(compactLeft))) {
      final shorter = compactLeft.length < compactRight.length
          ? compactLeft.length
          : compactRight.length;
      final longer = compactLeft.length > compactRight.length
          ? compactLeft.length
          : compactRight.length;
      final extraLength = longer - shorter;
      if (extraLength <= 4 || shorter >= 8) {
        return 88;
      }
    }

    final distance = _levenshtein(compactLeft, compactRight);
    final longest = compactLeft.length > compactRight.length
        ? compactLeft.length
        : compactRight.length;
    if (longest == 0) return 0;
    final score = ((1 - (distance / longest)) * 100).round();
    return score;
  }

  static int _levenshtein(String a, String b) {
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;

    var previous = List<int>.generate(b.length + 1, (index) => index);
    for (var i = 0; i < a.length; i += 1) {
      final current = List<int>.filled(b.length + 1, 0);
      current[0] = i + 1;
      for (var j = 0; j < b.length; j += 1) {
        final insertCost = current[j] + 1;
        final deleteCost = previous[j + 1] + 1;
        final replaceCost = previous[j] + (a[i] == b[j] ? 0 : 1);
        current[j + 1] = [
          insertCost,
          deleteCost,
          replaceCost,
        ].reduce((value, element) => value < element ? value : element);
      }
      previous = current;
    }
    return previous[b.length];
  }

  static int _countDataRowsAfter(List<List<String>> rows, int headerIndex) {
    var count = 0;
    for (var index = headerIndex + 1; index < rows.length; index += 1) {
      if (rows[index].any((cell) => cell.trim().isNotEmpty)) {
        count += 1;
      }
    }
    return count;
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
