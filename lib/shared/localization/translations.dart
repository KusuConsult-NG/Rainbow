import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppLanguage {
  english('en', 'English', 'EN 🇬🇧'),
  hausa('ha', 'Hausa', 'HA 🇳🇬'),
  pidgin('pcm', 'Pidgin', 'PG 🇳🇬');

  final String code;
  final String label;
  final String flagLabel;
  const AppLanguage(this.code, this.label, this.flagLabel);
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
    'sample_speech_prompt': {
      AppLanguage.english: 'Say something like: "Violent crash on Bauchi Road..."',
      AppLanguage.hausa: 'Fadi wani abu kamar: "Hadari mai tsanani a Bauchi Road..."',
      AppLanguage.pidgin: 'Talk something like: "Violent crash on Bauchi Road..."',
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
      AppLanguage.english: 'SELECT THE CATEGORY THAT BEST DESCRIBES THE CURRENT EMERGENCY. LOCATION TELEMETRY IS AUTO-ATTACHED.',
      AppLanguage.hausa: 'ZABI RUKUNIN DA YA FI DACHEWA DA MATSALAR. ANA HADA TELEMETRY TA KAI TSAYE.',
      AppLanguage.pidgin: 'SELECT CATEGORY WEY FIT DE DESCRIBE WAHALA. LOCATION DE AUTOMATICALLY ATTACH.',
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
  };

  static String get(String key, AppLanguage lang) {
    return _keys[key]?[lang] ?? key;
  }
}
