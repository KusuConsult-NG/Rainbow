import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:rainbow_app/core/supabase/supabase_config.dart';
import 'package:rainbow_app/core/theme/app_colors.dart';
import 'package:rainbow_app/providers/auth_provider.dart';
import 'package:rainbow_app/shared/widgets/rainbow_app_bar.dart';

class IncidentHistoryScreen extends ConsumerWidget {
  const IncidentHistoryScreen({super.key});

  Future<List<Map<String, dynamic>>> _fetchAlerts(String? userId, bool isOfficer) async {
    if (userId == null || userId.isEmpty) return [];
    try {
      List<Map<String, dynamic>> results = [];

      if (isOfficer) {
        // Officers see alerts they reported OR are assigned to
        final reported = await SupabaseConfig.client
            .from('alerts')
            .select('*')
            .eq('reported_by', userId)
            .order('created_at', ascending: false);
        final assigned = await SupabaseConfig.client
            .from('alerts')
            .select('*')
            .contains('assigned_responders', [userId])
            .order('created_at', ascending: false);
        final combined = [...(reported as List), ...(assigned as List)].cast<Map<String, dynamic>>();
        // Deduplicate by id
        final seen = <String>{};
        results = combined.where((a) => seen.add(a['id'] as String? ?? '')).toList();
      } else {
        // Citizens only see their own reported alerts
        final response = await SupabaseConfig.client
            .from('alerts')
            .select('*')
            .eq('reported_by', userId)
            .order('created_at', ascending: false);
        results = (response as List<dynamic>).cast<Map<String, dynamic>>();
      }
      return results;
    } catch (_) {
      return [];
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);
    final user = authState.user;
    final auth = authState;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const RainbowAppBar(
        title: 'TACTICAL INCIDENT LOGS',
        subtitle: 'HISTORICAL ARCHIVE',
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _fetchAlerts(user?.id, auth.role == UserRole.responder),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Text(
                'Error loading historical archives',
                style: GoogleFonts.outfit(color: AppColors.danger),
              ),
            );
          }

          final alerts = snapshot.data ?? [];
          if (alerts.isEmpty) {
            return Center(
              child: Text(
                'NO ARCHIVED INCIDENTS RECORDED',
                style: GoogleFonts.outfit(
                  color: AppColors.textDim,
                  fontSize: 12,
                  letterSpacing: 1.5,
                ),
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: alerts.length,
            itemBuilder: (context, index) {
              final item = alerts[index];
              final type = item['type'] as String? ?? 'INCIDENT';
              final severity = item['severity'] as String? ?? 'MEDIUM';
              final status = item['status'] as String? ?? 'PENDING';
              final desc = item['description'] as String? ?? 'No details provided';

              final createdAt = DateTime.tryParse(item['created_at'] as String? ?? '') ?? DateTime.now();
              final dateStr = '${createdAt.day.toString().padLeft(2, '0')} ${['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][createdAt.month]} ${createdAt.year} ${createdAt.hour.toString().padLeft(2, '0')}:${createdAt.minute.toString().padLeft(2, '0')}';

              return GestureDetector(
                onTap: () {
                  showModalBottomSheet(
                    context: context,
                    backgroundColor: AppColors.surface,
                    builder: (ctx) => Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('INCIDENT DETAILS', style: GoogleFonts.outfit(color: AppColors.onBackground, fontWeight: FontWeight.bold, fontSize: 16)),
                          const SizedBox(height: 16),
                          Text('Type: $type', style: GoogleFonts.inter(color: AppColors.textDim)),
                          Text('Severity: $severity', style: GoogleFonts.inter(color: AppColors.textDim)),
                          Text('Status: $status', style: GoogleFonts.inter(color: AppColors.textDim)),
                          Text('Date: ${item['created_at'] ?? 'Unknown'}', style: GoogleFonts.inter(color: AppColors.textDim)),
                          const SizedBox(height: 16),
                          Text(desc, style: GoogleFonts.inter(color: AppColors.onBackground)),
                          const SizedBox(height: 24),
                          if (item['media_urls'] != null && (item['media_urls'] as List).isNotEmpty)
                            ...[
                              Text('Media:', style: GoogleFonts.outfit(color: AppColors.onBackground, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 8),
                              SizedBox(
                                height: 80,
                                child: ListView(
                                  scrollDirection: Axis.horizontal,
                                  children: (item['media_urls'] as List).map((url) => Padding(
                                    padding: const EdgeInsets.only(right: 8.0),
                                    child: Image.network(url.toString(), width: 80, height: 80, fit: BoxFit.cover),
                                  )).toList(),
                                ),
                              ),
                              const SizedBox(height: 24),
                            ],
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: () {
                                Navigator.pop(ctx);
                                context.push('/dispatcher-chat', extra: item['id']);
                              },
                              icon: const Icon(Icons.chat),
                              label: const Text('DISPATCHER CHAT'),
                              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
                child: Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceContainer,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.outline),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            type.toUpperCase(),
                            style: GoogleFonts.outfit(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: AppColors.primary,
                            ),
                          ),
                          Chip(
                            label: Text(
                              status,
                              style: GoogleFonts.outfit(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            backgroundColor: status == 'RESOLVED'
                                ? AppColors.success
                                : AppColors.warning,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        dateStr,
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: AppColors.textDim,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        desc,
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          color: AppColors.onBackground,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
