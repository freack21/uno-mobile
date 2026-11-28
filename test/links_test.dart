import 'package:flutter_test/flutter_test.dart';
import 'package:uno_mobile/online/links.dart';

void main() {
  test('invite links give the room code', () {
    expect(
      joinCodeOf(Uri.parse('https://uno.refandi.my.id/join/ABC123-0517')),
      'ABC123-0517',
    );
    expect(
      joinCodeOf(Uri.parse('https://uno.refandi.my.id/#join=ABC123-0517')),
      'ABC123-0517',
      reason: 'older links still work',
    );
    expect(joinCodeOf(Uri.parse('https://uno.refandi.my.id/')), isNull);
    expect(joinCodeOf(Uri.parse('https://uno.refandi.my.id/join/')), isNull);
    expect(joinCodeOf(Uri.parse('https://uno.refandi.my.id/privacy')), isNull);
  });
}
