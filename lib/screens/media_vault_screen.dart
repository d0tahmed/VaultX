import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/vault_provider.dart';
import '../services/security_service.dart';
import '../models/media_entry.dart';
import '../theme/app_theme.dart';
import '../main.dart'; 

class MediaVaultScreen extends StatefulWidget {
  const MediaVaultScreen({super.key});

  @override
  State<MediaVaultScreen> createState() => MediaVaultScreenState();
}

class MediaVaultScreenState extends State<MediaVaultScreen> {

  /// Called by MainShell FAB
  void triggerAddMedia() {
    if (_vault != null && _vault!.isMediaUnlocked) {
      _showAddMediaMenu(context);
    }
  }

  final SecurityService _securityService = SecurityService();
  final ImagePicker _picker = ImagePicker();
  
  bool _isCheckingAuth = true;
  bool _hasPinSet = false;
  String _pinInput = '';
  String _authMessage = 'Enter Media PIN';
  bool _hasError = false;
  VaultProvider? _vault;

  @override
  void initState() {
    super.initState();
    _checkInitialState();
  }

  Future<void> _checkInitialState() async {
    final hasPin = await _securityService.hasMediaPinSet();
    if (mounted) {
      setState(() {
        _hasPinSet = hasPin;
        _authMessage = hasPin ? 'Enter Media PIN' : 'Create a Media PIN';
        _isCheckingAuth = false;
      });
    }
  }

  bool _isVerifying = false;

