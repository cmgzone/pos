class AppErrorMessage {
  static const generic = 'Something went wrong. Please try again.';
  static const saveFailed =
      'Your changes could not be saved. Please try again.';
  static const loadFailed = 'This information could not be loaded right now.';
  static const syncFailed =
      'Cloud sync could not finish. Check your connection and try again.';
  static const paymentFailed =
      'Payment could not be completed. Please try again.';
  static const pikiFailed =
      'Piki could not finish that request. Please try again.';

  static String from(Object? error, {String fallback = generic}) {
    final raw = error?.toString().trim() ?? '';
    if (raw.isEmpty) {
      return fallback;
    }

    final lowerRaw = raw.toLowerCase();
    if (_looksLikePaymentProviderIssue(lowerRaw)) {
      return _publicMessage(raw, fallback);
    }
    if (_looksLikeNetworkIssue(lowerRaw)) {
      return 'The server could not be reached. Check your internet connection and try again.';
    }
    if (_looksLikeTimeout(lowerRaw)) {
      return 'The request took too long. Please try again.';
    }
    if (_looksLikeAuthIssue(lowerRaw)) {
      return 'Your session has expired. Please sign in again.';
    }
    if (_looksLikePermissionIssue(lowerRaw)) {
      return 'You do not have permission to do that.';
    }
    if (_looksLikeMissingRecord(lowerRaw)) {
      return 'That record could not be found. It may have been changed or deleted.';
    }
    if (_looksLikeServerIssue(lowerRaw)) {
      return 'The server had a problem. Please try again shortly.';
    }
    if (_looksLikeCloudSetupIssue(lowerRaw)) {
      return 'Cloud services are not set up on this device. Contact support to finish setup.';
    }

    var message = _stripExceptionPrefixes(raw);
    message = _stripOuterQuotes(message);
    message = message.replaceAll(RegExp(r'\s+'), ' ').trim();

    if (message.isEmpty) {
      return fallback;
    }

    final lower = message.toLowerCase();
    if (_looksTechnical(lower, message)) {
      return fallback;
    }

    if (message.length > 180) {
      return fallback;
    }

    return _ensureSentence(message);
  }

  static String _publicMessage(String raw, String fallback) {
    var message = _stripExceptionPrefixes(raw);
    message = _stripOuterQuotes(message);
    message = message.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (message.isEmpty || message.length > 220) {
      return fallback;
    }
    return _ensureSentence(message);
  }

  static String withContext(
    Object? error, {
    required String fallback,
    String? prefix,
  }) {
    final message = from(error, fallback: fallback);
    if (prefix == null || prefix.trim().isEmpty) {
      return message;
    }
    if (message == fallback) {
      return message;
    }
    return '${prefix.trim()} $message';
  }

  static String _stripExceptionPrefixes(String raw) {
    var message = raw.trim();
    const prefixes = [
      'Exception: ',
      'FormatException: ',
      'StateError: ',
      'ArgumentError: ',
      'Invalid argument(s): ',
    ];

    var changed = true;
    while (changed) {
      changed = false;
      for (final prefix in prefixes) {
        if (message.startsWith(prefix)) {
          message = message.substring(prefix.length).trim();
          changed = true;
        }
      }
    }

    return message.replaceFirst(RegExp(r'^Error:\s*'), '').trim();
  }

  static String _stripOuterQuotes(String message) {
    if (message.length < 2) {
      return message;
    }
    final first = message[0];
    final last = message[message.length - 1];
    if ((first == '"' && last == '"') || (first == "'" && last == "'")) {
      return message.substring(1, message.length - 1).trim();
    }
    return message;
  }

  static bool _looksLikeNetworkIssue(String lower) {
    return lower.contains('socketexception') ||
        lower.contains('clientexception') ||
        lower.contains('failed host lookup') ||
        lower.contains('connection refused') ||
        lower.contains('connection reset') ||
        lower.contains('connection aborted') ||
        lower.contains('connection error') ||
        lower.contains('network is unreachable') ||
        lower.contains('networkerror') ||
        lower.contains('xmlhttprequest') ||
        lower.contains('failed to fetch') ||
        lower.contains('software caused connection abort');
  }

  static bool _looksLikeTimeout(String lower) {
    return lower.contains('timeoutexception') ||
        lower.contains('timed out') ||
        lower.contains('timeout');
  }

  static bool _looksLikeAuthIssue(String lower) {
    return lower.contains('401') ||
        lower.contains('unauthorized') ||
        lower.contains('jwt') ||
        lower.contains('token expired') ||
        lower.contains('invalid token');
  }

  static bool _looksLikePermissionIssue(String lower) {
    return lower.contains('403') ||
        lower.contains('forbidden') ||
        lower.contains('permission denied');
  }

  static bool _looksLikeMissingRecord(String lower) {
    return lower.contains('404') ||
        lower.contains('not found or access denied');
  }

  static bool _looksLikeServerIssue(String lower) {
    return lower.contains('500') ||
        lower.contains('502') ||
        lower.contains('503') ||
        lower.contains('504') ||
        lower.contains('internal server error') ||
        lower.contains('bad gateway') ||
        lower.contains('service unavailable');
  }

  static bool _looksLikePaymentProviderIssue(String lower) {
    return lower.contains('m-pesa') ||
        lower.contains('mpesa') ||
        lower.contains('daraja') ||
        lower.contains('stk') ||
        lower.contains('callback url') ||
        lower.contains('callbackurl') ||
        lower.contains('shortcode') ||
        lower.contains('passkey') ||
        lower.contains('consumer key') ||
        lower.contains('consumer secret');
  }

  static bool _looksLikeCloudSetupIssue(String lower) {
    return lower.contains('cloud backend url is not configured') ||
        lower.contains('cloud backend is not configured') ||
        lower.contains('cloud sync is not configured') ||
        lower.contains('backend url is not configured') ||
        lower.contains('public_base_url') ||
        lower.contains('public base url');
  }

  static bool _looksTechnical(String lower, String message) {
    return lower.contains('databaseexception') ||
        lower.contains('referenceerror') ||
        lower.contains('typeerror') ||
        lower.contains(' is not defined') ||
        lower.contains('provider returned error') ||
        lower.contains('unexpected character at character') ||
        lower.contains('<!doctype html') ||
        lower.contains('sqlexception') ||
        lower.contains('sqlite') ||
        lower.contains('sql ') ||
        lower.contains(' no such table') ||
        lower.contains(' no such column') ||
        lower.contains('syntax error') ||
        lower.contains('null check operator') ||
        lower.contains('nosuchmethoderror') ||
        lower.contains('lateinitializationerror') ||
        lower.contains('rangeerror') ||
        (lower.contains('type ') && lower.contains(' is not a subtype')) ||
        lower.contains('stack trace') ||
        lower.contains('package:') ||
        lower.contains('file:') ||
        lower.contains('http://') ||
        lower.contains('https://') ||
        lower.contains('/api/') ||
        lower.contains('postgres') ||
        lower.contains('neon') ||
        lower.contains('openrouter') ||
        lower.contains('serpapi') ||
        RegExp(r'#[0-9]+\s+').hasMatch(message) ||
        RegExp(r'[A-Za-z]:\\').hasMatch(message);
  }

  static String _ensureSentence(String message) {
    if (message.endsWith('.') ||
        message.endsWith('!') ||
        message.endsWith('?')) {
      return message;
    }
    return '$message.';
  }
}
