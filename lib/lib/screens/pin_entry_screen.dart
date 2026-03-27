import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // 🔴 UX UPGRADE: Added Haptics
import 'package:provider/provider.dart';
import 'dart:async'; 
import '../services/vault_provider.dart';
import '../services/security_service.dart';
import 'home_screen.dart';
import '../main.dart'; // 🔴 RED TEAM PATCH: Need this to access SecurityState

class PinEntryScreen extends StatefulWidget {
  final bool isRevealing; 
  
  const PinEntryScreen({super.key, this.isRevealing = false});

  @override
  State<PinEntryScreen> createState() => _PinEntryScreenState();
}

class _PinEntryScreenState extends State<PinEntryScreen> {
  final SecurityService _securityService = SecurityService();
  String currentPin = '';
  String message = 'Enter your 6-Digit PIN';
  bool hasError = false;

  Timer? _lockoutTimer;
  int _secondsRemaining = 0;

  @override
  void initState() {
    super.initState();
    _checkInitialLockout(); 
  }

  @override
  void dispose() {
    _lockoutTimer?.cancel(); 
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
      HapticFeedback.lightImpact(); // 🔴 UX UPGRADE: Premium keypress feel
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
    bool isCorrect = await _securityService.verifyPin(currentPin);
    if (!mounted) return;

    if (isCorrect) {
      HapticFeedback.heavyImpact(); // Success vibration
      _lockoutTimer?.cancel();
      
      // 🔴 RED TEAM PATCH: The Cold Boot Authorization!
      // This tells the app the user actually knows the Master PIN.
      SecurityState.hasColdBooted = true; 
      
      if (widget.isRevealing) {
        Navigator.pop(context, true); 
      } else {
        await Provider.of<VaultProvider>(context, listen: false).unlockVault(currentPin);
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
      HapticFeedback.vibrate(); // Error vibration
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
  }

  Widget _buildPinIndicator() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(6, (index) {
        bool isFilled = index < currentPin.length;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.symmetric(horizontal: 8),
          width: isFilled ? 18 : 14, // Dots grow slightly when filled
          height: isFilled ? 18 : 14,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isFilled 
                ? Colors.cyanAccent 
                : (hasError ? Colors.redAccent.withOpacity(0.5) : const Color(0xFF1A1A1A)),
            border: Border.all(
              color: isFilled ? Colors.cyanAccent : (hasError ? Colors.redAccent : Colors.white24),
              width: 2,
            ),
            boxShadow: isFilled ? [BoxShadow(color: Colors.cyanAccent.withOpacity(0.5), blurRadius: 10)] : [],
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
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            childAspectRatio: 1.2,
            mainAxisSpacing: 16,
            crossAxisSpacing: 16,
          ),
          itemCount: 12,
          itemBuilder: (context, index) {
            if (index == 9) return const SizedBox(); 
            if (index == 11) {
              return IconButton(
                icon: const Icon(Icons.backspace_outlined, color: Colors.white70, size: 28),
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
                  border: Border.all(color: Colors.white.withOpacity(0.05)),
                ),
                alignment: Alignment.center,
                child: Text(number, style: const TextStyle(fontSize: 28, color: Colors.white, fontWeight: FontWeight.w500)),
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
      backgroundColor: const Color(0xFF0F0F0F), // 🔴 Premium OLED Black
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
              decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFF1A1A1A), boxShadow: [BoxShadow(color: Colors.cyanAccent.withOpacity(0.1), blurRadius: 30, spreadRadius: 10)]),
              child: const Icon(Icons.dialpad, size: 60, color: Colors.cyanAccent),
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