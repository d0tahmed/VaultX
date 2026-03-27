import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'pin_entry_screen.dart';
import 'pin_setup_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Settings', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1.2)),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white70, size: 20),
          onPressed: () {
            HapticFeedback.lightImpact();
            Navigator.pop(context);
          },
        ),
      ),
      body: Column(
        children: [
          const SizedBox(height: 20),
          
          // --- THE PIN CHANGE TILE ---
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              decoration: BoxDecoration(
                color: const Color(0xFF161618),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.cyanAccent.withOpacity(0.1), width: 1.5),
              ),
              child: ListTile(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.cyanAccent.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.password, color: Colors.cyanAccent),
                ),
                title: const Text(
                  'Change VaultX SEC PIN', 
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)
                ),
                trailing: const Icon(Icons.chevron_right, color: Colors.white38),
                onTap: () async {
                  HapticFeedback.selectionClick();
                  
                  // 1. Force the user to prove who they are first!
                  final bool? verified = await Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const PinEntryScreen(isRevealing: true)),
                  );

                  // 2. If they enter the correct current PIN, let them set a new one
                  if (verified == true && context.mounted) {
                    HapticFeedback.mediumImpact();
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(builder: (context) => const PinSetupScreen()),
                    );
                  }
                },
              ),
            ),
          ),
          
          const Spacer(), // Pushes the watermark to the bottom

          // --- YOUR CUSTOM DEVELOPER SIGNATURE ---
          Padding(
            padding: const EdgeInsets.only(bottom: 40.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  'made with ', 
                  style: TextStyle(color: Colors.white38, fontSize: 14, fontWeight: FontWeight.w500)
                ),
                const Text('❤️', style: TextStyle(fontSize: 14)),
                const Text(
                  ' d0tahmed', 
                  style: TextStyle(color: Colors.cyanAccent, fontSize: 14, fontWeight: FontWeight.w800, letterSpacing: 1.5)
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}