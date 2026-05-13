import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/features/agent/data/piki_work_notes.dart';

void main() {
  group('PikiWorkNote', () {
    test('serializes through attached data json', () {
      final note = PikiWorkNote(
        stage: 'tool',
        title: 'Running local tools',
        detail: 'Checking low stock',
        loop: 2,
        timestamp: DateTime.utc(2026, 5, 13, 10),
      );
      const runState = PikiRunState(
        loopCount: 2,
        toolCount: 3,
        stopReason: 'completed',
        completed: true,
      );

      final encoded = jsonEncode({
        'work_notes': [note.toJson()],
        'run_state': runState.toJson(),
      });
      final decoded = jsonDecode(encoded) as Map<String, dynamic>;
      final notes = PikiWorkNote.listFromJson(decoded['work_notes']);
      final restoredRunState = PikiRunState.fromJson(
        decoded['run_state'] as Map<String, dynamic>,
      );

      expect(notes, hasLength(1));
      expect(notes.single.stage, 'tool');
      expect(notes.single.title, 'Running local tools');
      expect(notes.single.detail, 'Checking low stock');
      expect(notes.single.loop, 2);
      expect(restoredRunState.completed, isTrue);
      expect(restoredRunState.toolCount, 3);
    });
  });

  group('PikiAutoLoopGuard', () {
    test('allows multiple distinct tool batches before completion', () {
      final guard = PikiAutoLoopGuard(maxPlannerTurns: 8);

      final first = guard.checkToolBatch(
        loopCount: 1,
        totalToolCalls: 0,
        toolCalls: [
          {
            'tool': 'sales_summary',
            'arguments': {'daysRange': 1},
          },
        ],
      );
      final second = guard.checkToolBatch(
        loopCount: 2,
        totalToolCalls: 1,
        toolCalls: [
          {
            'tool': 'low_stock',
            'arguments': {'limit': 10},
          },
        ],
      );

      expect(first.shouldStop, isFalse);
      expect(second.shouldStop, isFalse);
      expect(guard.canStartPlannerTurn(8), isTrue);
      expect(guard.canStartPlannerTurn(9), isFalse);
    });

    test('stops repeated identical tool batches', () {
      final guard = PikiAutoLoopGuard();
      final batch = [
        {
          'tool': 'sales_summary',
          'arguments': {'daysRange': 1},
        },
      ];

      expect(
        guard
            .checkToolBatch(loopCount: 1, totalToolCalls: 0, toolCalls: batch)
            .shouldStop,
        isFalse,
      );
      final repeated = guard.checkToolBatch(
        loopCount: 2,
        totalToolCalls: 1,
        toolCalls: batch,
      );

      expect(repeated.shouldStop, isTrue);
      expect(repeated.reason, 'repeated_tool_batch');
    });

    test('stops before exceeding total tool cap', () {
      final guard = PikiAutoLoopGuard(maxTotalToolCalls: 2);

      final decision = guard.checkToolBatch(
        loopCount: 1,
        totalToolCalls: 1,
        toolCalls: [
          {'tool': 'low_stock'},
          {'tool': 'sales_summary'},
        ],
      );

      expect(decision.shouldStop, isTrue);
      expect(decision.reason, 'max_total_tool_calls');
    });

    test('normalizes argument order for repeated batch detection', () {
      final first = PikiAutoLoopGuard.toolBatchSignature([
        {
          'tool': 'sales_summary',
          'arguments': {'limit': 10, 'daysRange': 7},
        },
      ]);
      final second = PikiAutoLoopGuard.toolBatchSignature([
        {
          'tool': 'sales_summary',
          'arguments': {'daysRange': 7, 'limit': 10},
        },
      ]);

      expect(first, second);
    });
  });

  group('Piki answer stopping helpers', () {
    test('detects clarifying questions as needing user input', () {
      expect(
        PikiAnswerClassifier.needsUserInput(
          'What price should I use for Bread?',
        ),
        isTrue,
      );
      expect(
        PikiAnswerClassifier.needsUserInput('The product was created.'),
        isFalse,
      );
    });

    test('builds a useful partial summary when a safety guard stops work', () {
      final answer = PikiLoopSummary.bestEffortAnswerFromResults(
        results: [
          {'summary': 'Checked low stock'},
          {'title': 'Sales summary ready'},
        ],
        stopReason: 'Piki reached the planning safety limit',
      );

      expect(answer, contains('Checked low stock'));
      expect(answer, contains('Sales summary ready'));
      expect(answer, contains('planning safety limit'));
    });
  });
}
