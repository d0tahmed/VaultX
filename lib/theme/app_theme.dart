import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ─────────────────────────────────────────────────
// THE VAULTED HORIZON — Design System Tokens
// ─────────────────────────────────────────────────

class VaultColors {
  // Surfaces (layered glass hierarchy)
  static const background       = Color(0xFF0B1326);
  static const surface          = Color(0xFF0B1326);
  static const surfaceDim       = Color(0xFF0B1326);
  static const surfaceContainerLowest = Color(0xFF060E20);
  static const surfaceContainerLow    = Color(0xFF131B2E);
  static const surfaceContainer       = Color(0xFF171F33);
  static const surfaceContainerHigh   = Color(0xFF222A3D);
  static const surfaceContainerHighest = Color(0xFF2D3449);
  static const surfaceBright    = Color(0xFF31394D);
  static const surfaceVariant   = Color(0xFF2D3449);

  // Primary (Cyan — "Action / Unlock")
  static const primary          = Color(0xFFC3F5FF);
  static const primaryContainer = Color(0xFF00E5FF);
  static const onPrimary        = Color(0xFF00363D);
  static const onPrimaryContainer = Color(0xFF00626E);
  static const primaryFixedDim  = Color(0xFF00DAF3);

  // Secondary (Slate Blue)
  static const secondary        = Color(0xFFBCC7DE);
  static const secondaryContainer = Color(0xFF3E495D);
  static const onSecondary      = Color(0xFF263143);
  static const onSecondaryContainer = Color(0xFFAEB9D0);

  // Tertiary (Emerald — "Safety / Strong")
  static const tertiary         = Color(0xFFA8FFD2);
  static const tertiaryContainer = Color(0xFF5BE9AD);
  static const onTertiary       = Color(0xFF003824);
  static const onTertiaryContainer = Color(0xFF006645);

  // Error (Coral Red — "Danger / Breach")
  static const error            = Color(0xFFFFB4AB);
  static const errorContainer   = Color(0xFF93000A);
  static const onError          = Color(0xFF690005);
  static const onErrorContainer = Color(0xFFFFDAD6);

  // Text / Content
  static const onSurface        = Color(0xFFDAE2FD);
  static const onSurfaceVariant = Color(0xFFBAC9CC);
  static const onBackground     = Color(0xFFDAE2FD);

  // Borders
  static const outline          = Color(0xFF849396);
  static const outlineVariant   = Color(0xFF3B494C);

  // Inverse
  static const inverseSurface   = Color(0xFFDAE2FD);
  static const inverseOnSurface = Color(0xFF283044);
  static const inversePrimary   = Color(0xFF006875);
}

// ─────────────────────────────────────────────────
// Border Radius Tokens
// ─────────────────────────────────────────────────

class VaultRadius {
  static const sm   = 4.0;   // 0.25rem — subtle accents
  static const md   = 12.0;  // 0.75rem — input fields, small modules
  static const lg   = 16.0;  // 1rem — content cards
  static const xl   = 20.0;  // 1.25rem
  static const xxl  = 24.0;  // 1.5rem — bottom sheets
  static const full = 9999.0; // pills
}

// ─────────────────────────────────────────────────
// Typography — Manrope (authority) + Inter (function)
// ─────────────────────────────────────────────────

class VaultTypography {
  // Headlines — Manrope
  static TextStyle displayLg = GoogleFonts.manrope(
    fontSize: 40, fontWeight: FontWeight.w800, color: VaultColors.onSurface, letterSpacing: -1.0,
  );
  static TextStyle headlineLg = GoogleFonts.manrope(
    fontSize: 32, fontWeight: FontWeight.w800, color: VaultColors.onSurface, letterSpacing: -0.5,
  );
  static TextStyle headlineMd = GoogleFonts.manrope(
    fontSize: 24, fontWeight: FontWeight.w700, color: VaultColors.onSurface,
  );
  static TextStyle headlineSm = GoogleFonts.manrope(
    fontSize: 20, fontWeight: FontWeight.w700, color: VaultColors.onSurface,
  );
  static TextStyle titleLg = GoogleFonts.manrope(
    fontSize: 18, fontWeight: FontWeight.w700, color: VaultColors.onSurface,
  );
  static TextStyle titleMd = GoogleFonts.manrope(
    fontSize: 16, fontWeight: FontWeight.w700, color: VaultColors.onSurface,
  );

