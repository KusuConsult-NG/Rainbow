import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/app_colors.dart';
import '../../core/router/app_router.dart';
import '../../core/constants/alert_categories.dart';
import '../../shared/widgets/rainbow_app_bar.dart';
import '../../shared/widgets/offline_overlay.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../../services/alert_service.dart';
import '../../services/auth_service.dart';
import '../../services/location_service.dart';
import '../../core/constants/tactical_mapping.dart';

class ReportDetailsScreen extends ConsumerStatefulWidget {
  final AlertCategoryInfo categoryInfo;
  final String subType;
  const ReportDetailsScreen({super.key, required this.categoryInfo, required this.subType});

  @override
  ConsumerState<ReportDetailsScreen> createState() => _ReportDetailsScreenState();
}

class _ReportDetailsScreenState extends ConsumerState<ReportDetailsScreen> {
  final _narrativeCtrl = TextEditingController();
  bool _shareLocation = true;
  bool _manualOverride = false;
  
  TacticalJurisdiction? _selectedLga;
  TacticalWard? _selectedWard;
  String? _selectedPu;

  bool _anonymous = false;
  bool _submitting = false;
  final List<File> _attachedFiles = [];
  final ImagePicker _picker = ImagePicker();

  Future<void> _pickImage() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
    if (image != null) {
      setState(() => _attachedFiles.add(File(image.path)));
    }
  }

  Future<void> _takePhoto() async {
    final XFile? photo = await _picker.pickImage(source: ImageSource.camera, imageQuality: 70);
    if (photo != null) {
      setState(() => _attachedFiles.add(File(photo.path)));
    }
  }

  @override
  void dispose() {
    _narrativeCtrl.dispose();
    super.dispose();
  }

  void _submit() async {
    setState(() => _submitting = true);
    
    final userId = ref.read(authServiceProvider).currentUserId ?? 'anonymous';
    final desc = _narrativeCtrl.text.isEmpty ? 'No narrative provided' : _narrativeCtrl.text;
    
    final connectivityResult = await Connectivity().checkConnectivity();
    final isOffline = connectivityResult.contains(ConnectivityResult.none);
    final userLoc = ref.read(userLocationStreamProvider).value;
    final lat = userLoc?.latitude;
    final lng = userLoc?.longitude;

    if (isOffline && mounted) {
      await showOfflineSending(context, message: 'Incident Report Data');
      ref.read(alertServiceProvider).submitAlert(
        type: '${widget.categoryInfo.label} - ${widget.subType}',
        description: desc,
        reportedBy: _anonymous ? 'anonymous' : userId,
        priority: widget.categoryInfo.priority,
        latitude: _shareLocation ? lat : null,
        longitude: _shareLocation ? lng : null,
      );
      if (mounted) context.go(AppRoutes.home);
      return;
    }

    try {
      List<String> uploadedUrls = [];
      if (_attachedFiles.isNotEmpty) {
        for (var file in _attachedFiles) {
          final fileName = '${DateTime.now().millisecondsSinceEpoch}_${file.path.split('/').last}';
          final refStore = FirebaseStorage.instance.ref().child('alerts/$userId/$fileName');
          await refStore.putFile(file);
          final url = await refStore.getDownloadURL();
          uploadedUrls.add(url);
        }
      }

      await ref.read(alertServiceProvider).submitAlert(
        type: '${widget.categoryInfo.label} - ${widget.subType}',
        description: desc,
        reportedBy: _anonymous ? 'anonymous' : userId,
        priority: widget.categoryInfo.priority,
        latitude: _shareLocation ? lat : null,
        longitude: _shareLocation ? lng : null,
        attachments: uploadedUrls,
        geoLga: _manualOverride ? _selectedLga?.name : null,
        geoWard: _manualOverride ? _selectedWard?.name : null,
        geoPu: _manualOverride ? _selectedPu : null,
      );
    } catch (e) {
      debugPrint('[SYS_ERR] Report submission failed natively: $e');
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(children: [
            const Icon(Icons.check_circle_rounded, color: Colors.black),
            const SizedBox(width: 12),
            Text('TRANSMISSION SUCCESSFUL', style: GoogleFonts.outfit(fontWeight: FontWeight.w900, fontSize: 13, letterSpacing: 1.0)),
          ]),
          backgroundColor: AppColors.primary,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
      context.go(AppRoutes.home);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cat = widget.categoryInfo;
    final locAsync = ref.watch(userLocationStreamProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: const RainbowAppBar(title: 'INCIDENT DOSSIER', subtitle: 'COMPILE TACTICAL DATA', showBack: true),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          // Summary banner
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A1A),
              borderRadius: BorderRadius.circular(20),
              border: Border(left: BorderSide(color: cat.color, width: 6)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('TRANSMITTING REPORT FOR', style: GoogleFonts.outfit(fontSize: 10, fontWeight: FontWeight.w900, color: cat.color.withValues(alpha: 0.7), letterSpacing: 1.5)),
                const SizedBox(height: 4),
                Text(widget.subType.toUpperCase(), style: GoogleFonts.outfit(fontWeight: FontWeight.w900, fontSize: 20, color: Colors.white, letterSpacing: 1.0)),
                Text(cat.label.toUpperCase(), style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white38, letterSpacing: 0.5)),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Narrative
          const _SectionLabel('MISSION NARRATIVE'),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A1A),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white10),
            ),
            child: TextField(
              controller: _narrativeCtrl,
              maxLines: 6,
              decoration: InputDecoration(
                hintText: 'Enter mission details, observations, and objective status...',
                hintStyle: GoogleFonts.outfit(color: Colors.white24, fontSize: 13),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.all(20),
              ),
              style: GoogleFonts.outfit(fontSize: 14, height: 1.6, color: Colors.white, fontWeight: FontWeight.w500),
              onChanged: (_) => setState(() {}),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('${_narrativeCtrl.text.length} CHARS / MISSION_LOG_SENSITIVE', style: GoogleFonts.outfit(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white24, letterSpacing: 1.0)),
            ),
          ),
          const SizedBox(height: 24),

          // Media attachment
          const _SectionLabel('VISUAL TELEMETRY (OPTIONAL)'),
          const SizedBox(height: 12),
          Row(children: [
            _MediaBtn(icon: Icons.camera_alt_rounded, label: 'SCAN FIELD', onTap: _takePhoto),
            const SizedBox(width: 12),
            _MediaBtn(icon: Icons.photo_library_rounded, label: 'INTEL ARCHIVE', onTap: _pickImage),
          ]),

          // Attached files preview
          if (_attachedFiles.isNotEmpty) ...[
            const SizedBox(height: 16),
            ..._attachedFiles.map((f) => Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(12)),
              child: Row(children: [
                Icon(Icons.description_rounded, color: AppColors.primary.withValues(alpha: 0.5), size: 18),
                const SizedBox(width: 12),
                Expanded(child: Text(f.path.split('/').last, style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white70), overflow: TextOverflow.ellipsis)),
                GestureDetector(
                  onTap: () => setState(() => _attachedFiles.remove(f)),
                  child: const Icon(Icons.close_rounded, color: Colors.redAccent, size: 18),
                ),
              ]),
            )),
          ],
          const SizedBox(height: 24),

          // Location
          const _SectionLabel('GEOSPATIAL COORDINATES'),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A1A),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _shareLocation ? AppColors.primary.withValues(alpha: 0.3) : Colors.white10),
            ),
            child: Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('GPS TELEMETRY', style: GoogleFonts.outfit(fontSize: 9, fontWeight: FontWeight.w900, color: _shareLocation ? AppColors.primary : Colors.white24, letterSpacing: 1.5)),
                const SizedBox(height: 4),
                locAsync.when(
                  data: (pos) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('ACTIVE BEACON SIGNAL', style: GoogleFonts.outfit(fontWeight: FontWeight.w900, fontSize: 14, color: Colors.white, letterSpacing: 0.5)),
                      Text('${pos.latitude.toStringAsFixed(6)} N | ${pos.longitude.toStringAsFixed(6)} E', style: GoogleFonts.outfit(fontSize: 11, color: Colors.white38, letterSpacing: 1.0)),
                    ],
                  ),
                  loading: () => Text('ACQUIRING SIGNAL...', style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w900, color: AppColors.primary)),
                  error: (_, __) => Text('SIGNAL INTERRUPTED', style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w900, color: Colors.redAccent)),
                ),
              ])),
              Switch(
                value: _shareLocation, 
                onChanged: (v) => setState(() => _shareLocation = v),
                activeThumbColor: AppColors.primary,
                activeTrackColor: AppColors.primary.withValues(alpha: 0.2),
              ),
            ]),
          ),
          const SizedBox(height: 24),

          // Manual Override
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A1A),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _manualOverride ? AppColors.primary.withValues(alpha: 0.3) : Colors.white10),
            ),
            child: Column(
              children: [
                Row(children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('JURISDICTION OVERRIDE', style: GoogleFonts.outfit(fontSize: 9, fontWeight: FontWeight.w900, color: _manualOverride ? AppColors.primary : Colors.white24, letterSpacing: 1.5)),
                    const SizedBox(height: 4),
                    Text('MANUAL LOCATION ENTRY', style: GoogleFonts.outfit(fontWeight: FontWeight.w900, fontSize: 14, color: Colors.white, letterSpacing: 0.5)),
                    Text('USE IF GPS SIGNAL IS WEAK OR INACCURATE', style: GoogleFonts.outfit(fontSize: 10, color: Colors.white38, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
                  ])),
                  Switch(
                    value: _manualOverride, 
                    onChanged: (v) => setState(() => _manualOverride = v),
                    activeThumbColor: AppColors.primary,
                    activeTrackColor: AppColors.primary.withValues(alpha: 0.2),
                  ),
                ]),
                if (_manualOverride) ...[
                  const SizedBox(height: 20),
                  const Divider(color: Colors.white10),
                  const SizedBox(height: 20),
                  
                  // LGA Dropdown
                  _DropdownSection(
                    label: 'LOCAL GOVERNMENT AREA',
                    value: _selectedLga?.name,
                    items: plateauTacticalMap.map((lga) => lga.name).toList(),
                    onChanged: (val) {
                      setState(() {
                        _selectedLga = plateauTacticalMap.firstWhere((lga) => lga.name == val);
                        _selectedWard = null;
                        _selectedPu = null;
                      });
                    },
                  ),
                  const SizedBox(height: 16),

                  // Ward Dropdown
                  _DropdownSection(
                    label: 'WARD',
                    value: _selectedWard?.name,
                    items: _selectedLga?.wards.map((w) => w.name).toList() ?? [],
                    onChanged: (val) {
                      setState(() {
                        _selectedWard = _selectedLga?.wards.firstWhere((w) => w.name == val);
                        _selectedPu = null;
                      });
                    },
                  ),
                  const SizedBox(height: 16),

                  // PU Dropdown
                  _DropdownSection(
                    label: 'POLLING UNIT',
                    value: _selectedPu,
                    items: _selectedWard?.pollingUnits ?? [],
                    onChanged: (val) => setState(() => _selectedPu = val),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Anonymous toggle
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A1A),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white10),
            ),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.security_rounded, color: Colors.white70, size: 20),
              ),
              const SizedBox(width: 16),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('STEALTH MODE', style: GoogleFonts.outfit(fontWeight: FontWeight.w900, fontSize: 14, color: Colors.white, letterSpacing: 0.5)),
                Text('ENCRYPT SENDER IDENTITY ARCHIVE', style: GoogleFonts.outfit(fontSize: 10, color: Colors.white38, height: 1.3, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
              ])),
              Switch(
                value: _anonymous, 
                onChanged: (v) => setState(() => _anonymous = v),
                activeThumbColor: AppColors.primary,
                activeTrackColor: AppColors.primary.withValues(alpha: 0.2),
              ),
            ]),
          ),
          const SizedBox(height: 40),

          // Submit button
          SizedBox(
            width: double.infinity,
            height: 64,
            child: ElevatedButton(
              onPressed: _submitting ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.black,
                disabledBackgroundColor: Colors.white.withValues(alpha: 0.05),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 0,
              ),
              child: _submitting
                  ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 3, color: Colors.black))
                  : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Text('INITIATE TRANSMISSION', style: GoogleFonts.outfit(fontWeight: FontWeight.w900, fontSize: 15, letterSpacing: 1.5)),
                      const SizedBox(width: 12),
                      const Icon(Icons.bolt_rounded, color: Colors.black, size: 20),
                    ]),
            ),
          ),
          const SizedBox(height: 16),
          Center(child: Text('AES-256 ENCRYPTED TUNNEL · MISSION CRITICAL DATA', style: GoogleFonts.outfit(fontSize: 9, fontWeight: FontWeight.w900, color: Colors.white24, letterSpacing: 1.0))),
          const SizedBox(height: 60),
        ],
      ),
    );
  }
}

