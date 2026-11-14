/// What a Hausa speaker is asked to say, to build the recordings a Hausa
/// Guardian model needs (phase 3).
///
/// NEEDS A NATIVE SPEAKER'S REVIEW before recordings are collected: these
/// were written without one. Each prompt carries its English meaning so a
/// reviewer can check the Hausa says what is intended.
///
/// Two kinds, because a model must learn both:
/// - `sos`: distress, which Guardian must catch;
/// - `none`: everyday speech, including speech ABOUT danger and negated
///   danger, which Guardian must never send for.
///
/// The labels match tool/guardian_eval.dart, so the same recordings measure
/// the model once it exists.
library;

class RecordingPrompt {
  const RecordingPrompt(this.id, this.expect, this.hausa, this.english);

  /// Stable, used in file names.
  final String id;

  /// `sos` or `none`, as tool/guardian_eval.dart reads it.
  final String expect;
  final String hausa;
  final String english;
}

const List<RecordingPrompt> hausaPrompts = [
  // Distress: must send.
  RecordingPrompt('ha_sos_01', 'sos', 'Taimake ni! Suna son su kashe ni!', "Help me! They want to kill me!"),
  RecordingPrompt('ha_sos_02', 'sos', 'Za su kashe ni!', 'They are going to kill me!'),
  RecordingPrompt('ha_sos_03', 'sos', 'Don Allah kar ku kashe ni!', "Please don't kill me!"),
  RecordingPrompt('ha_sos_04', 'sos', 'An sace ni! Ku taimake ni!', "I've been kidnapped! Help me!"),
  RecordingPrompt('ha_sos_05', 'sos', 'Suna sace mu!', 'They are kidnapping us!'),
  RecordingPrompt('ha_sos_06', 'sos', 'Yana da bindiga, kar ka harbe ni!', "He has a gun, don't shoot me!"),
  RecordingPrompt('ha_sos_07', 'sos', 'Yana da wuka! Ku taimake ni!', 'He has a knife! Help me!'),
  RecordingPrompt('ha_sos_08', 'sos', 'Ku bar ni! Ku sake ni!', 'Leave me! Let me go!'),
  RecordingPrompt('ha_sos_09', 'sos', 'Wani ya taimake ni!', 'Somebody help me!'),
  RecordingPrompt('ha_sos_10', 'sos', 'Kar ku cuce ni, don Allah!', "Don't hurt me, please!"),
  // Everyday, and talk about danger: must not send.
  RecordingPrompt('ha_none_01', 'none', 'Ina kwana? Ya gida?', 'Good morning. How is the family?'),
  RecordingPrompt('ha_none_02', 'none', 'Za mu je kasuwa mu sayi tumatir da barkono.', "We're going to the market to buy tomatoes and pepper."),
  RecordingPrompt('ha_none_03', 'none', 'Ba wanda zai kashe ni, kwantar da hankalinka.', 'Nobody is going to kill me, calm down.'),
  RecordingPrompt('ha_none_04', 'none', 'Labarin fim din ya shafi satar mutane.', 'The film was about kidnapping.'),
  RecordingPrompt('ha_none_05', 'none', 'Na ji a labarai cewa an sace wani mutum jiya.', 'I heard on the news that a man was kidnapped yesterday.'),
  RecordingPrompt('ha_none_06', 'none', 'Don Allah ka mika min wukar in yanka doya.', 'Please pass me the knife so I can cut the yam.'),
  RecordingPrompt('ha_none_07', 'none', 'Ka taimake ni in dauki wannan kayan.', 'Help me carry this load.'),
  RecordingPrompt('ha_none_08', 'none', 'Wasan ya yi dadi, sun harba kwallo cikin raga.', 'The match was good, they shot the ball into the net.'),
];

/// The labels file for [rows], in the format tool/guardian_eval.dart reads:
/// `file,expect`, then the language and the prompt for the person training a
/// model. Commas inside a prompt are dropped so each row stays four columns.
String recordingLabelsCsv(List<(String file, RecordingPrompt prompt)> rows) {
  final b = StringBuffer('file,expect,lang,text\n');
  for (final (file, p) in rows) {
    b.writeln('$file,${p.expect},ha,${p.hausa.replaceAll(',', '')}');
  }
  return b.toString();
}
