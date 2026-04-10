import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; 
import 'package:provider/provider.dart';
import 'package:local_auth/local_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/vault_provider.dart';
import '../services/clipboard_service.dart'; 
import '../theme/app_theme.dart';
import 'pin_entry_screen.dart';
import '../models/password_entry.dart';
import '../main.dart'; 

class CategoryDetailScreen extends StatefulWidget {
  final String categoryId;
  final String categoryName;

  const CategoryDetailScreen({super.key, required this.categoryId, required this.categoryName});

  @override
  State<CategoryDetailScreen> createState() => _CategoryDetailScreenState();
}

class _CategoryDetailScreenState extends State<CategoryDetailScreen> {
  bool isEditMode = false;
  List<String> selectedEntryIds = [];

  Future<void> _gateEditWithAuth(BuildContext context, VoidCallback onVerified) async {
    final auth = LocalAuthentication();
    final bool bioAvailable = await auth.canCheckBiometrics && await auth.isDeviceSupported();

    if (bioAvailable) {
      try {
        SecurityState.isAuthenticating = true;
        final bool ok = await auth.authenticate(
          localizedReason: 'Verify identity to edit this entry',
          options: const AuthenticationOptions(
            stickyAuth: true,
            biometricOnly: false, 
          ),
        );
        SecurityState.isAuthenticating = false;
        if (ok && context.mounted) onVerified();
      } catch (_) {
        SecurityState.isAuthenticating = false;
        if (context.mounted) await _gateWithPin(context, onVerified);
      }
    } else {
      await _gateWithPin(context, onVerified);
    }
  }