  Future<bool> _onPinKeyPressed(String value, VaultProvider vault) async {
    if (_pinInput.length >= 6 || _isVerifying) return false;
    
    HapticFeedback.lightImpact();
    setState(() { _pinInput += value; _hasError = false; });

    if (_pinInput.length == 6) {
      _isVerifying = true;
      
      if (!_hasPinSet) {
        await _securityService.saveMediaPin(_pinInput);
        HapticFeedback.heavyImpact();
        vault.unlockMediaVault();
        if (mounted) setState(() { _hasPinSet = true; _pinInput = ''; });
        _isVerifying = false;
        return true; // unlocked
      } else {
        try {
          bool isValid = await _securityService.verifyMediaPin(_pinInput);
          if (isValid) {
            HapticFeedback.heavyImpact();
            vault.unlockMediaVault();
            if (mounted) setState(() => _pinInput = '');
            _isVerifying = false;
            return true; // unlocked
          } else {
            HapticFeedback.vibrate();
            if (mounted) setState(() { _hasError = true; _authMessage = 'Incorrect PIN'; _pinInput = ''; });
            _isVerifying = false;
            return false;
          }
        } on VaultDestroyedException {
          HapticFeedback.heavyImpact();
          vault.wipeMemory();
          _isVerifying = false;
          if (mounted) {
            showDialog(
              context: context, barrierDismissible: false,
              builder: (_) => AlertDialog(
                backgroundColor: VaultColors.surfaceContainerHigh,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(VaultRadius.xl)),
                title: Text('Vault Destroyed', style: VaultTypography.headlineSm.copyWith(color: VaultColors.error)),
                content: Text('Too many incorrect attempts. All vault data has been permanently wiped for your security.',
                  style: VaultTypography.bodyMd.copyWith(color: VaultColors.onSurfaceVariant)),
                actions: [
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: VaultColors.error, foregroundColor: VaultColors.onError),
                    onPressed: () => Navigator.of(context).popUntil((route) => route.isFirst),
                    child: Text('OK', style: GoogleFonts.manrope(fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            );
          }
          return false;
        }
      }
    }
    return false;
  }

  Future<void> _pickMedia(BuildContext context, String type) async {
    final vault = Provider.of<VaultProvider>(context, listen: false);
    HapticFeedback.lightImpact();
    SecurityState.isAuthenticating = true;
    try {
      if (type == 'photo') {
        final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
        if (image != null) await vault.addMedia('photo', image.path);
      } else if (type == 'video') {
        final XFile? video = await _picker.pickVideo(source: ImageSource.gallery);
        if (video != null) {
          final tempDir = await getTemporaryDirectory();
          final thumbPath = await VideoThumbnail.thumbnailFile(
            video: video.path, thumbnailPath: tempDir.path, imageFormat: ImageFormat.JPEG, quality: 75,
          );
          await vault.addMedia('video', video.path, thumbnailPath: thumbPath);
        }
      }
    } catch (e) {
      debugPrint("Media Picker Error: $e");
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error accessing gallery: $e', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
          backgroundColor: VaultColors.error,
        ));
      }
    } finally {
      SecurityState.isAuthenticating = false;
    }
  }

  void _showAddMediaMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: VaultColors.surfaceContainerHigh,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (BuildContext modalContext) {
        return SafeArea(
          child: Wrap(
            children: [
              Center(child: Container(margin: const EdgeInsets.only(top: 12), width: 40, height: 4, decoration: BoxDecoration(color: VaultColors.outlineVariant, borderRadius: BorderRadius.circular(10)))),
              Padding(padding: const EdgeInsets.all(24.0), child: Text('Secure Media', style: VaultTypography.headlineSm)),
              ListTile(
                leading: Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: VaultColors.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(VaultRadius.md)),
                  child: const Icon(Icons.photo, color: VaultColors.primary, size: 20)),
                title: Text('Add Photos', style: VaultTypography.labelLg),
                onTap: () { Navigator.pop(modalContext); _pickMedia(context, 'photo'); },
              ),
              ListTile(
                leading: Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: VaultColors.tertiary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(VaultRadius.md)),
                  child: const Icon(Icons.videocam, color: VaultColors.tertiary, size: 20)),
                title: Text('Add Videos', style: VaultTypography.labelLg),
                onTap: () { Navigator.pop(modalContext); _pickMedia(context, 'video'); },
              ),
              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }

  void _showRenameDialog(BuildContext context, MediaFolder folder) {
    final TextEditingController controller = TextEditingController(text: folder.name);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: VaultColors.surfaceContainerHigh,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(VaultRadius.xl)),
        title: Text('Rename Folder', style: VaultTypography.headlineSm),
        content: TextField(
          controller: controller, autofocus: true,
          style: GoogleFonts.inter(color: VaultColors.onSurface), cursorColor: VaultColors.primaryContainer,
          decoration: InputDecoration(filled: true, fillColor: VaultColors.surfaceContainerHighest,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(VaultRadius.md), borderSide: BorderSide.none)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text('Cancel', style: GoogleFonts.inter(color: VaultColors.onSurfaceVariant))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: VaultColors.primaryContainer, foregroundColor: VaultColors.onPrimary),
            onPressed: () { if (controller.text.isNotEmpty) { Provider.of<VaultProvider>(context, listen: false).renameMediaFolder(folder.id, controller.text); Navigator.pop(context); } },
            child: Text('Save', style: GoogleFonts.manrope(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final vault = Provider.of<VaultProvider>(context);
    _vault = vault;

    if (_isCheckingAuth) {
      return const Scaffold(backgroundColor: VaultColors.background, body: Center(child: CircularProgressIndicator(color: VaultColors.primaryContainer)));
    }

    // ─── LOCKED STATE ───
    if (!vault.isMediaUnlocked) {
      return Scaffold(
        backgroundColor: VaultColors.background,
        body: Stack(
          children: [
            // Ambient glows
            Positioned(top: -80, left: -80, child: Container(width: 300, height: 300, decoration: BoxDecoration(
              shape: BoxShape.circle, gradient: RadialGradient(colors: [VaultColors.primary.withValues(alpha: 0.08), Colors.transparent]),
            ))),
            Positioned(bottom: -60, right: -60, child: Container(width: 250, height: 250, decoration: BoxDecoration(
              shape: BoxShape.circle, gradient: RadialGradient(colors: [VaultColors.primaryContainer.withValues(alpha: 0.05), Colors.transparent]),
            ))),

            // Lock UI
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  children: [
                    const SizedBox(height: 60),
                    // Lock icon
                    Container(
                      width: 120, height: 120,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: VaultColors.surfaceContainerHighest,
                        border: Border.all(color: VaultColors.onSurfaceVariant.withValues(alpha: 0.1)),
                        boxShadow: [BoxShadow(color: VaultColors.primary.withValues(alpha: 0.06), blurRadius: 40, spreadRadius: 20)],
                      ),
                      child: Icon(Icons.lock, size: 52, color: VaultColors.primary),
                    ),
                    const SizedBox(height: 28),
                    Text('Media Vault is Locked', style: VaultTypography.headlineMd),
                    const SizedBox(height: 10),
                    Text('Provide authentication to access\nencrypted photos and videos.',
                      textAlign: TextAlign.center,
                      style: VaultTypography.bodyLg.copyWith(color: VaultColors.onSurfaceVariant, height: 1.5)),
                    const Spacer(),

                    // Enter Media PIN button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: VaultColors.primaryContainer,
                          foregroundColor: VaultColors.onPrimary,
                          padding: const EdgeInsets.symmetric(vertical: 18),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(VaultRadius.full)),
                        ),
                        icon: const Icon(Icons.dialpad, size: 20),
                        onPressed: () {
                          HapticFeedback.lightImpact();
                          _showPinPad(context, vault);
                        },
                        label: Text('Enter Media PIN', style: GoogleFonts.manrope(fontWeight: FontWeight.w700, fontSize: 15)),
                      ),
                    ),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    // ─── UNLOCKED STATE ───
    return Scaffold(
      backgroundColor: VaultColors.background,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                child: Row(children: [
                  const Icon(Icons.shield, color: VaultColors.primaryContainer, size: 22),
                  const SizedBox(width: 10),
                  Text('THE VAULT', style: GoogleFonts.manrope(fontSize: 18, fontWeight: FontWeight.w800, color: VaultColors.primaryContainer, letterSpacing: 3)),
                ]),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Secure Media', style: VaultTypography.headlineLg),
                const SizedBox(height: 4),
                Text('Your encrypted photos & videos', style: VaultTypography.bodyMd.copyWith(color: VaultColors.onSurfaceVariant)),
              ]),
            ),
          ),
          if (vault.mediaFolders.isEmpty)
            SliverFillRemaining(
              child: Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.perm_media_outlined, size: 56, color: VaultColors.onSurfaceVariant.withValues(alpha: 0.3)),
                  const SizedBox(height: 16),
                  Text('No secure media stored yet.', style: VaultTypography.bodyMd.copyWith(color: VaultColors.onSurfaceVariant)),
                ]),
              ),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate((context, index) {
                final folder = vault.mediaFolders[index];
                final isVideo = folder.type == 'video';
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
                  child: GestureDetector(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      Navigator.push(context, MaterialPageRoute(builder: (_) => MediaGridScreen(folder: folder)));
                    },
                    onLongPress: () { HapticFeedback.mediumImpact(); _showRenameDialog(context, folder); },
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: VaultDecorations.accentCard(
                        accent: isVideo ? VaultColors.tertiary : VaultColors.primary,
                        bgColor: VaultColors.surfaceContainerLow,
                      ),
                      child: Row(children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: (isVideo ? VaultColors.tertiary : VaultColors.primary).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(VaultRadius.md),
                          ),
                          child: Icon(isVideo ? Icons.videocam : Icons.photo, color: isVideo ? VaultColors.tertiary : VaultColors.primary, size: 22),
                        ),
                        const SizedBox(width: 16),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(folder.name, style: VaultTypography.titleMd),
                          Text('${folder.items.length} items', style: VaultTypography.labelMd),
                        ])),
                        const Icon(Icons.chevron_right, color: VaultColors.onSurfaceVariant, size: 20),
                      ]),
                    ),
                  ),
                );
              }, childCount: vault.mediaFolders.length),
            ),

          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }

  void _showPinPad(BuildContext context, VaultProvider vault) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: VaultColors.surfaceContainerHigh,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return SafeArea(
              child: SingleChildScrollView(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(24, 24, 24, MediaQuery.of(ctx).padding.bottom + 16),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(_authMessage, style: VaultTypography.headlineSm.copyWith(
                      color: _hasError ? VaultColors.error : VaultColors.onSurface)),
                    const SizedBox(height: 24),
                    // PIN dots
                    Row(mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(6, (index) => AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        margin: const EdgeInsets.symmetric(horizontal: 8),
                        width: index < _pinInput.length ? 16 : 12,
                        height: index < _pinInput.length ? 16 : 12,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: index < _pinInput.length ? VaultColors.primaryContainer : Colors.transparent,
                          border: Border.all(color: index < _pinInput.length ? VaultColors.primaryContainer : VaultColors.outlineVariant, width: 2),
                        ),
                      )),
                    ),
                    const SizedBox(height: 32),
                    // Numpad
                    SizedBox(
                      height: 320,
                      child: GridView.builder(
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, childAspectRatio: 1.4, mainAxisSpacing: 8, crossAxisSpacing: 10),
                        itemCount: 12,
                        itemBuilder: (context, index) {
                          if (index == 9) return const SizedBox();
                          if (index == 11) {
                            return IconButton(
                              icon: const Icon(Icons.backspace_outlined, color: VaultColors.onSurfaceVariant, size: 24),
                              onPressed: () {
                                if (_pinInput.isNotEmpty) {
                                  HapticFeedback.selectionClick();
                                  setState(() => _pinInput = _pinInput.substring(0, _pinInput.length - 1));
                                  setSheetState(() {});
                                }
                              },
                            );
                          }
                          final number = index == 10 ? '0' : '${index + 1}';
                          return InkWell(
                            borderRadius: BorderRadius.circular(50),
                            onTap: () async {
                              final unlocked = await _onPinKeyPressed(number, vault);
                              setSheetState(() {});
                              if (unlocked && ctx.mounted) Navigator.pop(ctx);
                            },
                            child: Container(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle, color: VaultColors.surfaceContainer,
                                border: Border.all(color: VaultColors.onSurface.withValues(alpha: 0.05)),
                              ),
                              alignment: Alignment.center,
                              child: Text(number, style: GoogleFonts.inter(fontSize: 24, color: VaultColors.onSurface, fontWeight: FontWeight.w500)),
                            ),
                          );
                        },
                      ),
                    ),
                  ]),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

