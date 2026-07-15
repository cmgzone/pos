import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:pos_app/core/services/piki_ai_job_service.dart';

void main() {
  test('Piki cloud response decoder accepts JSON objects', () {
    final decoded = decodePikiCloudJsonResponse(
      http.Response(
        '{"ok":true,"job":{"id":"job-1"}}',
        202,
        headers: {'content-type': 'application/json'},
      ),
    );

    expect(decoded['ok'], isTrue);
    expect((decoded['job'] as Map)['id'], 'job-1');
  });

  test('Piki cloud response decoder explains an undeployed HTML route', () {
    expect(
      () => decodePikiCloudJsonResponse(
        http.Response(
          '<!DOCTYPE html><html><body>Not found</body></html>',
          404,
          headers: {'content-type': 'text/html; charset=utf-8'},
        ),
      ),
      throwsA(
        isA<Exception>().having(
          (error) => error.toString(),
          'message',
          contains('current server deployment'),
        ),
      ),
    );
  });

  test('Piki cloud response decoder never exposes a raw JSON format error', () {
    expect(
      () => decodePikiCloudJsonResponse(
        http.Response(
          'temporarily unavailable',
          502,
          headers: {'content-type': 'text/plain'},
        ),
      ),
      throwsA(
        isA<Exception>().having(
          (error) => error.toString(),
          'message',
          contains('returned invalid data'),
        ),
      ),
    );
  });
}