  Future<void> _gateWithPin(BuildContext context, VoidCallback onVerified) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const PinEntryScreen(isRevealing: true)),
    );
    if (result == true && context.mounted) onVerified();
  }

  void _showEditMenu(BuildContext context, PasswordEntry entry) {
    HapticFeedback.mediumImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: VaultColors.surfaceContainerHigh,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (BuildContext modalContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Wrap(
              children: [
                Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: VaultColors.outlineVariant, borderRadius: BorderRadius.circular(10)))),
                Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Text('Manage ${entry.title}', style: VaultTypography.headlineSm),
                ),
                _buildMenuTile(Icons.password, 'Change Password', () {
                  Navigator.pop(modalContext);
                  _gateEditWithAuth(context, () => _showSingleEditDialog(context, entry, 'password'));
                }),
                _buildMenuTile(Icons.email_outlined, 'Change Email', () {
                  Navigator.pop(modalContext);
                  _gateEditWithAuth(context, () => _showSingleEditDialog(context, entry, 'email'));
                }),
                _buildMenuTile(Icons.edit_outlined, 'Rename Entry', () {
                  Navigator.pop(modalContext);
                  _gateEditWithAuth(context, () => _showSingleEditDialog(context, entry, 'title'));
                }),
                _buildMenuTile(Icons.delete_outline, 'Delete Entry', () {
                  Navigator.pop(modalContext);
                  _showDeleteConfirmation(context, entry);
                }, color: VaultColors.error),
                const SizedBox(height: 20),
              ],
            ),
          ),
        );
      },
    );
  }

  ListTile _buildMenuTile(IconData icon, String title, VoidCallback onTap, {Color color = VaultColors.primary}) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(VaultRadius.md)),
        child: Icon(icon, color: color),
      ),
      title: Text(title, style: GoogleFonts.inter(
        color: color == VaultColors.error ? VaultColors.error : VaultColors.onSurface,
        fontWeight: FontWeight.w500,
      )),
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
    );
  }

  void _showSingleEditDialog(BuildContext context, PasswordEntry entry, String fieldToEdit) {
    final TextEditingController controller = TextEditingController(
      text: fieldToEdit == 'title' ? entry.title : (fieldToEdit == 'email' ? entry.email : entry.password)
    );
    String dialogTitle = fieldToEdit == 'title' ? 'Change Name' : (fieldToEdit == 'email' ? 'Change Email' : 'Change Password');

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: VaultColors.surfaceContainerHigh,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(VaultRadius.xl)),
        title: Text(dialogTitle, style: VaultTypography.headlineSm),
        content: TextField(
          controller: controller,
          autofocus: true,
          obscureText: fieldToEdit == 'password',
          cursorColor: VaultColors.primaryContainer,
          style: GoogleFonts.inter(color: VaultColors.onSurface),
          decoration: InputDecoration(
            filled: true,
            fillColor: VaultColors.surfaceContainerHighest,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(VaultRadius.md), borderSide: BorderSide.none),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text('Cancel', style: GoogleFonts.inter(color: VaultColors.onSurfaceVariant))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: VaultColors.primaryContainer, foregroundColor: VaultColors.onPrimary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(VaultRadius.full)),
            ),
            onPressed: () {
              if (controller.text.isNotEmpty) {
                final vault = Provider.of<VaultProvider>(context, listen: false);
                if (fieldToEdit == 'title') vault.updateEntry(widget.categoryId, entry.id, newTitle: controller.text);
                if (fieldToEdit == 'email') vault.updateEntry(widget.categoryId, entry.id, newEmail: controller.text);
                if (fieldToEdit == 'password') vault.updateEntry(widget.categoryId, entry.id, newPassword: controller.text);
                Navigator.pop(context);
              }
            },
            child: Text('Save', style: GoogleFonts.manrope(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    ).then((_) {
      // 🛡️ SEC PATCH: Destroy the controller and clear plaintext from heap
      controller.clear();
      controller.dispose();
    });
  }

  void _showDeleteConfirmation(BuildContext context, PasswordEntry entry) {
    HapticFeedback.heavyImpact();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: VaultColors.surfaceContainerHigh,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(VaultRadius.xl)),
        title: Text('Delete Entry?', style: VaultTypography.headlineSm.copyWith(color: VaultColors.error)),
        content: Text('Are you sure you want to delete ${entry.title}?', style: VaultTypography.bodyMd.copyWith(color: VaultColors.onSurfaceVariant)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text('Cancel', style: GoogleFonts.inter(color: VaultColors.onSurfaceVariant))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: VaultColors.error, foregroundColor: VaultColors.onError,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(VaultRadius.full))),
            onPressed: () {
              Provider.of<VaultProvider>(context, listen: false).deleteEntry(widget.categoryId, entry.id);
              Navigator.pop(context);
            },
            child: Text('Delete', style: GoogleFonts.manrope(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  // 🛡️ SEC PATCH: Passing Entry object instead of raw password string
  void _showAuthOptions(BuildContext context, PasswordEntry entry) {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: VaultColors.surfaceContainerHigh,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (BuildContext modalContext) {
        return SafeArea(
          child: Wrap(
            children: [
              Center(child: Container(margin: const EdgeInsets.only(top: 12), width: 40, height: 4, decoration: BoxDecoration(color: VaultColors.outlineVariant, borderRadius: BorderRadius.circular(10)))),
              Padding(
                padding: const EdgeInsets.all(24.0),
                child: Text('Verify Identity', style: VaultTypography.headlineSm),
              ),
              _buildMenuTile(Icons.fingerprint, 'Use Fingerprint', () { Navigator.pop(modalContext); _verifyBiometric(context, entry); }),
              _buildMenuTile(Icons.dialpad, 'Use Vault PIN', () { Navigator.pop(modalContext); _verifyPin(context, entry); }),
              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }

  Future<void> _verifyBiometric(BuildContext context, PasswordEntry entry) async {
    final auth = LocalAuthentication();
    try {
      SecurityState.isAuthenticating = true; 
      
      bool authenticated = await auth.authenticate(
        localizedReason: 'Scan fingerprint to reveal password', 
        options: const AuthenticationOptions(stickyAuth: true, biometricOnly: true)
      );
      
      if (authenticated && mounted) {
        _showPasswordDialog(context, entry);
      }
    } catch (e) {
      debugPrint("Auth Error: $e");
    } finally {
      SecurityState.isAuthenticating = false; 
    }
  }

  Future<void> _verifyPin(BuildContext context, PasswordEntry entry) async {
    final result = await Navigator.push(context, MaterialPageRoute(builder: (context) => const PinEntryScreen(isRevealing: true)));
    if (result == true && mounted) _showPasswordDialog(context, entry);
  }

  void _showPasswordDialog(BuildContext context, PasswordEntry entry) {
    HapticFeedback.lightImpact();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: VaultColors.surfaceContainerHigh,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(VaultRadius.xl)),
        title: Row(
          children: [
            const Icon(Icons.lock_open, color: VaultColors.primaryContainer),
            const SizedBox(width: 10),
            Text(entry.title, style: VaultTypography.headlineSm),
          ],
        ),
        content: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: VaultColors.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(VaultRadius.md),
            border: Border.all(color: VaultColors.outlineVariant.withValues(alpha: 0.2)),
          ),
          child: SelectableText(entry.password, style: GoogleFonts.jetBrainsMono(
            color: VaultColors.primaryContainer, fontSize: 22, letterSpacing: 2.0, fontWeight: FontWeight.w600,
          ), textAlign: TextAlign.center),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text('Close', style: GoogleFonts.inter(color: VaultColors.onSurfaceVariant))),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: VaultColors.primaryContainer, foregroundColor: VaultColors.onPrimary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(VaultRadius.full)),
            ),
            icon: const Icon(Icons.copy, size: 18),
            label: Text('Copy Password', style: GoogleFonts.manrope(fontWeight: FontWeight.w700)),
            onPressed: () {
              HapticFeedback.mediumImpact();
              ClipboardService.secureCopy(entry.password);
              
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text('Copied! Auto-wiping in 15s...', style: GoogleFonts.inter(color: VaultColors.onPrimary, fontWeight: FontWeight.w600)),
                backgroundColor: VaultColors.primaryContainer,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(VaultRadius.md)),
              ));
            },
          ),
        ],
      ),
    );
  }

  void _showAddEntryDialog(BuildContext context) {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true, 
      backgroundColor: Colors.transparent, 
      builder: (context) => _AddEntrySheet(categoryId: widget.categoryId),
    );
  }

  @override
  Widget build(BuildContext context) {
    final vault = Provider.of<VaultProvider>(context);
    final category = vault.categories.firstWhere((cat) => cat.id == widget.categoryId);

    return Scaffold(
      backgroundColor: VaultColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(widget.categoryName, style: VaultTypography.titleLg),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: VaultColors.onSurfaceVariant, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: Icon(isEditMode ? Icons.done_all : Icons.edit_note,
              color: isEditMode ? VaultColors.primaryContainer : VaultColors.onSurfaceVariant),
            onPressed: () {
              HapticFeedback.lightImpact();
              setState(() {
                isEditMode = !isEditMode;
                selectedEntryIds.clear();
              });
            },
          ),
          if (isEditMode && selectedEntryIds.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_outline, color: VaultColors.error),
              onPressed: () {
                HapticFeedback.heavyImpact();
                for (var entryId in selectedEntryIds) vault.deleteEntry(widget.categoryId, entryId);
                setState(() => isEditMode = false);
              },
            ),
        ],
      ),
      body: category.entries.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.key_off, size: 80, color: VaultColors.onSurfaceVariant.withValues(alpha: 0.15)),
                  const SizedBox(height: 16),
                  Text('No passwords saved here.', style: VaultTypography.bodyMd.copyWith(color: VaultColors.onSurfaceVariant)),
                ],
              ),
            )
          : ListView.builder(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
              itemCount: category.entries.length,
              itemBuilder: (context, index) {
                final entry = category.entries[index];
                final isSelected = selectedEntryIds.contains(entry.id);

                return AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: isSelected ? VaultColors.primary.withValues(alpha: 0.08) : VaultColors.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(VaultRadius.lg),
                  ),
                  child: ListTile(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(VaultRadius.lg)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    leading: isEditMode
                        ? Checkbox(
                            value: isSelected,
                            activeColor: VaultColors.primaryContainer,
                            checkColor: VaultColors.onPrimary,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                            onChanged: (val) {
                              HapticFeedback.selectionClick();
                              setState(() => val == true ? selectedEntryIds.add(entry.id) : selectedEntryIds.remove(entry.id));
                            },
                          )
                        : Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: VaultColors.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(VaultRadius.md),
                            ),
                            child: const Icon(Icons.vpn_key_rounded, color: VaultColors.primary, size: 20),
                          ),
                    title: Text(entry.title, style: VaultTypography.titleMd),
                    subtitle: Text(entry.email, style: VaultTypography.labelMd), 
                    trailing: Icon(isEditMode ? null : Icons.visibility_outlined, color: VaultColors.onSurfaceVariant, size: 20),
                    onLongPress: () {
                      if (!isEditMode) _showEditMenu(context, entry);
                    },
                    onTap: () {
                      if (isEditMode) {
                        HapticFeedback.selectionClick();
                        setState(() => isSelected ? selectedEntryIds.remove(entry.id) : selectedEntryIds.add(entry.id));
                      } else {
                        _showAuthOptions(context, entry); // 🛡️ SEC PATCH: Pass entry
                      }
                    },
                  ),
                );
              },
            ),
      floatingActionButton: isEditMode
          ? null
          : FloatingActionButton(
              backgroundColor: VaultColors.primaryContainer,
              foregroundColor: VaultColors.onPrimary,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(VaultRadius.full)),
              onPressed: () => _showAddEntryDialog(context),
              child: const Icon(Icons.add, size: 28),
            ),
    );
  }
}

