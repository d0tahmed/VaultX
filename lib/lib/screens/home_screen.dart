import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // For Haptic Feedback
import 'package:provider/provider.dart';
import '../services/vault_provider.dart';
import 'category_detail_screen.dart';
import 'settings_screen.dart'; // 🔴 NEW: Imported the Settings Screen!

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool isEditMode = false;
  List<String> selectedCategoryIds = [];

  void _showAddCategorySheet(BuildContext context) {
    final TextEditingController categoryController = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: const BoxDecoration(
            color: Color(0xFF161618),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('New Folder', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),
              TextField(
                controller: categoryController,
                autofocus: true,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'e.g. Socials, Work',
                  hintStyle: const TextStyle(color: Colors.grey),
                  filled: true,
                  fillColor: const Color(0xFF222225),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00E5FF),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () {
                    if (categoryController.text.trim().isNotEmpty) {
                      HapticFeedback.mediumImpact();
                      Provider.of<VaultProvider>(context, listen: false).addCategory(categoryController.text.trim());
                      Navigator.pop(context);
                    }
                  },
                  child: const Text('Create Folder', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 🔴 UX UPGRADE: The Slide-Up Bottom Sheet for Folders!
  void _showFolderMenu(BuildContext context, dynamic category) {
    HapticFeedback.mediumImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF161618),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (BuildContext modalContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Wrap(
              children: [
                Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(10)))),
                Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Text('Manage ${category.name}', style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                ),
                ListTile(
                  leading: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: const Color(0xFF00E5FF).withOpacity(0.1), borderRadius: BorderRadius.circular(8)), child: const Icon(Icons.edit_outlined, color: Color(0xFF00E5FF))),
                  title: const Text('Rename Folder', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
                  onTap: () {
                    HapticFeedback.lightImpact();
                    Navigator.pop(modalContext);
                    _showRenameCategoryDialog(context, category.id, category.name);
                  },
                ),
                ListTile(
                  leading: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.redAccent.withOpacity(0.1), borderRadius: BorderRadius.circular(8)), child: const Icon(Icons.delete_outline, color: Colors.redAccent)),
                  title: const Text('Delete Folder', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w500)),
                  onTap: () {
                    HapticFeedback.heavyImpact();
                    Navigator.pop(modalContext);
                    _showDeleteConfirmation(context, category);
                  },
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showRenameCategoryDialog(BuildContext context, String categoryId, String currentName) {
    final TextEditingController nameController = TextEditingController(text: currentName);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF161618),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Rename Folder', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: nameController,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(hintText: 'Folder Name'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00E5FF), foregroundColor: Colors.black),
            onPressed: () {
              if (nameController.text.trim().isNotEmpty) {
                Provider.of<VaultProvider>(context, listen: false).renameCategory(categoryId, nameController.text.trim());
                Navigator.pop(context);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showDeleteConfirmation(BuildContext context, dynamic category) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF161618),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Delete Folder?', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
        content: Text('Are you sure you want to delete "${category.name}" and all its passwords? This cannot be undone.', style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            onPressed: () {
              Provider.of<VaultProvider>(context, listen: false).deleteCategory(category.id);
              Navigator.pop(context);
            },
            child: const Text('Delete', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final vault = Provider.of<VaultProvider>(context);

    return Scaffold(
      appBar: AppBar(
        // 🔴 FIX: Added the Settings Icon back!
        leading: IconButton(
          icon: const Icon(Icons.settings_outlined, color: Colors.white70),
          onPressed: () {
            HapticFeedback.lightImpact();
            Navigator.push(context, MaterialPageRoute(builder: (context) => const SettingsScreen()));
          },
        ),
        title: const Text('VaultX', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.5)),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(isEditMode ? Icons.close : Icons.edit_note, color: isEditMode ? Colors.redAccent : const Color(0xFF00E5FF)),
            onPressed: () {
              HapticFeedback.lightImpact();
              setState(() {
                isEditMode = !isEditMode;
                selectedCategoryIds.clear();
              });
            },
          ),
          if (isEditMode && selectedCategoryIds.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep, color: Colors.redAccent),
              onPressed: () {
                HapticFeedback.heavyImpact();
                for (var id in selectedCategoryIds) vault.deleteCategory(id);
                setState(() {
                  isEditMode = false;
                  selectedCategoryIds.clear();
                });
              },
            ),
        ],
      ),
      body: vault.categories.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Icon(Icons.folder_open, size: 80, color: Color(0xFF222225)),
                  SizedBox(height: 16),
                  Text('Your vault is empty.', style: TextStyle(color: Colors.grey, fontSize: 16)),
                ],
              ),
            )
          : ListView.builder(
              physics: const BouncingScrollPhysics(), 
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              itemCount: vault.categories.length,
              itemBuilder: (context, index) {
                final category = vault.categories[index];
                final isSelected = selectedCategoryIds.contains(category.id);

                return AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: isSelected ? const Color(0xFF00E5FF).withOpacity(0.1) : const Color(0xFF161618),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: isSelected ? const Color(0xFF00E5FF) : Colors.transparent, width: 1.5),
                  ),
                  child: ListTile(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    leading: isEditMode
                        ? Checkbox(
                            value: isSelected,
                            activeColor: const Color(0xFF00E5FF),
                            checkColor: Colors.black,
                            onChanged: (val) {
                              HapticFeedback.selectionClick();
                              setState(() {
                                val! ? selectedCategoryIds.add(category.id) : selectedCategoryIds.remove(category.id);
                              });
                            },
                          )
                        : const Icon(Icons.folder_special, color: Color(0xFF00E5FF), size: 28),
                    title: Text(category.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                    subtitle: Text('${category.entries.length} items', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                    onLongPress: () {
                      if (!isEditMode) _showFolderMenu(context, category); 
                    },
                    onTap: () {
                      if (isEditMode) {
                        HapticFeedback.selectionClick();
                        setState(() {
                          isSelected ? selectedCategoryIds.remove(category.id) : selectedCategoryIds.add(category.id);
                        });
                      } else {
                        HapticFeedback.lightImpact();
                        Navigator.push(
                          context,
                          PageRouteBuilder(
                            pageBuilder: (context, animation, secondaryAnimation) => CategoryDetailScreen(
                              categoryId: category.id,
                              categoryName: category.name,
                            ),
                            transitionsBuilder: (context, animation, secondaryAnimation, child) {
                              return FadeTransition(opacity: animation, child: child);
                            },
                          ),
                        );
                      }
                    },
                  ),
                );
              },
            ),
      floatingActionButton: isEditMode
          ? null
          : FloatingActionButton.extended(
              backgroundColor: const Color(0xFF00E5FF),
              foregroundColor: Colors.black,
              onPressed: () {
                HapticFeedback.lightImpact();
                _showAddCategorySheet(context);
              },
              icon: const Icon(Icons.add_circle_outline),
              label: const Text('New Folder', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
    );
  }
}