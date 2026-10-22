import 'package:flutter/material.dart';
import 'package:rainbow_app/core/theme/app_colors.dart';

/// Documentation for this public member.

enum AlertCategory {
  /// Documentation for this public member.
  lifeThreatening,

  /// Documentation for this public member.
  violentCriminal,

  /// Documentation for this public member.
  socialSensitive,

  /// Documentation for this public member.
  publicSafety,

  /// Documentation for this public member.
  cyberDigital,

  /// Documentation for this public member.
  general,
}

/// Documentation for this public member.

/// One question a responder needs answered before they set off, and the
/// handful of answers worth offering as a tap.
///
/// Every report used to carry the same three things whatever it was about: a
/// free-text narrative, optional media, and a place. For a responder that is
/// the difference between "Kidnap - Immediate Abduction near Naraguta" and
/// knowing whether the people who took them were armed, how long ago it
/// happened, and whether they left in a vehicle. The first is a reason to send
/// somebody; the second is what decides who, and how many, and how fast.
///
/// Taps, not typing, and never required. The brief this came from is explicit:
/// "Users shouldn't go through a lot before using the app. it should just be
/// simple taps and desired results are achieved." A person reporting an
/// abduction is not going to fill in a form, and a form that delays the report
/// costs more than the detail gains.
class ResponsePrompt {
  /// Documentation for this public member.
  const ResponsePrompt({required this.question, required this.options});

  /// What a responder needs to know, phrased as somebody would ask it aloud.
  final String question;

  /// The answers offered as chips. Short enough to read at a glance.
  final List<String> options;
}

class AlertCategoryInfo {
  /// Documentation for this public member.
  const AlertCategoryInfo({
    required this.category,
    required this.label,
    required this.emoji,
    required this.priority,
    required this.color,
    required this.bg,
    required this.icon,
    required this.subTypes,
    this.responsePrompts = const [],
  });

  /// Documentation for this public member.
  final AlertCategory category;

  /// Documentation for this public member.
  final String label;

  /// Documentation for this public member.
  final String emoji;

  /// Documentation for this public member.
  final String priority; // CRITICAL, HIGH, MEDIUM, LOW
  /// Documentation for this public member.
  final Color color;

  /// Documentation for this public member.
  final Color bg;

  /// Documentation for this public member.
  final IconData icon;

  /// Documentation for this public member.
  final List<String> subTypes;

  /// What a responder needs to know about THIS kind of incident.
  ///
  /// Empty for a category where the narrative is the detail — a cyber crime
  /// report is a story, not a set of fields — and that is a deliberate answer
  /// rather than an omission. Asking three questions that do not change the
  /// response is the same cost as asking three that do, paid by somebody in
  /// trouble.
  final List<ResponsePrompt> responsePrompts;
}

/// Documentation for this public member.