class _DropdownSection extends StatelessWidget {
  final String label;
  final String? value;
  final List<String> items;
  final ValueChanged<String?> onChanged;

  const _DropdownSection({required this.label, required this.value, required this.items, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(label, style: GoogleFonts.outfit(fontSize: 8, fontWeight: FontWeight.w900, color: Colors.white24, letterSpacing: 1.5)),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              items: items.map((i) => DropdownMenuItem(
                value: i,
                child: Text(i, style: GoogleFonts.outfit(fontSize: 14, color: Colors.white, fontWeight: FontWeight.w600)),
              )).toList(),
              onChanged: onChanged,
              dropdownColor: const Color(0xFF1A1A1A),
              isExpanded: true,
              hint: Text('SELECT...', style: GoogleFonts.outfit(fontSize: 13, color: Colors.white24)),
              icon: const Icon(Icons.arrow_drop_down_rounded, color: AppColors.primary),
            ),
          ),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel(this.label);
  @override
  Widget build(BuildContext context) => Text(label, style: GoogleFonts.outfit(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.white24, letterSpacing: 2.0));
}

class _MediaBtn extends StatelessWidget {
  final IconData icon; final String label; final VoidCallback onTap;
  const _MediaBtn({required this.icon, required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) => Expanded(
    child: GestureDetector(
      onTap: onTap,
      child: Container(
        height: 80,
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white10),
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, color: AppColors.primary, size: 24),
          const SizedBox(height: 8),
          Text(label, style: GoogleFonts.outfit(fontSize: 9, fontWeight: FontWeight.w900, color: Colors.white70, letterSpacing: 1.0)),
        ]),
      ),
    ),
  );
}