// ─── MEDIA GRID (unchanged logic) ───
class MediaGridScreen extends StatelessWidget {
  final MediaFolder folder;
  const MediaGridScreen({super.key, required this.folder});

  void _showMediaOptions(BuildContext context, MediaItem item) {
    HapticFeedback.mediumImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: VaultColors.surfaceContainerHigh,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: Wrap(children: [
          Center(child: Container(margin: const EdgeInsets.only(top: 12), width: 40, height: 4, decoration: BoxDecoration(color: VaultColors.outlineVariant, borderRadius: BorderRadius.circular(10)))),
          Padding(padding: const EdgeInsets.all(24.0), child: Text('Media Options', style: VaultTypography.headlineSm)),
          ListTile(
            leading: Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: VaultColors.error.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(VaultRadius.md)), child: const Icon(Icons.delete_outline, color: VaultColors.error, size: 20)),
            title: Text('Delete Permanently', style: VaultTypography.labelLg.copyWith(color: VaultColors.error)),
            onTap: () async {
              HapticFeedback.heavyImpact();
              Navigator.pop(ctx);
              await Provider.of<VaultProvider>(context, listen: false).deleteMedia(folder.id, item.id);
              if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Media permanently shredded.', style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: Colors.white)), backgroundColor: VaultColors.error));
            },
          ),
          ListTile(
            leading: Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: VaultColors.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(VaultRadius.md)), child: const Icon(Icons.restore, color: VaultColors.primary, size: 20)),
            title: Text('Recover to Gallery', style: VaultTypography.labelLg),
            subtitle: Text('Moves file back to your phone gallery', style: VaultTypography.labelMd),
            onTap: () async {
              HapticFeedback.lightImpact();
              Navigator.pop(ctx);
              bool success = await Provider.of<VaultProvider>(context, listen: false).recoverMedia(folder.id, item);
              if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(success ? 'Recovered to Phone Gallery!' : 'Recovery failed.', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
                backgroundColor: success ? VaultColors.tertiaryContainer : VaultColors.error));
            },
          ),
          const SizedBox(height: 20),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: VaultColors.background,
      appBar: AppBar(
        title: Text(folder.name, style: VaultTypography.titleLg),
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new, color: VaultColors.onSurfaceVariant, size: 20), onPressed: () => Navigator.pop(context)),
      ),
      body: folder.items.isEmpty
        ? Center(child: Text("Folder is empty", style: VaultTypography.bodyMd.copyWith(color: VaultColors.onSurfaceVariant)))
        : GridView.builder(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.all(12),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 8, mainAxisSpacing: 8),
          itemCount: folder.items.length,
          itemBuilder: (context, index) {
            final item = folder.items[index];
            final fileToDisplay = item.thumbnailPath != null ? File(item.thumbnailPath!) : File(item.path);
            return GestureDetector(
              onLongPress: () => _showMediaOptions(context, item),
              onTap: () { HapticFeedback.lightImpact(); Navigator.push(context, MaterialPageRoute(builder: (_) => FullScreenViewer(item: item, isVideo: folder.type == 'video'))); },
              child: ClipRRect(
                borderRadius: BorderRadius.circular(VaultRadius.md),
                child: Stack(fit: StackFit.expand, children: [
                  Image.file(fileToDisplay, fit: BoxFit.cover),
                  if (folder.type == 'video')
                    Container(color: Colors.black45, child: const Center(child: Icon(Icons.play_circle_fill, color: Colors.white, size: 36))),
                ]),
              ),
            );
          },
        ),
    );
  }
}

