import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart'; // 🔴 NEW: Core video engine
import 'package:chewie/chewie.dart';             // 🔴 NEW: Sleek video UI
import '../services/vault_provider.dart';
import '../services/security_service.dart';
import '../models/media_entry.dart';
import 'home_screen.dart';
import 'settings_screen.dart';
import 'dashboard_screen.dart';
import '../main.dart'; 

class MediaVaultScreen extends StatefulWidget {
  const MediaVaultScreen({super.key});

  @override
  State<MediaVaultScreen> createState() => _MediaVaultScreenState();
}

class _MediaVaultScreenState extends State<MediaVaultScreen> {
  final SecurityService _securityService = SecurityService();
  final ImagePicker _picker = ImagePicker();
  
  bool _isCheckingAuth = true;
  bool _hasPinSet = false;
  String _pinInput = '';
  String _authMessage = 'Enter Media PIN';
  bool _hasError = false;

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

  void _onPinKeyPressed(String value, VaultProvider vault) async {
    if (_pinInput.length < 6) {
      HapticFeedback.lightImpact();
      setState(() {
        _pinInput += value;
        _hasError = false;
      });

      if (_pinInput.length == 6) {
        if (!_hasPinSet) {
          await _securityService.saveMediaPin(_pinInput);
          HapticFeedback.heavyImpact();
          vault.unlockMediaVault();
          if (mounted) {
            setState(() {
              _hasPinSet = true;
              _pinInput = '';
            });
          }
        } else {
          try {
            bool isValid = await _securityService.verifyMediaPin(_pinInput);
            if (isValid) {
              HapticFeedback.heavyImpact();
              vault.unlockMediaVault();
              if (mounted) setState(() => _pinInput = '');
            } else {
              HapticFeedback.vibrate();
              if (mounted) {
                setState(() {
                  _hasError = true;
                  _authMessage = 'Incorrect PIN';
                  _pinInput = '';
                });
              }
            }
          } on VaultDestroyedException {
            // 8 wrong PINs — all storage wiped by security_service
            HapticFeedback.heavyImpact();
            vault.wipeMemory();
            if (mounted) {
              showDialog(
                context: context,
                barrierDismissible: false,
                builder: (_) => AlertDialog(
                  backgroundColor: const Color(0xFF161618),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  title: const Text('Vault Destroyed',
                      style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                  content: const Text(
                    'Too many incorrect attempts. All vault data has been permanently wiped for your security.',
                    style: TextStyle(color: Colors.white70, height: 1.5),
                  ),
                  actions: [
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                      onPressed: () {
                        Navigator.of(context).popUntil((route) => route.isFirst);
                      },
                      child: const Text('OK', style: TextStyle(color: Colors.white)),
                    ),
                  ],
                ),
              );
            }
          }
        }
      }
    }
  }

  Future<void> _pickMedia(BuildContext context, String type) async {
    final vault = Provider.of<VaultProvider>(context, listen: false);
    HapticFeedback.lightImpact();
    SecurityState.isAuthenticating = true; 

    try {
      if (type == 'photo') {
        final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
        if (image != null) {
          await vault.addMedia('photo', image.path);
        }
      } else if (type == 'video') {
        final XFile? video = await _picker.pickVideo(source: ImageSource.gallery);
        if (video != null) {
          final tempDir = await getTemporaryDirectory();
          final thumbPath = await VideoThumbnail.thumbnailFile(
            video: video.path,
            thumbnailPath: tempDir.path,
            imageFormat: ImageFormat.JPEG,
            quality: 75,
          );
          await vault.addMedia('video', video.path, thumbnailPath: thumbPath);
        }
      }
    } catch (e) {
      debugPrint("Media Picker Error: $e");
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error accessing gallery: $e', style: const TextStyle(fontWeight: FontWeight.bold)),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      SecurityState.isAuthenticating = false; 
    }
  }