// COLOURED BY PRIORITY, NOT BY TOPIC.
//
// Each category used to carry a hue of its own — Fire orange, Police
// brutality cobalt, Child abuse purple, Cattle rustling brown, Flood sky,
// Public property teal. Twelve hues, none of them in the Plateau Eye mark,
// written into this file where no palette change could reach them. A citizen
// scrolling the list saw a paint chart.
//
// Now the colour says something true instead: it is the priority. Red is an
// emergency, gold is high, navy is medium, emerald is one of the two everyday
// reports — the same emerald as the state silhouette in the logo, and the
// same split the database enforces when it decides whether to page anyone.
//
// The priority word is on every card beside the colour, because a colour that
// is the only thing saying "this is an emergency" says it to nobody using a
// screen reader, and to nobody who cannot tell these hues apart.
const List<AlertCategoryInfo> alertCategories = [
  AlertCategoryInfo(
    category: AlertCategory.lifeThreatening,
    label: 'Kidnap',
    emoji: '🟥',
    priority: 'CRITICAL',
    color: AppColors.danger,
    bg: AppColors.dangerTint,
    icon: Icons.person_off_rounded,
    subTypes: ['Immediate Abduction', 'Held Hostage', 'Attempted Kidnap'],
    responsePrompts: [
      ResponsePrompt(
        question: 'Are they armed?',
        options: ['Armed', 'Not armed', "Don't know"],
      ),
      ResponsePrompt(
        question: 'How long ago?',
        options: ['Happening now', 'Under an hour', 'Over an hour'],
      ),
      ResponsePrompt(
        question: 'How did they leave?',
        options: ['On foot', 'By vehicle', 'Still here', "Don't know"],
      ),
    ],
  ),
  AlertCategoryInfo(
    category: AlertCategory.publicSafety,
    label: 'Fire',
    emoji: '🔥',
    priority: 'CRITICAL',
    color: AppColors.danger,
    bg: AppColors.dangerTint,
    icon: Icons.local_fire_department_rounded,
    subTypes: ['Building Fire', 'Bush Fire', 'Vehicle Fire'],
    responsePrompts: [
      ResponsePrompt(
        question: 'Is anyone inside?',
        options: ['People inside', 'Everyone out', "Don't know"],
      ),
      ResponsePrompt(
        question: 'Is it spreading?',
        options: ['Spreading fast', 'Contained', "Don't know"],
      ),
    ],
  ),
  AlertCategoryInfo(
    category: AlertCategory.socialSensitive,
    label: 'Drug abuse',
    emoji: '💊',
    priority: 'MEDIUM',
    color: AppColors.primary,
    bg: AppColors.navyTint,
    icon: Icons.medication_liquid_rounded,
    subTypes: ['Public Drug Use', 'Drug Distribution', 'Overdose'],
    responsePrompts: [
      ResponsePrompt(
        question: 'Does anyone need medical help?',
        options: ['Medical help needed', 'Nobody hurt'],
      ),
    ],
  ),
  AlertCategoryInfo(
    category: AlertCategory.general,
    label: 'Police brutality',
    emoji: '👮',
    priority: 'HIGH',
    color: AppColors.warning,
    bg: AppColors.goldTint,
    icon: Icons.local_police_rounded,
    subTypes: ['Physical Assault', 'Extortion', 'Unlawful Arrest'],
    responsePrompts: [
      ResponsePrompt(
        question: 'Is it still happening?',
        options: ['Happening now', 'Already over'],
      ),
      ResponsePrompt(
        question: 'Is anyone hurt?',
        options: ['Someone hurt', 'Nobody hurt', "Don't know"],
      ),
    ],
  ),
  AlertCategoryInfo(
    category: AlertCategory.publicSafety,
    label: 'Flood',
    emoji: '🌊',
    priority: 'MEDIUM',
    color: AppColors.primary,
    bg: AppColors.navyTint,
    icon: Icons.water_damage_rounded,
    subTypes: ['Flash Flood', 'Blocked Drainage', 'Submerged Property'],
    responsePrompts: [
      ResponsePrompt(
        question: 'Is anyone trapped?',
        options: ['People trapped', 'Nobody trapped', "Don't know"],
      ),
      ResponsePrompt(
        question: 'How deep?',
        options: ['Ankle', 'Waist', 'Above head'],
      ),
    ],
  ),
  AlertCategoryInfo(
    category: AlertCategory.cyberDigital,
    label: 'Cyber crime',
    emoji: '💻',
    priority: 'MEDIUM',
    color: AppColors.primary,
    bg: AppColors.navyTint,
    icon: Icons.computer_rounded,
    subTypes: ['Online Fraud', 'Identity Theft', 'Blackmail'],
  ),
  AlertCategoryInfo(
    category: AlertCategory.lifeThreatening,
    label: 'Child abuse',
    emoji: '🧒',
    priority: 'CRITICAL',
    color: AppColors.danger,
    bg: AppColors.dangerTint,
    icon: Icons.child_care_rounded,
    subTypes: ['Physical Abuse', 'Neglect', 'Labor'],
    responsePrompts: [
      ResponsePrompt(
        question: 'Is the child in danger now?',
        options: ['In danger now', 'Safe for now', "Don't know"],
      ),
      ResponsePrompt(
        question: 'Is the person responsible there?',
        options: ['Still there', 'Gone', "Don't know"],
      ),
    ],
  ),
  AlertCategoryInfo(
    category: AlertCategory.violentCriminal,
    label: 'Domestic violence',
    emoji: '🏠',
    priority: 'HIGH',
    color: AppColors.warning,
    bg: AppColors.goldTint,
    icon: Icons.family_restroom_rounded,
    subTypes: ['Physical Violence', 'Threats', 'Trapped'],
    responsePrompts: [
      ResponsePrompt(
        question: 'Is the attacker still there?',
        options: ['Still there', 'Gone', "Don't know"],
      ),
      ResponsePrompt(
        question: 'Is anyone hurt?',
        options: ['Someone hurt', 'Nobody hurt', "Don't know"],
      ),
      ResponsePrompt(
        question: 'Is a weapon involved?',
        options: ['Weapon', 'No weapon', "Don't know"],
      ),
    ],
  ),
  AlertCategoryInfo(
    category: AlertCategory.violentCriminal,
    label: 'Cattle rustling',
    emoji: '🐄',
    priority: 'HIGH',
    color: AppColors.warning,
    bg: AppColors.goldTint,
    icon: Icons.agriculture_rounded,
    subTypes: ['Armed Rustling', 'Missing Herd', 'Trespassing'],
    responsePrompts: [
      ResponsePrompt(
        question: 'Are they armed?',
        options: ['Armed', 'Not armed', "Don't know"],
      ),
      ResponsePrompt(
        question: 'Which way did they go?',
        options: ['North', 'South', 'East', 'West', "Don't know"],
      ),
    ],
  ),
  AlertCategoryInfo(
    category: AlertCategory.lifeThreatening,
    label: 'Community attack',
    emoji: '⚔️',
    priority: 'CRITICAL',
    color: AppColors.danger,
    bg: AppColors.dangerTint,
    icon: Icons.warning_rounded,
    subTypes: ['Armed Invasion', 'Riot', 'Vandalism'],
    responsePrompts: [
      ResponsePrompt(
        question: 'Are they armed?',
        options: ['Armed', 'Not armed', "Don't know"],
      ),
      ResponsePrompt(
        question: 'Roughly how many?',
        options: ['A few', 'Dozens', 'More than fifty', "Don't know"],
      ),
      ResponsePrompt(
        question: 'Is it still going on?',
        options: ['Happening now', 'Already over'],
      ),
    ],
  ),
  // ── The two that are not emergencies ──────────────────────────────────────
  //
  // Everything above is somebody in danger now. These are not, and the
  // difference is enforced in the database rather than left to the label:
  // `is_non_emergency()` matches on the CATEGORY — the part of `type` before
  // ' - ' — so `PUBLIC PROPERTY` and `PUBLIC SERVICE` are filed at the LGA,
  // never pre-assigned to a responder, and never climbed by the timeout sweep.
  // A broken culvert reported at 02:00 would otherwise page the patrol that
  // cannot fix it and be an HQ-tier incident by morning.
  //
  // THE LABELS ARE LOAD-BEARING. They are what the database matches, through
  // `type` = '<label> - <subtype>'. `scripts/check_non_emergency_categories_agree.py`
  // fails if these two and the SQL function disagree, because a category the
  // app can file and the database does not recognise is paged out like an
  // emergency — silently, and at night.
  AlertCategoryInfo(
    category: AlertCategory.general,
    label: 'Public property',
    emoji: '🏛️',
    priority: 'LOW',
    color: AppColors.emeraldDeep,
    bg: AppColors.emeraldTint,
    icon: Icons.account_balance_rounded,
    subTypes: [
      'Abandoned or derelict',
      'Vandalised or destroyed',
      'Needs repair',
      'Mismanaged or misused',
      'Unsafe to the public',
      'Illegally occupied',
    ],
  ),
  AlertCategoryInfo(
    category: AlertCategory.general,
    label: 'Public service',
    emoji: '🛠️',
    priority: 'LOW',
    color: AppColors.emeraldDeep,
    bg: AppColors.emeraldTint,
    icon: Icons.handyman_rounded,
    subTypes: [
      'No water supply',
      'No power supply',
      'Blocked drain or refuse',
      'Road or bridge damaged',
      'Street light out',
      'Clinic or school neglected',
    ],
  ),
];

/// Documentation for this public member.

AlertCategoryInfo categoryById(AlertCategory cat) =>
    alertCategories.firstWhere((c) => c.category == cat);
