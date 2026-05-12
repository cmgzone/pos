enum PikiPosCommandType {
  addItem,
  removeItem,
  setQuantity,
  repeatLast,
  clearCart,
  checkout,
  holdSale,
  teachAlias,
  unknown,
}

class PikiPosCommand {
  final PikiPosCommandType type;
  final String? query;
  final double? quantity;
  final String? alias;
  final String? target;
  final String? paymentType;
  final bool requiresConfirmation;

  const PikiPosCommand({
    required this.type,
    this.query,
    this.quantity,
    this.alias,
    this.target,
    this.paymentType,
    this.requiresConfirmation = false,
  });

  bool get isKnown => type != PikiPosCommandType.unknown;
}

class PikiPosCommandEngine {
  static const _numberWords = <String, double>{
    'a': 1,
    'an': 1,
    'one': 1,
    'two': 2,
    'three': 3,
    'four': 4,
    'five': 5,
    'six': 6,
    'seven': 7,
    'eight': 8,
    'nine': 9,
    'ten': 10,
    'eleven': 11,
    'twelve': 12,
    'dozen': 12,
  };

  static PikiPosCommand parse(String rawText) {
    final original = rawText.trim();
    if (original.isEmpty) {
      return const PikiPosCommand(type: PikiPosCommandType.unknown);
    }

    final text = _normalizeSpeechText(original);
    final aliasCommand = _parseAliasCommand(text);
    if (aliasCommand != null) {
      return aliasCommand;
    }

    if (_containsAny(text, const [
      'clear cart',
      'empty cart',
      'remove all',
      'clear all',
      'reset cart',
      'cancel cart',
    ])) {
      return const PikiPosCommand(
        type: PikiPosCommandType.clearCart,
        requiresConfirmation: true,
      );
    }

    if (_containsAny(text, const [
      'hold sale',
      'hold this sale',
      'park sale',
      'save sale',
      'suspend sale',
    ])) {
      return const PikiPosCommand(type: PikiPosCommandType.holdSale);
    }

    final checkoutPayment = _paymentTypeFromText(text);
    if (_containsAny(text, const [
      'checkout',
      'check out',
      'process sale',
      'pay now',
      'complete sale',
      'finish sale',
      'done selling',
      'charge customer',
    ])) {
      return PikiPosCommand(
        type: PikiPosCommandType.checkout,
        paymentType: checkoutPayment,
        requiresConfirmation: checkoutPayment != null,
      );
    }

    if (_containsAny(text, const [
      'add another',
      'another one',
      'one more',
      'add one more',
      'same again',
      'add again',
    ])) {
      return PikiPosCommand(
        type: PikiPosCommandType.repeatLast,
        quantity: _firstQuantity(text) ?? 1,
      );
    }

    final setQuantity = _parseSetQuantity(text);
    if (setQuantity != null) {
      return setQuantity;
    }

    final remove = _parseRemove(text);
    if (remove != null) {
      return remove;
    }

    final add = _parseAdd(text, original);
    if (add != null) {
      return add;
    }

    return const PikiPosCommand(type: PikiPosCommandType.unknown);
  }

  static PikiPosCommand? _parseAliasCommand(String text) {
    final patterns = [
      RegExp(r'^when i say (.+?) (?:use|pick|choose|mean|means) (.+)$'),
      RegExp(r'^remember (.+?) (?:means|is|use|use as) (.+)$'),
      RegExp(r'^teach piki (.+?) (?:means|is|use|use as) (.+)$'),
      RegExp(r'^(.+?) is same as (.+)$'),
    ];
    for (final pattern in patterns) {
      final match = pattern.firstMatch(text);
      if (match == null) continue;
      final alias = _cleanQuery(match.group(1) ?? '');
      final target = _cleanQuery(match.group(2) ?? '');
      if (alias.isEmpty || target.isEmpty) {
        return null;
      }
      return PikiPosCommand(
        type: PikiPosCommandType.teachAlias,
        alias: alias,
        target: target,
      );
    }
    return null;
  }

  static PikiPosCommand? _parseSetQuantity(String text) {
    final patterns = [
      RegExp(r'^(?:set|change)\s+(.+?)\s+(?:to|as)\s+(.+)$'),
      RegExp(r'^(?:make)\s+(.+?)\s+(.+)$'),
    ];
    for (final pattern in patterns) {
      final match = pattern.firstMatch(text);
      if (match == null) continue;
      final rawTarget = _cleanQuery(match.group(1) ?? '');
      final quantity = _quantityFromToken(match.group(2) ?? '');
      if (quantity == null || quantity <= 0) continue;
      final target = _isContextReference(rawTarget) ? null : rawTarget;
      return PikiPosCommand(
        type: PikiPosCommandType.setQuantity,
        query: target,
        quantity: quantity,
      );
    }
    return null;
  }

