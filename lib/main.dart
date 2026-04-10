import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:root_checker_plus/root_checker_plus.dart'; 
import 'services/vault_provider.dart';
import 'screens/lock_screen.dart'; 
import 'theme/app_theme.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

class SecurityState {
  static bool isAuthenticating = false;
  static bool requiresAuth = false; 
  static bool hasColdBooted = false; 
}
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    ChangeNotifierProvider(
      create: (context) => VaultProvider(),
      child: const VaultXApp(),
    ),
  );
}

class VaultXApp extends StatefulWidget {
  const VaultXApp({super.key});

  @override
  State<VaultXApp> createState() => _VaultXAppState();
}

class _VaultXAppState extends State<VaultXApp> with WidgetsBindingObserver {
  bool _isRooted = false;
  bool _checkingRoot = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkDeviceIntegrity(); 
  }

  Future<void> _checkDeviceIntegrity() async {
    bool? isRooted = await RootCheckerPlus.isRootChecker();
    setState(() {
      _isRooted = isRooted ?? false;
      _checkingRoot = false;
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      if (!SecurityState.isAuthenticating) {
        final context = navigatorKey.currentContext;
        if (context != null) {
          Provider.of<VaultProvider>(context, listen: false).wipeMemory();
          navigatorKey.currentState?.pushAndRemoveUntil(
            PageRouteBuilder(
              pageBuilder: (context, animation, secondaryAnimation) => const LockScreen(),
              transitionDuration: Duration.zero,
            ),
            (route) => false,
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_checkingRoot && _isRooted) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildVaultTheme(),
        home: Scaffold(
          backgroundColor: VaultColors.background,
          body: Padding(
            padding: const EdgeInsets.all(30.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.gpp_bad, size: 100, color: VaultColors.error),
                const SizedBox(height: 30),
                Text('ENVIRONMENT COMPROMISED', textAlign: TextAlign.center,
                  style: VaultTypography.headlineMd.copyWith(color: VaultColors.onSurface)),
                const SizedBox(height: 20),
                Text('VaultX has detected that this device is Rooted.', textAlign: TextAlign.center,
                  style: VaultTypography.bodyMd.copyWith(color: VaultColors.onSurfaceVariant)),
              ],
            ),
          ),
        ),
      );
    }

    return MaterialApp(
      navigatorKey: navigatorKey, 
      debugShowCheckedModeBanner: false,
      title: 'VaultX',
      theme: buildVaultTheme(),
      home: _checkingRoot 
          ? Scaffold(
              backgroundColor: VaultColors.background,
              body: const Center(child: CircularProgressIndicator(color: VaultColors.primaryContainer)),
            )
          : const LockScreen(), 
    );
  }
}