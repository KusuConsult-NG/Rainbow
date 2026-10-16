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
