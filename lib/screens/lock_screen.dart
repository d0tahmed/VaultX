import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; 
import 'package:local_auth/local_auth.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart'; // 🛡️ SEC PATCH: Added for upfront permissions
import 'package:google_fonts/google_fonts.dart';
import '../services/vault_provider.dart'; 
import '../services/security_service.dart';
import '../theme/app_theme.dart';
import '../main.dart'; 
import 'main_shell.dart';
import 'pin_setup_screen.dart';
import 'pin_entry_screen.dart';

class LockScreen extends StatefulWidget {
  const LockScreen({super.key});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> with SingleTickerProviderStateMixin {
  final SecurityService _securityService = SecurityService();
  bool _isLoading = true;
  bool _needsSetup = false;
  bool _isPrompting = false; 
  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 2000));
    _pulseAnim = Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
    _pulseCtrl.repeat(reverse: true);
    _checkSetupStatus();
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  Future<void> _checkSetupStatus() async {
    // 🛡️ SEC PATCH: Request Camera Permission UPFRONT.
    final cameraStatus = await Permission.camera.status;
    if (!cameraStatus.isGranted) {
      await Permission.camera.request();
    }

    bool hasPin = await _securityService.hasPinSet();
    if (!mounted) return;

    if (!hasPin) {
      setState(() {
        _needsSetup = true;
        _isLoading = false;
      });
    } else {
      setState(() {
        _isLoading = false;
      });
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) _startBiometricAuth();
      });
    }
  }

  Future<void> _startBiometricAuth() async {
    if (_isPrompting) return; 
    
    HapticFeedback.lightImpact();
    setState(() { _isPrompting = true; });
    SecurityState.isAuthenticating = true; 

    final auth = LocalAuthentication();
    try {
      bool authenticated = await auth.authenticate(
        localizedReason: 'Scan fingerprint to unlock VaultX',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: false, 
        ),
      );

      if (authenticated && mounted) {
        HapticFeedback.heavyImpact(); 
        final sessionPin = await _securityService.getSessionPin();
        await Provider.of<VaultProvider>(context, listen: false).unlockVault(sessionPin ?? "");
        Navigator.pushReplacement(
          context,
          PageRouteBuilder( 
            pageBuilder: (context, animation, secondaryAnimation) => const MainShell(),
            transitionsBuilder: (context, animation, secondaryAnimation, child) {
              return FadeTransition(opacity: animation, child: child);
            },
          ),
        );
      }
    } on PlatformException catch (e) {
      debugPrint("Auth Error: ${e.code}");
      if (mounted) {
        HapticFeedback.heavyImpact();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Biometrics locked. Use your Master PIN instead.',
              style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w600)),
            backgroundColor: VaultColors.error,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 4),
          )
        );
      }
    } finally {
      if (mounted) setState(() { _isPrompting = false; });
      SecurityState.isAuthenticating = false; 
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: VaultColors.background,
        body: Center(child: CircularProgressIndicator(color: VaultColors.primaryContainer)),
      );
    }

    if (_needsSetup) {
      return Scaffold(
        backgroundColor: VaultColors.background,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: VaultColors.primaryContainer.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.shield_outlined, size: 80, color: VaultColors.primaryContainer),
                ),
                const SizedBox(height: 40),
                Text('INITIAL SETUP', style: VaultTypography.headlineMd.copyWith(letterSpacing: 1.5)),
                const SizedBox(height: 20),
                Text(
                  'Before securing your accounts, you must set a master 6-Digit PIN. This is your ultimate fallback if biometrics fail.\n\nDo not lose this PIN.',
                  textAlign: TextAlign.center,
                  style: VaultTypography.bodyLg.copyWith(color: VaultColors.onSurfaceVariant, height: 1.5),
                ),
                const SizedBox(height: 50),
                SizedBox(
                  width: double.infinity,
                  height: 55,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: VaultColors.primaryContainer,
                      foregroundColor: VaultColors.onPrimary,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(VaultRadius.full)),
                      elevation: 0,
                    ),
                    onPressed: () {
                      HapticFeedback.mediumImpact();
                      Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const PinSetupScreen()));
                    },
                    child: Text('Set Master PIN', style: GoogleFonts.manrope(fontSize: 16, fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: VaultColors.background,
      body: Stack(
        children: [
          // Subtle ambient glow
          Positioned(top: -100, left: -100,
            child: Container(width: 400, height: 400, decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(colors: [VaultColors.primary.withValues(alpha: 0.04), Colors.transparent]),
            )),
          ),

          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Lock icon with pulse
                AnimatedBuilder(
                  animation: _pulseAnim,
                  builder: (context, child) {
                    return Container(
                      padding: const EdgeInsets.all(28),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: VaultColors.surfaceContainerHigh,
                        boxShadow: [
                          BoxShadow(
                            color: VaultColors.primaryContainer.withValues(alpha: 0.05 + _pulseAnim.value * 0.1),
                            blurRadius: 40 + _pulseAnim.value * 20,
                            spreadRadius: 10 + _pulseAnim.value * 10,
                          ),
                        ],
                      ),
                      child: const Icon(Icons.lock_outline, size: 64, color: VaultColors.primary),
                    );
                  },
                ),
                const SizedBox(height: 40),
                Text('VAULTX', style: GoogleFonts.manrope(
                  fontSize: 28, fontWeight: FontWeight.w800, color: VaultColors.onSurface, letterSpacing: 6,
                )),
                const SizedBox(height: 8),
                Text('YOUR DIGITAL SANCTUARY', style: VaultTypography.labelSm.copyWith(letterSpacing: 3)),
                const SizedBox(height: 60),
                
                // Fingerprint button
                InkWell(
                  borderRadius: BorderRadius.circular(50),
                  onTap: _startBiometricAuth,
                  child: Container(
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: VaultColors.primary.withValues(alpha: 0.3), width: 2),
                    ),
                    child: const Icon(Icons.fingerprint, size: 56, color: VaultColors.primary),
                  ),
                ),
                const SizedBox(height: 16),
                Text('Tap to scan fingerprint', style: VaultTypography.bodySm),
                
                const SizedBox(height: 50),
                
                // Master PIN button
                TextButton.icon(
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                    backgroundColor: VaultColors.surfaceContainerHigh,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(VaultRadius.full)),
                  ),
                  icon: const Icon(Icons.dialpad, color: VaultColors.primaryContainer, size: 20),
                  label: Text('Use Master PIN', style: GoogleFonts.inter(
                    color: VaultColors.primaryContainer, fontSize: 14, fontWeight: FontWeight.w600,
                  )),
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    Navigator.push(context, MaterialPageRoute(builder: (context) => const PinEntryScreen()));
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}