  void _showAddMediaMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF161618),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (BuildContext modalContext) {
        return SafeArea(
          child: Wrap(
            children: [
              Center(child: Container(margin: const EdgeInsets.only(top: 12), width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(10)))),
              const Padding(
                padding: EdgeInsets.all(24.0),
                child: Text('Secure Media', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
              ),
              ListTile(
                leading: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.purpleAccent.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)), child: const Icon(Icons.photo, color: Colors.purpleAccent)),
                title: const Text('Add Photos', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                onTap: () {
                  Navigator.pop(modalContext);
                  _pickMedia(context, 'photo');
                },
              ),
              ListTile(
                leading: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.orangeAccent.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)), child: const Icon(Icons.videocam, color: Colors.orangeAccent)),
                title: const Text('Add Videos', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                onTap: () {
                  Navigator.pop(modalContext);
                  _pickMedia(context, 'video');
                },
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
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('Rename Folder', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(filled: true, fillColor: Color(0xFF2C2C2C)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.purpleAccent),
            onPressed: () {
              if (controller.text.isNotEmpty) {
                Provider.of<VaultProvider>(context, listen: false).renameMediaFolder(folder.id, controller.text);
                Navigator.pop(context);
              }
            },
            child: const Text('Save', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Drawer _buildDrawer(BuildContext context) {
    return Drawer(
      backgroundColor: const Color(0xFF161618),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.horizontal(right: Radius.circular(24))),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: Colors.cyanAccent.withValues(alpha: 0.1), shape: BoxShape.circle),
                    child: const Icon(Icons.shield_outlined, color: Colors.cyanAccent, size: 32),
                  ),
                  const SizedBox(width: 16),
                  const Text('VaultX', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                ],
              ),
            ),
            const Divider(color: Colors.white10, thickness: 1),
            const SizedBox(height: 16),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: Colors.cyanAccent.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.pie_chart_outline, color: Colors.cyanAccent),
              ),
              title: const Text('Security Dashboard', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
              onTap: () {
                HapticFeedback.lightImpact();
                Navigator.pop(context); 
                Navigator.push(context, MaterialPageRoute(builder: (context) => const DashboardScreen()));
              },
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: const Color(0xFF00E5FF).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.folder_special, color: Color(0xFF00E5FF)),
              ),
              title: const Text('Password Vault', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
              onTap: () {
                HapticFeedback.lightImpact();
                Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (context) => const HomeScreen()), (route) => false);
              },
            ),
            const SizedBox(height: 8),
            Opacity(
              opacity: 0.4,
              child: ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: Colors.purpleAccent.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                  child: const Icon(Icons.perm_media, color: Colors.purpleAccent),
                ),
                title: const Text('Secure Media', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                onTap: null, 
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.settings_outlined, color: Colors.white70),
              ),
              title: const Text('Settings', style: TextStyle(color: Colors.white70, fontSize: 16, fontWeight: FontWeight.w500)),
              onTap: () {
                HapticFeedback.lightImpact();
                Navigator.pop(context); 
                Navigator.push(context, MaterialPageRoute(builder: (context) => const SettingsScreen()));
              },
            ),
            const Spacer(),
            const Padding(
              padding: EdgeInsets.all(24.0),
              child: Text('v1.1.0-Secure', style: TextStyle(color: Colors.white24, fontSize: 12, letterSpacing: 1.2)),
            )
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final vault = Provider.of<VaultProvider>(context);

    if (_isCheckingAuth) return const Scaffold(backgroundColor: Color(0xFF0F0F0F), body: Center(child: CircularProgressIndicator()));

    if (!vault.isMediaUnlocked) {
      return Scaffold(
        backgroundColor: const Color(0xFF0F0F0F),
        appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0, leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white70), onPressed: () => Navigator.pop(context))),
        body: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFF1A1A1A), boxShadow: [BoxShadow(color: (_hasError ? Colors.redAccent : Colors.purpleAccent).withValues(alpha: 0.1), blurRadius: 30, spreadRadius: 10)]),
              child: Icon(Icons.lock_outline, size: 60, color: _hasError ? Colors.redAccent : Colors.purpleAccent),
            ),
            const SizedBox(height: 30),
            Text(_authMessage, style: TextStyle(color: _hasError ? Colors.redAccent : Colors.white, fontSize: 18, fontWeight: FontWeight.w600, letterSpacing: 1.2)),
            const SizedBox(height: 40),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(6, (index) => Container(
                margin: const EdgeInsets.symmetric(horizontal: 8),
                width: index < _pinInput.length ? 18 : 14, 
                height: index < _pinInput.length ? 18 : 14,
                decoration: BoxDecoration(
                  shape: BoxShape.circle, 
                  color: index < _pinInput.length ? Colors.purpleAccent : Colors.transparent, 
                  border: Border.all(color: index < _pinInput.length ? Colors.purpleAccent : Colors.white24, width: 2),
                  boxShadow: index < _pinInput.length ? [BoxShadow(color: Colors.purpleAccent.withValues(alpha: 0.5), blurRadius: 10)] : [],
                ),
              )),
            ),
            const SizedBox(height: 60),
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: GridView.builder(
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, childAspectRatio: 1.2, mainAxisSpacing: 16, crossAxisSpacing: 16),
                  itemCount: 12,
                  itemBuilder: (context, index) {
                    if (index == 9) return const SizedBox();
                    if (index == 11) {
                      return IconButton(icon: const Icon(Icons.backspace_outlined, color: Colors.white70, size: 28), onPressed: () {
                        if (_pinInput.isNotEmpty) {
                          HapticFeedback.selectionClick();
                          setState(() => _pinInput = _pinInput.substring(0, _pinInput.length - 1));
                        }
                      });
                    }
                    final number = index == 10 ? '0' : '${index + 1}';
                    return InkWell(
                      borderRadius: BorderRadius.circular(50),
                      onTap: () => _onPinKeyPressed(number, vault),
                      child: Container(
                        decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFF1A1A1A), border: Border.all(color: Colors.white.withValues(alpha: 0.05))),
                        alignment: Alignment.center,
                        child: Text(number, style: const TextStyle(fontSize: 28, color: Colors.white, fontWeight: FontWeight.w500)),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      drawer: _buildDrawer(context),
      appBar: AppBar(
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu, color: Colors.white70, size: 28),
            onPressed: () {
              HapticFeedback.lightImpact();
              Scaffold.of(context).openDrawer(); 
            },
          ),
        ),
        backgroundColor: Colors.transparent, elevation: 0,
        title: const Text('VaultX', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.5)), centerTitle: true,
      ),
      body: vault.mediaFolders.isEmpty
        ? Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: const [
                Icon(Icons.perm_media_outlined, size: 80, color: Color(0xFF222225)),
                SizedBox(height: 16),
                Text('No secure media stored yet.', style: TextStyle(color: Colors.grey, fontSize: 16)),
              ],
            ),
          )
        : ListView.builder(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            itemCount: vault.mediaFolders.length,
            itemBuilder: (context, index) {
              final folder = vault.mediaFolders[index];
              final isVideo = folder.type == 'video';
              
              return AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF161618),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: ListTile(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  leading: Icon(isVideo ? Icons.videocam : Icons.photo, color: isVideo ? Colors.orangeAccent : Colors.purpleAccent, size: 32),
                  title: Text(folder.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 16)),
                  subtitle: Text('${folder.items.length} items', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                  onLongPress: () {
                    HapticFeedback.mediumImpact();
                    _showRenameDialog(context, folder);
                  },
                  onTap: () {
                    HapticFeedback.lightImpact();
                    Navigator.push(context, MaterialPageRoute(builder: (_) => MediaGridScreen(folder: folder)));
                  },
                ),
              );
            },
          ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.purpleAccent,
        foregroundColor: Colors.white,
        elevation: 8,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        onPressed: () {
          HapticFeedback.lightImpact();
          _showAddMediaMenu(context);
        },
        child: const Icon(Icons.add, size: 32),
      ),
    );
  }
}

