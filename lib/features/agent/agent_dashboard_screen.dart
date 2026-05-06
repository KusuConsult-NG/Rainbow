import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import '../../core/theme/app_colors.dart';
import '../../core/router/app_router.dart';
import '../../services/background_tracking_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../shared/widgets/rainbow_map.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:local_auth/local_auth.dart' as local_auth;

class AgentDashboardScreen extends StatefulWidget {
  final String roleId;
  const AgentDashboardScreen({super.key, required this.roleId});

  @override
  State<AgentDashboardScreen> createState() => _AgentDashboardScreenState();
}

class _AgentDashboardScreenState extends State<AgentDashboardScreen> {
  Map<String, dynamic>? _userProfile;

  @override
  void initState() {
    super.initState();
    _fetchProfile();
  }

  Future<void> _fetchProfile() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      if (mounted) {
        setState(() {
          _userProfile = doc.data();
        });
      }
    }
  }
  String get _roleTitle {
    switch (widget.roleId) {
      case 'POLLING_UNIT': return 'UNIT COMMAND';
      case 'WARD_OFFICER': return 'WARD COMMAND';
      case 'LGA_OFFICER': return 'LGA COMMAND';
      default: return 'TACTICAL HQ';
    }
  }

  String get _assignedTier {
    switch (widget.roleId) {
      case 'POLLING_UNIT': return 'POLLING_UNIT';
      case 'WARD_OFFICER': return 'WARD';
      case 'LGA_OFFICER': return 'LGA';
      default: return 'POLLING_UNIT';
    }
  }

  bool _showMap = false;

  Future<void> _verifyAndExecute(VoidCallback onVerified) async {
    final auth = local_auth.LocalAuthentication();
    try {
      final didAuth = await auth.authenticate(
        localizedReason: 'SECURE MISSION AUTHORIZATION REQUIRED',
        options: const local_auth.AuthenticationOptions(stickyAuth: true, biometricOnly: true),
      );
      if (didAuth) {
        HapticFeedback.mediumImpact();
        onVerified();
      }
    } catch (_) {
       // Fallback logic could go here
    }
  }

  void _showActionDialog(DocumentSnapshot alertDoc) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => _TacticalActionSheet(
        alertDoc: alertDoc,
        assignedTier: _assignedTier,
        onAction: () => Navigator.pop(context),
        verifyAndExecute: _verifyAndExecute,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        SystemNavigator.pop();
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          backgroundColor: AppColors.background.withValues(alpha: 0.8),
          elevation: 0,
          flexibleSpace: ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Container(color: Colors.transparent),
            ),
          ),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _roleTitle,
                style: GoogleFonts.outfit(
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  fontSize: 18,
                  letterSpacing: 1.0,
                ),
              ),
              Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'LIVE MISSION FEED',
                    style: GoogleFonts.outfit(
                      color: AppColors.primary,
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2.0,
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            IconButton(
              icon: Icon(_showMap ? Icons.view_headline_rounded : Icons.radar_rounded, color: AppColors.primary),
              onPressed: () {
                HapticFeedback.lightImpact();
                setState(() => _showMap = !_showMap);
              },
            ),
            IconButton(
              icon: const Icon(Icons.power_settings_new_rounded, color: Colors.white38),
              onPressed: () => context.go(AppRoutes.login),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: Stack(
          children: [
            if (_userProfile == null)
              const Center(child: CircularProgressIndicator(color: AppColors.primary))
            else
              StreamBuilder<QuerySnapshot>(
                stream: _buildAlertsStream(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator(color: AppColors.primary));
                  }
                  
                  final allDocs = snapshot.data?.docs ?? [];
                  final filteredDocs = allDocs.where((doc) {
                    final alert = doc.data() as Map<String, dynamic>;
                    final assignedTo = alert['assigned_to'] as String?;
                    
                    if (widget.roleId == 'HQ_OFFICER') return true;
                    if (widget.roleId == 'LGA_OFFICER') return ['POLLING_UNIT', 'WARD', 'LGA'].contains(assignedTo);
                    if (widget.roleId == 'WARD_OFFICER') return ['POLLING_UNIT', 'WARD'].contains(assignedTo);
                    return assignedTo == 'POLLING_UNIT';
                  }).toList();

                  return AnimatedSwitcher(
                    duration: const Duration(milliseconds: 500),
                    child: _showMap ? _buildMap(filteredDocs) : _buildList(filteredDocs),
                  );
                },
              ),
            // Scanner overlay effect
            IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      AppColors.primary.withValues(alpha: 0.02),
                      Colors.transparent,
                      Colors.transparent,
                      AppColors.primary.withValues(alpha: 0.02),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Stream<QuerySnapshot> _buildAlertsStream() {
    Query query = FirebaseFirestore.instance
        .collection('alerts')
        .where('status', whereIn: ['ACTIVE', 'DURESS']);

    final profile = _userProfile!;
    
    // Support multi-jurisdiction assignment via arrays
    final List<dynamic> assignedLgas = profile['geo_lgas'] ?? (profile['geo_lga'] != null ? [profile['geo_lga']] : []);
    final List<dynamic> assignedWards = profile['geo_wards'] ?? (profile['geo_ward'] != null ? [profile['geo_ward']] : []);
    final List<dynamic> assignedPus = profile['geo_pus'] ?? (profile['geo_pu'] != null ? [profile['geo_pu']] : []);

    if (widget.roleId == 'LGA_OFFICER' && !assignedLgas.contains('ALL')) {
      if (assignedLgas.isNotEmpty) query = query.where('geo_lga', whereIn: assignedLgas);
    } else if (widget.roleId == 'WARD_OFFICER' && !assignedWards.contains('ALL')) {
      if (assignedWards.isNotEmpty) query = query.where('geo_ward', whereIn: assignedWards);
    } else if ((widget.roleId == 'POLLING_OFFICER' || widget.roleId == 'POLLING_UNIT') && !assignedPus.contains('ALL')) {
      if (assignedPus.isNotEmpty) query = query.where('geo_pu', whereIn: assignedPus);
    }

    return query.snapshots();
  }

  Widget _buildList(List<DocumentSnapshot> alerts) {
    if (alerts.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.radar_rounded, size: 64, color: Colors.white10),
            const SizedBox(height: 24),
            Text(
              'SCANNING FOR SIGNALS...',
              style: GoogleFonts.outfit(
                color: Colors.white24,
                fontWeight: FontWeight.w900,
                letterSpacing: 3,
                fontSize: 12,
              ),
            ),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 120, 16, 40),
      itemCount: alerts.length,
      itemBuilder: (context, index) {
        final alert = alerts[index].data() as Map<String, dynamic>;
        return _MissionCard(
          alert: alert,
          onTap: () => _showActionDialog(alerts[index]),
        );
      },
    );
  }

  Widget _buildMap(List<DocumentSnapshot> alerts) {
    return RainbowMap(
      center: const LatLng(9.9285, 8.8923),
      initialZoom: 13,
      markers: alerts.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        final lat = data['lat'] as double?;
        final lng = data['lng'] as double?;
        if (lat == null || lng == null) return null;
        final isEmergency = data['type']?.toString().contains('EMERGENCY') ?? false;
        return Marker(
          point: LatLng(lat, lng),
          width: 60,
          height: 60,
          child: GestureDetector(
            onTap: () => _showActionDialog(doc),
            child: _PulseMarker(isEmergency: isEmergency),
          ),
        );
      }).whereType<Marker>().toList(),
    );
  }
}

