import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/core/services/openrouter_service.dart';

void main() {
  group('OpenRouterService planner parser', () {
    test('extracts JSON from markdown fences', () {
      final parsed = OpenRouterService.extractPlannerResponseForTesting('''
```json
{
  "mode": "answer",
  "answer": "Stock looks fine today.",
  "tool_calls": []
}
```
''');

      expect(parsed['mode'], 'answer');
      expect(parsed['answer'], 'Stock looks fine today.');
    });

    test('repairs common model JSON issues in surrounding prose', () {
      final parsed = OpenRouterService.extractPlannerResponseForTesting('''
Here is the plan:
{mode: "tool", "tool_calls": [{"tool": "low_stock", "arguments": {"limit": 5,},},],}
Done.
''');

      expect(parsed['mode'], 'tool');
      final toolCalls = parsed['tool_calls'] as List;
      expect(toolCalls.single['tool'], 'low_stock');
      expect(toolCalls.single['arguments']['limit'], 5);
    });

    test('keeps braces inside JSON strings while extracting object', () {
      final parsed = OpenRouterService.extractPlannerResponseForTesting(
        'Before {"mode":"answer","answer":"Use {promo} as the shelf note."} after',
      );

      expect(parsed['mode'], 'answer');
      expect(parsed['answer'], 'Use {promo} as the shelf note.');
    });

    test('falls back to an answer instead of throwing for plain text', () {
      final parsed = OpenRouterService.extractPlannerResponseForTesting(
        'I can help with that. Please tell me the product price first.',
      );

      expect(parsed['mode'], 'answer');
      expect(
        parsed['answer'],
        'I can help with that. Please tell me the product price first.',
      );
      expect(parsed['tool_calls'], isEmpty);
    });

    test('uses explicit answer from malformed planner JSON', () {
      final parsed = OpenRouterService.extractPlannerResponseForTesting(
        '{mode: "answer", answer: "Please tell me the product price first."',
      );

      expect(parsed['mode'], 'answer');
      expect(parsed['answer'], 'Please tell me the product price first.');
    });
  });
}
