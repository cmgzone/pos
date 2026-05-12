import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/features/agent/data/piki_pos_command_engine.dart';

void main() {
  group('PikiPosCommandEngine', () {
    test('parses add commands with quantities', () {
      final command = PikiPosCommandEngine.parse('sell 2 coke');

      expect(command.type, PikiPosCommandType.addItem);
      expect(command.query, 'coke');
      expect(command.quantity, 2);
    });

    test('parses remove and quantity commands', () {
      final remove = PikiPosCommandEngine.parse('remove one coke');
      final setQty = PikiPosCommandEngine.parse('make coke three');

      expect(remove.type, PikiPosCommandType.removeItem);
      expect(remove.query, 'coke');
      expect(remove.quantity, 1);
      expect(setQty.type, PikiPosCommandType.setQuantity);
      expect(setQty.query, 'coke');
      expect(setQty.quantity, 3);
    });

    test('parses repeat, hold, checkout, and alias commands', () {
      expect(
        PikiPosCommandEngine.parse('same again').type,
        PikiPosCommandType.repeatLast,
      );
      expect(
        PikiPosCommandEngine.parse('hold sale').type,
        PikiPosCommandType.holdSale,
      );
      expect(PikiPosCommandEngine.parse('checkout cash').paymentType, 'cash');

      final alias = PikiPosCommandEngine.parse(
        'when i say small soda use fanta 300ml',
      );
      expect(alias.type, PikiPosCommandType.teachAlias);
      expect(alias.alias, 'small soda');
      expect(alias.target, 'fanta 300ml');
    });
  });
}
