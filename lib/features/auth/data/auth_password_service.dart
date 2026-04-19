import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

class AuthPasswordService {
  static const _hashPrefix = 'velora.v1';
  static const _defaultIterations = 12000;
  static const _saltByteLength = 16;

  static String hashPassword(String password) {
    final random = Random.secure();
    final saltBytes = List<int>.generate(
      _saltByteLength,
      (_) => random.nextInt(256),
    );
    final salt = base64Url.encode(saltBytes);
    final digest = _deriveDigest(
      password: password,
      salt: salt,
      iterations: _defaultIterations,
    );
    return '$_hashPrefix\$$_defaultIterations\$$salt\$$digest';
  }

  static bool verifyPassword({
    required String storedPassword,
    required String candidatePassword,
  }) {
    final parsedHash = _parseHash(storedPassword);
    if (parsedHash == null) {
      return _constantTimeEquals(storedPassword, candidatePassword);
    }

    final candidateDigest = _deriveDigest(
      password: candidatePassword,
      salt: parsedHash.salt,
      iterations: parsedHash.iterations,
    );
    return _constantTimeEquals(parsedHash.digest, candidateDigest);
  }

  static bool needsMigration(String storedPassword) {
    return _parseHash(storedPassword) == null;
  }

  static String _deriveDigest({
    required String password,
    required String salt,
    required int iterations,
  }) {
    final passwordBytes = utf8.encode(password);
    final saltBytes = utf8.encode(salt);

    var current = sha256.convert([...saltBytes, ...passwordBytes]).bytes;
    for (var round = 1; round < iterations; round++) {
      current = sha256.convert([
        ...current,
        ...saltBytes,
        ...passwordBytes,
      ]).bytes;
    }
    return base64Url.encode(current);
  }

  static _ParsedHash? _parseHash(String value) {
    final parts = value.split(r'$');
    if (parts.length != 4 || parts[0] != _hashPrefix) {
      return null;
    }

    final iterations = int.tryParse(parts[1]);
    final salt = parts[2].trim();
    final digest = parts[3].trim();
    if (iterations == null ||
        iterations <= 0 ||
        salt.isEmpty ||
        digest.isEmpty) {
      return null;
    }

    return _ParsedHash(iterations: iterations, salt: salt, digest: digest);
  }

  static bool _constantTimeEquals(String left, String right) {
    final leftBytes = utf8.encode(left);
    final rightBytes = utf8.encode(right);
    final maxLength = leftBytes.length > rightBytes.length
        ? leftBytes.length
        : rightBytes.length;

    var mismatch = leftBytes.length ^ rightBytes.length;
    for (var index = 0; index < maxLength; index++) {
      final leftByte = index < leftBytes.length ? leftBytes[index] : 0;
      final rightByte = index < rightBytes.length ? rightBytes[index] : 0;
      mismatch |= leftByte ^ rightByte;
    }
    return mismatch == 0;
  }
}

class _ParsedHash {
  const _ParsedHash({
    required this.iterations,
    required this.salt,
    required this.digest,
  });

  final int iterations;
  final String salt;
  final String digest;
}