class MediaGridScreen extends StatelessWidget {
  final MediaFolder folder;
  const MediaGridScreen({super.key, required this.folder});

  void _showMediaOptions(BuildContext context, MediaItem item) {
    HapticFeedback.mediumImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF161618),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            Center(child: Container(margin: const EdgeInsets.only(top: 12), width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(10)))),
            const Padding(
              padding: EdgeInsets.all(24.0),
              child: Text('Media Options', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
            ),
            
            ListTile(
              leading: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.redAccent.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)), child: const Icon(Icons.delete_outline, color: Colors.redAccent)),
              title: const Text('Delete Permanently', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w600)),
              onTap: () async {
                HapticFeedback.heavyImpact();
                Navigator.pop(ctx); 
                await Provider.of<VaultProvider>(context, listen: false).deleteMedia(folder.id, item.id);
                
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Media permanently shredded.', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                      backgroundColor: Colors.redAccent,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              },
            ),
            
            ListTile(
              leading: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.cyanAccent.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)), child: const Icon(Icons.restore, color: Colors.cyanAccent)),
              title: const Text('Recover to Gallery', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
              subtitle: const Text('Moves file back to your phone gallery', style: TextStyle(color: Colors.grey, fontSize: 12)),
              onTap: () async {
                HapticFeedback.lightImpact();
                Navigator.pop(ctx); 
                bool success = await Provider.of<VaultProvider>(context, listen: false).recoverMedia(folder.id, item);
                
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(success ? 'Recovered to Phone Gallery!' : 'Recovery failed.', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black)),
                      backgroundColor: success ? Colors.cyanAccent : Colors.redAccent,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              },
            ),

            const SizedBox(height: 8),

            ListTile(
              leading: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(8)), child: const Icon(Icons.close, color: Colors.white70)),
              title: const Text('Cancel', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600)),
              onTap: () => Navigator.pop(ctx),
            ),
            
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      appBar: AppBar(
        title: Text(folder.name, style: const TextStyle(fontWeight: FontWeight.w800)), 
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white70, size: 20), onPressed: () => Navigator.pop(context)),
      ),
      body: folder.items.isEmpty 
        ? const Center(child: Text("Folder is empty", style: TextStyle(color: Colors.white54))) 
        : GridView.builder(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.all(12),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 12, mainAxisSpacing: 12),
          itemCount: folder.items.length,
          itemBuilder: (context, index) {
            final item = folder.items[index];
            final fileToDisplay = item.thumbnailPath != null ? File(item.thumbnailPath!) : File(item.path);
            
            return GestureDetector(
              onLongPress: () => _showMediaOptions(context, item), 
              onTap: () {
                HapticFeedback.lightImpact();
                Navigator.push(context, MaterialPageRoute(builder: (_) => FullScreenViewer(item: item, isVideo: folder.type == 'video')));
              },
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.file(fileToDisplay, fit: BoxFit.cover),
                    if (folder.type == 'video')
                      Container(
                        color: Colors.black45,
                        child: const Center(child: Icon(Icons.play_circle_fill, color: Colors.white, size: 40)),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
    );
  }
}

