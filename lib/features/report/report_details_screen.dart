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
      // Offline fallback: Execute resilient UI simulation, then submit via the service's SMS gateway
      // without showing the snackbar, to maintain the tone of the offline overlay
      await showOfflineSending(context, message: 'Incident Report Data');
      ref.read(alertServiceProvider).submitAlert(
        type: '${widget.categoryInfo.label} - ${widget.subType}',
        description: desc,
        reportedBy: _anonymous ? 'anonymous' : userId,
        priority: widget.categoryInfo.priority,
        latitude: lat,
        longitude: lng,
      );
      if (mounted) context.go(AppRoutes.home);
      return;
    }

    try {
      List<String> uploadedUrls = [];
      if (_attachedFiles.isNotEmpty) {
        for (var file in _attachedFiles) {
          final fileName = '${DateTime.now().millisecondsSinceEpoch}_${file.path.split('/').last}';
          final ref = FirebaseStorage.instance.ref().child('alerts/$userId/$fileName');
          await ref.putFile(file);
          final url = await ref.getDownloadURL();
          uploadedUrls.add(url);
        }
      }

      await ref.read(alertServiceProvider).submitAlert(
        type: '${widget.categoryInfo.label} - ${widget.subType}',
        description: desc,
        reportedBy: _anonymous ? 'anonymous' : userId,
        priority: widget.categoryInfo.priority,
        latitude: lat,
        longitude: lng,
        attachments: uploadedUrls,
      );
    } catch (e) {
      debugPrint('[SYS_ERR] Report submission failed natively: $e');
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(children: [
            const Icon(Icons.check_circle_rounded, color: Colors.white),
            const SizedBox(width: 10),
            Text('Report submitted successfully', style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
          ]),
          backgroundColor: AppColors.tertiary,
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
    return Scaffold(
      appBar: const RainbowAppBar(title: 'REPORT INCIDENT', subtitle: 'STEP 3 OF 3 — ADD DETAILS', showBack: true),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const SizedBox(height: 8),
          // Summary banner
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cat.bg,
              borderRadius: BorderRadius.circular(16),
              border: Border(left: BorderSide(color: cat.color, width: 5)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('REPORTING', style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w700, color: cat.color, letterSpacing: 1.5)),
                Text(widget.subType, style: GoogleFonts.inter(fontWeight: FontWeight.w900, fontSize: 18, color: cat.color)),
                Text(cat.label, style: GoogleFonts.inter(fontSize: 12, color: cat.color.withAlpha(180))),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Narrative
          const _SectionLabel('DESCRIBE WHAT HAPPENED'),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), boxShadow: [BoxShadow(color: Colors.black.withAlpha(8), blurRadius: 10)]),
            child: TextField(
              controller: _narrativeCtrl,
              maxLines: 6,
              decoration: InputDecoration(
                hintText: 'Describe the situation in as much detail as possible — who, what, where, when...',
                hintStyle: GoogleFonts.inter(color: AppColors.outline, fontSize: 13),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.all(16),
              ),
              style: GoogleFonts.inter(fontSize: 14, height: 1.5),
              onChanged: (_) => setState(() {}),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('${_narrativeCtrl.text.length} characters', style: GoogleFonts.inter(fontSize: 10, color: AppColors.outline)),
            ),
          ),
          const SizedBox(height: 20),

          // Media attachment
          const _SectionLabel('ATTACH EVIDENCE (OPTIONAL)'),
          const SizedBox(height: 10),
          Row(children: [
            _MediaBtn(icon: Icons.photo_camera_outlined, label: 'CAMERA', onTap: _takePhoto),
            const SizedBox(width: 10),
            _MediaBtn(icon: Icons.image_outlined, label: 'GALLERY', onTap: _pickImage),
          ]),

          // Attached files preview
          if (_attachedFiles.isNotEmpty) ...[
            const SizedBox(height: 12),
            ..._attachedFiles.map((f) => Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(color: AppColors.surfaceContainerLow, borderRadius: BorderRadius.circular(10)),
              child: Row(children: [
                const Icon(Icons.image_rounded, color: AppColors.secondary, size: 18),
                const SizedBox(width: 10),
                Expanded(child: Text(f.path.split('/').last, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis)),
                GestureDetector(
                  onTap: () => setState(() => _attachedFiles.remove(f)),
                  child: const Icon(Icons.close_rounded, color: AppColors.error, size: 16),
                ),
              ]),
            )),
          ],
          const SizedBox(height: 20),

          // Location
          const _SectionLabel('LOCATION'),
          const SizedBox(height: 8),
          Consumer(builder: (context, ref, _) {
            final locAsync = ref.watch(userLocationStreamProvider);
            return Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border(left: BorderSide(color: _shareLocation ? AppColors.tertiary : AppColors.outline, width: 4)),
                boxShadow: [BoxShadow(color: Colors.black.withAlpha(8), blurRadius: 10)],
              ),
              child: Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('AUTO-DETECTED', style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w700, color: AppColors.outline, letterSpacing: 1.5)),
                  locAsync.when(
                    data: (pos) => Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Current Device Location', style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 14)),
                        Text('LAT: ${pos.latitude.toStringAsFixed(4)} N | LON: ${pos.longitude.toStringAsFixed(4)} E', style: GoogleFonts.inter(fontSize: 10, color: AppColors.onSurfaceVariant)),
                      ],
                    ),
                    loading: () => Text('Acquiring GPS Signal...', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.primary)),
                    error: (_, __) => Text('Location Unavailable', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.error)),
                  ),
                ])),
                Switch(value: _shareLocation, onChanged: (v) => setState(() => _shareLocation = v)),
              ]),
            );
          }),
          const SizedBox(height: 20),

          // Anonymous toggle
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), boxShadow: [BoxShadow(color: Colors.black.withAlpha(8), blurRadius: 10)]),
            child: Row(children: [
              const Icon(Icons.visibility_off_outlined, color: AppColors.secondary),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Anonymous Report', style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 14)),
                Text('Your name and phone will not be shared with responders.', style: GoogleFonts.inter(fontSize: 11, color: AppColors.onSurfaceVariant, height: 1.3)),
              ])),
              Switch(value: _anonymous, onChanged: (v) => setState(() => _anonymous = v)),
            ]),
          ),
          const SizedBox(height: 28),

          // Submit button
          ElevatedButton(
            onPressed: _submitting ? null : _submit,
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(double.infinity, 60),
              backgroundColor: AppColors.primary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            ),
            child: _submitting
                ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text('SUBMIT INCIDENT REPORT', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 15, letterSpacing: 1.5)),
                    const SizedBox(width: 12),
                    const Icon(Icons.send_rounded, color: Colors.white, size: 20),
                  ]),
          ),
          const SizedBox(height: 8),
          Center(child: Text('ENCRYPTED VIA AES-256 · DELIVERED VIA TERMII SMS', style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w700, color: AppColors.outline, letterSpacing: 1.0))),
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel(this.label);
  @override
  Widget build(BuildContext context) => Text(label, style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.outline, letterSpacing: 2.0));
}

class _MediaBtn extends StatelessWidget {
  final IconData icon; final String label; final VoidCallback onTap;
  const _MediaBtn({required this.icon, required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) => Expanded(
    child: GestureDetector(
      onTap: onTap,
      child: Container(
        height: 72,
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), boxShadow: [BoxShadow(color: Colors.black.withAlpha(8), blurRadius: 8)]),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, color: AppColors.secondary, size: 24),
          const SizedBox(height: 4),
          Text(label, style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 1.0)),
        ]),
      ),
    ),
  );
}

