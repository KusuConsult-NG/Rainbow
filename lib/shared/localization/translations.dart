import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppLanguage {
  english('en', 'English', 'EN 🇬🇧'),
  hausa('ha', 'Hausa', 'HA 🇳🇬'),
  pidgin('pcm', 'Pidgin', 'PG 🇳🇬');
  const AppLanguage(this.code, this.label, this.flagLabel);

  final String code;
  final String label;
  final String flagLabel;
}

class LanguageNotifier extends StateNotifier<AppLanguage> {
  LanguageNotifier() : super(AppLanguage.english) {
    unawaited(_loadLanguage());
  }

  Future<void> _loadLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString('app_lang') ?? 'en';
    state = AppLanguage.values.firstWhere(
      (l) => l.code == code,
      orElse: () => AppLanguage.english,
    );
  }

  Future<void> setLanguage(AppLanguage language) async {
    state = language;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('app_lang', language.code);
  }
}

final languageProvider = StateNotifierProvider<LanguageNotifier, AppLanguage>((ref) {
  return LanguageNotifier();
});

class Translations {
  static const Map<String, Map<AppLanguage, String>> _keys = {
    // Shown by `core/startup/startup_failure.dart` when the app cannot
    // start, or when a build threw. In a release build Flutter's own error
    // widget paints a pale rectangle with NO TEXT, which is the blank page an
    // installed APK opened to. These three strings are what replaces it, so
    // they are the only user-visible strings in the app that must render with
    // no Theme, no locale loaded and no provider scope alive.
    'startup_failed_title': {
      AppLanguage.english: 'Plateau Eye could not start',
      AppLanguage.hausa: 'Plateau Eye bai iya farawa ba',
      AppLanguage.pidgin: 'Plateau Eye no gree start',
    },
    'startup_failed_body': {
      AppLanguage.english:
          'This is a fault in the app, not in your phone. Tap Try Again. If it '
          'keeps happening, report the line below to the Plateau Eye team, and '
          'in an emergency call your local emergency number directly.',
      AppLanguage.hausa:
          'Wannan matsalar manhaja ce, ba ta wayarka ba. Danna Sake Gwadawa. '
          'Idan ya ci gaba, ka kai rahoton layin da ke ƙasa ga tawagar Plateau '
          'Eye, kuma a cikin gaggawa ka kira lambar gaggawa kai tsaye.',
      AppLanguage.pidgin:
          'Na the app get problem, no be your phone. Press Try Again. If e '
          'continue, send the line below to Plateau Eye team, and if e be '
          'emergency call your emergency number one time.',
    },
    'startup_failed_retry': {
      AppLanguage.english: 'TRY AGAIN',
      AppLanguage.hausa: 'SAKE GWADAWA',
      AppLanguage.pidgin: 'TRY AGAIN',
    },
    'choose_language': {
      AppLanguage.english: 'LANGUAGE',
      AppLanguage.hausa: 'HARSHE',
      AppLanguage.pidgin: 'LANGUAGE',
    },
    'choose_language_desc': {
      AppLanguage.english: 'Choose the language this app speaks to you in.',
      AppLanguage.hausa: 'Zabi harshen da wannan manhaja za ta yi maka magana.',
      AppLanguage.pidgin: 'Choose the language wey the app go talk to you.',
    },
    // REQUESTED BY dispatcher_chat_screen.dart AND NEVER DEFINED.
    //
    // `get()` returned the KEY on a miss, so the citizen's emergency chat
    // header read `live_dispatch_channel` and `alert_ref #a1b2c3d4` — in every
    // language, English included. `scripts/check_translation_keys.py` now
    // refuses a key that is asked for and not defined.
    'live_dispatch_channel': {
      AppLanguage.english: 'LIVE DISPATCH CHANNEL',
      AppLanguage.hausa: 'TASHAR TURA DAUKI KAI TSAYE',
      AppLanguage.pidgin: 'LIVE DISPATCH LINE',
    },
    'alert_ref': {
      AppLanguage.english: 'ALERT REF',
      AppLanguage.hausa: 'LAMARIN DAUKI',
      AppLanguage.pidgin: 'ALERT NUMBER',
    },
    // The app's own name, which is a proper noun and so reads the same in all
    // three. The rebrand changed the launcher label, the iOS bundle name and
    // the browser tab, and left this — the single most prominent line in the
    // app, at the top of the home screen.
    'title': {
      AppLanguage.english: 'PLATEAU EYE',
      AppLanguage.hausa: 'PLATEAU EYE',
      AppLanguage.pidgin: 'PLATEAU EYE',
    },
    'sos_button': {
      AppLanguage.english: 'TRIGGER SOS',
      AppLanguage.hausa: 'NEMI TAIMAKO',
      AppLanguage.pidgin: 'TAP FOR HELP',
    },
    'silent_sos': {
      AppLanguage.english: 'SILENT SOS',
      AppLanguage.hausa: 'TAIMAKO A DINGE',
      AppLanguage.pidgin: 'SILENT HELP',
    },
    'perm_allowed': {
      AppLanguage.english: 'ALLOWED',
      AppLanguage.hausa: 'AN BARI',
      AppLanguage.pidgin: 'E DON ALLOW',
    },
    'perm_not_yet_required': {
      AppLanguage.english: 'NOT YET \u00b7 REQUIRED',
      AppLanguage.hausa: 'BA TUKUNA \u00b7 DOLE NE',
      AppLanguage.pidgin: 'NEVER YET \u00b7 E MUST DEY',
    },
    'perm_not_yet_optional': {
      AppLanguage.english: 'NOT YET \u00b7 OPTIONAL',
      AppLanguage.hausa: 'BA TUKUNA \u00b7 ZABI NE',
      AppLanguage.pidgin: 'NEVER YET \u00b7 NA YOUR CHOICE',
    },
    'volume_sos_title': {
      AppLanguage.english: 'Volume Down \u00d73 sends a silent SOS',
      AppLanguage.hausa: 'Danna rage sauti sau 3 don SOS a boye',
      AppLanguage.pidgin: 'Press volume down 3 times to send silent SOS',
    },
    'sos_tap_three': {
      AppLanguage.english: 'TAP 3 TIMES',
      AppLanguage.hausa: 'DANNA SAU 3',
      AppLanguage.pidgin: 'TAP AM 3 TIMES',
    },
    'safe_zone': {
      AppLanguage.english: 'SAFE ZONES',
      AppLanguage.hausa: 'SASHEN TSIRA',
      AppLanguage.pidgin: 'SAFE AREA DEM',
    },
    'report_incident': {
      AppLanguage.english: 'REPORT INCIDENT',
      AppLanguage.hausa: 'KAI RAHOTO',
      AppLanguage.pidgin: 'REPORT GBEGE',
    },
    'tap_to_trigger': {
      AppLanguage.english: 'TAP TO TRIGGER SOS ALERT',
      AppLanguage.hausa: 'DANNA DOMIN NEMEN DAUKI',
      AppLanguage.pidgin: 'PRESS TO SEND HELP ALERT',
    },
    'silent_desc': {
      AppLanguage.english: 'Discreet background escalation',
      AppLanguage.hausa: 'Neman dauki a asirce ba tare da sanewa ba',
      AppLanguage.pidgin: 'Alert background low-key style',
    },
    'safe_desc': {
      AppLanguage.english: 'Locate nearby secure zones',
      AppLanguage.hausa: 'Nemo sashen tsira mafi kusa da kai',
      AppLanguage.pidgin: 'Find safe camp near you',
    },
    'report_desc': {
      AppLanguage.english: 'Submit non-emergency reports',
      AppLanguage.hausa: 'Tura rahotannin da basu gaggawa ba',
      AppLanguage.pidgin: 'Send info for things wey happen',
    },
    'late_night': {
      AppLanguage.english: 'LATE NIGHT · VIGILANCE MODE',
      AppLanguage.hausa: 'CIGABAN DARE · MATSALAR TSARO',
      AppLanguage.pidgin: 'LATE NIGHT · EYE OPEN MODE',
    },
    'good_morning': {
      AppLanguage.english: 'GOOD MORNING · SYSTEMS READY',
      AppLanguage.hausa: 'BARKA DA SAFARA · SASHEN A SHIRYAYE',
      AppLanguage.pidgin: 'MORNING AM · SYSTEM STANDBY',
    },
    'good_afternoon': {
      AppLanguage.english: 'GOOD AFTERNOON · ALL CLEAR',
      AppLanguage.hausa: 'BARKA DA RANA · KAI TSAYE KAFIN HUKUMA',
      AppLanguage.pidgin: 'GOOD AFTERNOON · NO WAHALA',
    },
    'good_evening': {
      AppLanguage.english: 'GOOD EVENING · SECURE PERIMETER',
      AppLanguage.hausa: 'BARKA DA YAMMA · KARFE DA TSARO',
      AppLanguage.pidgin: 'GOOD EVENING · KEEP SECURITY TIGHT',
    },
    'silent_sos_active': {
      AppLanguage.english: 'SILENT SOS ACTIVATED · SURVEILLANCE ACTIVE',
      AppLanguage.hausa: 'TAIMAKON ASIRCE YA SHIGA · ANA CIGABAN SA IDO',
      AppLanguage.pidgin: 'SILENT HELP DEY ACTIVE · WE DEY WATCH YOU NOW',
    },
    'patrol_active': {
      AppLanguage.english: 'PATROL ACTIVE',
      AppLanguage.hausa: 'KAYAN TSARO A SHIRYE',
      AppLanguage.pidgin: 'PATROL ACTIVE NOW',
    },
    'system_nominal': {
      AppLanguage.english: 'SYSTEM NOMINAL',
      AppLanguage.hausa: 'TSARI LAFIYA LAFIYA',
      AppLanguage.pidgin: 'SYSTEM DEY ALRIGHT',
    },
    'telemetry_stable': {
      AppLanguage.english: 'TELEMETRY UPLINK STABLE',
      AppLanguage.hausa: 'HUKUNCIN SADA ZUMUNTA YANA DA KYAU',
      AppLanguage.pidgin: 'TELEMERY CONNECTION STABLE',
    },
    'activate_patrol': {
      AppLanguage.english: 'ACTIVATE PATROL MODE',
      AppLanguage.hausa: 'KAI MAI TSARO TSAFI',
      AppLanguage.pidgin: 'START PATROL MODE',
    },
    'end_patrol': {
      AppLanguage.english: 'END PATROL MISSION',
      AppLanguage.hausa: 'KASHE MAI TSARO',
      AppLanguage.pidgin: 'STOP PATROL MISSION',
    },
    // AI VOICE & DUAL BUTTONS
    'ai_report': {
      AppLanguage.english: 'AI REPORT',
      AppLanguage.hausa: 'RAHOTON AI',
      AppLanguage.pidgin: 'AI VOICE REPORT',
    },
    'speak_to_report': {
      AppLanguage.english: 'SPEAK TO REPORT',
      AppLanguage.hausa: 'YI MAGANA MAI RAHOTO',
      AppLanguage.pidgin: 'TALK TO REPORT',
    },
    'listening_speak_now': {
      AppLanguage.english: 'LISTENING / SPEAK NOW',
      AppLanguage.hausa: 'ANA SAURARO / YI MAGANA YANZU',
      AppLanguage.pidgin: 'DEY LISTEN / TALK NOW',
    },
    'tap_to_record_again': {
      AppLanguage.english: 'TAP TO RECORD AGAIN',
      AppLanguage.hausa: 'DANNA DOMIN SAKE MAGANA',
      AppLanguage.pidgin: 'TAP TO TALK AGAIN',
    },
    'cancel': {
      AppLanguage.english: 'CANCEL',
      AppLanguage.hausa: 'KASHE',
      AppLanguage.pidgin: 'CANCEL',
    },
    'submit_report': {
      AppLanguage.english: 'SUBMIT REPORT',
      AppLanguage.hausa: 'TURA RAHOTO',
      AppLanguage.pidgin: 'SUBMIT REPORT',
    },
    'ai_triaging_incident': {
      AppLanguage.english: 'AI TRIAGING INCIDENT...',
      AppLanguage.hausa: 'AI ANA BINCIKEN MATSALAR...',
      AppLanguage.pidgin: 'AI DEY CHECK WAHALA...',
    },
    'classifying_details': {
      AppLanguage.english: 'Classifying category & priority',
      AppLanguage.hausa: 'Raba rukuni da gaggawa',
      AppLanguage.pidgin: 'De check category and priority',
    },
    'success_toast': {
      AppLanguage.english: 'AI REPORT SUBMITTED SUCCESSFULLY',
      AppLanguage.hausa: 'RAHOTON AI AN GABATAR LAFIYA',
      AppLanguage.pidgin: 'AI REPORT SUBMITTED WELL WELL',
    },
    'no_voice_input': {
      AppLanguage.english: 'No voice input recorded.',
      AppLanguage.hausa: 'Babu kalmomin da aka nada.',
      AppLanguage.pidgin: 'No voice input recorded.',
    },
    // The microphone is not available, which is a different thing from having
    // said nothing — and the person it happens to cannot type, so the wording
    // has to tell them what to do instead.
    'voice_note_unavailable': {
      AppLanguage.english:
          'This phone has not given Plateau Eye access to the '
          'microphone, so your voice cannot be recorded. Allow it in your '
          'phone settings, or send a photo instead.',
      AppLanguage.hausa:
          'Wannan wayar ba ta ba Plateau Eye damar amfani da makirufo '
          'ba, don haka ba za a iya naɗa muryar ka ba. Ba da izini a cikin '
          'saitunan wayar, ko ka aika hoto maimakon haka.',
      AppLanguage.pidgin:
          'Dis phone no gree give Plateau Eye access to di microphone, '
          'so we no go fit record your voice. Allow am inside your phone '
          'settings, abi send picture instead.',
    },
    'voice_note_recorded': {
      AppLanguage.english: 'Voice note recorded',
      AppLanguage.hausa: 'An naɗa saƙon murya',
      AppLanguage.pidgin: 'We don record your voice note',
    },
    'play_voice_note': {
      AppLanguage.english: 'Play the voice note',
      AppLanguage.hausa: 'Kunna saƙon murya',
      AppLanguage.pidgin: 'Play di voice note',
    },
    'sample_speech_prompt': {
      AppLanguage.english: 'Say something like: "Violent crash on Bauchi '
          'Road..."',
      AppLanguage.hausa: 'Fadi wani abu kamar: "Hadari mai tsanani a Bauchi '
          'Road..."',
      AppLanguage.pidgin: 'Talk something like: "Violent crash on Bauchi '
          'Road..."',
    },
    'error_initialize': {
      AppLanguage.english: 'Could not initialize speech recognition.',
      AppLanguage.hausa: 'Ba a iya fara gano murya ba.',
      AppLanguage.pidgin: 'Could not start voice recognition.',
    },
    // CHAT SCREEN
    'chat_title': {
      AppLanguage.english: 'DISPATCHER CHAT',
      AppLanguage.hausa: 'HIRA DA RESCUERS',
      AppLanguage.pidgin: 'DISPATCHER CHAT',
    },
    'chat_subtitle': {
      AppLanguage.english: 'LIVE HQ SUPPORT',
      AppLanguage.hausa: 'TAIMAKON HQ NA TAFIYA',
      AppLanguage.pidgin: 'LIVE HQ SUPPORT',
    },
    'chat_placeholder': {
      AppLanguage.english: 'HQ IS MONITORING. TYPE TO BEGIN.',
      AppLanguage.hausa: 'HQ ANA SA IDO. RUBUTA DOMIN FARAWA.',
      AppLanguage.pidgin: 'HQ DEY WATCH. WRITE TO START.',
    },
    // REPORT FLOW
    'incident_protocol': {
      AppLanguage.english: 'INCIDENT PROTOCOL',
      AppLanguage.hausa: 'TSARIN RAHOTO',
      AppLanguage.pidgin: 'GBEGE PROTOCOL',
    },
    'select_category_subtitle': {
      AppLanguage.english: 'SELECT CATEGORY FOR TACTICAL REPORT',
      AppLanguage.hausa: 'ZABI RUKUNI DON RAHOTON AIKI',
      AppLanguage.pidgin: 'PICK CATEGORY FOR THIS REPORT',
    },
    'select_category_desc': {
      AppLanguage.english: 'SELECT THE CATEGORY THAT BEST DESCRIBES THE '
          'CURRENT EMERGENCY. LOCATION TELEMETRY IS AUTO-ATTACHED.',
      AppLanguage.hausa: 'ZABI RUKUNIN DA YA FI DACHEWA DA MATSALAR. ANA HADA '
          'TELEMETRY TA KAI TSAYE.',
      AppLanguage.pidgin: 'SELECT CATEGORY WEY FIT DE DESCRIBE WAHALA. '
          'LOCATION DE AUTOMATICALLY ATTACH.',
    },
    'available_categories': {
      AppLanguage.english: 'AVAILABLE CATEGORIES',
      AppLanguage.hausa: 'RUKUNAN DA AKE SAMU',
      AppLanguage.pidgin: 'CATEGORIES WEY DEY GROUND',
    },
    'operational_subtypes': {
      AppLanguage.english: 'OPERATIONAL SUBTYPES',
      AppLanguage.hausa: 'KASHIN OPERATIONAL',
      AppLanguage.pidgin: 'OPERATIONAL SUBTYPES',
    },

    // ── Shared across screens ────────────────────────────────────────────
    'close': {
      AppLanguage.english: 'Close',
      AppLanguage.hausa: 'Rufe',
      AppLanguage.pidgin: 'Close',
    },
    'not_available': {
      AppLanguage.english: 'N/A',
      AppLanguage.hausa: 'BABU',
      AppLanguage.pidgin: 'N/A',
    },

    // ─────────────────────────────────────────────────────────────────
    // THE CITIZEN'S EMERGENCY PATH.
    //
    // Added for the four screens a person walks through while something is
    // happening: the situation chooser, the subtype, the live SOS screen and
    // the confirmation. Before this the picker worked, persisted and was
    // reachable from two places — and then every one of these screens spoke
    // English regardless, because only five files in the app asked this table
    // for anything.
    //
    // NOT in here, on purpose: 'PENDING', 'DISPATCHED', 'ACKNOWLEDGED',
    // 'ON_ROUTE', 'ON_SITE' and 'RESOLVED'. Those look like labels on this
    // screen and they are DATA — `alert['status']` compared by string, from
    // the database. Translating one would silently stop the status matching
    // and leave a citizen's screen reading LOCATION BROADCASTING while a
    // squad was standing next to them.
    // ─────────────────────────────────────────────────────────────────
    'rpt_situation_report': {
      AppLanguage.english: 'SITUATION REPORT',
      AppLanguage.hausa: 'RAHOTON YANAYI',
      AppLanguage.pidgin: 'SITUATION REPORT',
    },
    'rpt_what_situation': {
      AppLanguage.english: 'What is the\nsituation?',
      AppLanguage.hausa: 'Mene ne\nya faru?',
      AppLanguage.pidgin: 'Wetin dey\nhappen?',
    },
    'rpt_pick_category': {
      AppLanguage.english: 'Select the most accurate category to ensure rapid '
          'response deployment.',
      AppLanguage.hausa: "Zabi nau'in da ya fi dacewa domin a tura dauki da "
          "sauri.",
      AppLanguage.pidgin: 'Pick the category wey correct well, so help go '
          'reach you sharp sharp.',
    },
    'rpt_threat_to_life': {
      AppLanguage.english: 'THREAT TO LIFE',
      AppLanguage.hausa: 'HATSARI GA RAI',
      AppLanguage.pidgin: 'DANGER TO LIFE',
    },
    'rpt_threat_to_life_desc': {
      AppLanguage.english: 'Immediate danger to persons',
      AppLanguage.hausa: 'Hatsari da ke gaban mutane yanzu',
      AppLanguage.pidgin: 'Person dey in danger right now',
    },
    'rpt_criminal_activity': {
      AppLanguage.english: 'CRIMINAL ACTIVITY',
      AppLanguage.hausa: 'AIKIN LAIFI',
      AppLanguage.pidgin: 'CRIME DEY HAPPEN',
    },
    'rpt_criminal_activity_desc': {
      AppLanguage.english: 'Ongoing or witnessed crime',
      AppLanguage.hausa: 'Laifin da ake yi ko wanda ka gani',
      AppLanguage.pidgin: 'Crime wey dey happen or wey you see',
    },
    'rpt_suspicious_activity': {
      AppLanguage.english: 'SUSPICIOUS ACTIVITY',
      AppLanguage.hausa: 'ABU MAI TUHUMA',
      AppLanguage.pidgin: 'SOMETHING SUSPICIOUS',
    },
    'rpt_suspicious_activity_desc': {
      AppLanguage.english: 'Something feels wrong',
      AppLanguage.hausa: 'Wani abu bai yi daidai ba',
      AppLanguage.pidgin: 'Something no just correct',
    },
    'rpt_civil_hazard': {
      AppLanguage.english: 'CIVIL HAZARD',
      AppLanguage.hausa: "HATSARIN JAMA'A",
      AppLanguage.pidgin: 'PUBLIC DANGER',
    },
    'rpt_civil_hazard_desc': {
      AppLanguage.english: 'Environmental or infrastructure risk',
      AppLanguage.hausa: 'Hatsarin muhalli ko na gine-gine',
      AppLanguage.pidgin: 'Danger from environment or bad structure',
    },
    'rpt_showing_some': {
      AppLanguage.english: 'Showing {n} of {total} categories for this situation.',
      AppLanguage.hausa: 'Ana nuna nau\'i {n} cikin {total} na wannan yanayi.',
      AppLanguage.pidgin: 'Na {n} for the {total} type wey match dis matter.',
    },
    'rpt_show_all_categories': {
      AppLanguage.english: 'SHOW ALL',
      AppLanguage.hausa: 'NUNA DUKA',
      AppLanguage.pidgin: 'SHOW AM ALL',
    },
    'rpt_protocol': {
      AppLanguage.english: 'REPORT PROTOCOL',
      AppLanguage.hausa: 'TSARIN RAHOTO',
      AppLanguage.pidgin: 'REPORT STEPS',
    },
    'rpt_select_specific': {
      AppLanguage.english: 'SELECT SPECIFIC INCIDENT TYPE',
      AppLanguage.hausa: "ZABI AINIHIN NAU'IN LAMARI",
      AppLanguage.pidgin: 'PICK THE EXACT TYPE',
    },
    'rpt_tactical_category': {
      AppLanguage.english: 'TACTICAL CATEGORY',
      AppLanguage.hausa: "NAU'IN LAMARI",
      AppLanguage.pidgin: 'CATEGORY',
    },
    'rpt_change': {
      AppLanguage.english: 'CHANGE',
      AppLanguage.hausa: 'CANZA',
      AppLanguage.pidgin: 'CHANGE',
    },
    'rpt_identify_type': {
      AppLanguage.english: 'IDENTIFY INCIDENT TYPE',
      AppLanguage.hausa: "BAYYANA NAU'IN LAMARI",
      AppLanguage.pidgin: 'SAY WETIN HAPPEN',
    },
    'rpt_identification_required': {
      AppLanguage.english: 'IDENTIFICATION REQUIRED',
      AppLanguage.hausa: 'AKWAI BUKATAR BAYYANAWA',
      AppLanguage.pidgin: 'YOU MUST PICK ONE',
    },
    'rpt_initiate': {
      AppLanguage.english: 'INITIATE TACTICAL REPORT',
      AppLanguage.hausa: 'FARA RAHOTO',
      AppLanguage.pidgin: 'START THE REPORT',
    },
    'rpt_queued_locally': {
      AppLanguage.english: 'REPORT QUEUED LOCALLY',
      AppLanguage.hausa: 'AN AJIYE RAHOTO A WAYA',
      AppLanguage.pidgin: 'REPORT DEY WAIT INSIDE PHONE',
    },
    'rpt_transmitted': {
      AppLanguage.english: 'REPORT TRANSMITTED',
      AppLanguage.hausa: 'AN TURA RAHOTO',
      AppLanguage.pidgin: 'REPORT DONE SEND',
    },
    'rpt_reference_id': {
      AppLanguage.english: 'Incident Reference ID:',
      AppLanguage.hausa: 'Lambar Lamarin:',
      AppLanguage.pidgin: 'Incident Reference ID:',
    },
    'rpt_queued_offline': {
      AppLanguage.english: 'QUEUED IN OFFLINE STORAGE',
      AppLanguage.hausa: 'AN AJIYE SHI YAYIN DA BABU NET',
      AppLanguage.pidgin: 'E DEY SAVE TILL NETWORK COME',
    },
    'rpt_received_by_command': {
      AppLanguage.english: 'RECEIVED BY COMMAND CENTER',
      AppLanguage.hausa: 'CIBIYAR UMARNI TA KARBA',
      AppLanguage.pidgin: 'COMMAND CENTER DONE RECEIVE AM',
    },
    'rpt_report_another': {
      AppLanguage.english: 'REPORT ANOTHER',
      AppLanguage.hausa: 'KAI WANI RAHOTO',
      AppLanguage.pidgin: 'REPORT ANOTHER ONE',
    },
    'rpt_return_to_map': {
      AppLanguage.english: 'RETURN TO MAP',
      AppLanguage.hausa: 'KOMA TAswIRA',
      AppLanguage.pidgin: 'GO BACK TO MAP',
    },
    'eme_active': {
      AppLanguage.english: 'EMERGENCY ACTIVE',
      AppLanguage.hausa: 'GAGGAWA NA GUDANA',
      AppLanguage.pidgin: 'EMERGENCY DEY ON',
    },
    'eme_live_telemetry': {
      AppLanguage.english: 'LIVE TELEMETRY',
      AppLanguage.hausa: 'BAYANAI KAI TSAYE',
      AppLanguage.pidgin: 'LIVE INFO',
    },
    'eme_link_establishing': {
      AppLanguage.english: 'Establishing tactical data link...',
      AppLanguage.hausa: 'Ana kafa hanyar tura bayanai...',
      AppLanguage.pidgin: 'We dey connect...',
    },
    'eme_signal_established': {
      AppLanguage.english: 'SIGNAL ESTABLISHED',
      AppLanguage.hausa: 'AN SAMU SIGINA',
      AppLanguage.pidgin: 'SIGNAL DEY WORK',
    },
    'eme_squad_dispatched': {
      AppLanguage.english: 'SQUAD DISPATCHED',
      AppLanguage.hausa: "AN TURA JAMI'AI",
      AppLanguage.pidgin: 'TEAM DONE DEY COME',
    },
    'eme_squad_dispatched_desc': {
      AppLanguage.english: 'Tactical team dispatched to your location',
      AppLanguage.hausa: "An tura jami'ai zuwa wurin da kake",
      AppLanguage.pidgin: 'Dem send team go your place',
    },
    'eme_en_route': {
      AppLanguage.english: 'RESPONDERS EN ROUTE',
      AppLanguage.hausa: "JAMI'AI NA KAN HANYA",
      AppLanguage.pidgin: 'TEAM DEY ROAD',
    },
    'eme_en_route_desc': {
      AppLanguage.english: 'Units en route to your position',
      AppLanguage.hausa: "Jami'ai na kan hanya zuwa wurinka",
      AppLanguage.pidgin: 'Dem dey on the way come meet you',
    },
    'eme_on_site': {
      AppLanguage.english: 'RESPONDERS ON SITE',
      AppLanguage.hausa: "JAMI'AI SUN ISO",
      AppLanguage.pidgin: 'TEAM DONE REACH',
    },
    'eme_on_site_desc': {
      AppLanguage.english: 'Tactical team arrived at your location',
      AppLanguage.hausa: "Jami'ai sun isa wurin da kake",
      AppLanguage.pidgin: 'Team done reach your place',
    },
    'eme_secured': {
      AppLanguage.english: 'INCIDENT SECURED',
      AppLanguage.hausa: 'AN SHAWO KAN LAMARIN',
      AppLanguage.pidgin: 'EVERYTHING DONE SETTLE',
    },
    'eme_secured_desc': {
      AppLanguage.english: 'Emergency resolved and area secured',
      AppLanguage.hausa: 'An kammala gaggawar kuma wurin ya tsira',
      AppLanguage.pidgin: 'The emergency done finish, area safe',
    },
    'eme_broadcasting': {
      AppLanguage.english: 'LOCATION BROADCASTING',
      AppLanguage.hausa: 'ANA TURA WURINKA',
      AppLanguage.pidgin: 'DEM DEY SEE YOUR LOCATION',
    },
    'eme_broadcasting_triaging': {
      AppLanguage.english: 'Alert transmitted · Command HQ triaging...',
      AppLanguage.hausa: 'An tura kiran dauki · Cibiyar umarni na duba shi...',
      AppLanguage.pidgin: 'Alert done go · Command HQ dey check am...',
    },
    'eme_sending': {
      AppLanguage.english: 'SENDING ALERT',
      AppLanguage.hausa: 'ANA TURA KIRAN DAUKI',
      AppLanguage.pidgin: 'WE DEY SEND ALERT',
    },
    'eme_sending_desc': {
      AppLanguage.english: 'Sending your alert and location to HQ...',
      AppLanguage.hausa: 'Ana tura kiran dauki da wurinka zuwa cibiyar umarni...',
      AppLanguage.pidgin: 'We dey send your alert and where you dey go HQ...',
    },
    'eme_received': {
      AppLanguage.english: 'ALERT RECEIVED',
      AppLanguage.hausa: 'AN KARBI KIRAN DAUKI',
      AppLanguage.pidgin: 'HQ DON GET THE ALERT',
    },
    'eme_not_confirmed': {
      AppLanguage.english: 'NOT CONFIRMED BY HQ YET',
      AppLanguage.hausa: 'CIBIYAR UMARNI BA TA TABBATAR BA TUKUNA',
      AppLanguage.pidgin: 'HQ NEVER CONFIRM AM YET',
    },
    'eme_not_confirmed_desc': {
      AppLanguage.english: 'Saved on this phone and retrying when there is a connection. Your location is still being recorded.',
      AppLanguage.hausa: 'An ajiye a wayar nan, za a sake turawa idan an samu sadarwa. Ana ci gaba da daukar wurinka.',
      AppLanguage.pidgin: 'E dey save for this phone and e go send again when network come. We still dey record where you dey.',
    },
    // ---- No GPS fix: what the emergency screen says instead -----------
    //
    // Every string above this comment promises a location: "LOCATION
    // BROADCASTING", "Sending your alert AND LOCATION to HQ", "Your location
    // is still being recorded". The screen showed them whether or not the
    // phone had a fix, because the banner was driven by the alert's status
    // alone and never looked at the position. A person with location refused
    // or switched off read LOCATION BROADCASTING over a row of dashes, and had
    // no way to know HQ had been given nothing to go to.
    //
    // These are the same states told truthfully. Hausa and Pidgin want a
    // native speaker's eye before release.
    'eme_no_fix_title': {
      AppLanguage.english: 'NO LOCATION BEING SENT',
      AppLanguage.hausa: 'BA A TURA WURINKA',
      AppLanguage.pidgin: 'DEM NO DEY SEE WHERE YOU DEY',
    },
    'eme_no_fix_body': {
      AppLanguage.english: 'HQ has your alert, but not your position. Turn on location, or tell them where you are by call or SMS.',
      AppLanguage.hausa: 'Cibiyar umarni na da kiran daukin ka, amma ba ta san inda kake ba. Kunna GPS, ko ka gaya musu inda kake da waya ko SMS.',
      AppLanguage.pidgin: 'HQ get your alert, but dem no know where you dey. On location, or call or SMS dem make you tell dem where you dey.',
    },
    'eme_no_fix_action': {
      AppLanguage.english: 'TURN ON LOCATION',
      AppLanguage.hausa: 'KUNNA GPS',
      AppLanguage.pidgin: 'ON LOCATION',
    },
    'eme_no_fix_open_settings': {
      AppLanguage.english: 'OPEN APP SETTINGS',
      AppLanguage.hausa: 'BUDE SAITUNAN MANHAJA',
      AppLanguage.pidgin: 'OPEN APP SETTINGS',
    },
    'eme_no_fix_blocked': {
      AppLanguage.english: 'Location is blocked for this app. Allow it in app settings, then come back.',
      AppLanguage.hausa: 'An hana wannan manhaja amfani da GPS. Ka ba da izini a saitunan manhaja, sannan ka dawo.',
      AppLanguage.pidgin: 'Location dey block for this app. Allow am for app settings, then come back.',
    },
    'eme_sending_desc_no_fix': {
      AppLanguage.english: 'Sending your alert to HQ. It carries no location.',
      AppLanguage.hausa: 'Ana tura kiran daukin ka zuwa cibiyar umarni. Ba shi da inda kake.',
      AppLanguage.pidgin: 'We dey send your alert go HQ. E no carry where you dey.',
    },
    'eme_active_no_fix': {
      AppLanguage.english: 'ALERT ACTIVE · NO LOCATION',
      AppLanguage.hausa: 'KIRAN DAUKI NA AIKI · BABU WURI',
      AppLanguage.pidgin: 'ALERT DEY ACTIVE · NO LOCATION',
    },
    'eme_triaging_no_fix': {
      AppLanguage.english: 'Alert transmitted · no location attached · HQ triaging...',
      AppLanguage.hausa: 'An tura kiran dauki · babu inda kake a ciki · cibiyar umarni na duba shi...',
      AppLanguage.pidgin: 'Alert done go · but where you dey no dey inside · HQ dey check am...',
    },
    'eme_not_confirmed_desc_no_fix': {
      AppLanguage.english: 'Saved on this phone and retrying when there is a connection. No location has been recorded.',
      AppLanguage.hausa: 'An ajiye a wayar nan, za a sake turawa idan an samu sadarwa. Ba a dauki inda kake ba.',
      AppLanguage.pidgin: 'E dey save for this phone and e go send again when network come. We no record where you dey.',
    },
    'eme_scanning': {
      AppLanguage.english: 'SCANNING FOR SIGNAL...',
      AppLanguage.hausa: 'ANA NEMAN SIGINA...',
      AppLanguage.pidgin: 'WE DEY FIND SIGNAL...',
    },
    'eme_latitude': {
      AppLanguage.english: 'LATITUDE',
      AppLanguage.hausa: 'LATITUDE',
      AppLanguage.pidgin: 'LATITUDE',
    },
    'eme_longitude': {
      AppLanguage.english: 'LONGITUDE',
      AppLanguage.hausa: 'LONGITUDE',
      AppLanguage.pidgin: 'LONGITUDE',
    },
    'eme_accuracy': {
      AppLanguage.english: 'ACCURACY',
      AppLanguage.hausa: 'DAIDAITO',
      AppLanguage.pidgin: 'ACCURACY',
    },
    'eme_verifying_safety': {
      AppLanguage.english: 'VERIFYING SAFETY...',
      AppLanguage.hausa: 'ANA TABBATAR DA TSIRA...',
      AppLanguage.pidgin: 'WE DEY CONFIRM SAY YOU SAFE...',
    },
    'eme_hold_to_cancel': {
      AppLanguage.english: 'HOLD TO CANCEL SOS',
      AppLanguage.hausa: 'RIKE DOMIN SOKE KIRAN DAUKI',
      AppLanguage.pidgin: 'HOLD AM TO CANCEL SOS',
    },
    'eme_security_verification': {
      AppLanguage.english: 'SECURITY VERIFICATION',
      AppLanguage.hausa: 'TABBATAR DA TSARO',
      AppLanguage.pidgin: 'SECURITY CHECK',
    },
    'eme_enter_pin': {
      AppLanguage.english: 'Enter tactical PIN to confirm safety status',
      AppLanguage.hausa: 'Shigar da PIN domin tabbatar da cewa kana lafiya',
      AppLanguage.pidgin: 'Enter your PIN make we know say you safe',
    },
    'eme_no_pin_set': {
      AppLanguage.english: 'No emergency PIN is set for this account. ',
      AppLanguage.hausa: 'Ba a saita PIN na gaggawa ga wannan asusu ba. ',
      AppLanguage.pidgin: 'No emergency PIN dey for this account. ',
    },
    'eme_set_pin_hint': {
      AppLanguage.english: 'Set one under Settings → Emergency PIN.',
      AppLanguage.hausa: 'Ka saita daya a Settings → Emergency PIN.',
      AppLanguage.pidgin: 'Go set one for Settings → Emergency PIN.',
    },
    'eme_pin_locked': {
      AppLanguage.english: 'Too many attempts. PIN entry is locked for 15 '
          'minutes.',
      AppLanguage.hausa: 'An yi kokari da yawa. An kulle shigar da PIN na '
          'minti 15.',
      AppLanguage.pidgin: 'You try too many times. PIN lock for 15 minutes.',
    },
    'eme_pin_unverified': {
      AppLanguage.english: 'Could not verify the PIN — check your connection '
          'and try again.',
      AppLanguage.hausa: 'An kasa tabbatar da PIN — duba yanar gizonka ka sake '
          'gwadawa.',
      AppLanguage.pidgin: 'We no fit check the PIN — check your network and '
          'try again.',
    },
    'eme_awaiting_dispatch_link': {
      AppLanguage.english: 'AWAITING DISPATCH LINK',
      AppLanguage.hausa: 'ANA JIRAN HANYAR TURA DAUKI',
      AppLanguage.pidgin: 'WE DEY WAIT FOR DISPATCH LINE',
    },
    'eme_contact_dispatcher': {
      AppLanguage.english: 'CONTACT HQ DISPATCHER',
      AppLanguage.hausa: 'TUNTUBI MAI TURA DAUKI',
      AppLanguage.pidgin: 'TALK TO HQ DISPATCHER',
    },
    'eme_photo_evidence': {
      AppLanguage.english: 'PHOTO EVIDENCE',
      AppLanguage.hausa: 'HOTON SHAIDA',
      AppLanguage.pidgin: 'PHOTO EVIDENCE',
    },
    'eme_capturing': {
      AppLanguage.english: 'CAPTURING...',
      AppLanguage.hausa: 'ANA DAUKAR HOTO...',
      AppLanguage.pidgin: 'E DEY SNAP...',
    },
    'eme_broadcast_live': {
      AppLanguage.english: 'BROADCAST LIVE',
      AppLanguage.hausa: 'WATSA KAI TSAYE',
      AppLanguage.pidgin: 'GO LIVE',
    },
    'eme_stop_stream': {
      AppLanguage.english: 'STOP STREAM',
      AppLanguage.hausa: 'DAINA WATSAWA',
      AppLanguage.pidgin: 'STOP THE LIVE',
    },
    'eme_wait_before_stream': {
      AppLanguage.english: 'Wait for SOS alert confirmation before streaming '
          'live.',
      AppLanguage.hausa: 'Ka jira tabbatar da kiran dauki kafin ka fara '
          'watsawa kai tsaye.',
      AppLanguage.pidgin: 'Wait till SOS alert confirm before you go live.',
    },
    // The honest state between pressing the button and HQ receiving anything.
    //
    // There was no such string, because the screen had no such state: it went
    // straight from "off" to a red BROADCASTING LIVE TO HQ on the strength of
    // an offer having been sent. With no TURN relay configured that offer often
    // leads nowhere, and the person was told otherwise. T-96.
    'eme_stream_connecting': {
      AppLanguage.english: 'CONNECTING TO HQ — NOT LIVE YET',
      AppLanguage.hausa: 'ANA HADA DA HQ — BAI FARA BA TUKUNA',
      AppLanguage.pidgin: 'E DEY CONNECT TO HQ — E NO DEY LIVE YET',
    },
    'eme_stream_failed': {
      AppLanguage.english: 'Failed to start live stream',
      AppLanguage.hausa: 'An kasa fara watsawa kai tsaye',
      AppLanguage.pidgin: 'Live stream no gree start',
    },

    // REPORT DETAILS SCREEN
    'rpt_camera_denied': {
      AppLanguage.english:
          'This phone has not given Plateau Eye access to the camera. '
          'You can still send the report without a photo.',
      AppLanguage.hausa:
          'Wannan wayar ba ta ba Plateau Eye damar amfani da kyamara ba. '
          'Za ka iya tura rahoton ba tare da hoto ba.',
      AppLanguage.pidgin:
          'Dis phone no give Plateau Eye access to camera. '
          'You still fit send the report without photo.',
    },
    'rpt_attachment_failed': {
      AppLanguage.english:
          'That did not work on this phone. You can still send the report '
          'without an attachment.',
      AppLanguage.hausa:
          'Wannan bai yi aiki a wannan wayar ba. Za ka iya tura rahoton ba tare '
          'da abin da aka makala ba.',
      AppLanguage.pidgin:
          'Dat one no work for this phone. You still fit send the report '
          'without attachment.',
    },
    'rpt_mic_denied': {
      AppLanguage.english:
          'This phone has not given Plateau Eye access to the '
          'microphone. You can still type your report.',
      AppLanguage.hausa:
          'Wannan wayar ba ta ba Plateau Eye damar amfani da makirufo ba. '
          'Za ka iya rubuta rahotonka.',
      AppLanguage.pidgin:
          'Dis phone no give Plateau Eye access to microphone. '
          'You still fit type your report.',
    },
    'rpt_recorder_failed': {
      AppLanguage.english:
          'The voice recorder did not start on this phone. You can still '
          'type your report.',
      AppLanguage.hausa:
          "Na'urar daukar murya ba ta fara aiki a wannan wayar ba. Za ka iya "
          'rubuta rahotonka.',
      AppLanguage.pidgin:
          'Voice recorder no start for this phone. You still fit type your '
          'report.',
    },
    'rpt_no_narrative': {
      AppLanguage.english: 'No narrative provided',
      AppLanguage.hausa: 'Babu bayanin da aka bayar',
      AppLanguage.pidgin: 'No story dey here',
    },
    'rpt_incident_dossier': {
      AppLanguage.english: 'INCIDENT DOSSIER',
      AppLanguage.hausa: 'BAYANAN LAMARI',
      AppLanguage.pidgin: 'INCIDENT REPORT FILE',
    },
    'rpt_compile_tactical_data': {
      AppLanguage.english: 'COMPILE TACTICAL DATA',
      AppLanguage.hausa: 'TATTARA BAYANAN AIKI',
      AppLanguage.pidgin: 'GATHER ALL INFORMATION',
    },
    'rpt_transmitting_for': {
      AppLanguage.english: 'TRANSMITTING REPORT FOR',
      AppLanguage.hausa: 'ANA TURA RAHOTON DOMIN',
      AppLanguage.pidgin: 'DEY SEND REPORT FOR',
    },
    'rpt_mission_narrative': {
      AppLanguage.english: 'MISSION NARRATIVE',
      AppLanguage.hausa: 'BAYANIN AIKI',
      AppLanguage.pidgin: 'WETIN HAPPEN',
    },
    'rpt_recording_voice': {
      AppLanguage.english: 'RECORDING VOICE REPORT...',
      AppLanguage.hausa: 'ANA DAUKAR MURYAR RAHOTO...',
      AppLanguage.pidgin: 'DEY RECORD VOICE REPORT...',
    },
    'rpt_voice_optional': {
      AppLanguage.english: 'VOICE REPORTING (OPTIONAL)',
      AppLanguage.hausa: 'RAHOTON MURYA (ZABIN KAI)',
      AppLanguage.pidgin: 'VOICE REPORT (IF YOU WANT)',
    },
    'rpt_delete_recording': {
      AppLanguage.english: 'Delete the recording',
      AppLanguage.hausa: 'Goge muryar da aka dauka',
      AppLanguage.pidgin: 'Delete the recording',
    },
    'rpt_speak_now_stop': {
      AppLanguage.english: 'SPEAK NOW (TAP STOP TO FINISH)',
      AppLanguage.hausa: 'YI MAGANA YANZU (DANNA TSAIDA DOMIN KAMMALAWA)',
      AppLanguage.pidgin: 'TALK NOW (TAP STOP TO FINISH)',
    },
    'rpt_stop': {
      AppLanguage.english: 'STOP',
      AppLanguage.hausa: 'TSAIDA',
      AppLanguage.pidgin: 'STOP',
    },
    'rpt_voice_attached': {
      AppLanguage.english: 'VOICE NOTE ATTACHED & ENCRYPTED',
      AppLanguage.hausa: 'AN SANYA SAKON MURYA KUMA AN KARE SHI',
      AppLanguage.pidgin: 'VOICE NOTE DEY ATTACH & SECURE',
    },
    'rpt_record_voice_report': {
      AppLanguage.english: 'RECORD VOICE REPORT',
      AppLanguage.hausa: 'DAUKI MURYAR RAHOTO',
      AppLanguage.pidgin: 'RECORD VOICE REPORT',
    },
    'rpt_enter_details_hint': {
      AppLanguage.english:
          'Enter mission details, observations, and objective status...',
      AppLanguage.hausa:
          'Shigar da cikakkun bayanan aiki, abubuwan da ka lura da su, da '
          'halin da ake ciki...',
      AppLanguage.pidgin:
          'Type wetin happen, wetin you see, and everything...',
    },
    'rpt_visual_telemetry': {
      AppLanguage.english: 'VISUAL TELEMETRY (OPTIONAL)',
      AppLanguage.hausa: 'HOTUNA KO BIDIYO (ZABIN KAI)',
      AppLanguage.pidgin: 'PICTURE & VIDEO (IF YOU WANT)',
    },
    'rpt_scan_photo': {
      AppLanguage.english: 'SCAN PHOTO',
      AppLanguage.hausa: 'DAUKI HOTO',
      AppLanguage.pidgin: 'SNAP PHOTO',
    },
    'rpt_record_video': {
      AppLanguage.english: 'RECORD VIDEO',
      AppLanguage.hausa: 'DAUKI BIDIYO',
      AppLanguage.pidgin: 'RECORD VIDEO',
    },
    'rpt_photo_intel': {
      AppLanguage.english: 'PHOTO INTEL',
      AppLanguage.hausa: 'HOTON SHAIDA',
      AppLanguage.pidgin: 'PHOTO EVIDENCE',
    },
    'rpt_video_intel': {
      AppLanguage.english: 'VIDEO INTEL',
      AppLanguage.hausa: 'BIDIYON SHAIDA',
      AppLanguage.pidgin: 'VIDEO EVIDENCE',
    },
    'rpt_geospatial_coords': {
      AppLanguage.english: 'GEOSPATIAL COORDINATES',
      AppLanguage.hausa: 'BAYANAN WURI',
      AppLanguage.pidgin: 'LOCATION COORDINATES',
    },
    'rpt_gps_telemetry': {
      AppLanguage.english: 'GPS TELEMETRY',
      AppLanguage.hausa: 'SIGINAR GPS',
      AppLanguage.pidgin: 'GPS INFO',
    },
    'rpt_gps_unavailable': {
      AppLanguage.english: 'GPS UNAVAILABLE',
      AppLanguage.hausa: 'BABU GPS',
      AppLanguage.pidgin: 'GPS NO DEY',
    },
    'rpt_active_beacon': {
      AppLanguage.english: 'ACTIVE BEACON SIGNAL',
      AppLanguage.hausa: 'SIGINAR WURI NA AIKI',
      AppLanguage.pidgin: 'LOCATION SIGNAL DEY WORK',
    },
    'rpt_acquiring_signal': {
      AppLanguage.english: 'ACQUIRING SIGNAL...',
      AppLanguage.hausa: 'ANA NEMAN SIGINA...',
      AppLanguage.pidgin: 'DEY FIND SIGNAL...',
    },
    'rpt_signal_interrupted': {
      AppLanguage.english: 'SIGNAL INTERRUPTED',
      AppLanguage.hausa: 'SIGINA TA YANKE',
      AppLanguage.pidgin: 'SIGNAL DON CUT',
    },
    'rpt_jurisdiction_override': {
      AppLanguage.english: 'JURISDICTION OVERRIDE',
      AppLanguage.hausa: 'CANZA YANKI DA KAI',
      AppLanguage.pidgin: 'CHANGE AREA BY HAND',
    },
    'rpt_manual_location_entry': {
      AppLanguage.english: 'MANUAL LOCATION ENTRY',
      AppLanguage.hausa: 'SHIGAR DA WURI DA HANU',
      AppLanguage.pidgin: 'TYPE LOCATION YOURSELF',
    },
    'rpt_use_if_gps_weak': {
      AppLanguage.english: 'USE IF GPS SIGNAL IS WEAK OR INACCURATE',
      AppLanguage.hausa:
          'YI AMFANI IDAN SIGINAR GPS TA YI RAUNI KO BA DAIDAIBAGABA',
      AppLanguage.pidgin: 'USE THIS IF GPS SIGNAL NO STRONG WELL',
    },
    'rpt_lga': {
      AppLanguage.english: 'LOCAL GOVERNMENT AREA',
      AppLanguage.hausa: 'KARAMAR HUKUMA (LGA)',
      AppLanguage.pidgin: 'LOCAL GOVERNMENT (LGA)',
    },
    'rpt_federal_ward': {
      AppLanguage.english: 'FEDERAL WARD (INEC)',
      AppLanguage.hausa: 'MAZABAR TARAYYA (INEC)',
      AppLanguage.pidgin: 'FEDERAL WARD (INEC)',
    },
    'rpt_state_ward': {
      AppLanguage.english: 'STATE WARD (SIEC)',
      AppLanguage.hausa: 'MAZABAR JIHA (SIEC)',
      AppLanguage.pidgin: 'STATE WARD (SIEC)',
    },
    'rpt_polling_unit': {
      AppLanguage.english: 'POLLING UNIT (PU)',
      AppLanguage.hausa: 'RUKUNIN ZABE (PU)',
      AppLanguage.pidgin: 'POLLING UNIT (PU)',
    },
    'rpt_stealth_mode': {
      AppLanguage.english: 'STEALTH MODE',
      AppLanguage.hausa: 'YANAYIN ASIRCE',
      AppLanguage.pidgin: 'SECRET MODE',
    },
    'rpt_encrypt_identity': {
      AppLanguage.english: 'ENCRYPT SENDER IDENTITY ARCHIVE',
      AppLanguage.hausa: 'BOYE SUNA DA ASALIN MAI AIKAWA',
      AppLanguage.pidgin: 'HIDE WHO SEND DIS REPORT',
    },
    'rpt_initiate_transmission': {
      AppLanguage.english: 'INITIATE TRANSMISSION',
      AppLanguage.hausa: 'FARA TURAWA',
      AppLanguage.pidgin: 'SEND NOW',
    },
    'rpt_aes_encrypted_tunnel': {
      AppLanguage.english: 'AES-256 ENCRYPTED TUNNEL · MISSION CRITICAL DATA',
      AppLanguage.hausa: 'KARIYA TA AES-256 · BAYANAI MASU MUHIMMANCI',
      AppLanguage.pidgin: 'AES-256 SECURED · IMPORTANT DATA',
    },
    'rpt_select_placeholder': {
      AppLanguage.english: 'SELECT...',
      AppLanguage.hausa: 'ZABI...',
      AppLanguage.pidgin: 'SELECT...',
    },
    'rpt_transmission_error': {
      AppLanguage.english: 'TRANSMISSION ERROR',
      AppLanguage.hausa: 'KUSKUREN TURAWA',
      AppLanguage.pidgin: 'SENDING ERROR',
    },

    // SAFE ZONE SCREEN
    'sz_safe_zone_routing': {
      AppLanguage.english: 'SAFE-ZONE ROUTING',
      AppLanguage.hausa: 'HANYAR ZUWA SASHEN TSIRA',
      AppLanguage.pidgin: 'SAFE-ZONE ROUTE',
    },
    'sz_evacuation_zones': {
      AppLanguage.english: 'EVACUATION & SECURE ZONES',
      AppLanguage.hausa: 'WURAREN KAUCEWA DA TSARO',
      AppLanguage.pidgin: 'SECURE & SAFE AREAS',
    },
    'sz_navigate_shield_desc': {
      AppLanguage.english:
          'NAVIGATE TO NEAREST SHIELD ICON FOR IMMEDIATE PROTECTION. THESE '
          'ZONES ARE SECURED BY TACTICAL UNITS.',
      AppLanguage.hausa:
          "JE ZUWA ALAMAR GARKUWA MAFI KUSA DOMIN TSARO NAN DA NAN. JAMI'AN "
          'TSARO NA KARE WADANNAN WURARE.',
      AppLanguage.pidgin:
          'FOLLOW THE SHIELD ICON TO GO TO NEAREST SAFE PLACE. TACTICAL TEAM '
          'DEY GUARD DEM.',
    },
    'sz_active_zones_online': {
      AppLanguage.english: 'ACTIVE SECURE ZONES ONLINE',
      AppLanguage.hausa: 'SASHEN TSIRA NA AIKI',
      AppLanguage.pidgin: 'SAFE ZONES ONLINE NOW',
    },
    'sz_gps_denied': {
      AppLanguage.english:
          'GPS ACCESS DENIED\nEnable location permissions to view safe zones '
          'near you.',
      AppLanguage.hausa:
          'AN HANA DAMAR GPS\nBada izinin wuri domin ganin wuraren tsira '
          'kusa da kai.',
      AppLanguage.pidgin:
          'GPS ACCESS NO GREE\nAllow location make you fit see safe zones '
          'near you.',
    },
    'sz_no_active_zones': {
      AppLanguage.english:
          'NO ACTIVE SAFE ZONES IN YOUR AREA.\nCONTACT HQ VIA DISPATCHER CHAT.',
      AppLanguage.hausa:
          'BABU SASHEN TSIRA MAI AIKI A YANKINKA.\nTUNTUBI HQ TA HIKAR '
          'DISPATCHER.',
      AppLanguage.pidgin:
          'NO SAFE ZONE NEAR YOUR AREA.\nMESSAGE HQ FOR DISPATCHER CHAT.',
    },
    'sz_capacity': {
      AppLanguage.english: 'CAPACITY',
      AppLanguage.hausa: 'IYAKA',
      AppLanguage.pidgin: 'CAPACITY',
    },
    'sz_persons': {
      AppLanguage.english: 'PERSONS',
      AppLanguage.hausa: 'MUTANE',
      AppLanguage.pidgin: 'PEOPLE',
    },
    'sz_computing_path': {
      AppLanguage.english: 'COMPUTING RISK-AWARE EVACUATION PATH...',
      AppLanguage.hausa: 'ANA GANO AMINTACCIYAR HANYAR KAUCEWA...',
      AppLanguage.pidgin: 'DEY CALCULATE SAFE ROUTE...',
    },
    'sz_threat_en_route': {
      AppLanguage.english:
          'THREAT EN ROUTE · PATH DIVERTS AROUND ACTIVE UNREST HOTSPOTS',
      AppLanguage.hausa:
          'AKWAI HATSARI A HANYA · HANYA TA KAUCE WA WURAREN DA AKE RIGIMA',
      AppLanguage.pidgin:
          'DANGER DEY FOR ROAD · ROUTE GO PASS CORNER WEY NO GET WAHALA',
    },
    // ── ACCESSIBLE NAMES ────────────────────────────────────────────────────
    //
    // A screen-reader label is user-visible text, so it belongs here with
    // everything else a citizen reads. Added with T-76, which gave a name to
    // eight controls that had none — among them SUBMIT on the emergency PIN
    // pad and the marker that picks which shelter somebody is routed to.
    // What each map IS, for a screen reader. See RainbowMap.label and T-78:
    // flutter_map's pan recognizer makes an unwrapped map an unlabelled button
    // covering the screen.
    'eme_semantics_map_label': {
      AppLanguage.english: 'Map showing where you are',
      AppLanguage.hausa: 'Taswira mai nuna inda kake',
      AppLanguage.pidgin: 'Map wey show where you dey',
    },
    'sz_semantics_map_label': {
      AppLanguage.english: 'Map of shelters and threats near you',
      AppLanguage.hausa: 'Taswirar wuraren tsira da hatsari kusa da kai',
      AppLanguage.pidgin: 'Map of shelters and danger near you',
    },
    'sz_semantics_shelter_list': {
      AppLanguage.english: 'Shelters, as a list',
      AppLanguage.hausa: 'Wuraren tsira, a jerin',
      AppLanguage.pidgin: 'Shelters, as list',
    },
    'sz_semantics_route_to': {
      AppLanguage.english: 'Route me to {name}',
      AppLanguage.hausa: 'Nuna mini hanya zuwa {name}',
      AppLanguage.pidgin: 'Show me road go {name}',
    },
    'sz_semantics_close_details': {
      AppLanguage.english: 'Close these shelter details',
      AppLanguage.hausa: 'Rufe bayanan wurin tsira',
      AppLanguage.pidgin: 'Close this shelter info',
    },
    'eme_semantics_pin_checking': {
      AppLanguage.english: 'Checking your PIN',
      AppLanguage.hausa: 'Ana duba PIN naka',
      AppLanguage.pidgin: 'Dem dey check your PIN',
    },
    'eme_semantics_pin_submit': {
      AppLanguage.english: 'Submit your PIN',
      AppLanguage.hausa: 'Tura PIN naka',
      AppLanguage.pidgin: 'Send your PIN',
    },
    'eme_semantics_pin_submit_short': {
      AppLanguage.english:
          'Submit your PIN. Enter at least {count} digits first.',
      AppLanguage.hausa:
          'Tura PIN naka. Da farko shigar da akalla lambobi {count}.',
      AppLanguage.pidgin:
          'Send your PIN. Put at least {count} numbers first.',
    },
    'eme_semantics_pin_backspace': {
      AppLanguage.english: 'Delete the last digit',
      AppLanguage.hausa: 'Share lamba ta karshe',
      AppLanguage.pidgin: 'Clear the last number',
    },
    'rpt_semantics_remove_attachment': {
      AppLanguage.english: 'Remove this attachment',
      AppLanguage.hausa: 'Cire wannan abin da aka makala',
      AppLanguage.pidgin: 'Remove this file',
    },
    'trk_semantics_a_responder': {
      AppLanguage.english: 'A responder',
      AppLanguage.hausa: "Wani jami'i",
      AppLanguage.pidgin: 'One responder',
    },
    // A responder whose status nobody has reported. Not a DATA value — the
    // status strings the code compares are PATROLLING / EMERGENCY / ONLINE —
    // this is the word a dispatcher reads when there is none. T-88.
    'trk_status_unknown': {
      AppLanguage.english: 'STATUS UNKNOWN',
      AppLanguage.hausa: 'BA A SAN MATSAYI BA',
      AppLanguage.pidgin: 'STATUS NO DEY',
    },
    'trk_semantics_responder_list': {
      AppLanguage.english: 'Responders on duty, as a list',
      AppLanguage.hausa: "Jami'ai kan aiki, a jerin",
      AppLanguage.pidgin: 'Responders wey dey work, as list',
    },
    'trk_semantics_open_responder': {
      AppLanguage.english: 'Open the details for {who}, status {status}',
      AppLanguage.hausa: 'Bude bayanan {who}, matsayi {status}',
      AppLanguage.pidgin: 'Open the info for {who}, status {status}',
    },
    // The route, in writing.
    //
    // `_calculateSafeRoute` SPEAKS the outcome — "safe route calculated to
    // {name}, the path is clear" — through TtsService and writes it nowhere.
    // On a screen whose job is getting a frightened person to a shelter, the
    // one sentence saying whether the way is clear was audio-only: gone if the
    // phone is muted, if TTS is unavailable, if the street is loud, or if the
    // person cannot hear. The threat warning beside it was always written; the
    // confirmation was not. T-80.
    'sz_show_directions': {
      AppLanguage.english: 'SHOW THE WAY IN WRITING',
      AppLanguage.hausa: 'NUNA HANYAR A RUBUCE',
      AppLanguage.pidgin: 'SHOW THE ROAD IN WRITING',
    },
    'sz_hide_directions': {
      AppLanguage.english: 'HIDE THE WRITTEN DIRECTIONS',
      AppLanguage.hausa: 'BOYE HANYAR DA AKA RUBUTA',
      AppLanguage.pidgin: 'HIDE THE WRITING',
    },
    'sz_navigate_to_zone': {
      AppLanguage.english: 'NAVIGATE TO ZONE',
      AppLanguage.hausa: 'JE ZUWA WURIN TSIRA',
      AppLanguage.pidgin: 'GO TO THE ZONE',
    },
    'sz_unable_acquire_gps': {
      AppLanguage.english: 'UNABLE TO ACQUIRE GPS SIGNAL',
      AppLanguage.hausa: 'AN KASA SAMUN SIGINAR GPS',
      AppLanguage.pidgin: 'NO FIT GET GPS SIGNAL',
    },
    // Appended when the routing service could not be reached or refused, so
    // the path drawn is a straight line rather than roads. T-83.
    'sz_route_is_a_direct_line': {
      AppLanguage.english:
          'Routing is unavailable, so this is a direct line and not a road '
          'route. Follow the roads and keep away from the danger.',
      AppLanguage.hausa:
          'Ba a samu hanyar kewayawa ba, don haka wannan layi mikakke ne ba '
          'hanyar mota ba. Bi titi kuma ka nisanci hatsarin.',
      AppLanguage.pidgin:
          'Routing no dey work now, so this one na straight line, no road. '
          'Follow road and no go near the danger.',
    },
    // Appended when the shelter's own row says nobody has confirmed where it
    // is. Three of the seven seeded shelters were outside every surveyed ward
    // of the LGA their row claimed, the worst by 9.6km, and the screen drew a
    // confident route to the nearest one. Those three are deactivated now, but
    // an unverified position is still a guess and the person running has to be
    // told which it is: the NAME is reliable — a police division is a place
    // anyone can point you to — and the pin is not. T-94.
    // Shown when the app opened without being able to ask the server who this
    // account is, and is working from what this handset recorded last time.
    //
    // Said rather than hidden because a responder whose rung changed this
    // morning is looking at a board that may be the wrong one — and because
    // the alternative, which is what this replaced, was the app not opening at
    // all. T-100.
    'auth_working_from_record': {
      AppLanguage.english:
          'No connection. Showing what this phone recorded on {when} — your '
          'role may have changed since.',
      AppLanguage.hausa:
          'Babu haɗi. Ana nuna abin da wannan wayar ta ajiye a {when} — '
          'matsayinka na iya canzawa tun lokacin.',
      AppLanguage.pidgin:
          'No network. We dey show wetin this phone save on {when} — your role '
          'fit don change since then.',
    },
    'sz_position_not_confirmed': {
      AppLanguage.english:
          'Nobody has confirmed this exact spot, so ask for directions when '
          'you are close.',
      AppLanguage.hausa:
          'Babu wanda ya tabbatar da ainihin wurin, don haka ka tambayi hanya '
          'idan ka kusa.',
      AppLanguage.pidgin:
          'Nobody confam this exact place yet, so ask person for direction '
          'when you near.',
    },
    'sz_not_confirmed_chip': {
      AppLanguage.english: 'POSITION NOT CONFIRMED',
      AppLanguage.hausa: 'WURIN BAI TABBATA BA',
      AppLanguage.pidgin: 'PLACE NO CONFAM',
    },
    'sz_route_calculated_clear': {
      AppLanguage.english:
          'Route to {name}. No incident has been reported near this route, '
          'but that does not mean it is safe. Stay alert.',
      AppLanguage.hausa:
          'Hanya zuwa {name}. Ba a kai rahoton wani lamari kusa da hanyar ba, '
          'amma hakan ba yana nufin babu hatsari ba. Ka kula.',
      AppLanguage.pidgin:
          'Road to {name}. Nobody report wahala near this road, '
          'but e no mean say e safe. Shine your eye.',
    },
    'sz_route_calculated_warning': {
      AppLanguage.english:
          'Route to {name}. Warning: this route passes near an active '
          'incident. Proceed with extreme caution.',
      AppLanguage.hausa:
          'An gano hanya zuwa {name}. Gargadi: Hanyar ta kusa da hatsari. '
          'Yi tafiya da matukar kula.',
      AppLanguage.pidgin:
          'Route to {name} ready. Warning: Danger dey near this road. '
          'Shine your eye well.',
    },

    // LIVE TRACKING SCREEN
    'trk_unknown_officer': {
      AppLanguage.english: 'Unknown Officer',
      AppLanguage.hausa: "Jami'in da ba a sani ba",
      AppLanguage.pidgin: 'Unknown Officer',
    },
    'trk_responder_details': {
      AppLanguage.english: 'RESPONDER DETAILS',
      AppLanguage.hausa: "BAYANAN JAMI'I",
      AppLanguage.pidgin: 'RESPONDER DETAILS',
    },
    'trk_tactical_map': {
      AppLanguage.english: 'TACTICAL MAP',
      AppLanguage.hausa: 'TASWIRAR AIKI',
      AppLanguage.pidgin: 'TACTICAL MAP',
    },
    'trk_live_command_feed': {
      AppLanguage.english: 'LIVE COMMAND FEED',
      AppLanguage.hausa: 'BAYANAN CIBIYAR UMARNI',
      AppLanguage.pidgin: 'LIVE COMMAND UPDATE',
    },
    'trk_location_denied': {
      AppLanguage.english: 'LOCATION ACCESS DENIED',
      AppLanguage.hausa: 'AN HANA DAMAR WURI',
      AppLanguage.pidgin: 'LOCATION ACCESS DENIED',
    },
    'trk_enable_location_settings': {
      AppLanguage.english:
          'Enable location in device Settings to use the tactical map.',
      AppLanguage.hausa:
          'Kunna wuri a Settings na wayarka domin amfani da taswira.',
      AppLanguage.pidgin:
          'Turn on location for device Settings to use this map.',
    },
    'trk_semantics_map_label': {
      AppLanguage.english: 'Tactical map of incidents and responders',
      AppLanguage.hausa: "Taswirar aiki ta lamurra da jami'ai",
      AppLanguage.pidgin: 'Tactical map of incidents and responders',
    },
    'trk_dispatched_alert': {
      AppLanguage.english: 'DISPATCHED / ALERT',
      AppLanguage.hausa: "AN TURA JAMI'I / SANARWA",
      AppLanguage.pidgin: 'TEAM SENT / ALERT',
    },
    'trk_status': {
      AppLanguage.english: 'Status',
      AppLanguage.hausa: 'Hali',
      AppLanguage.pidgin: 'Status',
    },
    'trk_battery': {
      AppLanguage.english: 'Battery',
      AppLanguage.hausa: 'Baturi',
      AppLanguage.pidgin: 'Battery',
    },
    'trk_last_updated': {
      AppLanguage.english: 'Last Updated',
      AppLanguage.hausa: 'Sabuntawa ta karshe',
      AppLanguage.pidgin: 'Last Updated',
    },
    'trk_unknown': {
      AppLanguage.english: 'Unknown',
      AppLanguage.hausa: 'Ba a sani ba',
      AppLanguage.pidgin: 'Unknown',
    },
    'trk_id': {
      AppLanguage.english: 'ID',
      AppLanguage.hausa: 'LAMBA',
      AppLanguage.pidgin: 'ID',
    },

    // LOCK SCREEN
    'lock_no_phone_error': {
      AppLanguage.english:
          'This account has no phone number on it. Sign out and sign in again.',
      AppLanguage.hausa:
          'Wannan asusun ba shi da lambar waya a kai. Fita sannan ka sake shiga.',
      AppLanguage.pidgin:
          'Dis account no get phone number. Sign out make you sign in again.',
    },
    'lock_code_rejected': {
      AppLanguage.english: 'That code was not accepted.',
      AppLanguage.hausa: 'Ba a karbi wannan lambar ba.',
      AppLanguage.pidgin: 'Dat code no work.',
    },
    'lock_welcome_back': {
      AppLanguage.english: 'WELCOME BACK',
      AppLanguage.hausa: 'BARKA DA DAWOWA',
      AppLanguage.pidgin: 'WELCOME BACK',
    },
    'lock_sos_emergency': {
      AppLanguage.english: 'EMERGENCY — TAP 3 TIMES FOR SOS',
      AppLanguage.hausa: 'GAGGAWA — DANNA SAU 3 DON SOS',
      AppLanguage.pidgin: 'EMERGENCY — TAP AM 3 TIMES FOR SOS',
    },
    'lock_sos_open_active': {
      AppLanguage.english: 'SOS ACTIVE — OPEN IT',
      AppLanguage.hausa: 'SOS NA GUDANA — BUDE SHI',
      AppLanguage.pidgin: 'SOS DEY RUN — OPEN AM',
    },
    'lock_sos_works_always': {
      AppLanguage.english: 'Works whether or not you unlock.',
      AppLanguage.hausa: 'Yana aiki ko da ka bude wayar ko ba ka bude ba.',
      AppLanguage.pidgin: 'E dey work whether you unlock or not.',
    },
    'lock_sending': {
      AppLanguage.english: 'SENDING…',
      AppLanguage.hausa: 'ANA TURAWA…',
      AppLanguage.pidgin: 'DEY SEND…',
    },
    'lock_send_my_code': {
      AppLanguage.english: 'SEND MY CODE',
      AppLanguage.hausa: 'TURA MIN LAMBATA',
      AppLanguage.pidgin: 'SEND MY CODE',
    },
    'lock_code_sent_to': {
      AppLanguage.english: 'CODE SENT TO',
      AppLanguage.hausa: 'AN TURA LAMBA ZUWA',
      AppLanguage.pidgin: 'CODE DON GO TO',
    },
    'lock_checking': {
      AppLanguage.english: 'CHECKING…',
      AppLanguage.hausa: 'ANA DUBAWA…',
      AppLanguage.pidgin: 'DEY CHECK…',
    },
    'lock_unlock': {
      AppLanguage.english: 'UNLOCK',
      AppLanguage.hausa: 'BUDE',
      AppLanguage.pidgin: 'UNLOCK',
    },
    'lock_send_another_code': {
      AppLanguage.english: 'SEND ANOTHER CODE',
      AppLanguage.hausa: 'SAKE TURA WATA LAMBAR',
      AppLanguage.pidgin: 'SEND ANOTHER CODE',
    },
    'lock_check_connection': {
      AppLanguage.english: 'CHECK FOR A CONNECTION AGAIN',
      AppLanguage.hausa: 'SAKE DUBA HANYAR SADARWA',
      AppLanguage.pidgin: 'CHECK NETWORK AGAIN',
    },
    'lock_sign_out': {
      AppLanguage.english: 'SIGN OUT INSTEAD',
      AppLanguage.hausa: 'FITA DAGA ASUSU MAIMAKON HAKA',
      AppLanguage.pidgin: 'SIGN OUT INSTEAD',
    },
    'lock_explanation_code_sms': {
      AppLanguage.english:
          'For your safety, confirm this is your phone. We will send a '
          'code to your number.',
      AppLanguage.hausa:
          'Domin amincinka, tabbatar da wannan wayarka ce. Za mu tura lamba '
          'zuwa lambarka.',
      AppLanguage.pidgin:
          'For your safety, make sure say na your phone. We go send code to '
          'your number.',
    },
    'lock_explanation_offline': {
      AppLanguage.english:
          'You are offline, so a code cannot be sent. Your emergency '
          'button still works — everything else is locked until you have a '
          'connection.',
      AppLanguage.hausa:
          'Ba ka da intanet, don haka ba za a iya tura lamba ba. Maballin '
          'gaggawa na nan yana aiki — sauran abubuwa duk a kulle suke har sai '
          'ka sami hanyar sadarwa.',
      AppLanguage.pidgin:
          'You dey offline, so code no fit enter. Your emergency button '
          'still dey work — everything else don lock till network show.',
    },
    // AI Emergency Guardian (phase 1). The Hausa and Pidgin need review by
    // a native speaker before release.
    'guardian_title': {
      AppLanguage.english: 'AI Emergency Guardian',
      AppLanguage.hausa: 'Mai Tsaro na AI don Gaggawa',
      AppLanguage.pidgin: 'AI Emergency Guardian',
    },
    'guardian_settings_desc': {
      AppLanguage.english: 'Listens for your secret phrase or a clear call for help, and sends a silent SOS by itself.',
      AppLanguage.hausa: 'Yana sauraron kalmarka ta sirri ko kiran neman taimako bayyananne, sannan ya aika SOS a boye da kansa.',
      AppLanguage.pidgin: 'E dey listen for your secret phrase or clear cry for help, then e go send silent SOS by itself.',
    },
    'guardian_consent_heading': {
      AppLanguage.english: 'Before you switch it on',
      AppLanguage.hausa: 'Kafin ka kunna shi',
      AppLanguage.pidgin: 'Before you on am',
    },
    'guardian_consent_listens': {
      AppLanguage.english: 'While a session is on, Plateau Eye listens through the microphone for your secret phrase and for clear calls for help in English or Pidgin, such as "they are trying to kill me" or "dem wan kill me", and in Hausa too if you download it below.',
      AppLanguage.hausa: 'Lokacin da yake kunne, Plateau Eye yana sauraro ta makirufo don kalmarka ta sirri da kiran neman taimako bayyananne a Turanci ko Pidgin, kamar "they are trying to kill me" ko "dem wan kill me", da Hausa ma idan ka sauke ta a kasa.',
      AppLanguage.pidgin: 'When e dey on, Plateau Eye go dey listen with the microphone for your secret phrase and clear cry for help for English or Pidgin, like "they are trying to kill me" or "dem wan kill me", and for Hausa too if you download am for down.',
    },
    'guardian_consent_sends': {
      AppLanguage.english: 'When it hears one, it sends a silent SOS with your location straight away, without asking you first. Cancel a false alarm with your Safe PIN.',
      AppLanguage.hausa: 'Idan ya ji daya, zai aika SOS a boye tare da wurin da kake nan take, ba tare da ya tambaye ka ba. Soke kuskure da Safe PIN dinka.',
      AppLanguage.pidgin: 'If e hear one, e go send silent SOS with your location sharp sharp, e no go ask you first. Cancel false alarm with your Safe PIN.',
    },
    'guardian_consent_private': {
      AppLanguage.english: 'What it hears is turned into text on the phone itself and then dropped. Nothing is recorded, saved or sent anywhere, on Android and iPhone alike. HQ is told only which rule matched, never your words.',
      AppLanguage.hausa: 'Ana mayar da abin da ya ji zuwa rubutu a cikin wayar kanta sannan a jefar. Ba a nadar, ajiye ko aika komai ko\'ina, a Android da iPhone duka. HQ tana samun sanin wace doka ce kawai ta yi daidai, ba kalmominka ba.',
      AppLanguage.pidgin: 'Wetin e hear, na inside the phone itself e dey turn am to text, then e go throw am away. Nothing dey record, save or go anywhere, for Android and iPhone. HQ go only know which rule match, dem no go see your words.',
    },
    'guardian_consent_limits': {
      AppLanguage.english: 'It keeps listening with the app in the background or the screen off. On Android a notification shows while it listens, with a Stop button. It pauses while you dictate a voice report. It cannot listen once the phone is off or the app is swiped away from recent apps.',
      AppLanguage.hausa: 'Yana ci gaba da saurare ko da manhajar tana baya ko allo a kashe. A Android sanarwa tana bayyana yayin da yake saurare, tare da maballin Tsayawa. Yana dakatawa lokacin da kake fadin rahoto da murya. Ba zai iya saurare ba idan waya a kashe take ko an rufe manhajar daga jerin manhajoji na kwanan nan.',
      AppLanguage.pidgin: 'E go still dey listen even if the app dey background or screen off. For Android, notification go show while e dey listen, with Stop button. E go pause when you dey talk voice report. E no fit listen if phone off or you close the app from recent apps.',
    },
    'guardian_consent_accept': {
      AppLanguage.english: 'I UNDERSTAND',
      AppLanguage.hausa: 'NA FAHIMTA',
      AppLanguage.pidgin: 'I UNDERSTAND',
    },
    'guardian_phrase_heading': {
      AppLanguage.english: 'Your secret phrase',
      AppLanguage.hausa: 'Kalmarka ta sirri',
      AppLanguage.pidgin: 'Your secret phrase',
    },
    'guardian_phrase_desc': {
      AppLanguage.english: 'A sentence only you would say, at least three words, that sounds ordinary to anyone nearby. Say it in English, or in Hausa if Hausa listening is on below. It is stored only on this phone.',
      AppLanguage.hausa: 'Jimla da kai kadai za ka fada, akalla kalmomi uku, wadda za ta yi kama da magana ta yau da kullum ga wanda ke kusa. Fade ta da Turanci, ko da Hausa idan sauraron Hausa yana kunne a kasa. Ana ajiye ta a wannan wayar kawai.',
      AppLanguage.pidgin: 'Sentence wey only you go talk, at least three words, wey go sound normal to anybody wey dey near. Talk am for English, or for Hausa if Hausa listening dey on for down. Na only this phone e dey.',
    },
    'guardian_phrase_set': {
      AppLanguage.english: 'A secret phrase is set.',
      AppLanguage.hausa: 'An saita kalmar sirri.',
      AppLanguage.pidgin: 'Secret phrase don set.',
    },
    'guardian_phrase_not_set': {
      AppLanguage.english: 'No secret phrase yet. Guardian will listen only for clear calls for help.',
      AppLanguage.hausa: 'Babu kalmar sirri tukuna. Mai Tsaro zai saurari kiran neman taimako bayyananne kawai.',
      AppLanguage.pidgin: 'No secret phrase yet. Guardian go only listen for clear cry for help.',
    },
    'guardian_phrase_hint': {
      AppLanguage.english: 'For example: The mangoes are ripe',
      AppLanguage.hausa: 'Misali: The mangoes are ripe',
      AppLanguage.pidgin: 'Like: The mangoes are ripe',
    },
    'guardian_phrase_save': {
      AppLanguage.english: 'SAVE PHRASE',
      AppLanguage.hausa: 'AJIYE KALMA',
      AppLanguage.pidgin: 'SAVE PHRASE',
    },
    'guardian_phrase_remove': {
      AppLanguage.english: 'REMOVE PHRASE',
      AppLanguage.hausa: 'CIRE KALMA',
      AppLanguage.pidgin: 'REMOVE PHRASE',
    },
    'guardian_phrase_saved': {
      AppLanguage.english: 'Secret phrase saved on this phone.',
      AppLanguage.hausa: 'An ajiye kalmar sirri a wannan wayar.',
      AppLanguage.pidgin: 'Secret phrase don save for this phone.',
    },
    'guardian_phrase_too_short': {
      AppLanguage.english: 'Use at least three words.',
      AppLanguage.hausa: 'Yi amfani da akalla kalmomi uku.',
      AppLanguage.pidgin: 'Use at least three words.',
    },
    'guardian_phrase_too_common': {
      AppLanguage.english: 'That is too close to something people say every day, or to a call for help. Choose something more unusual.',
      AppLanguage.hausa: 'Wannan ya yi kama da abin da mutane ke fada kullum, ko kiran neman taimako. Zabi wani abu da ba a saba ji ba.',
      AppLanguage.pidgin: 'That one too resemble wetin people dey talk every day, or cry for help. Choose something wey no common.',
    },
    'guardian_length': {
      AppLanguage.english: 'Listen for',
      AppLanguage.hausa: 'Saurara na tsawon',
      AppLanguage.pidgin: 'Listen for',
    },
    'guardian_hours': {
      AppLanguage.english: '{n} h',
      AppLanguage.hausa: 'awa {n}',
      AppLanguage.pidgin: '{n} h',
    },
    'guardian_start': {
      AppLanguage.english: 'START GUARDIAN',
      AppLanguage.hausa: 'FARA MAI TSARO',
      AppLanguage.pidgin: 'START GUARDIAN',
    },
    'guardian_stop': {
      AppLanguage.english: 'STOP GUARDIAN',
      AppLanguage.hausa: 'DAKATAR DA MAI TSARO',
      AppLanguage.pidgin: 'STOP GUARDIAN',
    },
    'guardian_listening_until': {
      AppLanguage.english: 'Listening until {time}',
      AppLanguage.hausa: 'Yana saurare har zuwa {time}',
      AppLanguage.pidgin: 'E dey listen till {time}',
    },
    'guardian_paused_dictation': {
      AppLanguage.english: 'Paused while you dictate',
      AppLanguage.hausa: 'An dakata yayin da kake magana',
      AppLanguage.pidgin: 'E pause while you dey talk',
    },
    'guardian_paused_background': {
      AppLanguage.english: 'Paused: Plateau Eye is not on screen',
      AppLanguage.hausa: 'An dakata: Plateau Eye ba ya kan allo',
      AppLanguage.pidgin: 'E pause: Plateau Eye no dey for screen',
    },
    'guardian_off': {
      AppLanguage.english: 'Guardian is off',
      AppLanguage.hausa: 'Mai Tsaro a kashe yake',
      AppLanguage.pidgin: 'Guardian dey off',
    },
    'guardian_problem_unsupported': {
      AppLanguage.english: 'Guardian needs the Android or iPhone app.',
      AppLanguage.hausa: 'Mai Tsaro yana bukatar manhajar Android ko iPhone.',
      AppLanguage.pidgin: 'Guardian need the Android or iPhone app.',
    },
    'guardian_problem_mic': {
      AppLanguage.english: 'Guardian needs the microphone. Allow it in your phone settings.',
      AppLanguage.hausa: 'Mai Tsaro yana bukatar makirufo. Ba da izini a saitunan wayarka.',
      AppLanguage.pidgin: 'Guardian need microphone. Allow am for your phone settings.',
    },
    'guardian_problem_recognizer': {
      AppLanguage.english: 'Guardian\'s speech model could not start on this phone, so Guardian cannot run on it yet.',
      AppLanguage.hausa: 'Samfurin magana na Mai Tsaro bai iya farawa a wannan wayar ba, don haka Mai Tsaro ba zai yi aiki a kanta ba tukuna.',
      AppLanguage.pidgin: 'Guardian speech model no fit start for this phone, so Guardian no fit run for am yet.',
    },
    'guardian_problem_failing': {
      AppLanguage.english: 'The microphone kept stopping, so Guardian has stopped. Try again.',
      AppLanguage.hausa: 'Makirufo ya ci gaba da tsayawa, don haka Mai Tsaro ya tsaya. Sake gwadawa.',
      AppLanguage.pidgin: 'The microphone dey stop again and again, so Guardian don stop. Try again.',
    },
    'guardian_sent': {
      AppLanguage.english: 'Guardian heard distress and sent a silent SOS.',
      AppLanguage.hausa: 'Mai Tsaro ya ji alamar hatsari kuma ya aika SOS a boye.',
      AppLanguage.pidgin: 'Guardian hear say wahala dey and e don send silent SOS.',
    },
    'guardian_home_banner': {
      AppLanguage.english: 'Guardian is listening',
      AppLanguage.hausa: 'Mai Tsaro yana saurare',
      AppLanguage.pidgin: 'Guardian dey listen',
    },
    'guardian_notify_text': {
      AppLanguage.english: 'Listening for distress on this phone. Nothing is recorded or sent unless it sends an SOS.',
      AppLanguage.hausa: 'Yana sauraron alamar hatsari a wannan wayar. Ba a nadar ko aika komai sai idan ya aika SOS.',
      AppLanguage.pidgin: 'E dey listen for wahala for this phone. Nothing dey record or go anywhere unless e send SOS.',
    },
    'guardian_notify_stop': {
      AppLanguage.english: 'Stop',
      AppLanguage.hausa: 'Tsayawa',
      AppLanguage.pidgin: 'Stop',
    },
    'guardian_ha_heading': {
      AppLanguage.english: 'Hausa',
      AppLanguage.hausa: 'Hausa',
      AppLanguage.pidgin: 'Hausa',
    },
    'guardian_ha_unavailable': {
      AppLanguage.english: 'Guardian cannot listen in Hausa yet. The Hausa model is still being trained.',
      AppLanguage.hausa: 'Mai Tsaro bai iya saurare da Hausa ba tukuna. Ana ci gaba da horar da samfurin Hausa.',
      AppLanguage.pidgin: 'Guardian never fit listen for Hausa. Dem still dey train the Hausa model.',
    },
    'guardian_ha_desc': {
      AppLanguage.english: 'Guardian can also listen for calls for help in Hausa. This needs a one-time download, kept on this phone. Like the rest of Guardian, it works offline once downloaded.',
      AppLanguage.hausa: 'Mai Tsaro na iya sauraron kiran neman taimako da Hausa ma. Wannan yana bukatar saukewa sau daya, wanda zai zauna a wannan wayar. Kamar sauran Mai Tsaro, yana aiki ba tare da intanet ba bayan an sauke shi.',
      AppLanguage.pidgin: 'Guardian fit also listen for cry for help for Hausa. E need one-time download wey go stay for this phone. Like the rest of Guardian, e go work without network after you download am.',
    },
    'guardian_ha_download': {
      AppLanguage.english: 'DOWNLOAD HAUSA ({mb} MB)',
      AppLanguage.hausa: 'SAUKE HAUSA ({mb} MB)',
      AppLanguage.pidgin: 'DOWNLOAD HAUSA ({mb} MB)',
    },
    'guardian_ha_downloading': {
      AppLanguage.english: 'Downloading Hausa… {pct}%',
      AppLanguage.hausa: 'Ana sauke Hausa… {pct}%',
      AppLanguage.pidgin: 'E dey download Hausa… {pct}%',
    },
    'guardian_ha_failed': {
      AppLanguage.english: 'The Hausa download did not finish, so nothing from it was kept. Try again on a steadier connection.',
      AppLanguage.hausa: 'Saukewar Hausa ba ta kammala ba, don haka ba a ajiye komai ba. Sake gwadawa a kan intanet mai karfi.',
      AppLanguage.pidgin: 'The Hausa download no finish, so nothing from am stay. Try again when network strong.',
    },
    'guardian_ha_on': {
      AppLanguage.english: 'Also listen in Hausa',
      AppLanguage.hausa: 'Saurara da Hausa ma',
      AppLanguage.pidgin: 'Listen for Hausa too',
    },
    'guardian_ha_note': {
      AppLanguage.english: 'Hausa listening is new and uses more battery than English alone. A secret phrase in Hausa is heard only while this is on.',
      AppLanguage.hausa: 'Sauraron Hausa sabo ne kuma yana amfani da batir fiye da Turanci kadai. Ana jin kalmar sirri ta Hausa ne kawai idan wannan yana kunne.',
      AppLanguage.pidgin: 'Hausa listening still new and e dey use more battery pass English alone. Secret phrase for Hausa go only work when this one dey on.',
    },
    'guardian_ha_lost': {
      AppLanguage.english: 'Hausa listening stopped: the Hausa model failed on this phone. Guardian is still listening in English and Pidgin.',
      AppLanguage.hausa: 'Sauraron Hausa ya tsaya: samfurin Hausa ya kasa aiki a wannan wayar. Mai Tsaro yana ci gaba da saurare da Turanci da Pidgin.',
      AppLanguage.pidgin: 'Hausa listening don stop: the Hausa model no work for this phone. Guardian still dey listen for English and Pidgin.',
    },
    'guardian_ha_remove': {
      AppLanguage.english: 'REMOVE HAUSA MODEL',
      AppLanguage.hausa: 'CIRE SAMFURIN HAUSA',
      AppLanguage.pidgin: 'REMOVE HAUSA MODEL',
    },
    'guardian_ha_mobile_title': {
      AppLanguage.english: 'Download on mobile data?',
      AppLanguage.hausa: 'A sauke da data ta waya?',
      AppLanguage.pidgin: 'Download with mobile data?',
    },
    'guardian_ha_mobile_body': {
      AppLanguage.english: 'This phone is not on Wi-Fi. The Hausa model is about {mb} MB of data.',
      AppLanguage.hausa: 'Wannan wayar ba ta kan Wi-Fi. Samfurin Hausa ya kai kusan {mb} MB na data.',
      AppLanguage.pidgin: 'This phone no dey on Wi-Fi. The Hausa model na about {mb} MB of data.',
    },
    'guardian_ha_mobile_go': {
      AppLanguage.english: 'DOWNLOAD',
      AppLanguage.hausa: 'SAUKE',
      AppLanguage.pidgin: 'DOWNLOAD',
    },
    'guardian_ha_cancel': {
      AppLanguage.english: 'NOT NOW',
      AppLanguage.hausa: 'BA YANZU BA',
      AppLanguage.pidgin: 'NO BE NOW',
    },
    'guardian_rec_entry': {
      AppLanguage.english: 'Help build Guardian for Hausa',
      AppLanguage.hausa: 'Taimaka a gina Mai Tsaro na Hausa',
      AppLanguage.pidgin: 'Help build Guardian for Hausa',
    },
    'guardian_rec_title': {
      AppLanguage.english: 'Hausa recordings',
      AppLanguage.hausa: 'Muryoyin Hausa',
      AppLanguage.pidgin: 'Hausa recordings',
    },
    'guardian_rec_consent': {
      AppLanguage.english: 'Guardian cannot understand Hausa yet. If Hausa is your first language, you can help by reading a few short sentences aloud, some calls for help and some everyday talk.\n\nYour voice is recorded only while you press Record, and the recordings stay on this phone. Nothing is sent unless you press Share and choose where to send them yourself. You can delete them all at any time.\n\nThey will be used only to build and test Guardian for Hausa. Do not say your name or anything private.',
      AppLanguage.hausa: 'Mai Tsaro bai fahimci Hausa ba tukuna. Idan Hausa ce harshenka na farko, za ka iya taimakawa ta karanta wasu gajerun jimloli da babbar murya, wasu kiran neman taimako, wasu kuma maganar yau da kullum.\n\nAna nadar muryarka ne kawai lokacin da ka danna Nada, kuma nadin yana zama a wannan wayar. Ba a aika komai sai idan ka danna Raba ka zabi inda za a aika da kanka. Za ka iya goge su duka a kowane lokaci.\n\nZa a yi amfani da su ne kawai don gina da gwada Mai Tsaro na Hausa. Kada ka fadi sunanka ko wani abu na sirri.',
      AppLanguage.pidgin: 'Guardian never understand Hausa. If Hausa na your first language, you fit help by reading some short sentences loud, some cry for help and some everyday talk.\n\nNa only when you press Record e go record your voice, and the recordings go stay for this phone. Nothing go send unless you press Share and choose where to send am yourself. You fit delete all of them anytime.\n\nNa only to build and test Guardian for Hausa dem go use am. No talk your name or anything private.',
    },
    'guardian_rec_accept': {
      AppLanguage.english: 'I AGREE',
      AppLanguage.hausa: 'NA YARDA',
      AppLanguage.pidgin: 'I AGREE',
    },
    'guardian_rec_record': {
      AppLanguage.english: 'RECORD',
      AppLanguage.hausa: 'NADA',
      AppLanguage.pidgin: 'RECORD',
    },
    'guardian_rec_stop': {
      AppLanguage.english: 'STOP',
      AppLanguage.hausa: 'TSAYA',
      AppLanguage.pidgin: 'STOP',
    },
    'guardian_rec_done': {
      AppLanguage.english: 'Recorded. Press Record to say it again.',
      AppLanguage.hausa: 'An nada. Danna Nada don sake fada.',
      AppLanguage.pidgin: 'E don record. Press Record to talk am again.',
    },
    'guardian_rec_share': {
      AppLanguage.english: 'SHARE RECORDINGS',
      AppLanguage.hausa: 'RABA NADE-NADEN',
      AppLanguage.pidgin: 'SHARE RECORDINGS',
    },
    'guardian_rec_delete': {
      AppLanguage.english: 'DELETE ALL RECORDINGS',
      AppLanguage.hausa: 'GOGE DUKAN NADE-NADEN',
      AppLanguage.pidgin: 'DELETE ALL RECORDINGS',
    },
    'guardian_rec_none_yet': {
      AppLanguage.english: 'Nothing recorded yet.',
      AppLanguage.hausa: 'Ba a nada komai ba tukuna.',
      AppLanguage.pidgin: 'Nothing don record yet.',
    },

    // ---- DRAFT TRANSLATIONS, AWAITING A NATIVE SPEAKER (2026-11-17) ----
    //
    // The citizen screens that still spoke English whatever language was
    // chosen (scripts/check_citizen_screens_speak_the_language.py). The
    // English is unchanged. The Hausa and Pidgin are drafts that have NOT yet
    // been checked by a speaker; the emergency PIN keys (pin_*) matter most,
    // because a misread word there can make someone use the wrong PIN under
    // threat. Everything between these two markers is what the review covers:
    // python3 scripts/export_translation_review.py writes it out as a sheet.
    // Move a key above the markers once a speaker has checked it.
    // splash
    'splash_status_init': {
      AppLanguage.english: 'INITIALIZING ENCRYPTED PROTOCOL',
      AppLanguage.hausa: 'ANA FARA TSARIN SIRRI',
      AppLanguage.pidgin: 'WE DEY START SECURE SYSTEM',
    },
    'splash_status_channel': {
      AppLanguage.english: 'ESTABLISHING SECURE CHANNEL...',
      AppLanguage.hausa: 'ANA HAƊA HANYAR SADARWA MAI TSARO...',
      AppLanguage.pidgin: 'WE DEY CONNECT SECURE LINE...',
    },
    'splash_status_guard': {
      AppLanguage.english: 'VERIFYING SENTINEL GUARD v4.2...',
      AppLanguage.hausa: 'ANA TABBATAR DA SENTINEL GUARD v4.2...',
      AppLanguage.pidgin: 'WE DEY CHECK SENTINEL GUARD v4.2...',
    },
    'splash_status_ready': {
      AppLanguage.english: 'ALL SYSTEMS OPERATIONAL',
      AppLanguage.hausa: 'KOMAI YANA AIKI',
      AppLanguage.pidgin: 'EVERYTHING DEY WORK',
    },
    'splash_encryption': {
      AppLanguage.english: 'ENCRYPTION: AES-256',
      AppLanguage.hausa: 'ƁOYEWA: AES-256',
      AppLanguage.pidgin: 'ENCRYPTION: AES-256',
    },
    // home
    'home_location_required': {
      AppLanguage.english: 'LOCATION REQUIRED',
      AppLanguage.hausa: 'ANA BUƘATAR WURINKA',
      AppLanguage.pidgin: 'WE NEED YOUR LOCATION',
    },
    'home_location_required_body': {
      AppLanguage.english: 'Plateau Eye requires active location permissions to route emergency responders to your position. Please enable location in device settings.',
      AppLanguage.hausa: 'Plateau Eye na buƙatar izinin sanin wurinka domin ta tura masu kai ɗauki zuwa inda kake. Don Allah ka kunna wuri (location) a saitunan wayarka.',
      AppLanguage.pidgin: 'Plateau Eye need your location so e fit send helpers come where you dey. Abeg on location for your phone settings.',
    },
    'common_ok': {
      AppLanguage.english: 'OK',
      AppLanguage.hausa: 'TO',
      AppLanguage.pidgin: 'OK',
    },
    'home_open_settings': {
      AppLanguage.english: 'SETTINGS',
      AppLanguage.hausa: 'SAITUNA',
      AppLanguage.pidgin: 'SETTINGS',
    },
    'home_open_menu': {
      AppLanguage.english: 'Open the menu',
      AppLanguage.hausa: 'Buɗe menu',
      AppLanguage.pidgin: 'Open the menu',
    },
    'home_notifications': {
      AppLanguage.english: 'Notifications',
      AppLanguage.hausa: 'Sanarwa',
      AppLanguage.pidgin: 'Notifications',
    },
    // voice note player
    'vnp_label': {
      AppLanguage.english: 'VOICE NOTE FROM THE REPORTER',
      AppLanguage.hausa: 'SAƘON MURYA DAGA MAI RAHOTO',
      AppLanguage.pidgin: 'VOICE NOTE FROM THE PERSON WEY REPORT',
    },
    'vnp_failed': {
      AppLanguage.english: 'This voice note did not play on this phone.',
      AppLanguage.hausa: 'Wannan saƙon murya bai kunna a wannan wayar ba.',
      AppLanguage.pidgin: 'This voice note no gree play for this phone.',
    },
    'vnp_try_again': {
      AppLanguage.english: 'Press play to try again.',
      AppLanguage.hausa: 'Danna kunna don sake gwadawa.',
      AppLanguage.pidgin: 'Press play make you try again.',
    },
    'vnp_pause': {
      AppLanguage.english: 'Pause the voice note',
      AppLanguage.hausa: 'Dakatar da saƙon murya',
      AppLanguage.pidgin: 'Pause the voice note',
    },
    'vnp_play': {
      AppLanguage.english: 'Play the voice note',
      AppLanguage.hausa: 'Kunna saƙon murya',
      AppLanguage.pidgin: 'Play the voice note',
    },
    // login
    'login_code_not_sent': {
      AppLanguage.english: 'THE CODE COULD NOT BE SENT.',
      AppLanguage.hausa: 'BA A IYA AIKA LAMBAR BA.',
      AppLanguage.pidgin: 'THE CODE NO GREE SEND.',
    },
    'login_badge_not_recognised': {
      AppLanguage.english: 'BADGE OR PASSWORD NOT RECOGNISED',
      AppLanguage.hausa: 'BA A GANE BAJI KO KALMAR SIRRI BA',
      AppLanguage.pidgin: 'WE NO KNOW THAT BADGE OR PASSWORD',
    },
    'login_verification_failed': {
      AppLanguage.english: 'VERIFICATION FAILED',
      AppLanguage.hausa: 'TABBATARWA TA GAZA',
      AppLanguage.pidgin: 'CHECKING NO WORK',
    },
    'login_identity_verification': {
      AppLanguage.english: 'IDENTITY VERIFICATION',
      AppLanguage.hausa: 'TABBATAR DA KAI',
      AppLanguage.pidgin: 'CONFIRM NA YOU',
    },
    'login_staff_password': {
      AppLanguage.english: 'STAFF PASSWORD',
      AppLanguage.hausa: 'KALMAR SIRRIN MA’AIKACI',
      AppLanguage.pidgin: 'STAFF PASSWORD',
    },
    'login_secure_identifier': {
      AppLanguage.english: 'SECURE IDENTIFIER',
      AppLanguage.hausa: 'SHAIDARKA',
      AppLanguage.pidgin: 'YOUR ID',
    },
    'login_code_sent_to': {
      AppLanguage.english: 'CODE SENT TO',
      AppLanguage.hausa: 'AN AIKA LAMBAR ZUWA',
      AppLanguage.pidgin: 'WE DON SEND CODE GO',
    },
    'login_back_to_identifier': {
      AppLanguage.english: 'BACK TO IDENTIFIER',
      AppLanguage.hausa: 'KOMA WAJEN SHAIDA',
      AppLanguage.pidgin: 'GO BACK TO ID',
    },
    'login_phone_or_code': {
      AppLanguage.english: 'PHONE OR ACCESS CODE',
      AppLanguage.hausa: 'LAMBAR WAYA KO LAMBAR SHIGA',
      AppLanguage.pidgin: 'PHONE NUMBER OR ACCESS CODE',
    },
    'login_password_for': {
      AppLanguage.english: 'PASSWORD FOR',
      AppLanguage.hausa: 'KALMAR SIRRI NA',
      AppLanguage.pidgin: 'PASSWORD FOR',
    },
    'login_badge': {
      AppLanguage.english: 'BADGE',
      AppLanguage.hausa: 'BAJI',
      AppLanguage.pidgin: 'BADGE',
    },
    'login_verify_otp': {
      AppLanguage.english: 'VERIFY OTP',
      AppLanguage.hausa: 'TABBATAR DA LAMBA',
      AppLanguage.pidgin: 'CHECK THE CODE',
    },
    'login_sign_in': {
      AppLanguage.english: 'SIGN IN',
      AppLanguage.hausa: 'SHIGA',
      AppLanguage.pidgin: 'SIGN IN',
    },
    'login_authorize': {
      AppLanguage.english: 'AUTHORIZE ACCESS',
      AppLanguage.hausa: 'BA DA IZININ SHIGA',
      AppLanguage.pidgin: 'ALLOW ME ENTER',
    },
    // setup: permissions
    'onb_perm_title': {
      AppLanguage.english: 'TACTICAL CLEARANCE',
      AppLanguage.hausa: 'IZININ AIKI',
      AppLanguage.pidgin: 'PERMISSION TO WORK',
    },
    'onb_perm_subtitle': {
      AppLanguage.english: 'Establish operational permissions to enable field telemetry.',
      AppLanguage.hausa: 'Ba da izinin da manhaja ke buƙata domin ta yi aiki a filin.',
      AppLanguage.pidgin: 'Give the app the permission wey e need make e fit work.',
    },
    'onb_perm_location': {
      AppLanguage.english: 'GEOSPATIAL',
      AppLanguage.hausa: 'WURI',
      AppLanguage.pidgin: 'LOCATION',
    },
    'onb_perm_location_desc': {
      AppLanguage.english: 'Real-time location beacon',
      AppLanguage.hausa: 'Nuna wurinka a lokacin gaggawa',
      AppLanguage.pidgin: 'Show where you dey for emergency',
    },
    'onb_perm_sms': {
      AppLanguage.english: 'COMMS LINK',
      AppLanguage.hausa: 'SAƘON SMS',
      AppLanguage.pidgin: 'SMS',
    },
    'onb_perm_sms_desc': {
      AppLanguage.english: 'Offline SMS redundancy',
      AppLanguage.hausa: 'Aika rahoto ta SMS idan babu intanet',
      AppLanguage.pidgin: 'Send report by SMS when network no dey',
    },
    'onb_perm_mic': {
      AppLanguage.english: 'FIELD AUDIO',
      AppLanguage.hausa: 'MURYA',
      AppLanguage.pidgin: 'VOICE',
    },
    'onb_perm_mic_desc': {
      AppLanguage.english: 'Active evidence recording',
      AppLanguage.hausa: 'Naɗar shaida yayin gaggawa',
      AppLanguage.pidgin: 'Record evidence for emergency',
    },
    'onb_perm_background': {
      AppLanguage.english: 'PERSISTENCE',
      AppLanguage.hausa: 'AIKI A BAYA',
      AppLanguage.pidgin: 'WORK FOR BACKGROUND',
    },
    'onb_perm_background_desc': {
      AppLanguage.english: 'Background session lock',
      AppLanguage.hausa: 'Kulle manhaja idan ba ka amfani da ita',
      AppLanguage.pidgin: 'Lock the app when you no dey use am',
    },
    'onb_perm_level': {
      AppLanguage.english: 'CLEARANCE LEVEL: STANDARD',
      AppLanguage.hausa: 'MATAKIN IZINI: NA YAU DA KULLUM',
      AppLanguage.pidgin: 'PERMISSION LEVEL: NORMAL',
    },
    'onb_perm_location_blocked': {
      AppLanguage.english: 'Your phone has stopped asking about location, so it can only be switched on in settings. Without it an alert cannot say where you are, and nobody can be sent to you.',
      AppLanguage.hausa: 'Wayarka ta daina tambaya game da wuri, don haka sai a saituna kaɗai za a iya kunna shi. Ba tare da shi ba, saƙon gaggawa ba zai faɗi inda kake ba, kuma ba za a iya tura kowa zuwa gare ka ba.',
      AppLanguage.pidgin: 'Your phone don stop to ask about location, so na only for settings you fit on am. If e no dey, your alert no go talk where you dey, and nobody fit come meet you.',
    },
    'onb_perm_location_refused': {
      AppLanguage.english: 'Location is how a responder finds you. Without it your alert says that something happened but not where, and nobody can be sent. Please allow it to continue.',
      AppLanguage.hausa: 'Ta wurin ne mai kai ɗauki zai same ka. Ba tare da shi ba, saƙonka zai faɗi cewa wani abu ya faru amma ba inda ya faru ba, kuma ba za a iya tura kowa ba. Don Allah ka ba da izini domin ci gaba.',
      AppLanguage.pidgin: 'Na location helpers dey use find you. If e no dey, your alert go talk say something happen but e no go talk where, and nobody fit come. Abeg allow am make you continue.',
    },
    'onb_perm_privacy': {
      AppLanguage.english: 'You stay anonymous. No personal data is collected — your phone number is your only identity in this app, and it is there so responders can reach you.',
      AppLanguage.hausa: 'Ba za a san ko kai wane ne ba. Ba a tattara bayanan sirrinka ba — lambar wayarka ce kaɗai shaidarka a wannan manhaja, kuma tana nan ne domin masu kai ɗauki su iya kiranka.',
      AppLanguage.pidgin: 'Nobody go know who you be. We no dey collect your personal data — na only your phone number be your ID for this app, and e dey there so helpers fit call you.',
    },
    'onb_perm_authorizing': {
      AppLanguage.english: 'AUTHORIZING...',
      AppLanguage.hausa: 'ANA BA DA IZINI...',
      AppLanguage.pidgin: 'E DEY ALLOW...',
    },
    'onb_perm_open_settings': {
      AppLanguage.english: 'OPEN SETTINGS',
      AppLanguage.hausa: 'BUƊE SAITUNA',
      AppLanguage.pidgin: 'OPEN SETTINGS',
    },
    'onb_perm_allow_location': {
      AppLanguage.english: 'ALLOW LOCATION',
      AppLanguage.hausa: 'BA DA IZININ WURI',
      AppLanguage.pidgin: 'ALLOW LOCATION',
    },
    'onb_perm_grant': {
      AppLanguage.english: 'GRANT CLEARANCE',
      AppLanguage.hausa: 'BA DA IZINI',
      AppLanguage.pidgin: 'ALLOW AM',
    },
    'onb_header': {
      AppLanguage.english: 'INITIALIZATION',
      AppLanguage.hausa: 'SHIRYAWA',
      AppLanguage.pidgin: 'SETUP',
    },
    'onb_step_of': {
      AppLanguage.english: 'STEP {step} / {total}',
      AppLanguage.hausa: 'MATAKI NA {step} / {total}',
      AppLanguage.pidgin: 'STEP {step} / {total}',
    },
    'onb_back': {
      AppLanguage.english: 'Go back to the previous setup step',
      AppLanguage.hausa: 'Koma matakin da ya gabata',
      AppLanguage.pidgin: 'Go back to the step wey pass',
    },
    // setup: emergency contacts
    'onb_contacts_title': {
      AppLanguage.english: 'EMERGENCY CONTACTS',
      AppLanguage.hausa: 'LAMBOBIN GAGGAWA',
      AppLanguage.pidgin: 'EMERGENCY CONTACTS',
    },
    'onb_contacts_subtitle': {
      AppLanguage.english: 'Add trusted contacts to be notified during SOS emergencies',
      AppLanguage.hausa: 'Ƙara mutanen da ka amince da su domin a sanar da su lokacin gaggawa (SOS)',
      AppLanguage.pidgin: 'Add people wey you trust make dem hear when you get SOS emergency',
    },
    'onb_contacts_name': {
      AppLanguage.english: 'Contact Name',
      AppLanguage.hausa: 'Sunan mutumin',
      AppLanguage.pidgin: 'Name of the person',
    },
    'onb_contacts_phone': {
      AppLanguage.english: 'Contact Phone Number',
      AppLanguage.hausa: 'Lambar wayar mutumin',
      AppLanguage.pidgin: 'Phone number of the person',
    },
    'onb_contacts_not_saved': {
      AppLanguage.english: 'YOUR CONTACT DID NOT SAVE. CHECK YOUR CONNECTION AND TRY AGAIN.',
      AppLanguage.hausa: 'BA A AJIYE LAMBAR BA. DUBA INTANET ƊINKA KA SAKE GWADAWA.',
      AppLanguage.pidgin: 'YOUR CONTACT NO SAVE. CHECK YOUR NETWORK AND TRY AGAIN.',
    },
    'onb_contacts_save': {
      AppLanguage.english: 'SAVE & CONTINUE',
      AppLanguage.hausa: 'AJIYE KA CI GABA',
      AppLanguage.pidgin: 'SAVE AND CONTINUE',
    },
    // voice report
    'vr_title': {
      AppLanguage.english: 'AI Voice Report',
      AppLanguage.hausa: 'Rahoto da Murya',
      AppLanguage.pidgin: 'Voice Report',
    },
    'vr_recorder_failed': {
      AppLanguage.english: 'Error starting recorder:',
      AppLanguage.hausa: 'Naɗar murya bai fara ba:',
      AppLanguage.pidgin: 'Recorder no gree start:',
    },
    'vr_send_failed': {
      AppLanguage.english: 'Triage request failed. Please try again.',
      AppLanguage.hausa: 'Ba a iya aika rahoton ba. Don Allah ka sake gwadawa.',
      AppLanguage.pidgin: 'The report no gree send. Abeg try again.',
    },
    'vr_failed': {
      AppLanguage.english: 'Triage failed:',
      AppLanguage.hausa: 'Rahoton ya gaza:',
      AppLanguage.pidgin: 'The report fail:',
    },
    'vr_stop_and_send': {
      AppLanguage.english: 'Stop recording and send this voice report',
      AppLanguage.hausa: 'Dakatar da naɗi ka aika wannan rahoton murya',
      AppLanguage.pidgin: 'Stop to record and send this voice report',
    },
    'vr_start': {
      AppLanguage.english: 'Start recording a voice report',
      AppLanguage.hausa: 'Fara naɗar rahoton murya',
      AppLanguage.pidgin: 'Start to record voice report',
    },
    // incident history
    'hist_title': {
      AppLanguage.english: 'TACTICAL INCIDENT LOGS',
      AppLanguage.hausa: 'TARIHIN RAHOTANNI',
      AppLanguage.pidgin: 'YOUR REPORTS',
    },
    'hist_subtitle': {
      AppLanguage.english: 'HISTORICAL ARCHIVE',
      AppLanguage.hausa: 'RAHOTANNIN DA SUKA GABATA',
      AppLanguage.pidgin: 'REPORTS WEY DON PASS',
    },
    'hist_load_failed': {
      AppLanguage.english: 'Error loading historical archives',
      AppLanguage.hausa: 'Ba a iya buɗe rahotannin da suka gabata ba',
      AppLanguage.pidgin: 'We no fit load your old reports',
    },
    'hist_empty': {
      AppLanguage.english: 'NO ARCHIVED INCIDENTS RECORDED',
      AppLanguage.hausa: 'BABU RAHOTON DA AKA AJIYE',
      AppLanguage.pidgin: 'NO OLD REPORT DEY',
    },
    'hist_incident': {
      AppLanguage.english: 'INCIDENT',
      AppLanguage.hausa: 'LAMARI',
      AppLanguage.pidgin: 'INCIDENT',
    },
    'hist_no_details': {
      AppLanguage.english: 'No details provided',
      AppLanguage.hausa: 'Ba a ba da cikakken bayani ba',
      AppLanguage.pidgin: 'Dem no give details',
    },
    'hist_details': {
      AppLanguage.english: 'INCIDENT DETAILS',
      AppLanguage.hausa: 'BAYANIN LAMARIN',
      AppLanguage.pidgin: 'INCIDENT DETAILS',
    },
    'hist_type': {
      AppLanguage.english: 'Type:',
      AppLanguage.hausa: 'Nau’i:',
      AppLanguage.pidgin: 'Type:',
    },
    'hist_severity': {
      AppLanguage.english: 'Severity:',
      AppLanguage.hausa: 'Tsanani:',
      AppLanguage.pidgin: 'How serious:',
    },
    'hist_status': {
      AppLanguage.english: 'Status:',
      AppLanguage.hausa: 'Matsayi:',
      AppLanguage.pidgin: 'Status:',
    },
    'hist_date': {
      AppLanguage.english: 'Date:',
      AppLanguage.hausa: 'Kwanan wata:',
      AppLanguage.pidgin: 'Date:',
    },
    'hist_unknown': {
      AppLanguage.english: 'Unknown',
      AppLanguage.hausa: 'Ba a sani ba',
      AppLanguage.pidgin: 'We no know',
    },
    'hist_media': {
      AppLanguage.english: 'Media:',
      AppLanguage.hausa: 'Hotuna da bidiyo:',
      AppLanguage.pidgin: 'Pictures and video:',
    },
    'hist_dispatcher_chat': {
      AppLanguage.english: 'DISPATCHER CHAT',
      AppLanguage.hausa: 'MAGANA DA MAI TURAWA',
      AppLanguage.pidgin: 'CHAT WITH DISPATCHER',
    },
    // emergency PIN (REVIEW FIRST)
    'pin_title': {
      AppLanguage.english: 'EMERGENCY PIN',
      AppLanguage.hausa: 'LAMBAR SIRRIN GAGGAWA',
      AppLanguage.pidgin: 'EMERGENCY PIN',
    },
    'pin_step_of': {
      AppLanguage.english: 'Step {step} of {total}',
      AppLanguage.hausa: 'Mataki na {step} cikin {total}',
      AppLanguage.pidgin: 'Step {step} of {total}',
    },
    'pin_choose_safe': {
      AppLanguage.english: 'Choose your SAFE PIN',
      AppLanguage.hausa: 'Zaɓi lambar sirrinka ta TSARO (SAFE PIN)',
      AppLanguage.pidgin: 'Choose your SAFE PIN',
    },
    'pin_confirm_safe': {
      AppLanguage.english: 'Confirm your SAFE PIN',
      AppLanguage.hausa: 'Tabbatar da lambar sirrinka ta TSARO (SAFE PIN)',
      AppLanguage.pidgin: 'Confirm your SAFE PIN',
    },
    'pin_choose_duress': {
      AppLanguage.english: 'Choose your DURESS PIN',
      AppLanguage.hausa: 'Zaɓi lambar sirrinka ta TILASTAWA (DURESS PIN)',
      AppLanguage.pidgin: 'Choose your DURESS PIN',
    },
    'pin_confirm_duress': {
      AppLanguage.english: 'Confirm your DURESS PIN',
      AppLanguage.hausa: 'Tabbatar da lambar sirrinka ta TILASTAWA (DURESS PIN)',
      AppLanguage.pidgin: 'Confirm your DURESS PIN',
    },
    'pin_safe_hint': {
      AppLanguage.english: 'Enter this to cancel an SOS normally. 4–8 digits.',
      AppLanguage.hausa: 'Shigar da wannan domin soke SOS kamar yadda aka saba. Lambobi 4 zuwa 8.',
      AppLanguage.pidgin: 'Put this one when you wan cancel SOS normally. 4 to 8 numbers.',
    },
    'pin_same_again': {
      AppLanguage.english: 'Enter the same PIN again.',
      AppLanguage.hausa: 'Sake shigar da lambar sirrin nan.',
      AppLanguage.pidgin: 'Put the same PIN again.',
    },
    'pin_duress_hint': {
      AppLanguage.english: 'Enter this if you are forced to cancel. The screen will look normal, but HQ will be told you are in danger. Must differ from your safe PIN.',
      AppLanguage.hausa: 'Shigar da wannan idan an tilasta maka ka soke. Allon zai yi kamar komai lafiya, amma za a sanar da HQ cewa kana cikin haɗari. Dole ya bambanta da lambar sirrinka ta tsaro.',
      AppLanguage.pidgin: 'Put this one if person force you to cancel. The screen go look normal, but HQ go know say you dey danger. E must different from your safe PIN.',
    },
    'pin_err_length': {
      AppLanguage.english: 'Use 4 to 8 digits.',
      AppLanguage.hausa: 'Yi amfani da lambobi 4 zuwa 8.',
      AppLanguage.pidgin: 'Use 4 to 8 numbers.',
    },
    'pin_err_mismatch': {
      AppLanguage.english: 'The PINs do not match. Try again.',
      AppLanguage.hausa: 'Lambobin sirrin ba su yi daidai ba. Sake gwadawa.',
      AppLanguage.pidgin: 'The two PIN no match. Try again.',
    },
    'pin_err_same': {
      AppLanguage.english: 'The duress PIN must be different from the safe PIN.',
      AppLanguage.hausa: 'Dole lambar sirrin tilastawa ta bambanta da lambar sirrin tsaro.',
      AppLanguage.pidgin: 'The duress PIN must different from the safe PIN.',
    },
    'pin_saved': {
      AppLanguage.english: 'Emergency PINs saved.',
      AppLanguage.hausa: 'An ajiye lambobin sirrin gaggawa.',
      AppLanguage.pidgin: 'Emergency PINs don save.',
    },
    'pin_save_failed': {
      AppLanguage.english: 'Could not save PINs — check your connection and try again.',
      AppLanguage.hausa: 'Ba a iya ajiye lambobin sirrin ba — duba intanet ɗinka ka sake gwadawa.',
      AppLanguage.pidgin: 'PINs no gree save — check your network and try again.',
    },
    'pin_save': {
      AppLanguage.english: 'SAVE PINS',
      AppLanguage.hausa: 'AJIYE LAMBOBIN',
      AppLanguage.pidgin: 'SAVE PINS',
    },
    'pin_continue': {
      AppLanguage.english: 'CONTINUE',
      AppLanguage.hausa: 'CI GABA',
      AppLanguage.pidgin: 'CONTINUE',
    },
    // dispatcher chat
    'chat_not_sent': {
      AppLanguage.english: 'MESSAGE NOT SENT — check your connection and retry',
      AppLanguage.hausa: 'BA A AIKA SAƘON BA — duba intanet ɗinka ka sake gwadawa',
      AppLanguage.pidgin: 'MESSAGE NO SEND — check your network and try again',
    },
    'chat_retry': {
      AppLanguage.english: 'RETRY',
      AppLanguage.hausa: 'SAKE GWADAWA',
      AppLanguage.pidgin: 'TRY AGAIN',
    },
    'chat_load_failed': {
      AppLanguage.english: 'Error loading channel messages',
      AppLanguage.hausa: 'Ba a iya buɗe saƙonnin ba',
      AppLanguage.pidgin: 'We no fit load the messages',
    },
    'chat_empty': {
      AppLanguage.english: 'NO SECURE MESSAGES RECORDED',
      AppLanguage.hausa: 'BABU SAƘO TUKUNA',
      AppLanguage.pidgin: 'NO MESSAGE YET',
    },
    'chat_dispatcher': {
      AppLanguage.english: 'Dispatcher',
      AppLanguage.hausa: 'Mai turawa',
      AppLanguage.pidgin: 'Dispatcher',
    },
    'chat_you': {
      AppLanguage.english: 'YOU',
      AppLanguage.hausa: 'KAI',
      AppLanguage.pidgin: 'YOU',
    },
    'chat_stop_dictating': {
      AppLanguage.english: 'Stop dictating',
      AppLanguage.hausa: 'Daina faɗa',
      AppLanguage.pidgin: 'Stop to talk',
    },
    'chat_dictate': {
      AppLanguage.english: 'Dictate a message',
      AppLanguage.hausa: 'Faɗi saƙo da baki',
      AppLanguage.pidgin: 'Talk your message',
    },
    'chat_hint': {
      AppLanguage.english: 'Type secure message...',
      AppLanguage.hausa: 'Rubuta saƙo...',
      AppLanguage.pidgin: 'Type your message...',
    },
    'chat_send': {
      AppLanguage.english: 'Send',
      AppLanguage.hausa: 'Aika',
      AppLanguage.pidgin: 'Send',
    },
    // settings
    'set_bt_unavailable': {
      AppLanguage.english: 'Bluetooth relay is on, but Bluetooth is off or not allowed. Turn on Bluetooth and allow it for Plateau Eye.',
      AppLanguage.hausa: 'An kunna isar da saƙo ta Bluetooth, amma Bluetooth a kashe yake ko ba a ba da izini ba. Kunna Bluetooth ka ba Plateau Eye izini.',
      AppLanguage.pidgin: 'Bluetooth relay don on, but Bluetooth off or e no get permission. On Bluetooth and allow am for Plateau Eye.',
    },
    'set_edit_name_title': {
      AppLanguage.english: 'Edit Name',
      AppLanguage.hausa: 'Gyara Suna',
      AppLanguage.pidgin: 'Change Name',
    },
    'set_full_name': {
      AppLanguage.english: 'Full Name',
      AppLanguage.hausa: 'Cikakken Suna',
      AppLanguage.pidgin: 'Full Name',
    },
    'set_cancel': {
      AppLanguage.english: 'Cancel',
      AppLanguage.hausa: 'Soke',
      AppLanguage.pidgin: 'Cancel',
    },
    'set_save': {
      AppLanguage.english: 'Save',
      AppLanguage.hausa: 'Ajiye',
      AppLanguage.pidgin: 'Save',
    },
    'set_add_contact_title': {
      AppLanguage.english: 'Add Emergency Contact',
      AppLanguage.hausa: 'Ƙara Lambar Gaggawa',
      AppLanguage.pidgin: 'Add Emergency Contact',
    },
    'set_phone_number': {
      AppLanguage.english: 'Phone Number',
      AppLanguage.hausa: 'Lambar Waya',
      AppLanguage.pidgin: 'Phone Number',
    },
    'set_add': {
      AppLanguage.english: 'Add',
      AppLanguage.hausa: 'Ƙara',
      AppLanguage.pidgin: 'Add',
    },
    'set_default_name': {
      AppLanguage.english: 'Citizen User',
      AppLanguage.hausa: 'Ɗan Ƙasa',
      AppLanguage.pidgin: 'Citizen',
    },
    'set_title': {
      AppLanguage.english: 'TACTICAL SYSTEM SETTINGS',
      AppLanguage.hausa: 'SAITUNA',
      AppLanguage.pidgin: 'SETTINGS',
    },
    'set_subtitle': {
      AppLanguage.english: 'PREFERENCES & SECURITY',
      AppLanguage.hausa: 'ZAƁI DA TSARO',
      AppLanguage.pidgin: 'WETIN YOU LIKE AND SECURITY',
    },
    'set_phone_user': {
      AppLanguage.english: 'Phone User:',
      AppLanguage.hausa: 'Mai waya:',
      AppLanguage.pidgin: 'Phone user:',
    },
    'set_unknown': {
      AppLanguage.english: 'Unknown',
      AppLanguage.hausa: 'Ba a sani ba',
      AppLanguage.pidgin: 'We no know',
    },
    'set_edit_name': {
      AppLanguage.english: 'Edit your name',
      AppLanguage.hausa: 'Gyara sunanka',
      AppLanguage.pidgin: 'Change your name',
    },
    'set_push': {
      AppLanguage.english: 'Push Notifications',
      AppLanguage.hausa: 'Sanarwa',
      AppLanguage.pidgin: 'Notifications',
    },
    'set_push_desc': {
      AppLanguage.english: 'Receive emergency alerts',
      AppLanguage.hausa: 'Karɓi saƙonnin gaggawa',
      AppLanguage.pidgin: 'Receive emergency alerts',
    },
    'set_relay': {
      AppLanguage.english: 'Relay emergency alerts',
      AppLanguage.hausa: 'Isar da saƙonnin gaggawa',
      AppLanguage.pidgin: 'Pass emergency alerts',
    },
    'set_relay_desc': {
      AppLanguage.english: 'When there is no network, pass sealed SOS alerts between nearby phones over Bluetooth until one reaches HQ. Phones that carry an alert cannot read it.',
      AppLanguage.hausa: 'Idan babu sabis, a isar da saƙonnin SOS da aka rufe tsakanin wayoyin da ke kusa ta Bluetooth har sai ɗaya ya kai HQ. Wayoyin da ke ɗauke da saƙon ba za su iya karanta shi ba.',
      AppLanguage.pidgin: 'When network no dey, pass closed SOS alerts from one phone to another wey dey near through Bluetooth until one reach HQ. The phones wey carry the alert no fit read am.',
    },
    'set_contacts': {
      AppLanguage.english: 'Emergency Contacts',
      AppLanguage.hausa: 'Lambobin Gaggawa',
      AppLanguage.pidgin: 'Emergency Contacts',
    },
    'set_add_contact': {
      AppLanguage.english: 'Add an emergency contact',
      AppLanguage.hausa: 'Ƙara lambar gaggawa',
      AppLanguage.pidgin: 'Add emergency contact',
    },
    'set_no_contacts': {
      AppLanguage.english: 'No emergency contacts added.',
      AppLanguage.hausa: 'Ba a ƙara lambar gaggawa ba.',
      AppLanguage.pidgin: 'You never add emergency contact.',
    },
    'set_remove_contact': {
      AppLanguage.english: 'Remove this emergency contact',
      AppLanguage.hausa: 'Cire wannan lambar gaggawa',
      AppLanguage.pidgin: 'Remove this emergency contact',
    },
    'set_pin': {
      AppLanguage.english: 'Emergency PIN',
      AppLanguage.hausa: 'Lambar Sirrin Gaggawa',
      AppLanguage.pidgin: 'Emergency PIN',
    },
    'set_pin_desc': {
      AppLanguage.english: 'Set or change your safe and duress PINs',
      AppLanguage.hausa: 'Saita ko canza lambobin sirrinka na tsaro da na tilastawa',
      AppLanguage.pidgin: 'Set or change your safe PIN and duress PIN',
    },
    'set_lock': {
      AppLanguage.english: 'Lock This Phone',
      AppLanguage.hausa: 'Kulle Wannan Manhaja',
      AppLanguage.pidgin: 'Lock This App',
    },
    'set_lock_desc': {
      AppLanguage.english: 'Ask for a code before this app can be used again. The emergency button keeps working.',
      AppLanguage.hausa: 'A nemi lamba kafin a sake amfani da manhajar. Maɓallin gaggawa zai ci gaba da aiki.',
      AppLanguage.pidgin: 'Ask for code before person fit use this app again. The emergency button go still work.',
    },
    'set_removal': {
      AppLanguage.english: 'App Removal Authorization',
      AppLanguage.hausa: 'Izinin Cire Manhaja',
      AppLanguage.pidgin: 'Permission to Remove App',
    },
    'set_sign_out': {
      AppLanguage.english: 'Sign Out Tactical Session',
      AppLanguage.hausa: 'Fita',
      AppLanguage.pidgin: 'Sign Out',
    },
    // app removal request
    'uninst_submitted': {
      AppLanguage.english: 'Uninstall request submitted to HQ Command for authorization.',
      AppLanguage.hausa: 'An aika buƙatar cire manhaja ga HQ domin amincewa.',
      AppLanguage.pidgin: 'We don send your request to remove the app to HQ make dem approve am.',
    },
    'uninst_not_sent': {
      AppLanguage.english: 'Request NOT sent. Check your connection and submit again.',
      AppLanguage.hausa: 'BA A AIKA buƙatar ba. Duba intanet ɗinka ka sake aikawa.',
      AppLanguage.pidgin: 'Request NO SEND. Check your network and send again.',
    },
    'uninst_title': {
      AppLanguage.english: 'APP REMOVAL AUTHORIZATION',
      AppLanguage.hausa: 'IZININ CIRE MANHAJA',
      AppLanguage.pidgin: 'PERMISSION TO REMOVE APP',
    },
    'uninst_subtitle': {
      AppLanguage.english: 'TACTICAL SECURITY POLICY',
      AppLanguage.hausa: 'DOKAR TSARO',
      AppLanguage.pidgin: 'SECURITY RULE',
    },
    'uninst_category': {
      AppLanguage.english: 'REMOVAL CATEGORY',
      AppLanguage.hausa: 'DALILIN CIREWA',
      AppLanguage.pidgin: 'WHY YOU WAN REMOVE AM',
    },
    'uninst_transfer': {
      AppLanguage.english: 'Transfer to Another Unit',
      AppLanguage.hausa: 'Canjin wurin aiki zuwa wata runduna',
      AppLanguage.pidgin: 'Transfer to another unit',
    },
    'uninst_retirement': {
      AppLanguage.english: 'Retirement / End of Service',
      AppLanguage.hausa: 'Ritaya / Ƙarshen aiki',
      AppLanguage.pidgin: 'Retirement / End of service',
    },
    'uninst_phone_change': {
      AppLanguage.english: 'Device Replacement',
      AppLanguage.hausa: 'Canjin waya',
      AppLanguage.pidgin: 'Change of phone',
    },
    'uninst_misconduct': {
      AppLanguage.english: 'Disciplinary Removal',
      AppLanguage.hausa: 'Cirewa saboda ladabtarwa',
      AppLanguage.pidgin: 'Removal because of discipline',
    },
    'uninst_other': {
      AppLanguage.english: 'Other (specify in remarks)',
      AppLanguage.hausa: 'Wani dalili (bayyana a ƙasa)',
      AppLanguage.pidgin: 'Other reason (write am below)',
    },
    'uninst_reason': {
      AppLanguage.english: 'REMOVAL REASON & JUSTIFICATION',
      AppLanguage.hausa: 'BAYANIN DALILIN CIREWA',
      AppLanguage.pidgin: 'EXPLAIN WHY YOU WAN REMOVE AM',
    },
    'uninst_reason_hint': {
      AppLanguage.english: 'Enter operational justification...',
      AppLanguage.hausa: 'Rubuta dalilin...',
      AppLanguage.pidgin: 'Write the reason...',
    },
    'uninst_sending': {
      AppLanguage.english: 'TRANSMITTING...',
      AppLanguage.hausa: 'ANA AIKAWA...',
      AppLanguage.pidgin: 'E DEY SEND...',
    },
    'uninst_submit': {
      AppLanguage.english: 'SUBMIT UNINSTALL REQUEST',
      AppLanguage.hausa: 'AIKA BUƘATAR CIREWA',
      AppLanguage.pidgin: 'SEND REQUEST TO REMOVE',
    },
    // settings: volume SOS with the phone locked (2026-11-18)
    'volume_sos_desc': {
      AppLanguage.english:
          'Press Volume Down three times within 3 seconds to send a silent SOS '
          'without touching the screen. Works while Plateau Eye is open on '
          'screen. On Android it can also work with the phone locked: set that '
          'up below. Off by default, because turning the volume down quickly '
          'can send one by accident.',
      AppLanguage.hausa:
          'Danna maballin rage sauti sau uku cikin dakika 3 don tura SOS a boye '
          'ba tare da taba allo ba. Yana aiki idan Plateau Eye na bude a kan '
          'allo. A wayar Android zai iya aiki ko da wayar a kulle take: saita '
          'hakan a kasa. A kashe yake da farko, domin rage sauti da sauri na '
          'iya tura shi bisa kuskure.',
      AppLanguage.pidgin:
          'Press volume down three times inside 3 seconds to send silent SOS '
          'without touching the screen. E dey work when Plateau Eye dey open '
          'for screen. For Android phone e fit work even when phone lock: set '
          'am up below. E dey off first, because if you press volume down '
          'quick-quick e fit send one by mistake.',
    },
    'vsos_lock_on': {
      AppLanguage.english: 'Works with the phone locked too.',
      AppLanguage.hausa: 'Yana aiki ko da wayar a kulle take.',
      AppLanguage.pidgin: 'E dey work even when phone lock.',
    },
    'vsos_lock_off': {
      AppLanguage.english: 'Only works while the app is open. To use it with the phone locked, turn on Plateau Eye in Android’s Accessibility settings.',
      AppLanguage.hausa: 'Yana aiki ne kawai idan manhajar a bude take. Don amfani da shi idan wayar a kulle take, kunna Plateau Eye a saitunan Accessibility na Android.',
      AppLanguage.pidgin: 'E dey work only when the app dey open. To use am when phone lock, on Plateau Eye for Android Accessibility settings.',
    },
    'vsos_lock_setup': {
      AppLanguage.english: 'SET UP FOR A LOCKED PHONE',
      AppLanguage.hausa: 'SAITA DOMIN WAYA A KULLE',
      AppLanguage.pidgin: 'SET AM FOR LOCKED PHONE',
    },
    'vsos_lock_check_again': {
      AppLanguage.english: 'CHECK AGAIN',
      AppLanguage.hausa: 'SAKE DUBAWA',
      AppLanguage.pidgin: 'CHECK AGAIN',
    },
    'vsos_disclosure_title': {
      AppLanguage.english: 'Volume Down SOS with the phone locked',
      AppLanguage.hausa: 'SOS ta rage sauti idan waya a kulle take',
      AppLanguage.pidgin: 'Volume down SOS when phone lock',
    },
    'vsos_disclosure_body': {
      AppLanguage.english: 'To hear Volume Down while the phone is locked or the app is closed, Plateau Eye uses an Android accessibility service.\n\nIt only notices the Volume Down button. It does not read your screen, what you type, or anything in other apps, and it sends nothing anywhere except the SOS itself. The volume still changes as normal, so nobody watching can tell.\n\nOn the next screen, choose "Plateau Eye: Volume Down SOS" and switch it on. If Android says the setting is restricted, open Plateau Eye in App info, tap the ⋮ menu, choose "Allow restricted settings", and try again.',
      AppLanguage.hausa: 'Domin jin maballin rage sauti idan wayar a kulle take ko manhajar a rufe, Plateau Eye na amfani da sabis na Accessibility na Android.\n\nMaballin rage sauti kawai yake lura da shi. Ba ya karanta allonka, abin da kake rubutawa, ko komai a wasu manhajoji, kuma ba ya aika komai sai SOS kanta. Sauti zai ci gaba da raguwa kamar yadda aka saba, don haka mai kallo ba zai gane ba.\n\nA shafi na gaba, zaɓi "Plateau Eye: Volume Down SOS" ka kunna shi. Idan Android ta ce an taƙaita saitin, buɗe Plateau Eye a App info, danna menu ⋮, zaɓi "Allow restricted settings", sannan ka sake gwadawa.',
      AppLanguage.pidgin: 'To hear volume down when phone lock or the app close, Plateau Eye dey use Android accessibility service.\n\nE only dey notice the volume down button. E no dey read your screen, wetin you type, or anything for other apps, and e no dey send anything except the SOS itself. The volume still go reduce normal, so person wey dey look no go know.\n\nFor the next screen, choose "Plateau Eye: Volume Down SOS" and on am. If Android talk say the setting dey restricted, open Plateau Eye for App info, press the ⋮ menu, choose "Allow restricted settings", then try again.',
    },
    'vsos_disclosure_open': {
      AppLanguage.english: 'OPEN SETTINGS',
      AppLanguage.hausa: 'BUƊE SAITUNA',
      AppLanguage.pidgin: 'OPEN SETTINGS',
    },
    'vsos_disclosure_cancel': {
      AppLanguage.english: 'NOT NOW',
      AppLanguage.hausa: 'BA YANZU BA',
      AppLanguage.pidgin: 'NO BE NOW',
    },
    'rpt_outside_plateau': {
      AppLanguage.english: 'Outside Plateau boundary polygons',
      AppLanguage.hausa: 'A wajen iyakar Jihar Filato',
      AppLanguage.pidgin: 'Outside Plateau State boundary',
    },
    'rpt_pinned_location': {
      AppLanguage.english: 'PINNED INCIDENT LOCATION',
      AppLanguage.hausa: 'WURIN DA AKA ZABA A TASWIRA',
      AppLanguage.pidgin: 'PINNED INCIDENT LOCATION',
    },
    'rpt_hide_map_picker': {
      AppLanguage.english: 'HIDE MAP PIN PICKER',
      AppLanguage.hausa: 'BOYE TASWIRAR ZABAR WURI',
      AppLanguage.pidgin: 'HIDE MAP PIN PICKER',
    },
    'rpt_pick_on_map': {
      AppLanguage.english: 'PICK / ADJUST ON MAP',
      AppLanguage.hausa: 'ZABI WURI A KAN TASWIRA',
      AppLanguage.pidgin: 'PICK / ADJUST FOR MAP',
    },
    'rpt_use_live_gps': {
      AppLanguage.english: 'USE LIVE GPS',
      AppLanguage.hausa: 'YI AMFANI DA GPS KAI TSAYE',
      AppLanguage.pidgin: 'USE LIVE GPS',
    },
    'rpt_map_tap_hint': {
      AppLanguage.english:
          'Tap anywhere on the map to pin exact incident coordinates.',
      AppLanguage.hausa:
          'Danna ko ina a kan taswirar don nuna ainihin inda abin ya faru.',
      AppLanguage.pidgin:
          'Tap anywhere for the map to pin the exact place wey e happen.',
    },
    'trk_stale_tag': {
      AppLanguage.english: 'STALE',
      AppLanguage.hausa: 'TSOHON BAYANI',
      AppLanguage.pidgin: 'OLD SIGNAL',
    },
    'trk_live_tag': {
      AppLanguage.english: 'LIVE',
      AppLanguage.hausa: 'Yanzu',
      AppLanguage.pidgin: 'LIVE',
    },
    // ---- END OF DRAFT TRANSLATIONS AWAITING A NATIVE SPEAKER ----
  };

  /// The string for [key] in [lang].
  ///
  /// Falls back to ENGLISH when a key exists but has no entry for that
  /// language — a half-translated key should read as English, not as a
  /// variable name. A key that is not defined at all still returns the key
  /// itself, which is loud and debuggable;
  /// `scripts/check_translation_keys.py` stops one reaching a release, because
  /// the citizen's emergency chat header shipped reading
  /// `live_dispatch_channel` in every language.
  static String get(String key, AppLanguage lang) {
    final entry = _keys[key];
    if (entry == null) return key;
    return entry[lang] ?? entry[AppLanguage.english] ?? key;
  }

  /// Every key this table defines. Used by the tests and the CI check.
  static Iterable<String> get keys => _keys.keys;

  /// The languages [key] has a string for.
  static Iterable<AppLanguage> languagesFor(String key) =>
      _keys[key]?.keys ?? const <AppLanguage>[];
}
