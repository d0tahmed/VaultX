import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:path_provider/path_provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/vault_provider.dart';
import '../models/password_entry.dart';
import '../services/hibp_service.dart';
import '../theme/app_theme.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> with TickerProviderStateMixin {
  bool _isScanning = false;
  bool _isDisposed = false;
  Map<String, int> _pwnedCache = {};
  List<File> _breachLogs = [];

  late AnimationController _gaugeAnimCtrl;
  late Animation<double> _gaugeAnim;

  @override
  void initState() {
    super.initState();
    _gaugeAnimCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200));
    _gaugeAnim = CurvedAnimation(parent: _gaugeAnimCtrl, curve: Curves.easeOutCubic);
    _loadBreachLogs();
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) _gaugeAnimCtrl.forward();
    });
  }

  @override
  void dispose() {
    _isDisposed = true;
    _pwnedCache.clear();
    _breachLogs.clear();
    _gaugeAnimCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadBreachLogs() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final breachDir = Directory('${dir.path}/vaultx_breaches');
      if (await breachDir.exists()) {
        final List<FileSystemEntity> entities = await breachDir.list().toList();
        final List<File> files = entities.whereType<File>().where((f) => f.path.endsWith('.jpg')).toList();
        files.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
        if (!_isDisposed) setState(() => _breachLogs = files);
      }
    } catch (e) {
      debugPrint("Error loading breach logs: $e");
    } finally {
      // loading complete
    }
  }

  Future<void> _deleteLog(File file) async {
    HapticFeedback.mediumImpact();
    try {
      if (await file.exists()) {
        await file.delete();
        if (!_isDisposed) _loadBreachLogs();
      }
    } catch (e) {
      debugPrint("Error deleting log: $e");
    }
  }

  int _calculateStrength(String pass) {
    if (pass.isEmpty) return 1;
    bool hasUpper = RegExp(r'[A-Z]').hasMatch(pass);
    bool hasLower = RegExp(r'[a-z]').hasMatch(pass);
    bool hasDigit = RegExp(r'[0-9]').hasMatch(pass);
    bool hasSym   = RegExp(r'[!@#\$&*~_=+^%().,-]').hasMatch(pass);
    int length    = pass.length;
    if (length >= 8 && hasUpper && hasSym && hasDigit) return 3;
    if (length >= 8 && hasDigit && hasLower) return 2;
    return 1;
  }

  Future<void> _runDeepScan(List<PasswordCategory> categories) async {
    if (_isDisposed) return;
    setState(() => _isScanning = true);
    HapticFeedback.mediumImpact();
    Map<String, int> results = {};
    int foundLeaks = 0;
    for (var cat in categories) {
      for (var entry in cat.entries) {
        if (_isDisposed) return;
        int breachCount = await HIBPService.checkPassword(entry.password);
        if (breachCount > 0) {
          results[entry.id] = breachCount;
          foundLeaks++;
        }
      }
    }
    if (mounted && !_isDisposed) {
      setState(() { _pwnedCache = results; _isScanning = false; });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(foundLeaks > 0 ? 'Deep Scan Complete: Found $foundLeaks leaked passwords!' : 'Deep Scan Complete: No leaks found!',
            style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
          backgroundColor: foundLeaks > 0 ? VaultColors.error : VaultColors.tertiaryContainer,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final vault = Provider.of<VaultProvider>(context);

    // Compute stats
    int totalEntries = 0;
    int totalCategories = vault.categories.length;
    int totalMedia = 0;
    int strongCount = 0, mediumCount = 0, weakCount = 0;
    List<Map<String, dynamic>> vulnerableAccounts = [];

    for (var folder in vault.mediaFolders) {
      totalMedia += folder.items.length;
    }

    for (var cat in vault.categories) {
      for (var entry in cat.entries) {
        totalEntries++;
        int strength = _calculateStrength(entry.password);
        bool isPwned = _pwnedCache.containsKey(entry.id);
        if (strength == 3 && !isPwned) {
          strongCount++;
        } else if (isPwned || strength == 1) {
          weakCount++;
          vulnerableAccounts.add({'entry': entry, 'category': cat.name, 'strength': 1, 'pwned': isPwned ? _pwnedCache[entry.id] : 0});
        } else {
          mediumCount++;
        }
      }
    }

    int total = strongCount + mediumCount + weakCount;
    double securityScore = total == 0 ? 100 : ((strongCount / total) * 100);

    return Scaffold(
      backgroundColor: VaultColors.background,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          // Sticky Top Bar
          SliverToBoxAdapter(
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(children: [
                      const Icon(Icons.shield, color: VaultColors.primaryContainer, size: 22),
                      const SizedBox(width: 10),
                      Text('VAULTX', style: GoogleFonts.manrope(
                        fontSize: 18, fontWeight: FontWeight.w800, color: VaultColors.primaryContainer,
                        letterSpacing: 3,
                      )),
                    ]),
                    _isScanning
                      ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: VaultColors.primaryContainer))
                      : IconButton(
                          icon: const Icon(Icons.radar, color: VaultColors.primaryContainer, size: 22),
                          tooltip: 'Deep Scan',
                          onPressed: () => _runDeepScan(vault.categories),
                        ),
                  ],
                ),
              ),
            ),
          ),

          // Header
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('SYSTEM STATUS', style: VaultTypography.labelSm.copyWith(
                    letterSpacing: 3, color: VaultColors.onSurfaceVariant,
                  )),
                  const SizedBox(height: 6),
                  Text('Digital Sanctuary', style: VaultTypography.displayLg),
                  const SizedBox(height: 12),
                  // AES badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: VaultColors.tertiary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(VaultRadius.full),
                      border: Border.all(color: VaultColors.tertiary.withValues(alpha: 0.2)),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.verified_user, color: VaultColors.tertiary, size: 14),
                      const SizedBox(width: 8),
                      Text('AES-256 ENCRYPTION ACTIVE', style: GoogleFonts.inter(
                        fontSize: 11, fontWeight: FontWeight.w700, color: VaultColors.tertiary, letterSpacing: 1,
                      )),
                      const SizedBox(width: 8),
                      Container(width: 6, height: 6, decoration: const BoxDecoration(
                        shape: BoxShape.circle, color: VaultColors.tertiary,
                      )),
                    ]),
                  ),
                ],
              ),
            ),
          ),

          // Security Score Gauge
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 0),
              child: Container(
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: VaultColors.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(VaultRadius.lg),
                ),
                child: Column(children: [
                  Text('SECURITY SCORE', style: VaultTypography.labelSm.copyWith(letterSpacing: 3)),
                  const SizedBox(height: 24),
                  AnimatedBuilder(
                    animation: _gaugeAnim,
                    builder: (context, child) {
                      return SizedBox(
                        width: 180, height: 180,
                        child: CustomPaint(
                          painter: _GaugePainter(
                            progress: _gaugeAnim.value * (securityScore / 100),
                            score: securityScore,
                          ),
                          child: Center(
                            child: Column(mainAxisSize: MainAxisSize.min, children: [
                              Text('${(securityScore * _gaugeAnim.value).toInt()}',
                                style: GoogleFonts.manrope(fontSize: 52, fontWeight: FontWeight.w800, color: VaultColors.primary)),
                              Text('PROTECTED', style: VaultTypography.labelSm),
                            ]),
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 20),
                  Text.rich(TextSpan(children: [
                    TextSpan(text: 'Your security health is ', style: VaultTypography.bodySm),
                    TextSpan(text: securityScore >= 80 ? 'Excellent' : securityScore >= 50 ? 'Fair' : 'Poor',
                      style: VaultTypography.bodySm.copyWith(color: VaultColors.tertiary, fontWeight: FontWeight.w700)),
                    TextSpan(text: '. ${weakCount > 0 ? '$weakCount actions remaining.' : 'All clear!'}', style: VaultTypography.bodySm),
                  ])),
                ]),
              ),
            ),
          ),

          // Metrics Row
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
              child: Row(children: [
                Expanded(child: _buildMetricCard(Icons.key, '$totalEntries', 'Logins')),
                const SizedBox(width: 8),
                Expanded(child: _buildMetricCard(Icons.folder_special, '$totalCategories', 'Folders')),
                const SizedBox(width: 8),
                Expanded(child: _buildMetricCard(Icons.perm_media, '$totalMedia', 'Media')),
              ]),
            ),
          ),

          // Strength Bar
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 10, 24, 0),
              child: _buildStrengthBar(strongCount, mediumCount, weakCount, total),
            ),
          ),

          // Critical Recommendations
          if (vulnerableAccounts.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 12),
                child: Row(children: [
                  const Icon(Icons.priority_high, color: VaultColors.primary, size: 20),
                  const SizedBox(width: 8),
                  Text('Take Action', style: VaultTypography.headlineSm),
                ]),
              ),
            ),
            SliverList(
              delegate: SliverChildBuilderDelegate((context, index) {
                if (index >= vulnerableAccounts.length || index >= 3) return null;
                final item = vulnerableAccounts[index];
                final PasswordEntry entry = item['entry'];
                final bool isPwned = (item['pwned'] ?? 0) > 0;
                final isWeak = item['strength'] == 1;
                
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: VaultDecorations.accentCard(
                      accent: isPwned ? VaultColors.errorContainer : (isWeak ? VaultColors.error : VaultColors.primary),
                      bgColor: VaultColors.surfaceContainer,
                    ),
                    child: Row(children: [
                      Icon(isPwned ? Icons.dangerous : Icons.warning_amber_rounded,
                        color: isPwned ? VaultColors.errorContainer : VaultColors.error, size: 20),
                      const SizedBox(width: 10),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(entry.title, style: VaultTypography.labelLg, maxLines: 1, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 2),
                        Text(isPwned ? 'Found in data breach' : 'Weak or reused',
                          style: VaultTypography.labelMd, maxLines: 1, overflow: TextOverflow.ellipsis),
                      ])),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: isPwned ? VaultColors.errorContainer : VaultColors.secondaryContainer,
                          borderRadius: BorderRadius.circular(VaultRadius.full),
                        ),
                        child: Text(isPwned ? 'Fix' : 'Fix',
                          style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700,
                            color: isPwned ? VaultColors.onErrorContainer : VaultColors.onSecondaryContainer)),
                      ),
                    ]),
                  ),
                );
              }, childCount: min(vulnerableAccounts.length, 3)),
            ),
          ],

          // Recent Activity
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 12),
              child: Row(children: [
                const Icon(Icons.history, color: VaultColors.primary, size: 20),
                const SizedBox(width: 8),
                Text('Recent Activity', style: VaultTypography.headlineSm),
              ]),
            ),
          ),

          // Activity items
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Container(
                decoration: BoxDecoration(
                  color: VaultColors.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(VaultRadius.lg),
                ),
                child: Column(children: [
                  if (_breachLogs.isNotEmpty) ...[
                    ..._breachLogs.take(3).map((file) {
                      final filename = file.path.split(Platform.pathSeparator).last;
                      final rawTime = filename.replaceAll('intruder_', '').replaceAll('.jpg', '');
                      return _buildActivityItem(
                        Icons.warning_amber_rounded, VaultColors.error,
                        'Unauthorized Access Attempt',
                        rawTime.replaceAll('T', ' at ').replaceAll('-', ':'),
                        onTap: () => _showBreachLogDetail(file),
                      );
                    }),
                  ],
                  _buildActivityItem(Icons.login, VaultColors.primary,
                    'Vault Unlocked', 'Current session'),
                  if (vault.categories.isNotEmpty)
                    _buildActivityItem(Icons.folder_special, VaultColors.tertiary,
                      '${vault.categories.length} folders secured', 'Encrypted with AES-256'),
                ]),
              ),
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }

  Widget _buildMetricCard(IconData icon, String value, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
      decoration: VaultDecorations.card(color: VaultColors.surfaceContainer),
      child: Column(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Icon(icon, color: VaultColors.primary, size: 22),
        const SizedBox(height: 8),
        Text(value, style: GoogleFonts.manrope(fontSize: 24, fontWeight: FontWeight.w800, color: VaultColors.onSurface)),
        const SizedBox(height: 2),
        Text(label, style: VaultTypography.labelSm.copyWith(letterSpacing: 1, fontSize: 10)),
      ]),
    );
  }

  Widget _buildStrengthBar(int strong, int medium, int weak, int total) {
    double strongPct = total == 0 ? 0 : strong / total;
    double medPct = total == 0 ? 0 : medium / total;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: VaultDecorations.card(color: VaultColors.surfaceContainerLow),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: VaultColors.tertiary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.bolt, color: VaultColors.tertiary, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Flexible(child: Text('Strength', style: VaultTypography.labelLg)),
              const SizedBox(width: 8),
              Text(
                total == 0 ? 'No data' : '${(strongPct * 100).toInt()}% Strong',
                style: VaultTypography.labelMd.copyWith(color: VaultColors.tertiary, fontWeight: FontWeight.w700),
              ),
            ]),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: SizedBox(
                height: 6,
                child: Row(children: [
                  if (total > 0) ...[
                    Expanded(flex: (strongPct * 100).toInt().clamp(1, 100),
                      child: Container(color: VaultColors.tertiary)),
                    const SizedBox(width: 2),
                    Expanded(flex: (medPct * 100).toInt().clamp(1, 100),
                      child: Container(color: VaultColors.primary)),
                    const SizedBox(width: 2),
                    Expanded(flex: ((1 - strongPct - medPct) * 100).toInt().clamp(1, 100),
                      child: Container(color: VaultColors.error)),
                  ] else
                    Expanded(child: Container(color: VaultColors.surfaceContainerHighest)),
                ]),
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _buildActivityItem(IconData icon, Color color, String title, String subtitle, {VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 16),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: VaultTypography.labelLg),
            Text(subtitle, style: VaultTypography.labelSm.copyWith(letterSpacing: 0)),
          ])),
        ]),
      ),
    );
  }

  void _showBreachLogDetail(File file) {
    showModalBottomSheet(
      context: context,
      backgroundColor: VaultColors.surfaceContainerHigh,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(VaultRadius.md),
              child: Image.file(file, height: 200, fit: BoxFit.cover),
            ),
            const SizedBox(height: 20),
            Text('Intruder captured after 3 failed PIN attempts.',
              style: VaultTypography.bodyMd.copyWith(color: VaultColors.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: VaultColors.error,
                  foregroundColor: VaultColors.onError,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(VaultRadius.full)),
                ),
                icon: const Icon(Icons.delete_outline, size: 18),
                label: Text('Delete Log', style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
                onPressed: () {
                  Navigator.pop(ctx);
                  _deleteLog(file);
                },
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────
// Security Score Gauge Painter
// ─────────────────────────────────────────────────
class _GaugePainter extends CustomPainter {
  final double progress;
  final double score;

  _GaugePainter({required this.progress, required this.score});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 8;

    // Background ring
    final bgPaint = Paint()
      ..color = VaultColors.surfaceContainerHighest
      ..strokeWidth = 12
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, bgPaint);

    // Progress arc
    final progressPaint = Paint()
      ..strokeWidth = 12
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        startAngle: -pi / 2,
        endAngle: 3 * pi / 2,
        colors: const [VaultColors.primaryContainer, VaultColors.primary, VaultColors.tertiary],
      ).createShader(Rect.fromCircle(center: center, radius: radius));

    final sweepAngle = 2 * pi * progress;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -pi / 2,
      sweepAngle,
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _GaugePainter old) => old.progress != progress;
}