// ─── FULL SCREEN VIEWER (security logic untouched) ───
class FullScreenViewer extends StatefulWidget {
  final MediaItem item;
  final bool isVideo;
  const FullScreenViewer({super.key, required this.item, required this.isVideo});
  @override
  State<FullScreenViewer> createState() => _FullScreenViewerState();
}

class _FullScreenViewerState extends State<FullScreenViewer> {
  VideoPlayerController? _videoPlayerController;
  ChewieController? _chewieController;
  bool _isVideoLoading = true;

  @override
  void initState() {
    super.initState();
    if (widget.isVideo) _initializeVideo();
  }

  Future<void> _initializeVideo() async {
    final file = File(widget.item.path);
    _videoPlayerController = VideoPlayerController.file(file);
    try {
      await _videoPlayerController!.initialize();
      _chewieController = ChewieController(
        videoPlayerController: _videoPlayerController!, autoPlay: true, looping: false,
        aspectRatio: _videoPlayerController!.value.aspectRatio,
        materialProgressColors: ChewieProgressColors(
          playedColor: VaultColors.primaryContainer, handleColor: VaultColors.primaryContainer,
          backgroundColor: VaultColors.surfaceContainerHighest, bufferedColor: VaultColors.onSurfaceVariant,
        ),
        placeholder: Container(color: Colors.black), autoInitialize: true,
        errorBuilder: (context, errorMessage) => Center(child: Text("Error: $errorMessage", style: TextStyle(color: VaultColors.error))),
      );
      setState(() => _isVideoLoading = false);
    } catch (e) {
      debugPrint("Video Player Error: $e");
      setState(() => _isVideoLoading = false);
    }
  }

  @override
  void dispose() {
    _videoPlayerController?.dispose();
    _chewieController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0, iconTheme: const IconThemeData(color: Colors.white)),
      body: Center(
        child: widget.isVideo
          ? (_isVideoLoading
              ? const CircularProgressIndicator(color: VaultColors.primaryContainer)
              : (_chewieController != null && _chewieController!.videoPlayerController.value.isInitialized
                  ? Chewie(controller: _chewieController!)
                  : Text("Failed to load secure video.", style: VaultTypography.bodyMd.copyWith(color: VaultColors.onSurfaceVariant))))
          : InteractiveViewer(minScale: 0.1, maxScale: 4.0, child: Image.file(File(widget.item.path))),
      ),
    );
  }
}