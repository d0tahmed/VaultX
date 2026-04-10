import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/clipboard_service.dart';
import '../theme/app_theme.dart';

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
            color: isSelected ? VaultColors.primaryContainer : VaultColors.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(VaultRadius.md),
          ),
          child: Center(
            child: Text('$length', style: GoogleFonts.inter(
              color: isSelected ? VaultColors.onPrimary : VaultColors.onSurfaceVariant,
              fontWeight: FontWeight.bold, fontSize: 16,
            )),
          ),
        ),
      ),
    );
  }

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
      decoration: const BoxDecoration(
        color: VaultColors.surfaceContainerHigh,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Secure Generator', style: GoogleFonts.manrope(
            color: VaultColors.primaryContainer, fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: 1.2,
          )),
          const SizedBox(height: 24),
          
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
            decoration: BoxDecoration(
              color: VaultColors.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(VaultRadius.lg),
              border: Border.all(color: _isFinished ? VaultColors.primaryContainer : VaultColors.outlineVariant.withValues(alpha: 0.2)),
              boxShadow: _isFinished ? [BoxShadow(color: VaultColors.primaryContainer.withValues(alpha: 0.15), blurRadius: 20)] : [],
            ),
            child: Text(
              _currentDisplay,
              textAlign: TextAlign.center,
              style: GoogleFonts.jetBrainsMono(
                color: _isFinished ? VaultColors.primaryContainer : VaultColors.onSurfaceVariant,
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
                backgroundColor: _isFinished ? VaultColors.surfaceContainerHighest : VaultColors.primaryContainer,
                foregroundColor: _isFinished ? VaultColors.primaryContainer : VaultColors.onPrimary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(VaultRadius.full)),
                elevation: 0,
              ),
              onPressed: _isGenerating ? null : (_isFinished ? () {
                ClipboardService.secureCopy(_currentDisplay);
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text('Password Copied! Auto-wiping in 30s...', style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: VaultColors.onPrimary)),
                  backgroundColor: VaultColors.primaryContainer));
              } : _generatePassword),
              icon: Icon(_isFinished ? Icons.copy : Icons.memory),
              label: Text(_isFinished ? 'COPY TO CLIPBOARD' : 'GENERATE',
                style: GoogleFonts.manrope(fontWeight: FontWeight.w800, fontSize: 14, letterSpacing: 1.5)),
            ),
          ),
          SizedBox(height: MediaQuery.of(context).padding.bottom), 
        ],
      ),
    );
  }
}