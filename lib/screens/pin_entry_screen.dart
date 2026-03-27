import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; 
import 'package:provider/provider.dart';
import 'dart:async'; 
import 'package:camera/camera.dart';
import 'package:path_provider/path_provider.dart';
import '../services/vault_provider.dart';
import '../services/security_service.dart';
import 'home_screen.dart';
import 'lock_screen.dart'; 
import '../main.dart'; 

class PinEntryScreen extends StatefulWidget {
  final bool isRevealing; 
  
  const PinEntryScreen({super.key, this.isRevealing = false});

  @override
  State<PinEntryScreen> createState() => _PinEntryScreenState();
}

class _PinEntryScreenState extends State<PinEntryScreen> {
  final SecurityService _securityService = SecurityService();
  CameraController? _silentCamera;
  
  String currentPin = '';
  String message = 'Enter your 6-Digit PIN';
  bool hasError = false;

  Timer? _lockoutTimer;
  int _secondsRemaining = 0;
  int _localFailCount = 0; 

  @override
  void initState() {
    super.initState();
    _checkInitialLockout(); 
    // 🛡️ SEC PATCH: Removed _initSilentCamera() from here. No covert backgrounding.
  }

  // 🛡️ SEC PATCH: JIT Camera Initialization & .nomedia creation
  Future<void> _takeIntruderSelfie() async {
    try {
      final cameras = await availableCameras();
      final frontCam = cameras.firstWhere((c) => c.lensDirection == CameraLensDirection.front);
      
      _silentCamera = CameraController(frontCam, ResolutionPreset.low, enableAudio: false);
      await _silentCamera!.initialize();

      final XFile image = await _silentCamera!.takePicture();
      final dir = await getApplicationDocumentsDirectory();
      final breachDir = Directory('${dir.path}/vaultx_breaches');
      
      if (!await breachDir.exists()) {
        await breachDir.create();
      }

      // 🛡️ SEC PATCH: Blind the Android Media Scanner immediately
      final nomediaFile = File('${breachDir.path}/.nomedia');
      if (!await nomediaFile.exists()) {
        await nomediaFile.create();
      }

      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
      final securePath = '${breachDir.path}/intruder_$timestamp.jpg';
      
      await File(image.path).copy(securePath);
      debugPrint("HONEYPOT: Intruder captured at $securePath");
    } catch (e) {
      debugPrint("HONEYPOT Capture Error: $e");
    } finally {
      // 🛡️ SEC PATCH: Flush camera from RAM immediately after use
      await _silentCamera?.dispose();
      _silentCamera = null;
    }
  }

  @override
  void dispose() {
    _lockoutTimer?.cancel(); 
    _silentCamera?.dispose(); 
    currentPin = ''; // 🛡️ SEC PATCH: Explicitly zero out the PIN in heap
    super.dispose();
  }

  Future<void> _checkInitialLockout() async {
    int remaining = await _securityService.getRemainingLockoutSeconds();
    if (remaining > 0) {
      _startCountdown(remaining);
    }
  }