  static PikiPosCommand? _parseRemove(String text) {
    final patterns = [
      RegExp(
        r'^(?:remove|delete|void|take off|take out)\s+(.+?)\s+from\s+cart$',
      ),
      RegExp(r'^(?:remove|delete|void|take off|take out)\s+(.+)$'),
    ];
    for (final pattern in patterns) {
      final match = pattern.firstMatch(text);
      if (match == null) continue;
      final body = _cleanQuery(match.group(1) ?? '');
      if (body.isEmpty) continue;
      if (_isContextReference(body)) {
        return const PikiPosCommand(type: PikiPosCommandType.removeItem);
      }
      final split = _splitLeadingQuantity(body);
      return PikiPosCommand(
        type: PikiPosCommandType.removeItem,
        query: _isContextReference(split.query) ? null : split.query,
        quantity: split.quantity,
      );
    }

    if (_containsAny(text, const ['undo last', 'remove last', 'void last'])) {
      return const PikiPosCommand(type: PikiPosCommandType.removeItem);
    }
    return null;
  }

  static PikiPosCommand? _parseAdd(String text, String original) {
    final addVerb = RegExp(
      r'^(?:sell|add|ring up|give me|scan|get|put|cart)\s+(.+)$',
    );
    final match = addVerb.firstMatch(text);
    if (match != null) {
      final split = _splitLeadingQuantity(match.group(1) ?? '');
      if (split.query.isNotEmpty) {
        return PikiPosCommand(
          type: PikiPosCommandType.addItem,
          query: split.query,
          quantity: split.quantity ?? 1,
        );
      }
    }

    final productXQty = RegExp(r'^(.+?)\s+x\s*(.+)$').firstMatch(text);
    if (productXQty != null) {
      final quantity = _quantityFromToken(productXQty.group(2) ?? '');
      final query = _cleanQuery(productXQty.group(1) ?? '');
      if (quantity != null && quantity > 0 && query.isNotEmpty) {
        return PikiPosCommand(
          type: PikiPosCommandType.addItem,
          query: query,
          quantity: quantity,
        );
      }
    }

    final split = _splitLeadingQuantity(text);
    if (split.query.isNotEmpty) {
      return PikiPosCommand(
        type: PikiPosCommandType.addItem,
        query: split.query,
        quantity: split.quantity ?? 1,
      );
    }

    final fallback = _cleanQuery(original);
    if (fallback.isNotEmpty) {
      return PikiPosCommand(
        type: PikiPosCommandType.addItem,
        query: fallback,
        quantity: 1,
      );
    }

    return null;
  }

  static ({double? quantity, String query}) _splitLeadingQuantity(String text) {
    final clean = _cleanQuery(text);
    if (clean.isEmpty) {
      return (quantity: null, query: '');
    }
    final match = RegExp(r'^([a-z]+|\d+(?:\.\d+)?)\s+(.+)$').firstMatch(clean);
    if (match == null) {
      return (quantity: null, query: clean);
    }
    final quantity = _quantityFromToken(match.group(1) ?? '');
    if (quantity == null || quantity <= 0) {
      return (quantity: null, query: clean);
    }
    return (quantity: quantity, query: _cleanQuery(match.group(2) ?? ''));
  }

  static double? _firstQuantity(String text) {
    final tokens = text.split(RegExp(r'\s+'));
    for (final token in tokens) {
      final quantity = _quantityFromToken(token);
      if (quantity != null && quantity > 0) {
        return quantity;
      }
    }
    return null;
  }

  static double? _quantityFromToken(String token) {
    final clean = token.trim().toLowerCase();
    if (clean.isEmpty) return null;
    return double.tryParse(clean) ?? _numberWords[clean];
  }

  static String _normalizeSpeechText(String text) {
    return text
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[,;.!?]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceFirst(RegExp(r'^(please|piki|hey piki|okay piki)\s+'), '')
        .trim();
  }

  static String _cleanQuery(String value) {
    return value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'\b(the|a|an|please|cart)\b'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static bool _isContextReference(String text) {
    final clean = _cleanQuery(text);
    return clean.isEmpty ||
        const {
          'it',
          'that',
          'last',
          'last item',
          'same',
          'this',
        }.contains(clean);
  }

  static bool _containsAny(String text, List<String> phrases) {
    return phrases.any(text.contains);
  }

  static String? _paymentTypeFromText(String text) {
    if (text.contains('kopesha') || text.contains('credit')) {
      return 'kopesha';
    }
    if (text.contains('mpesa') ||
        text.contains('m pesa') ||
        text.contains('mobile money') ||
        text.contains('mobile')) {
      return 'mobile_money';
    }
    if (text.contains('card')) {
      return 'card';
    }
    if (text.contains('cash')) {
      return 'cash';
    }
    return null;
  }
}
