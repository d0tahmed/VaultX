import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; 
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/security_service.dart';
import '../services/vault_provider.dart'; 
import '../theme/app_theme.dart';
import 'main_shell.dart'; 

class PinSetupScreen extends StatefulWidget {
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
    HapticFeedback.lightImpact(); 
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
        isConfirming = false;
        firstPin = '';
        message = widget.isChangingPin ? 'Create a NEW 6-Digit PIN' : 'Create a 6-Digit Vault PIN';
      }
    });
  }

  @override
  void dispose() {
    // 🛡️ SEC PATCH: Wipe initial setup PINs from heap
    firstPin = '';
    confirmPin = '';
    super.dispose();
  }

  Future<void> _verifyAndSavePin() async {
    if (firstPin == confirmPin) {
      HapticFeedback.heavyImpact(); 
      final vault = Provider.of<VaultProvider>(context, listen: false);

      if (widget.isChangingPin) {
        await _securityService.savePin(firstPin);
        await vault.changeMasterPin(firstPin); 
      } else {
        await _securityService.savePin(firstPin);
        await vault.unlockVault(firstPin); 
      }

      if (!mounted) return;
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.isChangingPin ? 'PIN Successfully Updated!' : 'PIN Successfully Secured!', 
            style: GoogleFonts.inter(color: VaultColors.onPrimary, fontWeight: FontWeight.w700),
          ), 
          backgroundColor: VaultColors.primaryContainer,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(VaultRadius.md)),
        ),
      );

      firstPin = '';
      confirmPin = '';
      
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const MainShell()),
        (route) => false,
      );
    } else {
      HapticFeedback.vibrate(); 
      setState(() {
        firstPin = '';
        confirmPin = '';
        isConfirming = false;
        message = 'PINs did not match. Try again.';
      });
    }
  }

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
            color: isFilled ? VaultColors.primaryContainer : Colors.transparent,
            border: Border.all(color: isFilled ? VaultColors.primaryContainer : VaultColors.outlineVariant, width: 2),
            boxShadow: isFilled ? [BoxShadow(color: VaultColors.primaryContainer.withValues(alpha: 0.5), blurRadius: 10)] : [],
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
              return IconButton(icon: const Icon(Icons.backspace_outlined, color: VaultColors.onSurfaceVariant, size: 28), onPressed: _onBackspace);
            }
            final number = index == 10 ? '0' : '${index + 1}';
            return InkWell(
              borderRadius: BorderRadius.circular(50),
              onTap: () => _onKeyPressed(number),
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: VaultColors.surfaceContainerHigh,
                  border: Border.all(color: VaultColors.onSurface.withValues(alpha: 0.05)),
                ),
                alignment: Alignment.center,
                child: Text(number, style: GoogleFonts.inter(fontSize: 28, color: VaultColors.onSurface, fontWeight: FontWeight.w500)),
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
      backgroundColor: VaultColors.background, 
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 60),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                shape: BoxShape.circle, 
                color: VaultColors.surfaceContainerHigh, 
                boxShadow: [BoxShadow(color: VaultColors.primaryContainer.withValues(alpha: 0.1), blurRadius: 30, spreadRadius: 10)],
              ),
              child: const Icon(Icons.shield_outlined, size: 60, color: VaultColors.primaryContainer),
            ),
            const SizedBox(height: 30),
            Text(message, style: GoogleFonts.manrope(color: VaultColors.onSurface, fontSize: 18, fontWeight: FontWeight.w600, letterSpacing: 1.2)),
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