class _AddEntrySheet extends StatefulWidget {
  final String categoryId;
  const _AddEntrySheet({required this.categoryId});

  @override
  State<_AddEntrySheet> createState() => _AddEntrySheetState();
}

class _AddEntrySheetState extends State<_AddEntrySheet> {
  final titleController = TextEditingController();
  final emailController = TextEditingController(); 
  final passController = TextEditingController();

  int _strength = 0; 

  @override
  void dispose() {
    // 🛡️ SEC PATCH: Destroy controllers and wipe plaintext from heap
    titleController.clear();
    titleController.dispose();
    emailController.clear();
    emailController.dispose();
    passController.clear();
    passController.dispose();
    super.dispose();
  }

  void _checkPassword(String pass) {
    if (pass.isEmpty) {
      setState(() => _strength = 0);
      return;
    }

    bool hasUpper = RegExp(r'[A-Z]').hasMatch(pass);
    bool hasLower = RegExp(r'[a-z]').hasMatch(pass);
    bool hasDigit = RegExp(r'[0-9]').hasMatch(pass);
    bool hasSym   = RegExp(r'[!@#\$&*~_=+^%().,-]').hasMatch(pass);
    int length    = pass.length;

    if (length >= 8 && hasUpper && hasSym && hasDigit) {
      setState(() => _strength = 3); 
    } else if (length >= 8 && hasDigit && hasLower) {
      setState(() => _strength = 2); 
    } else {
      setState(() => _strength = 1); 
    }
  }

