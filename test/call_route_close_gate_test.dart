import 'package:flutter_test/flutter_test.dart';
import 'package:my_chat_app/utils/call_route_close_gate.dart';

void main() {
  test('terminal auto-close waits for permission dialog to close', () {
    final gate = CallRouteCloseGate();

    expect(gate.beginDialog(), isTrue);
    expect(gate.requestClose(), isFalse);
    expect(gate.endDialog(), isTrue);
    expect(gate.requestClose(), isTrue);
  });

  test('duplicate permission dialogs are suppressed', () {
    final gate = CallRouteCloseGate();

    expect(gate.beginDialog(), isTrue);
    expect(gate.beginDialog(), isFalse);
    expect(gate.endDialog(), isFalse);
  });
}
