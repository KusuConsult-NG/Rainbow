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

const List<AlertCategoryInfo> alertCategories = [
  AlertCategoryInfo(
    category: AlertCategory.lifeThreatening,
    label: 'Kidnap',
    emoji: '🟥',
    priority: 'CRITICAL',
    color: AppColors.primary,
    bg: Color(0xFFFFDAD6),
    icon: Icons.person_off_rounded,
    subTypes: ['Immediate Abduction', 'Held Hostage', 'Attempted Kidnap'],
  ),
  AlertCategoryInfo(
    category: AlertCategory.publicSafety,
    label: 'Fire',
    emoji: '🔥',
    priority: 'CRITICAL',
    color: Color(0xFFE65100),
    bg: Color(0xFFFFE0B2),
    icon: Icons.local_fire_department_rounded,
    subTypes: ['Building Fire', 'Bush Fire', 'Vehicle Fire'],
  ),
  AlertCategoryInfo(
    category: AlertCategory.socialSensitive,
    label: 'Drug abuse',
    emoji: '💊',
    priority: 'MEDIUM',
    color: Color(0xFFF57F17),
    bg: Color(0xFFFFF9C4),
    icon: Icons.medication_liquid_rounded,
    subTypes: ['Public Drug Use', 'Drug Distribution', 'Overdose'],
  ),
  AlertCategoryInfo(
    category: AlertCategory.general,
    label: 'Police brutality',
    emoji: '👮',
    priority: 'HIGH',
    color: Color(0xFF0D47A1),
    bg: Color(0xFFE3F2FD),
    icon: Icons.local_police_rounded,
    subTypes: ['Physical Assault', 'Extortion', 'Unlawful Arrest'],
  ),
  AlertCategoryInfo(
    category: AlertCategory.publicSafety,
    label: 'Flood',
    emoji: '🌊',
    priority: 'MEDIUM',
    color: Color(0xFF0288D1),
    bg: Color(0xFFE1F5FE),
    icon: Icons.water_damage_rounded,
    subTypes: ['Flash Flood', 'Blocked Drainage', 'Submerged Property'],
  ),
  AlertCategoryInfo(
    category: AlertCategory.cyberDigital,
    label: 'Cyber crime',
    emoji: '💻',
    priority: 'MEDIUM',
    color: Color(0xFF1B5E20),
    bg: Color(0xFFE8F5E9),
    icon: Icons.computer_rounded,
    subTypes: ['Online Fraud', 'Identity Theft', 'Blackmail'],
  ),
  AlertCategoryInfo(
    category: AlertCategory.lifeThreatening,
    label: 'Child abuse',
    emoji: '🧒',
    priority: 'CRITICAL',
    color: Color(0xFF6A1B9A),
    bg: Color(0xFFF3E5F5),
    icon: Icons.child_care_rounded,
    subTypes: ['Physical Abuse', 'Neglect', 'Labor'],
  ),
  AlertCategoryInfo(
    category: AlertCategory.violentCriminal,
    label: 'Domestic violence',
    emoji: '🏠',
    priority: 'HIGH',
    color: Color(0xFFC2185B),
    bg: Color(0xFFFCE4EC),
    icon: Icons.family_restroom_rounded,
    subTypes: ['Physical Violence', 'Threats', 'Trapped'],
  ),
  AlertCategoryInfo(
    category: AlertCategory.violentCriminal,
    label: 'Cattle rustling',
    emoji: '🐄',
    priority: 'HIGH',
    color: Color(0xFF4E342E),
    bg: Color(0xFFEFEBE9),
    icon: Icons.agriculture_rounded,
    subTypes: ['Armed Rustling', 'Missing Herd', 'Trespassing'],
  ),
  AlertCategoryInfo(
    category: AlertCategory.lifeThreatening,
    label: 'Community attack',
    emoji: '⚔️',
    priority: 'CRITICAL',
    color: Color(0xFFB71C1C),
    bg: Color(0xFFFFEBEE),
    icon: Icons.warning_rounded,
    subTypes: ['Armed Invasion', 'Riot', 'Vandalism'],
  ),
];

/// Documentation for this public member.

AlertCategoryInfo categoryById(AlertCategory cat) =>
    alertCategories.firstWhere((c) => c.category == cat);
