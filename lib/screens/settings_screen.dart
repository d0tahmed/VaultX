import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../services/security_service.dart';
import '../services/vault_provider.dart';
import 'pin_entry_screen.dart';
import 'pin_setup_screen.dart';
import 'lock_screen.dart'; // 🛡️ FIX: Added missing import so the app can route here after wiping

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> with SingleTickerProviderStateMixin {
  late AnimationController _animCtrl;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 480));
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero).animate(CurvedAnimation(parent: _animCtrl, curve: Curves.easeOutCubic));
    _animCtrl.forward();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  Widget _buildTile({required IconData icon, required Color color, required String title, String? subtitle, required VoidCallback onTap, bool isDanger = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      child: Material(
        color: const Color(0xFF161618),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          splashColor: color.withValues(alpha: 0.08),
          highlightColor: color.withValues(alpha: 0.04),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: isDanger ? Colors.redAccent.withValues(alpha: 0.2) : color.withValues(alpha: 0.12), width: 1.5),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
                  child: Icon(icon, color: color, size: 20),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: TextStyle(color: isDanger ? Colors.redAccent : Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(subtitle, style: const TextStyle(color: Colors.white38, fontSize: 12)),
                      ],
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: isDanger ? Colors.redAccent.withValues(alpha: 0.5) : Colors.white24, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 24, top: 20, bottom: 6),
      child: Text(text.toUpperCase(), style: const TextStyle(color: Colors.white24, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.4)),
    );
  }

  Future<void> _changeVaultPin(BuildContext context) async {
    HapticFeedback.selectionClick();
    final bool? verified = await Navigator.push(context, _smoothRoute(const PinEntryScreen(isRevealing: true)));
    if (verified == true && context.mounted) {
      HapticFeedback.mediumImpact();
      Navigator.push(context, _smoothRoute(const PinSetupScreen(isChangingPin: true)));
    }
  }

  Future<void> _resetMediaPin(BuildContext context) async {
    HapticFeedback.selectionClick();
    final bool? verified = await Navigator.push(context, _smoothRoute(const PinEntryScreen(isRevealing: true)));
    if (verified != true || !context.mounted) return;

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF161618),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Reset Media PIN?', style: TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.bold)),
        content: const Text('This will delete your current Media PIN. Your photos and videos are safe.', style: TextStyle(color: Colors.white70, height: 1.5)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel', style: TextStyle(color: Colors.white54))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orangeAccent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Reset PIN', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    await SecurityService().clearMediaPin();
    HapticFeedback.heavyImpact();

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Media PIN reset. Set a new one on next entry.', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          backgroundColor: Colors.orangeAccent,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Route<T> _smoothRoute<T>(Widget page) {
    return PageRouteBuilder<T>(
      pageBuilder: (_, animation, __) => page,
      transitionDuration: const Duration(milliseconds: 320),
      transitionsBuilder: (_, animation, __, child) {
        return FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
          child: SlideTransition(
            position: Tween<Offset>(begin: const Offset(0, 0.04), end: Offset.zero).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
            child: child,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        title: const Text('Settings', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1.2)),
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white70, size: 20), onPressed: () { HapticFeedback.lightImpact(); Navigator.pop(context); }),
      ),
      body: FadeTransition(
        opacity: _fadeAnim,
        child: SlideTransition(
          position: _slideAnim,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionLabel('Security'),
              _buildTile(icon: Icons.password_rounded, color: Colors.cyanAccent, title: 'Change Vault PIN', subtitle: 'Update your master 6-digit PIN', onTap: () => _changeVaultPin(context)),
              _buildTile(icon: Icons.photo_library_outlined, color: Colors.orangeAccent, title: 'Reset Media PIN', subtitle: 'Forgot your media vault PIN? Reset it here', onTap: () => _resetMediaPin(context)),
              _sectionLabel('Danger zone'),
              _buildTile(icon: Icons.delete_forever_rounded, color: Colors.redAccent, title: 'Wipe Entire Vault', subtitle: 'Permanently delete all data', isDanger: true, onTap: () => _confirmWipe(context)),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.only(bottom: 40),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    Text('made with ', style: TextStyle(color: Colors.white38, fontSize: 13)),
                    Text('❤️', style: TextStyle(fontSize: 13)),
                    Text(' by d0tahmed', style: TextStyle(color: Colors.cyanAccent, fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 1.5)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmWipe(BuildContext context) async {
    HapticFeedback.heavyImpact();
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF161618),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Wipe Everything?', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
        content: const Text('This will permanently delete ALL passwords, media, and settings. There is no recovery.', style: TextStyle(color: Colors.white70, height: 1.5)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel', style: TextStyle(color: Colors.white54))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Wipe All', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      await SecurityService().resetAll();
      final vault = Provider.of<VaultProvider>(context, listen: false);
      await vault.deleteVaultFile();
      vault.wipeMemory();
      HapticFeedback.heavyImpact();
      
      // 🛡️ SEC PATCH: Rebuild LockScreen from scratch to kill old state variables
      Navigator.pushAndRemoveUntil(
        context, 
        MaterialPageRoute(builder: (context) => const LockScreen()), 
        (route) => false
      );
    }
  }
}