import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/vault_provider.dart';
import '../services/security_service.dart';
import '../theme/app_theme.dart';
import 'lock_screen.dart';
import 'pin_setup_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final SecurityService _securityService = SecurityService();

  void _changeVaultPin() {
    HapticFeedback.mediumImpact();
    Navigator.push(context, MaterialPageRoute(
      builder: (context) => const PinSetupScreen(isChangingPin: true),
    ));
  }

  void _resetMediaPin() async {
    HapticFeedback.mediumImpact();
    await _securityService.clearMediaPin();
    Provider.of<VaultProvider>(context, listen: false).lockMediaVault();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Media PIN has been reset. Set a new one next time you access the vault.',
            style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
          backgroundColor: VaultColors.tertiaryContainer,
        ),
      );
    }
  }

  void _confirmWipe(BuildContext context) {
    HapticFeedback.heavyImpact();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: VaultColors.surfaceContainerHigh,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(VaultRadius.xl)),
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: VaultColors.error, size: 24),
            const SizedBox(width: 8),
            Text('Confirm Total Wipe', style: VaultTypography.headlineSm.copyWith(color: VaultColors.error)),
          ],
        ),
        content: Text(
          'This will permanently destroy:\n\n• All stored passwords\n• All encrypted media\n• All security keys\n• Master PIN & Media PIN\n\nThis action is IRREVERSIBLE. Your data cannot be recovered.',
          style: VaultTypography.bodyMd.copyWith(color: VaultColors.onSurfaceVariant, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: GoogleFonts.inter(color: VaultColors.onSurfaceVariant)),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: VaultColors.error,
              foregroundColor: VaultColors.onError,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(VaultRadius.full)),
            ),
            icon: const Icon(Icons.delete_forever, size: 18),
            label: Text('DESTROY VAULT', style: GoogleFonts.manrope(fontWeight: FontWeight.w800, letterSpacing: 0.5)),
            onPressed: () async {
              HapticFeedback.heavyImpact();
              final vault = Provider.of<VaultProvider>(context, listen: false);
              await vault.deleteVaultFile();
              await _securityService.resetAll();
              vault.wipeMemory();
              if (context.mounted) {
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (context) => const LockScreen()),
                  (route) => false,
                );
              }
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: VaultColors.background,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          // Header
          SliverToBoxAdapter(
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 32, 24, 0),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('CONFIGURATION & IDENTITY', style: VaultTypography.labelSm.copyWith(letterSpacing: 3, color: VaultColors.onSurfaceVariant)),
                  const SizedBox(height: 6),
                  Text('Settings', style: VaultTypography.displayLg),
                ]),
              ),
            ),
          ),

          // Security Protocol Section
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 0),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _buildSectionHeader('Security Protocol', VaultColors.tertiary),
                const SizedBox(height: 12),
                Container(
                  decoration: VaultDecorations.card(color: VaultColors.surfaceContainerLow),
                  child: Column(children: [
                    _buildSettingsTile(
                      icon: Icons.lock_reset,
                      title: 'Reset VaultX Password',
                      subtitle: 'Change your master PIN',
                      trailing: const Icon(Icons.lock_reset, color: VaultColors.onSurfaceVariant, size: 20),
                      onTap: _changeVaultPin,
                    ),
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 16),
                      height: 1,
                      color: VaultColors.outlineVariant.withValues(alpha: 0.15),
                    ),
                    _buildSettingsTile(
                      icon: Icons.report_outlined,
                      title: 'Reset Media Password',
                      subtitle: 'Clear media vault PIN',
                      trailing: const Icon(Icons.enhanced_encryption, color: VaultColors.onSurfaceVariant, size: 20),
                      onTap: _resetMediaPin,
                    ),
                  ]),
                ),
              ]),
            ),
          ),

          // App Preferences Section
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 0),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _buildSectionHeader('App Preferences', VaultColors.secondary),
                const SizedBox(height: 12),
                Container(
                  decoration: VaultDecorations.card(color: VaultColors.surfaceContainerLow),
                  child: Column(children: [
                    _buildSettingsTile(
                      icon: Icons.security,
                      title: 'Biometric Lock',
                      subtitle: 'Fingerprint or face unlock',
                      trailing: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: VaultColors.tertiary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(VaultRadius.full),
                        ),
                        child: Text('ACTIVE', style: GoogleFonts.inter(fontSize: 11, color: VaultColors.tertiary, fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ]),
                ),
              ]),
            ),
          ),

          // About Section
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 0),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _buildSectionHeader('About', VaultColors.primary),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: VaultDecorations.card(color: VaultColors.surfaceContainerLow),
                  child: Row(children: [
                    Container(
                      width: 44, height: 44,
                      decoration: BoxDecoration(
                        color: VaultColors.primaryContainer.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(VaultRadius.md),
                      ),
                      child: const Icon(Icons.shield, color: VaultColors.primaryContainer, size: 22),
                    ),
                    const SizedBox(width: 14),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('VaultX', style: VaultTypography.titleMd),
                      const SizedBox(height: 2),
                      Text('Version 3.0.0 — AES-256 Encrypted', style: VaultTypography.labelMd),
                    ])),
                  ]),
                ),
              ]),
            ),
          ),

          // Danger Zone
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 0),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _buildSectionHeader('Danger Zone', VaultColors.error),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: VaultColors.errorContainer.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(VaultRadius.lg),
                    border: Border.all(color: VaultColors.error.withValues(alpha: 0.1)),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Icon(Icons.dangerous, color: VaultColors.error, size: 40),
                    const SizedBox(height: 16),
                    Text('Wipe the Vault', style: VaultTypography.headlineSm.copyWith(color: VaultColors.error)),
                    const SizedBox(height: 8),
                    Text(
                      'Permanently erase all passwords, encrypted media, security keys, and authentication data. This action is irreversible. Use only as a last resort.',
                      style: VaultTypography.bodySm.copyWith(color: VaultColors.onSurfaceVariant, height: 1.5),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: VaultColors.error,
                          foregroundColor: VaultColors.onError,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(VaultRadius.full)),
                        ),
                        icon: const Icon(Icons.delete_forever, size: 18),
                        label: Text('Execute Permanent Wipe', style: GoogleFonts.manrope(fontWeight: FontWeight.w700, fontSize: 14)),
                        onPressed: () => _confirmWipe(context),
                      ),
                    ),
                  ]),
                ),
              ]),
            ),
          ),

          // Made with ❤️ footer
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 40, 24, 32),
              child: Center(
                child: Column(
                  children: [
                    Container(
                      width: 48,
                      height: 1,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            VaultColors.outlineVariant.withValues(alpha: 0.0),
                            VaultColors.outlineVariant.withValues(alpha: 0.3),
                            VaultColors.outlineVariant.withValues(alpha: 0.0),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: 'Made with ',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.w400,
                              color: VaultColors.onSurfaceVariant.withValues(alpha: 0.5),
                            ),
                          ),
                          const TextSpan(
                            text: '❤️',
                            style: TextStyle(fontSize: 12),
                          ),
                          TextSpan(
                            text: ' by ',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.w400,
                              color: VaultColors.onSurfaceVariant.withValues(alpha: 0.5),
                            ),
                          ),
                          TextSpan(
                            text: 'd0tahmed',
                            style: GoogleFonts.manrope(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: VaultColors.primaryContainer.withValues(alpha: 0.7),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 8)),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, Color accent) {
    return Row(children: [
      Container(width: 4, height: 20, decoration: BoxDecoration(
        color: accent, borderRadius: BorderRadius.circular(2),
      )),
      const SizedBox(width: 10),
      Text(title, style: VaultTypography.titleMd.copyWith(color: accent)),
    ]);
  }

  Widget _buildSettingsTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required Widget trailing,
    VoidCallback? onTap,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: VaultColors.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(VaultRadius.md),
        ),
        child: Icon(icon, color: VaultColors.onSurfaceVariant, size: 20),
      ),
      title: Text(title, style: VaultTypography.titleMd),
      subtitle: Text(subtitle, style: VaultTypography.labelMd),
      trailing: trailing,
      onTap: () {
        if (onTap != null) {
          HapticFeedback.lightImpact();
          onTap();
        }
      },
    );
  }
}