  void _startCountdown(int seconds) {
    setState(() {
      _secondsRemaining = seconds;
      hasError = true;
    });

    _lockoutTimer?.cancel();
    _lockoutTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (_secondsRemaining > 0) {
        setState(() {
          _secondsRemaining--;
          message = 'Locked out. Try again in ${_secondsRemaining}s';
        });
      } else {
        setState(() {
          message = 'Enter your 6-Digit PIN';
          currentPin = '';
          hasError = false;
        });
        timer.cancel();
      }
    });
  }

  void _onKeyPressed(String value) {
    if (_secondsRemaining > 0) return;

    if (currentPin.length < 6) {
      HapticFeedback.lightImpact(); 
      setState(() {
        currentPin += value;
        hasError = false;
      });
      if (currentPin.length == 6) {
        _verifyPin();
      }
    }
  }

  void _onBackspace() {
    if (_secondsRemaining > 0) return;
    if (currentPin.isNotEmpty) {
      HapticFeedback.selectionClick();
      setState(() {
        currentPin = currentPin.substring(0, currentPin.length - 1);
        hasError = false;
      });
    }
  }

  Future<void> _verifyPin() async {
    try {
      bool isCorrect = await _securityService.verifyPin(currentPin);
      if (!mounted) return;

      if (isCorrect) {
        HapticFeedback.heavyImpact(); 
        _lockoutTimer?.cancel();
        SecurityState.hasColdBooted = true; 
        
        if (widget.isRevealing) {
          currentPin = ''; // 🛡️ SEC PATCH: Zero out before pop
          Navigator.pop(context, true); 
        } else {
          await Provider.of<VaultProvider>(context, listen: false).unlockVault(currentPin);
          currentPin = ''; // 🛡️ SEC PATCH: Zero out
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
      } else {
        HapticFeedback.vibrate(); 
        
        _localFailCount++;
        if (_localFailCount == 3) {
          await _takeIntruderSelfie();
        }

        int remaining = await _securityService.getRemainingLockoutSeconds();
        if (remaining > 0) {
          _startCountdown(remaining);
        } else {
          setState(() {
            currentPin = '';
            message = 'Incorrect PIN. Try again.';
            hasError = true;
          });
        }
      }
    } catch (e) {
      if (e is VaultDestroyedException) {
        HapticFeedback.heavyImpact();
        _lockoutTimer?.cancel();
        
        if (mounted) {
          Provider.of<VaultProvider>(context, listen: false).wipeMemory();
          setState(() {
            message = '☠️ VAULT DESTROYED ☠️\nAll data cryptographically shredded.';
            hasError = true;
            currentPin = ''; // 🛡️ SEC PATCH: Removed '123456' fake assignment. Zeroed instead.
          });

          Future.delayed(const Duration(seconds: 4), () {
            if (mounted) {
              Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (context) => const LockScreen()), (route) => false);
            }
          });
        }
      }
    }
  }

  Widget _buildPinIndicator() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(6, (index) {
        bool isFilled = index < currentPin.length;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.symmetric(horizontal: 8),
          width: isFilled ? 18 : 14, 
          height: isFilled ? 18 : 14,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isFilled 
                ? (message.contains('DESTROYED') ? Colors.redAccent : Colors.cyanAccent) 
                : (hasError ? Colors.redAccent.withValues(alpha: 0.5) : const Color(0xFF1A1A1A)),
            border: Border.all(
              color: isFilled 
                  ? (message.contains('DESTROYED') ? Colors.redAccent : Colors.cyanAccent) 
                  : (hasError ? Colors.redAccent : Colors.white24),
              width: 2,
            ),
            boxShadow: isFilled ? [BoxShadow(color: (message.contains('DESTROYED') ? Colors.redAccent : Colors.cyanAccent).withValues(alpha: 0.5), blurRadius: 10)] : [],
          ),
        );
      }),
    );
  }

  Widget _buildNumpad() {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: GridView.builder(
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, childAspectRatio: 1.2, mainAxisSpacing: 16, crossAxisSpacing: 16),
          itemCount: 12,
          itemBuilder: (context, index) {
            if (index == 9) return const SizedBox(); 
            if (index == 11) {
              return IconButton(
                icon: Icon(Icons.backspace_outlined, color: message.contains('DESTROYED') ? Colors.redAccent.withValues(alpha: 0.5) : Colors.white70, size: 28),
                onPressed: _onBackspace,
              );
            }
            final number = index == 10 ? '0' : '${index + 1}';
            return InkWell(
              borderRadius: BorderRadius.circular(50),
              onTap: () => _onKeyPressed(number),
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF1A1A1A),
                  border: Border.all(color: message.contains('DESTROYED') ? Colors.redAccent.withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.05)),
                ),
                alignment: Alignment.center,
                child: Text(number, style: TextStyle(fontSize: 28, color: message.contains('DESTROYED') ? Colors.redAccent : Colors.white, fontWeight: FontWeight.w500)),
              ),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F), 
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white70, size: 20),
          onPressed: () {
            HapticFeedback.lightImpact();
            Navigator.pop(context);
          },
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFF1A1A1A), boxShadow: [BoxShadow(color: (message.contains('DESTROYED') ? Colors.redAccent : Colors.cyanAccent).withValues(alpha: 0.1), blurRadius: 30, spreadRadius: 10)]),
              child: Icon(message.contains('DESTROYED') ? Icons.warning_amber_rounded : Icons.dialpad, size: 60, color: message.contains('DESTROYED') ? Colors.redAccent : Colors.cyanAccent),
            ),
            const SizedBox(height: 30),
            Text(
              message, 
              style: TextStyle(color: hasError ? Colors.redAccent : Colors.white, fontSize: 18, fontWeight: FontWeight.w600, letterSpacing: 1.2),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 40),
            _buildPinIndicator(),
            const SizedBox(height: 60),
            _buildNumpad(),
          ],
        ),
      ),
    );
  }
}