class _MissionCard extends StatelessWidget {
  final Map<String, dynamic> alert;
  final VoidCallback onTap;

  const _MissionCard({required this.alert, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isEmergency = alert['type']?.toString().contains('EMERGENCY') ?? false;
    final priority = alert['priority']?.toString().toUpperCase() ?? 'MEDIUM';
    
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isEmergency ? AppColors.emergency.withValues(alpha: 0.3) : Colors.white10,
          width: 1,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _StatusBadge(
                        label: priority,
                        color: isEmergency ? AppColors.emergency : AppColors.primary,
                      ),
                      const Spacer(),
                      Text(
                        _formatTime(alert['createdAt'] ?? alert['timestamp']),
                        style: GoogleFonts.outfit(
                          fontSize: 11,
                          color: Colors.white38,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    alert['type']?.toString().toUpperCase() ?? 'UNKNOWN MISSION',
                    style: GoogleFonts.outfit(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    alert['description'] ?? 'No narrative provided',
                    style: GoogleFonts.outfit(
                      color: Colors.white60,
                      fontSize: 13,
                      height: 1.5,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 20),
                  const Divider(color: AppColors.white05, height: 1),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Icon(Icons.location_on_rounded, color: AppColors.primary, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${alert['geo_lga'] ?? 'PLATEAU'} · ${alert['geo_ward'] ?? 'HQ'} · ${alert['geo_pu'] ?? 'UNIT'}'.toUpperCase(),
                          style: GoogleFonts.outfit(
                            color: Colors.white38,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.0,
                          ),
                        ),
                      ),
                      const Icon(Icons.chevron_right_rounded, color: Colors.white24, size: 20),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _formatTime(dynamic timestamp) {
    if (timestamp == null) return 'T-00:00';
    if (timestamp is Timestamp) {
      final dt = timestamp.toDate();
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')} HRS';
    }
    return 'RECENT';
  }
}

class _StatusBadge extends StatelessWidget {
  final String label;
  final Color color;
  const _StatusBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 4,
            height: 4,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: GoogleFonts.outfit(
              fontSize: 9,
              fontWeight: FontWeight.w900,
              color: color,
              letterSpacing: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _TacticalActionSheet extends StatelessWidget {
  final DocumentSnapshot alertDoc;
  final String assignedTier;
  final VoidCallback onAction;
  final Function(VoidCallback) verifyAndExecute;

  const _TacticalActionSheet({
    required this.alertDoc,
    required this.assignedTier,
    required this.onAction,
    required this.verifyAndExecute,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 40),
      decoration: const BoxDecoration(
        color: Color(0xFF0F0F0F),
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        border: Border(top: BorderSide(color: Colors.white10)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(color: Colors.white12, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(height: 24),
          Text(
            'TACTICAL ENGAGEMENT',
            style: GoogleFonts.outfit(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 16,
              letterSpacing: 2.0,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'MISSION ID: ${alertDoc.id.substring(0, 8).toUpperCase()}',
            style: GoogleFonts.outfit(
              color: Colors.white38,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 32),
          Row(
            children: [
              _TacticalButton(
                label: 'DEPLOY',
                color: AppColors.primary,
                icon: Icons.local_police_rounded,
                onTap: () => verifyAndExecute(() async {
                  onAction();
                  final userId = FirebaseAuth.instance.currentUser?.uid ?? 'AGENT';
                  await FirebaseFirestore.instance.collection('alerts').doc(alertDoc.id).update({
                    'responder': userId,
                    'responder_assigned_at': FieldValue.serverTimestamp(),
                    'last_edited_by': userId,
                  });
                  await BackgroundTrackingService().startTracking(alertDoc.id, userId);
                }),
              ),
              const SizedBox(width: 12),
              _TacticalButton(
                label: 'ESCALATE',
                color: AppColors.warning,
                icon: Icons.trending_up_rounded,
                onTap: () => verifyAndExecute(() async {
                  onAction();
                  final currentLevel = alertDoc['assigned_to'] ?? 'POLLING_UNIT';
                  String nextTier = 'WARD';
                  if (currentLevel == 'WARD') nextTier = 'LGA';
                  if (currentLevel == 'LGA') nextTier = 'HQ';
                  if (currentLevel == 'HQ') return; // Max level reached
                  
                  await FirebaseFirestore.instance.collection('alerts').doc(alertDoc.id).update({
                    'assigned_to': nextTier,
                    'last_edited_by': FirebaseAuth.instance.currentUser?.uid,
                  });
                }),
              ),
              const SizedBox(width: 12),
              _TacticalButton(
                label: 'RESOLVE',
                color: AppColors.safe,
                icon: Icons.verified_user_rounded,
                onTap: () => verifyAndExecute(() async {
                  onAction();
                  await FirebaseFirestore.instance.collection('alerts').doc(alertDoc.id).update({
                    'status': 'RESOLVED',
                    'resolved_by': FirebaseAuth.instance.currentUser?.uid,
                  });
                }),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TacticalButton extends StatelessWidget {
  final String label;
  final Color color;
  final IconData icon;
  final VoidCallback onTap;

  const _TacticalButton({
    required this.label,
    required this.color,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 24),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withValues(alpha: 0.2)),
          ),
          child: Column(
            children: [
              Icon(icon, color: color, size: 28),
              const SizedBox(height: 12),
              Text(
                label,
                style: GoogleFonts.outfit(
                  color: color,
                  fontWeight: FontWeight.w900,
                  fontSize: 10,
                  letterSpacing: 1.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PulseMarker extends StatefulWidget {
  final bool isEmergency;
  const _PulseMarker({required this.isEmergency});
  @override
  _PulseMarkerState createState() => _PulseMarkerState();
}

class _PulseMarkerState extends State<_PulseMarker> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat();
  }
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    final color = widget.isEmergency ? AppColors.emergency : AppColors.primary;
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) => Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 60 * _ctrl.value,
            height: 60 * _ctrl.value,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: color.withValues(alpha: 1 - _ctrl.value), width: 2),
            ),
          ),
          Container(
            width: 40 * _ctrl.value,
            height: 40 * _ctrl.value,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: (1 - _ctrl.value) * 0.5),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 10, spreadRadius: 2),
              ],
            ),
            child: Icon(
              widget.isEmergency ? Icons.warning_rounded : Icons.radar_rounded,
              color: Colors.white,
              size: 18,
            ),
          ),
        ],
      ),
    );
  }
}

