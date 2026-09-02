import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:rainbow_app/core/supabase/supabase_config.dart';
import 'package:rainbow_app/core/theme/app_colors.dart';
import 'package:rainbow_app/providers/auth_provider.dart';
import 'package:rainbow_app/services/cloudinary_service.dart';
import 'package:rainbow_app/shared/widgets/rainbow_app_bar.dart';
import 'package:rainbow_app/shared/widgets/rainbow_map.dart';
import 'package:url_launcher/url_launcher.dart';

class MissionIntelScreen extends ConsumerStatefulWidget {
  const MissionIntelScreen({required this.alertData, super.key});
  final Map<String, dynamic> alertData;
  @override
  ConsumerState<MissionIntelScreen> createState() => _MissionIntelScreenState();
}

class _MissionIntelScreenState extends ConsumerState<MissionIntelScreen> {
  late Map<String, dynamic> alertData;
  final ImagePicker _picker = ImagePicker();
  bool _isUploading = false;

  @override
  void initState() {
    super.initState();
    alertData = Map.from(widget.alertData);
  }

  Future<void> _updateStatus(String newStatus) async {
    final alertId = alertData['id'] as String?;
    if (alertId != null) {
      try {
        await SupabaseConfig.client.from('alerts').update({'status': newStatus}).eq('id', alertId);
        setState(() { alertData['status'] = newStatus; });
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Status updated to $newStatus')));
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _attachEvidence() async {
    unawaited(showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surfaceContainerHigh,
      builder: (ctx) {
        return SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt, color: AppColors.primary),
                title: const Text('Camera Photo', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(ctx);
                  unawaited(_pickAndUploadMedia(ImageSource.camera, false));
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library, color: AppColors.primary),
                title: const Text('Gallery Photo', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(ctx);
                  unawaited(_pickAndUploadMedia(ImageSource.gallery, false));
                },
              ),
              ListTile(
                leading: const Icon(Icons.videocam, color: AppColors.primary),
                title: const Text('Record Video', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(ctx);
                  unawaited(_pickAndUploadMedia(ImageSource.camera, true));
                },
              ),
            ],
          ),
        );
      },
    ),);
  }

  Future<void> _pickAndUploadMedia(ImageSource source, bool isVideo) async {
    try {
      XFile? file;
      if (isVideo) {
        file = await _picker.pickVideo(source: source);
      } else {
        file = await _picker.pickImage(source: source);
      }

      if (file == null) return;

      setState(() => _isUploading = true);

      final url = await CloudinaryService.instance.uploadMedia(File(file.path));
      if (url != null) {
        final alertId = alertData['id'] as String?;
        if (alertId == null) {
          // Without an id the .eq('id', null) filter matches nothing, so the
          // upload would silently fail to attach while the UI still reported
          // "Evidence uploaded successfully". Fail into the catch below, which
          // clears the spinner and surfaces the error, as the Cloudinary
          // failure path already does.
          throw Exception('Alert has no id — cannot attach evidence');
        }
        final existingMedia = (alertData['media_urls'] as List<dynamic>?)?.cast<String>() ?? [];
        final newMediaUrls = [...existingMedia, url];

        await SupabaseConfig.client.from('alerts').update({'media_urls': newMediaUrls}).eq('id', alertId);
        
        setState(() {
          alertData['media_urls'] = newMediaUrls;
          _isUploading = false;
        });
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Evidence uploaded successfully'), backgroundColor: AppColors.success),
          );
        }
      } else {
        throw Exception('Failed to get URL from Cloudinary');
      }
    } catch (e) {
      setState(() => _isUploading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Upload failed: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final type = alertData['type'] as String? ?? 'INCIDENT';
    final severity = alertData['severity'] as String? ?? 'MEDIUM';
    final desc = alertData['description'] as String? ?? 'No details provided';
    final lat = (alertData['latitude'] as num?)?.toDouble();
    final lng = (alertData['longitude'] as num?)?.toDouble();
    final alertId = alertData['id'] as String?;
    final mediaUrls = (alertData['media_urls'] as List<dynamic>?)?.cast<String>() ?? [];
    final authState = ref.watch(authProvider);
    final isAgent = authState.role == UserRole.responder;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const RainbowAppBar(title: 'TACTICAL MISSION INTEL', subtitle: 'INCIDENT DATA DOSSIER'),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(type.toUpperCase(), style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.primary)),
            const SizedBox(height: 8),
            Text('SEVERITY: $severity', style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.warning, letterSpacing: 1.5)),
            const SizedBox(height: 16),
            if (lat != null && lng != null) ...[
              SizedBox(height: 200, child: ClipRRect(borderRadius: BorderRadius.circular(16), child: RainbowMap(center: LatLng(lat, lng), markers: [Marker(point: LatLng(lat, lng), child: const Icon(Icons.location_on, color: AppColors.danger))]))),
              const SizedBox(height: 16),
            ],
            Text(desc, style: GoogleFonts.inter(fontSize: 14, color: AppColors.onBackground)),
            const SizedBox(height: 24),
            if (mediaUrls.isNotEmpty) ...[
              Text('EVIDENCE ACQUIRED', style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textDim)),
              const SizedBox(height: 8),
              SizedBox(
                height: 120,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: mediaUrls.length,
                  itemBuilder: (context, index) {
                    final url = mediaUrls[index];
                    final urlLower = url.toLowerCase();
                    final isVideo = urlLower.contains('/video/') || urlLower.endsWith('.mp4') || urlLower.endsWith('.mov');
                    final isAudio = urlLower.contains('/raw/') || urlLower.endsWith('.m4a') || urlLower.endsWith('.mp3') || urlLower.endsWith('.wav');
                    final isImage = !isVideo && !isAudio;
                    
                    return GestureDetector(
                      onTap: () {
                        if (isAudio) {
                          unawaited(launchUrl(Uri.parse(url)));
                        } else {
                          unawaited(showDialog<void>(
                            context: context,
                            builder: (context) => Dialog(
                              backgroundColor: Colors.black,
                              child: isVideo
                                ? const Center(child: Icon(Icons.play_circle_fill, color: Colors.white, size: 64))
                                : InteractiveViewer(child: Image.network(url)),
                            ),
                          ),);
                        }
                      },
                      child: Container(
                        width: 120,
                        margin: const EdgeInsets.only(right: 8),
                        decoration: BoxDecoration(color: AppColors.surfaceContainer, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.outline)),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: isImage
                              ? Image.network(url, fit: BoxFit.cover, errorBuilder: (c, e, s) => const Icon(Icons.broken_image, color: AppColors.textDim))
                              : isVideo
                                  ? const Stack(
                                      fit: StackFit.expand,
                                      children: [
                                        Center(child: Icon(Icons.movie, color: AppColors.primary, size: 40)),
                                        Center(child: Icon(Icons.play_circle_fill, color: Colors.white, size: 32)),
                                      ],
                                    )
                                  : Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        const Icon(Icons.mic, color: AppColors.primary, size: 32),
                                        const SizedBox(height: 8),
                                        Text('TAP TO PLAY', style: GoogleFonts.outfit(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.textDim)),
                                      ],
                                    ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 24),
            ],
            if (isAgent) ...[
              Text('TACTICAL STATUS', style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textDim)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: ElevatedButton(onPressed: () => _updateStatus('RESOLVED'), style: ElevatedButton.styleFrom(backgroundColor: AppColors.success), child: const Text('RESOLVE', style: TextStyle(color: Colors.white)))),
                  const SizedBox(width: 8),
                  Expanded(child: ElevatedButton(onPressed: () => _updateStatus('DISPATCHED'), style: ElevatedButton.styleFrom(backgroundColor: AppColors.warning), child: const Text('DISPATCH', style: TextStyle(color: Colors.black)))),
                ],
              ),
              const SizedBox(height: 24),
            ],
            if (alertId != null) ...[
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => context.push('/dispatcher-chat?alertId=$alertId'),
                  icon: const Icon(Icons.chat, color: Colors.white),
                  label: Text('DISPATCHER CHAT', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: Colors.white)),
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, padding: const EdgeInsets.symmetric(vertical: 16)),
                ),
              ),
            ],
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isUploading ? null : _attachEvidence,
        backgroundColor: AppColors.warning,
        icon: _isUploading
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2))
            : const Icon(Icons.attach_file, color: Colors.black),
        label: Text(
          _isUploading ? 'UPLOADING...' : 'ATTACH EVIDENCE',
          style: GoogleFonts.outfit(color: Colors.black, fontWeight: FontWeight.bold),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }
}