  Widget _buildTextField(TextEditingController controller, String hint, IconData icon, {bool obscure = false, Function(String)? onChanged}) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      onChanged: onChanged,
      style: GoogleFonts.inter(color: VaultColors.onSurface),
      cursorColor: VaultColors.primaryContainer,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.inter(color: VaultColors.onSurfaceVariant),
        prefixIcon: Icon(icon, color: VaultColors.onSurfaceVariant),
        filled: true,
        fillColor: VaultColors.surfaceContainerHighest,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(VaultRadius.lg), borderSide: BorderSide.none),
      ),
    );
  }

  Widget _buildStrengthMeter() {
    if (_strength == 0) return const SizedBox.shrink(); 

    Color color1 = VaultColors.surfaceContainerHighest;
    Color color2 = VaultColors.surfaceContainerHighest;
    Color color3 = VaultColors.surfaceContainerHighest;
    String text = "";
    Color textColor = VaultColors.onSurfaceVariant;

    if (_strength == 1) { 
      color1 = VaultColors.error; 
      text = "Weak Password"; 
      textColor = VaultColors.error; 
    }
    if (_strength == 2) { 
      color1 = VaultColors.primary; 
      color2 = VaultColors.primary; 
      text = "Medium Password"; 
      textColor = VaultColors.primary; 
    }
    if (_strength == 3) { 
      color1 = VaultColors.tertiary; 
      color2 = VaultColors.tertiary; 
      color3 = VaultColors.tertiary; 
      text = "Strong Password"; 
      textColor = VaultColors.tertiary; 
    }

    return Padding(
      padding: const EdgeInsets.only(top: 12.0),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: AnimatedContainer(duration: const Duration(milliseconds: 300), height: 6, decoration: BoxDecoration(color: color1, borderRadius: BorderRadius.circular(3)))),
              const SizedBox(width: 8),
              Expanded(child: AnimatedContainer(duration: const Duration(milliseconds: 300), height: 6, decoration: BoxDecoration(color: color2, borderRadius: BorderRadius.circular(3)))),
              const SizedBox(width: 8),
              Expanded(child: AnimatedContainer(duration: const Duration(milliseconds: 300), height: 6, decoration: BoxDecoration(color: color3, borderRadius: BorderRadius.circular(3)))),
            ],
          ),
          const SizedBox(height: 8),
          Text(text, style: GoogleFonts.inter(color: textColor, fontWeight: FontWeight.bold, fontSize: 13)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 24, right: 24, top: 24),
      decoration: const BoxDecoration(
        color: VaultColors.surfaceContainerHigh,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('New Password', style: VaultTypography.headlineSm),
          const SizedBox(height: 20),
          _buildTextField(titleController, 'Service (e.g. Netflix)', Icons.title),
          const SizedBox(height: 12),
          _buildTextField(emailController, 'Username / Email', Icons.person_outline),
          const SizedBox(height: 12),
          _buildTextField(
            passController, 
            'Password', 
            Icons.password, 
            obscure: true,
            onChanged: _checkPassword, 
          ),
          
          _buildStrengthMeter(),

          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: VaultColors.primaryContainer,
                foregroundColor: VaultColors.onPrimary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(VaultRadius.full)),
                elevation: 0,
              ),
              onPressed: () {
                if (titleController.text.isNotEmpty && passController.text.isNotEmpty) {
                  HapticFeedback.mediumImpact();
                  Provider.of<VaultProvider>(context, listen: false).addEntryToCategory(widget.categoryId, titleController.text, emailController.text, passController.text);
                  Navigator.pop(context);
                }
              },
              child: Text('Save Entry', style: GoogleFonts.manrope(fontSize: 15, fontWeight: FontWeight.w700)),
            ),
          ),
          const SizedBox(height: 30),
        ],
      ),
    );
  }
}