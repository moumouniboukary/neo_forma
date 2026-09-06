import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/brand.dart';
import '../../core/theme/tokens.dart';

/// Ouverture en 2 temps : blanc vide 1 s, puis logo + nom de marque.
class BrandSplashView extends StatefulWidget {
  const BrandSplashView({super.key, this.onFinished});

  final VoidCallback? onFinished;

  @override
  State<BrandSplashView> createState() => _BrandSplashViewState();
}

class _BrandSplashViewState extends State<BrandSplashView> {
  static const _whiteMs = 1000;
  static const _brandMs = 3800;

  bool _showBrand = false;

  @override
  void initState() {
    super.initState();
    // Toujours afficher la barre système (heure / batterie) — certains
    // SplashScreen Android laissent un mode immersif après le blanc natif.
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemNavigationBarColor: Colors.white,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
    );
    Future<void>.delayed(const Duration(milliseconds: _whiteMs), () {
      if (!mounted) return;
      setState(() => _showBrand = true);
    });
    Future<void>.delayed(
      const Duration(milliseconds: _whiteMs + _brandMs),
      () {
        if (!mounted) return;
        widget.onFinished?.call();
      },
    );
  }

  static const _nameStyle = TextStyle(
    fontSize: 36,
    fontWeight: FontWeight.w800,
    color: NfTokens.brand,
    letterSpacing: -0.6,
    height: 1,
    fontFamily: 'sans-serif',
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: AnimatedOpacity(
          opacity: _showBrand ? 1 : 0,
          duration: const Duration(milliseconds: 280),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Image(
                image: AssetImage('assets/branding/logo-icon.png'),
                width: 88,
                height: 88,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.high,
                gaplessPlayback: true,
              ),
              const SizedBox(height: 18),
              Text(kAppName, style: _nameStyle),
            ],
          ),
        ),
      ),
    );
  }
}
