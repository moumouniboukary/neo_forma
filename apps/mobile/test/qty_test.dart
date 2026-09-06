import 'package:flutter_test/flutter_test.dart';
import 'package:neoforma/core/utils/qty.dart';

void main() {
  test('parseQty accepte virgule FR et point', () {
    expect(parseQty('1,5'), 1.5);
    expect(parseQty('1.5'), 1.5);
    expect(parseQty('20'), 20);
  });

  test('formatQty sans décimale inutile', () {
    expect(formatQty(2), '2');
    expect(formatQty(1.5), '1,5');
    expect(formatQty(1.25), '1,25');
  });

  test('appendQtyDigit max 3 décimales', () {
    expect(appendQtyDigit('1', ','), '1,');
    expect(appendQtyDigit('1,5', '2'), '1,52');
    expect(appendQtyDigit('1,555', '9'), '1,555');
  });

  test('normalizeUnite', () {
    expect(normalizeUnite('kilo'), 'kg');
    expect(normalizeUnite('grammes'), 'g');
    expect(normalizeUnite('litre'), 'l');
    expect(normalizeUnite(null), 'u');
  });
}