// 🔴 THE NEW SECURE IN-APP MEDIA PLAYER 🔴
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
    if (widget.isVideo) {
      _initializeVideo();
    }
  }

  Future<void> _initializeVideo() async {
    final file = File(widget.item.path);
    _videoPlayerController = VideoPlayerController.file(file);
    
    try {
      await _videoPlayerController!.initialize();
      _chewieController = ChewieController(
        videoPlayerController: _videoPlayerController!,
        autoPlay: true,
        looping: false,
        aspectRatio: _videoPlayerController!.value.aspectRatio,
        materialProgressColors: ChewieProgressColors(
          playedColor: Colors.orangeAccent,
          handleColor: Colors.orangeAccent,
          backgroundColor: Colors.white24,
          bufferedColor: Colors.white54,
        ),
        placeholder: Container(color: Colors.black),
        autoInitialize: true,
        errorBuilder: (context, errorMessage) {
          return Center(
            child: Text(
              "Error loading video: $errorMessage",
              style: const TextStyle(color: Colors.redAccent),
            ),
          );
        },
      );
      
      setState(() {
        _isVideoLoading = false;
      });
    } catch (e) {
      debugPrint("Video Player Error: $e");
      setState(() {
        _isVideoLoading = false;
      });
    }
  }

  @override
  void dispose() {
    // 🔴 SECURE CLEANUP: Instantly flushes the video from RAM when you close it
    _videoPlayerController?.dispose();
    _chewieController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent, 
        elevation: 0, 
        iconTheme: const IconThemeData(color: Colors.white)
      ),
      body: Center(
        child: widget.isVideo
          ? (_isVideoLoading 
              ? const CircularProgressIndicator(color: Colors.orangeAccent)
              : (_chewieController != null && _chewieController!.videoPlayerController.value.isInitialized
                  ? Chewie(controller: _chewieController!)
                  : const Text("Failed to load secure video.", style: TextStyle(color: Colors.white54))))
          : InteractiveViewer(
              minScale: 0.1,
              maxScale: 4.0,
              child: Image.file(File(widget.item.path)),
            ),
      ),
    );
  }
}