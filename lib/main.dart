import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:root_checker_plus/root_checker_plus.dart'; 
import 'services/vault_provider.dart';
import 'screens/lock_screen.dart'; 

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
        home: Scaffold(
          backgroundColor: const Color(0xFF0F0F0F),
          body: Padding(
            padding: const EdgeInsets.all(30.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.gpp_bad, size: 100, color: Colors.redAccent),
                const SizedBox(height: 30),
                const Text('ENVIRONMENT COMPROMISED', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                const SizedBox(height: 20),
                const Text('VaultX has detected that this device is Rooted.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white54, fontSize: 16)),
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
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0F0F0F),
        primaryColor: Colors.cyanAccent,
        colorScheme: const ColorScheme.dark(
          primary: Colors.cyanAccent,
          secondary: Colors.cyanAccent,
          surface: Color(0xFF1A1A1A), 
        ),
        appBarTheme: const AppBarTheme(backgroundColor: Colors.transparent, elevation: 0),
      ),
      home: _checkingRoot 
          ? const Scaffold(backgroundColor: Color(0xFF0F0F0F), body: Center(child: CircularProgressIndicator(color: Colors.cyanAccent))) 
          : const LockScreen(), 
    );
  }
}