import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/api_client.dart';
import 'core/auth_store.dart';
import 'core/theme.dart';
import 'ui/home_screen.dart';
import 'ui/login_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: BraveColors.midnight,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
  runApp(const BraveGrowthApp());
}

class BraveGrowthApp extends StatefulWidget {
  const BraveGrowthApp({super.key});

  @override
  State<BraveGrowthApp> createState() => _BraveGrowthAppState();
}

class _BraveGrowthAppState extends State<BraveGrowthApp> {
  final _auth = AuthStore();
  ApiClient? _api;
  bool _restoring = true;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    _api = await _auth.restore();
    if (mounted) setState(() => _restoring = false);
  }

  Future<void> _signOut() async {
    await _auth.signOut();
    if (mounted) setState(() => _api = null);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '勇敢成长',
      debugShowCheckedModeBanner: false,
      theme: braveTheme(),
      home: _restoring
          ? const _LaunchScreen()
          : _api == null
          ? LoginScreen(
              authStore: _auth,
              onLoggedIn: (api) => setState(() => _api = api),
            )
          : HomeScreen(api: _api!, onSignOut: _signOut),
    );
  }
}

class _LaunchScreen extends StatelessWidget {
  const _LaunchScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: AuroraBackground(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SnowFoxMark(size: 104),
              SizedBox(height: 26),
              Text(
                '勇敢成长',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 34,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 3,
                ),
              ),
              SizedBox(height: 18),
              SizedBox(
                width: 120,
                child: LinearProgressIndicator(
                  color: BraveColors.aurora,
                  backgroundColor: Colors.white24,
                  borderRadius: BorderRadius.all(Radius.circular(99)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
