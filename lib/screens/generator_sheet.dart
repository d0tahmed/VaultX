import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/clipboard_service.dart';

class GeneratorSheet extends StatefulWidget {
  const GeneratorSheet({super.key});

  @override
  State<GeneratorSheet> createState() => _GeneratorSheetState();
}

class _GeneratorSheetState extends State<GeneratorSheet> {
  int _selectedLength = 16;
  String _currentDisplay = "CLICK GENERATE";
  bool _isGenerating = false;
  bool _isFinished = false;

  final String _chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!@#\$%^&*()-_=+';
  final Random _secureRandom = Random.secure();

  void _generatePassword() {
    if (_isGenerating) return;

    HapticFeedback.mediumImpact();
    setState(() {
      _isGenerating = true;
      _isFinished = false;
    });

    int frames = 0;
    const int totalFrames = 20; 

    Timer.periodic(const Duration(milliseconds: 50), (timer) {
      frames++;
      
      String scramble = String.fromCharCodes(Iterable.generate(
        _selectedLength, (_) => _chars.codeUnitAt(_secureRandom.nextInt(_chars.length))
      ));

      setState(() { _currentDisplay = scramble; });
      HapticFeedback.selectionClick(); 

      if (frames >= totalFrames) {
        timer.cancel();
        _finalizePassword();
      }
    });
  }

  void _finalizePassword() {
    HapticFeedback.heavyImpact(); 
    String finalPass = String.fromCharCodes(Iterable.generate(
      _selectedLength, (_) => _chars.codeUnitAt(_secureRandom.nextInt(_chars.length))
    ));

    setState(() {
      _currentDisplay = finalPass;
      _isGenerating = false;
      _isFinished = true;
    });
  }

  Widget _buildLengthButton(int length) {
    bool isSelected = _selectedLength == length;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          if (!_isGenerating) {
            HapticFeedback.lightImpact();
            setState(() { 
              _selectedLength = length; 
              _isFinished = false;
              _currentDisplay = "TAP GENERATE";
            });
          }
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? Colors.cyanAccent.shade700 : const Color(0xFF222225),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: isSelected ? Colors.cyanAccent : Colors.transparent),
          ),
          child: Center(
            child: Text('$length', style: TextStyle(color: isSelected ? Colors.black : Colors.white54, fontWeight: FontWeight.bold, fontSize: 16)),
          ),
        ),
      ),
    );
  }

// (Add this inside the _GeneratorSheetState class in lib/screens/generator_sheet.dart)

  @override
  void dispose() {
    // 🛡️ SEC PATCH: Destroy the generated plaintext string from heap when dismissed
    _currentDisplay = ''; 
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: const BoxDecoration(color: Color(0xFF161618), borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Secure Generator', style: TextStyle(color: Colors.cyanAccent, fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
          const SizedBox(height: 24),
          
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
            decoration: BoxDecoration(
              color: const Color(0xFF0F0F0F),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _isFinished ? Colors.cyanAccent : Colors.white10),
              boxShadow: _isFinished ? [BoxShadow(color: Colors.cyanAccent.withValues(alpha: 0.2), blurRadius: 20)] : [],
            ),
            child: Text(
              _currentDisplay,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _isFinished ? Colors.cyanAccent : Colors.white70,
                fontFamily: 'monospace', 
                fontSize: _selectedLength == 32 ? 14 : 20, 
                letterSpacing: 2.0,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          
          const SizedBox(height: 24),
          Row(children: [_buildLengthButton(8), _buildLengthButton(16), _buildLengthButton(32)]),
          const SizedBox(height: 24),
          
          SizedBox(
            width: double.infinity,
            height: 55,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: _isFinished ? const Color(0xFF222225) : Colors.cyanAccent.shade700,
                foregroundColor: _isFinished ? Colors.cyanAccent : Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              onPressed: _isGenerating ? null : (_isFinished ? () {
                ClipboardService.secureCopy(_currentDisplay);
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Password Copied! Auto-wiping in 30s...'), backgroundColor: Colors.cyanAccent));
              } : _generatePassword),
              icon: Icon(_isFinished ? Icons.copy : Icons.memory),
              label: Text(_isFinished ? 'COPY TO CLIPBOARD' : 'GENERATE', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: 1.5)),
            ),
          ),
          SizedBox(height: MediaQuery.of(context).padding.bottom), 
        ],
      ),
    );
  }
}