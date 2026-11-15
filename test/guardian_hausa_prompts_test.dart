import 'package:flutter_test/flutter_test.dart';
import 'package:rainbow_app/core/guardian/hausa_prompts.dart';

/// The recordings a Hausa speaker makes must come out in the shape
/// tool/guardian_eval.dart reads, or they cannot measure a Hausa model.
void main() {
  test('there are both calls for help and everyday speech to record', () {
    expect(hausaPrompts.where((p) => p.expect == 'sos'), isNotEmpty);
    expect(hausaPrompts.where((p) => p.expect == 'none'), isNotEmpty);
    expect(hausaPrompts.every((p) => p.expect == 'sos' || p.expect == 'none'), isTrue);
  });

  test('every prompt has its own id and an English meaning for the reviewer', () {
    expect(hausaPrompts.map((p) => p.id).toSet().length, hausaPrompts.length);
    expect(hausaPrompts.every((p) => p.english.isNotEmpty && p.hausa.isNotEmpty), isTrue);
  });

  test('labels.csv starts file,expect and keeps four columns per row', () {
    final csv = recordingLabelsCsv([('a.wav', hausaPrompts.first), ('b.wav', hausaPrompts.last)]);
    final lines = csv.trim().split('\n');
    expect(lines.first, 'file,expect,lang,text');
    for (final l in lines.skip(1)) {
      final cols = l.split(',');
      expect(cols.length, 4, reason: l);
      expect(['sos', 'none'], contains(cols[1]));
    }
  });
}
