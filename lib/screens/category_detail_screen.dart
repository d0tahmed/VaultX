import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; 
import 'package:provider/provider.dart';
import 'package:local_auth/local_auth.dart';
import '../services/vault_provider.dart';
import '../services/clipboard_service.dart'; // 🔴 RED TEAM PATCH: Added Clipboard Service
import 'pin_entry_screen.dart';
import '../models/password_entry.dart';
import '../main.dart'; // 🔴 Needed to talk to the Watchdog's SecurityState

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

  // --- SMOOTH EDIT MENU ---
  // ── AUTH GATE: fires before ANY edit action ───────────────────────────────
  // Tries biometric first; if unavailable or fails, falls back to PIN screen.
  // Only calls [onVerified] if the user actually passes auth.
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
            biometricOnly: false, // allows PIN fallback from OS too
          ),
        );
        SecurityState.isAuthenticating = false;
        if (ok && context.mounted) onVerified();
      } catch (_) {
        SecurityState.isAuthenticating = false;
        // Biometric threw — fall through to PIN
        if (context.mounted) await _gateWithPin(context, onVerified);
      }
    } else {
      // No biometric on device — go straight to PIN
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
  // ─────────────────────────────────────────────────────────────────────────

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
                // ✅ ALL edits now go through _gateEditWithAuth first
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
                // Delete still requires confirmation dialog (no auth needed — it's destructive but not secret)
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

  ListTile _buildMenuTile(IconData icon, String title, VoidCallback onTap, {Color color = Colors.cyanAccent}) {
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
          cursorColor: Colors.cyanAccent,
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
            style: ElevatedButton.styleFrom(backgroundColor: Colors.cyanAccent.shade700, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            onPressed: () {
              if (controller.text.isNotEmpty) {
                final vault = Provider.of<VaultProvider>(context, listen: false);
                if (fieldToEdit == 'title') vault.updateEntry(widget.categoryId, entry.id, newTitle: controller.text);
                if (fieldToEdit == 'email') vault.updateEntry(widget.categoryId, entry.id, newEmail: controller.text);
                if (fieldToEdit == 'password') vault.updateEntry(widget.categoryId, entry.id, newPassword: controller.text);
                Navigator.pop(context);
              }
            },
            child: const Text('Save', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
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

  void _showAuthOptions(BuildContext context, String title, String password) {
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
              _buildMenuTile(Icons.fingerprint, 'Use Fingerprint', () { Navigator.pop(modalContext); _verifyBiometric(context, title, password); }),
              _buildMenuTile(Icons.dialpad, 'Use Vault PIN', () { Navigator.pop(modalContext); _verifyPin(context, title, password); }),
              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }
Future<void> _verifyBiometric(BuildContext context, String title, String password) async {
    final auth = LocalAuthentication();
    try {
      // 🔴 RED TEAM PATCH: Tell the Watchdog "We are authenticating, do not wipe memory!"
      SecurityState.isAuthenticating = true; 
      
      bool authenticated = await auth.authenticate(
        localizedReason: 'Scan fingerprint to reveal password', 
        options: const AuthenticationOptions(stickyAuth: true, biometricOnly: true)
      );
      
      if (authenticated && mounted) {
        _showPasswordDialog(context, title, password);
      }
    } catch (e) {
      debugPrint("Auth Error: $e");
    } finally {
      // 🔴 RED TEAM PATCH: Turn the Watchdog back on!
      SecurityState.isAuthenticating = false; 
    }
  }

  Future<void> _verifyPin(BuildContext context, String title, String password) async {
    final result = await Navigator.push(context, MaterialPageRoute(builder: (context) => const PinEntryScreen(isRevealing: true)));
    if (result == true && mounted) _showPasswordDialog(context, title, password);
  }

  void _showPasswordDialog(BuildContext context, String title, String password) {
    HapticFeedback.lightImpact();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.lock_open, color: Colors.cyanAccent),
            const SizedBox(width: 10),
            Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: const Color(0xFF0F0F0F), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white10)),
          child: SelectableText(password, style: const TextStyle(color: Colors.cyanAccent, fontSize: 24, letterSpacing: 2.0, fontWeight: FontWeight.w600), textAlign: TextAlign.center),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close', style: TextStyle(color: Colors.white54))),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.cyanAccent.shade700, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            icon: const Icon(Icons.copy, color: Colors.black, size: 18),
            label: const Text('Copy Password', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
            onPressed: () {
              HapticFeedback.mediumImpact();
              
              // 🔴 RED TEAM FIX: Secure Copy triggers the auto-wipe!
              ClipboardService.secureCopy(password);
              
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: const Text('Copied! Auto-wiping in 15s...', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                backgroundColor: Colors.cyanAccent.shade700,
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
    final titleController = TextEditingController();
    final emailController = TextEditingController(); 
    final passController = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true, 
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 24, right: 24, top: 24),
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
            _buildTextField(passController, 'Password', Icons.password, obscure: true),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.cyanAccent.shade700, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                onPressed: () {
                  if (titleController.text.isNotEmpty && passController.text.isNotEmpty) {
                    HapticFeedback.mediumImpact();
                    Provider.of<VaultProvider>(context, listen: false).addEntryToCategory(widget.categoryId, titleController.text, emailController.text, passController.text);
                    Navigator.pop(context);
                  }
                },
                child: const Text('Save Entry', style: TextStyle(color: Colors.black, fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField(TextEditingController controller, String hint, IconData icon, {bool obscure = false}) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      style: const TextStyle(color: Colors.white),
      cursorColor: Colors.cyanAccent,
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
            icon: Icon(isEditMode ? Icons.done_all : Icons.edit_note, color: isEditMode ? Colors.cyanAccent : Colors.white70),
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
                    color: isSelected ? Colors.cyanAccent.withOpacity(0.1) : const Color(0xFF1A1A1A),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: isSelected ? Colors.cyanAccent : Colors.white.withOpacity(0.05), width: 1.5),
                  ),
                  child: ListTile(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    leading: isEditMode
                        ? Checkbox(
                            value: isSelected,
                            activeColor: Colors.cyanAccent.shade700,
                            checkColor: Colors.black,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                            onChanged: (val) {
                              HapticFeedback.selectionClick();
                              setState(() => val == true ? selectedEntryIds.add(entry.id) : selectedEntryIds.remove(entry.id));
                            },
                          )
                        : Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(color: const Color(0xFF2C2C2C), borderRadius: BorderRadius.circular(12)),
                            child: const Icon(Icons.vpn_key_rounded, color: Colors.cyanAccent),
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
                        _showAuthOptions(context, entry.title, entry.password);
                      }
                    },
                  ),
                );
              },
            ),
      floatingActionButton: isEditMode
          ? null
          : FloatingActionButton(
              backgroundColor: Colors.cyanAccent.shade700,
              elevation: 8,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              onPressed: () => _showAddEntryDialog(context),
              child: const Icon(Icons.add, color: Colors.black, size: 28),
            ),
    );
  }
}