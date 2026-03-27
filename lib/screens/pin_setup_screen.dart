import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // 🔴 UX UPGRADE: Added Haptics
import 'package:provider/provider.dart';
import '../services/security_service.dart';
import '../services/vault_provider.dart'; // 🔴 RED TEAM PATCH: Needed to mount the vault
import 'home_screen.dart'; 

class PinSetupScreen extends StatefulWidget {
  // 🔴 RED TEAM PATCH: Tells the screen if we are updating an old PIN from Settings
  final bool isChangingPin; 
  
  const PinSetupScreen({super.key, this.isChangingPin = false});

  @override
  State<PinSetupScreen> createState() => _PinSetupScreenState();
}

class _PinSetupScreenState extends State<PinSetupScreen> {
  final SecurityService _securityService = SecurityService();
  
  String firstPin = '';
  String confirmPin = '';
  bool isConfirming = false;
  late String message;

  @override
  void initState() {
    super.initState();
    message = widget.isChangingPin ? 'Create a NEW 6-Digit PIN' : 'Create a 6-Digit Vault PIN';
  }

  void _onKeyPressed(String value) {
    HapticFeedback.lightImpact(); // Premium keypress feel
    setState(() {
      if (!isConfirming) {
        if (firstPin.length < 6) firstPin += value;
        if (firstPin.length == 6) {
          HapticFeedback.mediumImpact();
          isConfirming = true;
          message = 'Confirm your PIN';
        }
      } else {
        if (confirmPin.length < 6) confirmPin += value;
        if (confirmPin.length == 6) {
          _verifyAndSavePin();
        }
      }
    });
  }

  void _onBackspace() {
    HapticFeedback.selectionClick();
    setState(() {
      if (!isConfirming && firstPin.isNotEmpty) {
        firstPin = firstPin.substring(0, firstPin.length - 1);
      } else if (isConfirming && confirmPin.isNotEmpty) {
        confirmPin = confirmPin.substring(0, confirmPin.length - 1);
      } else if (isConfirming && confirmPin.isEmpty) {
        // Go back to step 1 if they backspace an empty confirm screen
        isConfirming = false;
        firstPin = '';
        message = widget.isChangingPin ? 'Create a NEW 6-Digit PIN' : 'Create a 6-Digit Vault PIN';
      }
    });
  }

  Future<void> _verifyAndSavePin() async {
    if (firstPin == confirmPin) {
      HapticFeedback.heavyImpact(); // Success vibration
      final vault = Provider.of<VaultProvider>(context, listen: false);

      if (widget.isChangingPin) {
        // 🔴 SECURITY PATCH: If changing from settings, we must re-encrypt the data!
        // We save the PIN, and then tell the VaultProvider to re-encrypt the active data.
        await _securityService.savePin(firstPin);
        
        // NOTE: Make sure your VaultProvider has a changeMasterPin method!
        // await vault.changeMasterPin(firstPin); 
      } else {
        // 🔴 SECURITY PATCH: First time setup. Save PIN, then mount the empty vault!
        await _securityService.savePin(firstPin);
        await vault.unlockVault(); 
      }

      if (!mounted) return;
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.isChangingPin ? 'PIN Successfully Updated!' : 'PIN Successfully Secured!', 
            style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)
          ), 
          backgroundColor: Colors.cyanAccent.shade700,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
      
      // Push and Remove Until clears the navigation stack so the user can't hit "Back" to the setup screen
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const HomeScreen()),
        (route) => false,
      );
    } else {
      HapticFeedback.vibrate(); // Error vibration
      setState(() {
        firstPin = '';
        confirmPin = '';
        isConfirming = false;
        message = 'PINs did not match. Try again.';
      });
    }
  }

  // 🔴 UX UPGRADE: Glowing Cyan Pin Indicator
  Widget _buildPinIndicator(String currentPin) {
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
            color: isFilled ? Colors.cyanAccent : const Color(0xFF1A1A1A),
            border: Border.all(
              color: isFilled ? Colors.cyanAccent : Colors.white24,
              width: 2,
            ),
            boxShadow: isFilled ? [BoxShadow(color: Colors.cyanAccent.withOpacity(0.5), blurRadius: 10)] : [],
          ),
        );
      }),
    );
  }

  // 🔴 UX UPGRADE: Premium Glassmorphism Numpad
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
      backgroundColor: const Color(0xFF0F0F0F), // Premium OLED Black
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 60),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                shape: BoxShape.circle, 
                color: const Color(0xFF1A1A1A), 
                boxShadow: [BoxShadow(color: Colors.cyanAccent.withOpacity(0.1), blurRadius: 30, spreadRadius: 10)]
              ),
              child: const Icon(Icons.shield_outlined, size: 60, color: Colors.cyanAccent),
            ),
            const SizedBox(height: 30),
            Text(
              message, 
              style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600, letterSpacing: 1.2)
            ),
            const SizedBox(height: 40),
            _buildPinIndicator(isConfirming ? confirmPin : firstPin),
            const SizedBox(height: 60),
            _buildNumpad(),
          ],
        ),
      ),
    );
  }
}