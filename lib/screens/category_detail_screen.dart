import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; 
import 'package:provider/provider.dart';
import 'package:local_auth/local_auth.dart';
import '../services/vault_provider.dart';
import '../services/clipboard_service.dart'; 
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
      backgroundColor: const Color(0xFF1A1A1A),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (BuildContext modalContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Wrap(
              children: [
                Center(
                  child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(10))),
                ),
                Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Text('Manage ${entry.title}', style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
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
                }, color: Colors.redAccent),
                const SizedBox(height: 20),
              ],
            ),
          ),
        );
      },
    );
  }

  ListTile _buildMenuTile(IconData icon, String title, VoidCallback onTap, {Color color = Colors.purpleAccent}) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
        child: Icon(icon, color: color),
      ),
      title: Text(title, style: TextStyle(color: color == Colors.redAccent ? Colors.redAccent : Colors.white, fontWeight: FontWeight.w500)),
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
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(dialogTitle, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: controller,
          autofocus: true,
          obscureText: fieldToEdit == 'password',
          cursorColor: Colors.purpleAccent,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            filled: true,
            fillColor: const Color(0xFF2C2C2C),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel', style: TextStyle(color: Colors.white54))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.purpleAccent, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            onPressed: () {
              if (controller.text.isNotEmpty) {
                final vault = Provider.of<VaultProvider>(context, listen: false);
                if (fieldToEdit == 'title') vault.updateEntry(widget.categoryId, entry.id, newTitle: controller.text);
                if (fieldToEdit == 'email') vault.updateEntry(widget.categoryId, entry.id, newEmail: controller.text);
                if (fieldToEdit == 'password') vault.updateEntry(widget.categoryId, entry.id, newPassword: controller.text);
                Navigator.pop(context);
              }
            },
            child: const Text('Save', style: TextStyle(fontWeight: FontWeight.bold)),
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
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Delete Entry?', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
        content: Text('Are you sure you want to delete ${entry.title}?', style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel', style: TextStyle(color: Colors.white54))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            onPressed: () {
              Provider.of<VaultProvider>(context, listen: false).deleteEntry(widget.categoryId, entry.id);
              Navigator.pop(context);
            },
            child: const Text('Delete', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (BuildContext modalContext) {
        return SafeArea(
          child: Wrap(
            children: [
              Center(child: Container(margin: const EdgeInsets.only(top: 12), width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(10)))),
              const Padding(
                padding: EdgeInsets.all(24.0),
                child: Text('Verify Identity', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
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
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.lock_open, color: Colors.purpleAccent),
            const SizedBox(width: 10),
            Text(entry.title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: const Color(0xFF0F0F0F), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white10)),
          child: SelectableText(entry.password, style: const TextStyle(color: Colors.purpleAccent, fontSize: 24, letterSpacing: 2.0, fontWeight: FontWeight.w600), textAlign: TextAlign.center),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close', style: TextStyle(color: Colors.white54))),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.purpleAccent, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            icon: const Icon(Icons.copy, size: 18),
            label: const Text('Copy Password', style: TextStyle(fontWeight: FontWeight.bold)),
            onPressed: () {
              HapticFeedback.mediumImpact();
              ClipboardService.secureCopy(entry.password);
              
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: const Text('Copied! Auto-wiping in 15s...', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                backgroundColor: Colors.purpleAccent,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
      backgroundColor: const Color(0xFF0F0F0F),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(widget.categoryName, style: const TextStyle(fontWeight: FontWeight.w700)),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(isEditMode ? Icons.done_all : Icons.edit_note, color: isEditMode ? Colors.purpleAccent : Colors.white70),
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
              icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
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
                  Icon(Icons.key_off, size: 80, color: Colors.white.withOpacity(0.1)),
                  const SizedBox(height: 16),
                  Text('No passwords saved here.', style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 16)),
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
                    color: isSelected ? Colors.purpleAccent.withOpacity(0.1) : const Color(0xFF1A1A1A),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: isSelected ? Colors.purpleAccent : Colors.white.withOpacity(0.05), width: 1.5),
                  ),
                  child: ListTile(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    leading: isEditMode
                        ? Checkbox(
                            value: isSelected,
                            activeColor: Colors.purpleAccent,
                            checkColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                            onChanged: (val) {
                              HapticFeedback.selectionClick();
                              setState(() => val == true ? selectedEntryIds.add(entry.id) : selectedEntryIds.remove(entry.id));
                            },
                          )
                        : Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(color: const Color(0xFF2C2C2C), borderRadius: BorderRadius.circular(12)),
                            child: const Icon(Icons.vpn_key_rounded, color: Colors.purpleAccent),
                          ),
                    title: Text(entry.title, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600)),
                    subtitle: Text(entry.email, style: const TextStyle(color: Colors.white54)), 
                    trailing: Icon(isEditMode ? null : Icons.visibility_outlined, color: Colors.white38, size: 20),
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
              backgroundColor: Colors.purpleAccent,
              foregroundColor: Colors.white,
              elevation: 8,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
      style: const TextStyle(color: Colors.white),
      cursorColor: Colors.purpleAccent,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white38),
        prefixIcon: Icon(icon, color: Colors.white54),
        filled: true,
        fillColor: const Color(0xFF2C2C2C),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
      ),
    );
  }

  Widget _buildStrengthMeter() {
    if (_strength == 0) return const SizedBox.shrink(); 

    Color color1 = const Color(0xFF2C2C2C);
    Color color2 = const Color(0xFF2C2C2C);
    Color color3 = const Color(0xFF2C2C2C);
    String text = "";
    Color textColor = Colors.white54;

    if (_strength == 1) { 
      color1 = Colors.redAccent; 
      text = "Weak Password"; 
      textColor = Colors.redAccent; 
    }
    if (_strength == 2) { 
      color1 = Colors.orangeAccent; 
      color2 = Colors.orangeAccent; 
      text = "Medium Password"; 
      textColor = Colors.orangeAccent; 
    }
    if (_strength == 3) { 
      color1 = Colors.greenAccent; 
      color2 = Colors.greenAccent; 
      color3 = Colors.greenAccent; 
      text = "Strong Password"; 
      textColor = Colors.greenAccent; 
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
          Text(text, style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 13)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 24, right: 24, top: 24),
      decoration: const BoxDecoration(
        color: Color(0xFF1A1A1A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('New Password', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
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
              style: ElevatedButton.styleFrom(backgroundColor: Colors.purpleAccent, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
              onPressed: () {
                if (titleController.text.isNotEmpty && passController.text.isNotEmpty) {
                  HapticFeedback.mediumImpact();
                  Provider.of<VaultProvider>(context, listen: false).addEntryToCategory(widget.categoryId, titleController.text, emailController.text, passController.text);
                  Navigator.pop(context);
                }
              },
              child: const Text('Save Entry', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(height: 30),
        ],
      ),
    );
  }
}