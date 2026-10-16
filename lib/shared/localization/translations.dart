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
    'title': {
      AppLanguage.english: 'OPERATION RAINBOW',
      AppLanguage.hausa: 'AIKIN RAINBOW',
      AppLanguage.pidgin: 'OPERATION RAINBOW',
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
          'This phone has not given Operation Rainbow access to the '
          'microphone, so your voice cannot be recorded. Allow it in your '
          'phone settings, or send a photo instead.',
      AppLanguage.hausa:
          'Wannan wayar ba ta ba Operation Rainbow damar amfani da makirufo '
          'ba, don haka ba za a iya naɗa muryar ka ba. Ba da izini a cikin '
          'saitunan wayar, ko ka aika hoto maimakon haka.',
      AppLanguage.pidgin:
          'Dis phone no gree give Operation Rainbow access to di microphone, '
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