  // Body — Inter
  static TextStyle bodyLg = GoogleFonts.inter(
    fontSize: 16, fontWeight: FontWeight.w400, color: VaultColors.onSurface,
  );
  static TextStyle bodyMd = GoogleFonts.inter(
    fontSize: 14, fontWeight: FontWeight.w400, color: VaultColors.onSurface,
  );
  static TextStyle bodySm = GoogleFonts.inter(
    fontSize: 12, fontWeight: FontWeight.w400, color: VaultColors.onSurfaceVariant,
  );

  // Labels — Inter
  static TextStyle labelLg = GoogleFonts.inter(
    fontSize: 14, fontWeight: FontWeight.w600, color: VaultColors.onSurface,
  );
  static TextStyle labelMd = GoogleFonts.inter(
    fontSize: 12, fontWeight: FontWeight.w500, color: VaultColors.onSurfaceVariant,
  );
  static TextStyle labelSm = GoogleFonts.inter(
    fontSize: 10, fontWeight: FontWeight.w500, color: VaultColors.onSurfaceVariant,
    letterSpacing: 1.2,
  );
}

// ─────────────────────────────────────────────────
// Reusable Decorations
// ─────────────────────────────────────────────────

class VaultDecorations {
  /// Card surface — no borders, tonal shift only
  static BoxDecoration card({Color? color, double radius = VaultRadius.lg}) {
    return BoxDecoration(
      color: color ?? VaultColors.surfaceContainer,
      borderRadius: BorderRadius.circular(radius),
    );
  }

  /// Card with left accent strip (strength indicator)
  static BoxDecoration accentCard({required Color accent, Color? bgColor}) {
    return BoxDecoration(
      color: bgColor ?? VaultColors.surfaceContainerLow,
      borderRadius: BorderRadius.circular(VaultRadius.lg),
    );
  }

  /// Glass panel — for floating elements
  static BoxDecoration glassPanel({double opacity = 0.6}) {
    return BoxDecoration(
      color: VaultColors.surfaceContainer.withValues(alpha: opacity),
      borderRadius: BorderRadius.circular(VaultRadius.lg),
    );
  }

  /// Bottom nav bar decoration
  static BoxDecoration bottomNav = BoxDecoration(
    color: const Color(0xFF020A1A).withValues(alpha: 0.85),
    borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
    border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.05))),
    boxShadow: [
      BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 32, offset: const Offset(0, -8)),
    ],
  );
}

// ─────────────────────────────────────────────────
// ThemeData Builder
// ─────────────────────────────────────────────────

ThemeData buildVaultTheme() {
  return ThemeData.dark().copyWith(
    scaffoldBackgroundColor: VaultColors.background,
    primaryColor: VaultColors.primary,
    colorScheme: const ColorScheme.dark(
      primary: VaultColors.primary,
      primaryContainer: VaultColors.primaryContainer,
      secondary: VaultColors.secondary,
      secondaryContainer: VaultColors.secondaryContainer,
      tertiary: VaultColors.tertiary,
      tertiaryContainer: VaultColors.tertiaryContainer,
      error: VaultColors.error,
      errorContainer: VaultColors.errorContainer,
      surface: VaultColors.surface,
      onPrimary: VaultColors.onPrimary,
      onSecondary: VaultColors.onSecondary,
      onSurface: VaultColors.onSurface,
      onError: VaultColors.onError,
      outline: VaultColors.outline,
      outlineVariant: VaultColors.outlineVariant,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: VaultTypography.titleLg,
      iconTheme: const IconThemeData(color: VaultColors.onSurfaceVariant),
    ),
    cardTheme: CardThemeData(
      color: VaultColors.surfaceContainer,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(VaultRadius.lg)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: VaultColors.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(VaultRadius.xl)),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: VaultColors.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(VaultRadius.md)),
    ),
    dividerTheme: DividerThemeData(
      color: VaultColors.outlineVariant.withValues(alpha: 0.15),
      thickness: 1,
    ),
  );
}
