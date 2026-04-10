import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; 
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/vault_provider.dart';
import '../theme/app_theme.dart';
import 'category_detail_screen.dart';
import 'generator_sheet.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> {
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
            color: VaultColors.surfaceContainerHigh,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('New Folder', style: VaultTypography.headlineSm),
              const SizedBox(height: 20),
              TextField(
                controller: categoryController,
                autofocus: true,
                style: GoogleFonts.inter(color: VaultColors.onSurface),
                cursorColor: VaultColors.primaryContainer,
                decoration: InputDecoration(
                  hintText: 'e.g. Socials, Work',
                  hintStyle: GoogleFonts.inter(color: VaultColors.onSurfaceVariant),
                  filled: true,
                  fillColor: VaultColors.surfaceContainerHighest,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(VaultRadius.md), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: VaultColors.primaryContainer,
                    foregroundColor: VaultColors.onPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(VaultRadius.full)),
                  ),
                  onPressed: () async { 
                    if (categoryController.text.trim().isNotEmpty) {
                      HapticFeedback.mediumImpact();
                      await Provider.of<VaultProvider>(context, listen: false).addCategory(categoryController.text.trim());
                      if (mounted) Navigator.pop(context);
                    }
                  },
                  child: Text('Create Folder', style: GoogleFonts.manrope(fontWeight: FontWeight.w700, fontSize: 15)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void showActionMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: VaultColors.surfaceContainerHigh,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (BuildContext modalContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Wrap(
              children: [
                Center(child: Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 8), decoration: BoxDecoration(color: VaultColors.outlineVariant, borderRadius: BorderRadius.circular(10)))),
                Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Text('Add to Vault', style: VaultTypography.headlineSm),
                ),
                _buildSheetTile(Icons.vpn_key, VaultColors.primaryContainer, 'Generate Password', 'Create a secure, random key', () {
                  Navigator.pop(modalContext); 
                  showModalBottomSheet(context: context, backgroundColor: Colors.transparent, isScrollControlled: true,
                    builder: (context) => const GeneratorSheet());
                }),
                _buildSheetTile(Icons.create_new_folder, VaultColors.tertiary, 'New Folder', 'Organize your credentials', () {
                  Navigator.pop(modalContext); 
                  _showAddCategorySheet(context); 
                }),
                const SizedBox(height: 20),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSheetTile(IconData icon, Color color, String title, String subtitle, VoidCallback onTap) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(VaultRadius.md)),
        child: Icon(icon, color: color, size: 20),
      ),
      title: Text(title, style: VaultTypography.labelLg),
      subtitle: Text(subtitle, style: VaultTypography.labelMd),
      onTap: () { HapticFeedback.lightImpact(); onTap(); },
    );
  }

  void _showFolderMenu(BuildContext context, dynamic category) {
    HapticFeedback.mediumImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: VaultColors.surfaceContainerHigh,
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
                  child: Text('Manage ${category.name}', style: VaultTypography.headlineSm),
                ),
                _buildSheetTile(Icons.edit_outlined, VaultColors.primary, 'Rename Folder', 'Change folder name', () {
                  Navigator.pop(modalContext);
                  _showRenameCategoryDialog(context, category.id, category.name);
                }),
                _buildSheetTile(Icons.delete_outline, VaultColors.error, 'Delete Folder', 'Remove permanently', () {
                  Navigator.pop(modalContext);
                  _showDeleteConfirmation(context, category);
                }),
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
        backgroundColor: VaultColors.surfaceContainerHigh,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(VaultRadius.xl)),
        title: Text('Rename Folder', style: VaultTypography.headlineSm),
        content: TextField(
          controller: nameController,
          autofocus: true,
          style: GoogleFonts.inter(color: VaultColors.onSurface),
          cursorColor: VaultColors.primaryContainer,
          decoration: InputDecoration(
            hintText: 'Folder Name',
            hintStyle: GoogleFonts.inter(color: VaultColors.onSurfaceVariant),
            filled: true,
            fillColor: VaultColors.surfaceContainerHighest,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(VaultRadius.md), borderSide: BorderSide.none),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text('Cancel', style: GoogleFonts.inter(color: VaultColors.onSurfaceVariant))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: VaultColors.primaryContainer, foregroundColor: VaultColors.onPrimary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(VaultRadius.full))),
            onPressed: () async { 
              if (nameController.text.trim().isNotEmpty) {
                await Provider.of<VaultProvider>(context, listen: false).renameCategory(categoryId, nameController.text.trim());
                if (mounted) Navigator.pop(context);
              }
            },
            child: Text('Save', style: GoogleFonts.manrope(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  void _showDeleteConfirmation(BuildContext context, dynamic category) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: VaultColors.surfaceContainerHigh,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(VaultRadius.xl)),
        title: Text('Delete Folder?', style: VaultTypography.headlineSm.copyWith(color: VaultColors.error)),
        content: Text('Are you sure you want to delete "${category.name}" and all its passwords? This cannot be undone.',
          style: VaultTypography.bodyMd.copyWith(color: VaultColors.onSurfaceVariant)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text('Cancel', style: GoogleFonts.inter(color: VaultColors.onSurfaceVariant))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: VaultColors.error, foregroundColor: VaultColors.onError,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(VaultRadius.full))),
            onPressed: () async { 
              await Provider.of<VaultProvider>(context, listen: false).deleteCategory(category.id);
              if (mounted) Navigator.pop(context);
            },
            child: Text('Delete', style: GoogleFonts.manrope(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final vault = Provider.of<VaultProvider>(context);
    final totalItems = vault.categories.fold<int>(0, (sum, cat) => sum + cat.entries.length);
    
    // Collect recent entries across all categories
    List<Map<String, dynamic>> recentEntries = [];
    for (var cat in vault.categories) {
      for (var entry in cat.entries) {
        recentEntries.add({'entry': entry, 'category': cat});
      }
    }

    // Category colors for left border accent
    final accentColors = [
      VaultColors.primary, VaultColors.tertiary, VaultColors.outline, VaultColors.secondary,
      VaultColors.primaryContainer, VaultColors.tertiaryContainer,
    ];
    final catIcons = [Icons.login, Icons.credit_card, Icons.description, Icons.perm_media, Icons.key, Icons.folder_special];

    return Scaffold(
      backgroundColor: VaultColors.background,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          // Top bar
          SliverToBoxAdapter(
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(children: [
                      Container(
                        width: 36, height: 36,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: VaultColors.primary.withValues(alpha: 0.2), width: 2),
                        ),
                        child: const Icon(Icons.shield, color: VaultColors.primaryContainer, size: 18),
                      ),
                      const SizedBox(width: 12),
                      Text('The Vault', style: GoogleFonts.manrope(
                        fontSize: 22, fontWeight: FontWeight.w800, color: VaultColors.primary, letterSpacing: -0.5,
                      )),
                    ]),
                    Row(children: [
                      if (isEditMode && selectedCategoryIds.isNotEmpty)
                        IconButton(
                          icon: const Icon(Icons.delete_sweep, color: VaultColors.error),
                          onPressed: () async { 
                            HapticFeedback.heavyImpact();
                            for (var id in selectedCategoryIds) await vault.deleteCategory(id);
                            setState(() { isEditMode = false; selectedCategoryIds.clear(); });
                          },
                        ),
                      IconButton(
                        icon: Icon(isEditMode ? Icons.close : Icons.search,
                          color: isEditMode ? VaultColors.error : VaultColors.primary, size: 22),
                        onPressed: () {
                          HapticFeedback.lightImpact();
                          setState(() { isEditMode = !isEditMode; selectedCategoryIds.clear(); });
                        },
                      ),
                    ]),
                  ],
                ),
              ),
            ),
          ),

          // Header
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 0),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Your Digital\nSanctuary', style: VaultTypography.headlineLg),
                const SizedBox(height: 8),
                Text('$totalItems secure items stored and encrypted', style: VaultTypography.bodyMd.copyWith(color: VaultColors.onSurfaceVariant)),
              ]),
            ),
          ),

          // Category Grid
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
              child: vault.categories.isEmpty
                ? Container(
                    padding: const EdgeInsets.symmetric(vertical: 48),
                    decoration: VaultDecorations.card(color: VaultColors.surfaceContainerLow),
                    child: Column(children: [
                      Icon(Icons.folder_open, size: 56, color: VaultColors.onSurfaceVariant.withValues(alpha: 0.3)),
                      const SizedBox(height: 16),
                      Text('Your vault is empty.', style: VaultTypography.bodyMd.copyWith(color: VaultColors.onSurfaceVariant)),
                      const SizedBox(height: 4),
                      Text('Tap + to create a folder', style: VaultTypography.labelSm),
                    ]),
                  )
                : GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 1.4,
                    ),
                    itemCount: vault.categories.length,
                    itemBuilder: (context, index) {
                      final category = vault.categories[index];
                      final isSelected = selectedCategoryIds.contains(category.id);
                      final accent = accentColors[index % accentColors.length];
                      final icon = catIcons[index % catIcons.length];

                      return GestureDetector(
                        onTap: () {
                          if (isEditMode) {
                            HapticFeedback.selectionClick();
                            setState(() => isSelected ? selectedCategoryIds.remove(category.id) : selectedCategoryIds.add(category.id));
                          } else {
                            HapticFeedback.lightImpact();
                            Navigator.push(context, PageRouteBuilder(
                              pageBuilder: (context, animation, secondaryAnimation) => CategoryDetailScreen(categoryId: category.id, categoryName: category.name),
                              transitionsBuilder: (context, animation, secondaryAnimation, child) => FadeTransition(opacity: animation, child: child),
                            ));
                          }
                        },
                        onLongPress: () { if (!isEditMode) _showFolderMenu(context, category); },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: isSelected ? accent.withValues(alpha: 0.1) : VaultColors.surfaceContainerLow,
                            borderRadius: BorderRadius.circular(VaultRadius.lg),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Icon(icon, color: accent, size: 24),
                              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(category.name, style: VaultTypography.titleMd, maxLines: 1, overflow: TextOverflow.ellipsis),
                                Text('${category.entries.length} items', style: VaultTypography.labelMd),
                              ]),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
            ),
          ),

          // Recent Access
          if (recentEntries.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Recent Access', style: VaultTypography.headlineSm),
                    Text('View All', style: VaultTypography.labelLg.copyWith(color: VaultColors.primary)),
                  ],
                ),
              ),
            ),
            SliverList(
              delegate: SliverChildBuilderDelegate((context, index) {
                if (index >= recentEntries.length || index >= 5) return null;
                final item = recentEntries[index];
                final entry = item['entry'];
                final cat = item['category'];
                final accent = accentColors[vault.categories.indexOf(cat) % accentColors.length];

                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
                  child: GestureDetector(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      Navigator.push(context, MaterialPageRoute(
                        builder: (_) => CategoryDetailScreen(categoryId: cat.id, categoryName: cat.name),
                      ));
                    },
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: VaultDecorations.accentCard(accent: accent, bgColor: VaultColors.surfaceContainerLow),
                      child: Row(children: [
                        Container(
                          width: 44, height: 44,
                          decoration: BoxDecoration(
                            color: VaultColors.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(VaultRadius.md),
                          ),
                          child: Icon(Icons.key, color: accent, size: 20),
                        ),
                        const SizedBox(width: 14),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(entry.title, style: VaultTypography.titleMd),
                          Text('In ${cat.name}', style: VaultTypography.labelMd),
                        ])),
                        IconButton(
                          icon: const Icon(Icons.content_copy, color: VaultColors.onSurfaceVariant, size: 18),
                          onPressed: () => HapticFeedback.lightImpact(),
                        ),
                      ]),
                    ),
                  ),
                );
              }, childCount: recentEntries.length.clamp(0, 5)),
            ),
          ],

          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }
}