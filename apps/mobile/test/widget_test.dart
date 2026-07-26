import 'package:flutter_test/flutter_test.dart';
import 'package:neoforma/core/api/config.dart';

void main() {
  test('resolveApiBase defaults to Android emulator host', () {
    expect(resolveApiBase(), 'http://10.0.2.2:3001');
  });
}
