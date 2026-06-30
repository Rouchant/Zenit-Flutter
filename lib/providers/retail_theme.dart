import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'specs_provider.dart';

class RetailTheme {
  final Color primary;
  final Color secondary;
  final Color gradientStart;
  final Color gradientEnd;
  /// Path to SVG logo asset (null for Paris which uses PNG)
  final String? logoAsset;
  /// Path to PNG logo asset (used for Paris)
  final String? logoPngAsset;

  const RetailTheme({
    required this.primary,
    required this.secondary,
    required this.gradientStart,
    required this.gradientEnd,
    this.logoAsset,
    this.logoPngAsset,
  });

  /// Returns the store logo widget (SVG or PNG depending on the store)
  Widget get storeLogoWidget {
    if (logoPngAsset != null) {
      return Image.asset(logoPngAsset!, height: 60, fit: BoxFit.contain);
    }
    if (logoAsset != null) {
      return SvgPicture.asset(logoAsset!, height: 60, semanticsLabel: 'Store Logo');
    }
    return const SizedBox.shrink();
  }

  /// True if this theme has any logo configured
  bool get hasLogo => logoAsset != null || logoPngAsset != null;

  factory RetailTheme.of(RetailStore store) {
    switch (store) {
      case RetailStore.falabella:
        return const RetailTheme(
          primary: Color(0xFFB9D40D),
          secondary: Color(0xFF1E1E1E),
          gradientStart: Color(0x7F121E02),
          gradientEnd: Color(0xFF000000),
          logoAsset: 'assets/images/store-falabella.svg',
        );
      case RetailStore.paris:
        return const RetailTheme(
          primary: Color(0xFF00D1FF),
          secondary: Color(0xFF1E1E1E),
          gradientStart: Color(0x7F000B1A),
          gradientEnd: Color(0xFF000000),
          logoPngAsset: 'assets/images/store-paris.png', // PNG en vez de SVG
        );
      case RetailStore.ripley:
        return const RetailTheme(
          primary: Color(0xFFAF47FF),
          secondary: Color(0xFF1E1E1E),
          gradientStart: Color(0x7F0E021A),
          gradientEnd: Color(0xFF000000),
          logoAsset: 'assets/images/store-ripley.svg',
        );
      case RetailStore.none:
        return const RetailTheme(
          primary: Color(0xFF00F2AA),
          secondary: Color(0xFF1E1E1E),
          gradientStart: Color(0x7F021A12),
          gradientEnd: Color(0xFF000000),
        );
    }
  }
}
