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
    'eme_broadcasting_notified': {
      AppLanguage.english: 'Emergency alert active · Command HQ notified',
      AppLanguage.hausa: 'Kiran dauki na gudana · An sanar da cibiyar umarni',
      AppLanguage.pidgin: 'Emergency dey on · Command HQ know',
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
    'trk_semantics_open_responder': {
      AppLanguage.english: 'Open the details for {who}, status {status}',
      AppLanguage.hausa: 'Bude bayanan {who}, matsayi {status}',
      AppLanguage.pidgin: 'Open the info for {who}, status {status}',
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
    'sz_route_calculated_clear': {
      AppLanguage.english: 'Safe route calculated to {name}. The path is clear.',
      AppLanguage.hausa:
          'An gano amintacciyar hanya zuwa {name}. Hanyar a bude take.',
      AppLanguage.pidgin:
          'Safe road to {name} dey ready. The road clear well.',
    },
    'sz_route_calculated_warning': {
      AppLanguage.english:
          'Safe route calculated to {name}. Warning: The route passes near '
          'an active threat. Proceed with extreme caution.',
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
      AppLanguage.english: 'EMERGENCY — SEND SOS NOW',
      AppLanguage.hausa: 'GAGGAWA — NEMI TAIMAKON SOS YANZU',
      AppLanguage.pidgin: 'EMERGENCY — SEND SOS NOW',
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
