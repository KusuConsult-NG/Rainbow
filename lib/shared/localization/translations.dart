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
  };

  static String get(String key, AppLanguage lang) {
    return _keys[key]?[lang] ?? key;
  }
}
