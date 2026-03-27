import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; 
import 'package:local_auth/local_auth.dart';
import 'package:provider/provider.dart';
import '../services/vault_provider.dart'; 
import '../services/security_service.dart';
import '../main.dart'; 
import 'home_screen.dart';
import 'pin_setup_screen.dart';
import 'pin_entry_screen.dart';

class LockScreen extends StatefulWidget {
  const LockScreen({super.key});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  final SecurityService _securityService = SecurityService();
  bool _isLoading = true;
  bool _needsSetup = false;
  bool _isPrompting = false; 

  @override
  void initState() {
    super.initState();
    _checkSetupStatus();
  }

  Future<void> _checkSetupStatus() async {
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
      // Small delay for smooth startup animation, then auto-prompt
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
          biometricOnly: true, // Keeps the Phone PIN fallback disabled!
        ),
      );

      if (authenticated && mounted) {
        HapticFeedback.heavyImpact(); 
        final sessionPin = await _securityService.getSessionPin();
        await Provider.of<VaultProvider>(context, listen: false).unlockVault(sessionPin ?? '');
        Navigator.pushReplacement(
          context,
          PageRouteBuilder( 
            pageBuilder: (context, animation, secondaryAnimation) => const HomeScreen(),
            transitionsBuilder: (context, animation, secondaryAnimation, child) {
              return FadeTransition(opacity: animation, child: child);
            },
          ),
        );
      }
    } on PlatformException catch (e) {
      // 🔴 THE REBOOT DETECTOR: If the OS rejects biometrics (often happens after a reboot or lockout)
      debugPrint("Auth Error: ${e.code}");
      if (mounted) {
        HapticFeedback.heavyImpact();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('You have rebooted your phone or biometrics are locked. Enter PIN to verify yourself.', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            backgroundColor: Colors.redAccent.shade700,
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
      return const Scaffold(backgroundColor: Color(0xFF0F0F0F), body: Center(child: CircularProgressIndicator(color: Colors.cyanAccent)));
    }

    if (_needsSetup) {
      return Scaffold(
        backgroundColor: const Color(0xFF0F0F0F),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: Colors.orangeAccent.withOpacity(0.1), shape: BoxShape.circle), child: const Icon(Icons.shield_outlined, size: 80, color: Colors.orangeAccent)),
                const SizedBox(height: 40),
                const Text('INITIAL SETUP', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: 1.5)),
                const SizedBox(height: 20),
                const Text('Before securing your accounts, you must set a master 6-Digit PIN. This is your ultimate fallback if biometrics fail.\n\nDo not lose this PIN.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white54, fontSize: 16, height: 1.5)),
                const SizedBox(height: 50),
                SizedBox(
                  width: double.infinity,
                  height: 55,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.cyanAccent.shade700, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), elevation: 8),
                    onPressed: () {
                      HapticFeedback.mediumImpact();
                      Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const PinSetupScreen()));
                    },
                    child: const Text('Set Master PIN', style: TextStyle(color: Colors.black, fontSize: 18, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFF1A1A1A), boxShadow: [BoxShadow(color: Colors.cyanAccent.withOpacity(0.1), blurRadius: 30, spreadRadius: 10)]),
              child: const Icon(Icons.lock_outline, size: 80, color: Colors.cyanAccent),
            ),
            const SizedBox(height: 40),
            const Text('VAULTX IS LOCKED', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: 2.0)),
            const SizedBox(height: 60),
            
            InkWell(
              borderRadius: BorderRadius.circular(50),
              onTap: _startBiometricAuth,
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.cyanAccent.withOpacity(0.3), width: 2)),
                child: const Icon(Icons.fingerprint, size: 60, color: Colors.cyanAccent),
              ),
            ),
            const SizedBox(height: 20),
            const Text('Tap to scan fingerprint', style: TextStyle(color: Colors.white54)),
            
            const SizedBox(height: 50),
            
            TextButton.icon(
              style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12), backgroundColor: const Color(0xFF1A1A1A)),
              icon: const Icon(Icons.dialpad, color: Colors.cyanAccent),
              label: const Text('Use Master PIN', style: TextStyle(color: Colors.cyanAccent, fontSize: 16, fontWeight: FontWeight.bold)),
              onPressed: () {
                HapticFeedback.lightImpact();
                Navigator.push(context, MaterialPageRoute(builder: (context) => const PinEntryScreen()));
              },
            ),
          ],
        ),
      ),
    );
  }
}