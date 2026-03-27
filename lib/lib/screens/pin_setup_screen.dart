import 'package:flutter/material.dart';
import '../services/security_service.dart';
import 'home_screen.dart'; // We will navigate here after setup

class PinSetupScreen extends StatefulWidget {
  const PinSetupScreen({super.key});

  @override
  State<PinSetupScreen> createState() => _PinSetupScreenState();
}

class _PinSetupScreenState extends State<PinSetupScreen> {
  final SecurityService _securityService = SecurityService();
  
  String firstPin = '';
  String confirmPin = '';
  bool isConfirming = false;
  String message = 'Create a 6-Digit Vault PIN';

  void _onKeyPressed(String value) {
    setState(() {
      if (!isConfirming) {
        if (firstPin.length < 6) firstPin += value;
        if (firstPin.length == 6) {
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
    setState(() {
      if (!isConfirming && firstPin.isNotEmpty) {
        firstPin = firstPin.substring(0, firstPin.length - 1);
      } else if (isConfirming && confirmPin.isNotEmpty) {
        confirmPin = confirmPin.substring(0, confirmPin.length - 1);
      } else if (isConfirming && confirmPin.isEmpty) {
        // Go back to step 1 if they backspace an empty confirm screen
        isConfirming = false;
        firstPin = '';
        message = 'Create a 6-Digit Vault PIN';
      }
    });
  }

  Future<void> _verifyAndSavePin() async {
    if (firstPin == confirmPin) {
      // Pins match! Save securely and go to Home
      await _securityService.savePin(firstPin);
      if (!mounted) return;
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PIN Successfully Secured!'), backgroundColor: Colors.green),
      );
      
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const HomeScreen()),
      );
    } else {
      // Pins don't match! Reset.
      setState(() {
        firstPin = '';
        confirmPin = '';
        isConfirming = false;
        message = 'PINs did not match. Try again.';
      });
    }
  }

  // This builds the visual dots (⚫⚫⚫⚪⚪⚪)
  Widget _buildPinIndicator(String currentPin) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(6, (index) {
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 8),
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: index < currentPin.length ? Colors.blueAccent : Colors.grey[800],
          ),
        );
      }),
    );
  }

  // The Custom Hacker-Style Keypad
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
            if (index == 9) return const SizedBox(); // Empty bottom-left
            if (index == 11) {
              return IconButton(
                icon: const Icon(Icons.backspace, color: Colors.white, size: 32),
                onPressed: _onBackspace,
              );
            }
            final number = index == 10 ? '0' : '${index + 1}';
            return ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2C2C2C),
                shape: const CircleBorder(),
              ),
              onPressed: () => _onKeyPressed(number),
              child: Text(number, style: const TextStyle(fontSize: 28, color: Colors.white)),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 60),
            const Icon(Icons.lock_outline, size: 80, color: Colors.blueAccent),
            const SizedBox(height: 20),
            Text(message, style: const TextStyle(color: Colors.white, fontSize: 18)),
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