import 'package:flutter/material.dart';

/// Camera overlay colours from the Okabe–Ito colour-blind-safe palette.
class Palette {
  static const orange = Color(0xFFE69F00);
  static const skyBlue = Color(0xFF56B4E9);
  static const yellow = Color(0xFFF0E442);
}

/// Key colours for one brightness of a [ColourPalette].
class PaletteColours {
  const PaletteColours({
    required this.primary,
    required this.secondary,
    required this.tertiary,
    required this.error,
    required this.surface,
    this.text,
  });

  final Color primary;
  final Color secondary;
  final Color tertiary;
  final Color error;
  final Color surface;

  /// Body text colour; black or white (whichever contrasts more) when null.
  final Color? text;
}

/// Whole-app colour themes, chosen in Settings. Each avoids the colour pairs
/// its users confuse, and nothing in the app relies on colour alone: every
/// state also has an icon and text.
enum ColourPalette {
  normal(
    'Normal',
    'Fresh green on clean white. For typical colour vision.',
    light: PaletteColours(
      primary: Color(0xFF15803D),
      secondary: Color(0xFF0F766E),
      tertiary: Color(0xFF365314),
      error: Color(0xFFB91C1C),
      surface: Color(0xFFFFFFFF),
    ),
    dark: PaletteColours(
      primary: Color(0xFF86EFAC),
      secondary: Color(0xFF5EEAD4),
      tertiary: Color(0xFFBEF264),
      error: Color(0xFFFCA5A5),
      surface: Color(0xFF08130D),
    ),
  ),
  midnight(
    'Midnight',
    'Bright, friendly blue on clean white. For typical colour vision.',
    light: PaletteColours(
      primary: Color(0xFF0A66C2),
      secondary: Color(0xFF0B5CAD),
      tertiary: Color(0xFF004182),
      error: Color(0xFFB91C1C),
      surface: Color(0xFFFFFFFF),
    ),
    dark: PaletteColours(
      primary: Color(0xFF70B5F9),
      secondary: Color(0xFF8AB4F8),
      tertiary: Color(0xFFA8C7FA),
      error: Color(0xFFFCA5A5),
      surface: Color(0xFF0D1117),
    ),
  ),
  blueOrange(
    'Blue and orange',
    'Best for red-green colour blindness (protanopia, deuteranopia). The default.',
    light: PaletteColours(
      primary: Color(0xFF005A9C),
      secondary: Color(0xFF8A5A00),
      tertiary: Color(0xFF37474F),
      error: Color(0xFFA63F00),
      surface: Color(0xFFF7F9FC),
    ),
    dark: PaletteColours(
      primary: Color(0xFF7CC4FF),
      secondary: Color(0xFFFFC163),
      tertiary: Color(0xFFCFD8DC),
      error: Color(0xFFFFA477),
      surface: Color(0xFF0B1220),
    ),
  ),
  tealPink(
    'Teal and pink',
    'Best for blue-yellow colour blindness (tritanopia).',
    light: PaletteColours(
      primary: Color(0xFF00696B),
      secondary: Color(0xFF9C2A5E),
      tertiary: Color(0xFF3D4F5C),
      error: Color(0xFFB3261E),
      surface: Color(0xFFF6FAFA),
    ),
    dark: PaletteColours(
      primary: Color(0xFF6FD8D6),
      secondary: Color(0xFFFFB0D0),
      tertiary: Color(0xFFB8C8D6),
      error: Color(0xFFFFB4AB),
      surface: Color(0xFF0A1414),
    ),
  ),
  monochrome(
    'Black and white',
    'Highest contrast, no colours. For no colour vision (achromatopsia) or low vision.',
    light: PaletteColours(
      primary: Color(0xFF000000),
      secondary: Color(0xFF2B2B2B),
      tertiary: Color(0xFF000000),
      error: Color(0xFF000000),
      surface: Color(0xFFFFFFFF),
    ),
    dark: PaletteColours(
      primary: Color(0xFFFFFFFF),
      secondary: Color(0xFFE0E0E0),
      tertiary: Color(0xFFFFFFFF),
      error: Color(0xFFFFFFFF),
      surface: Color(0xFF000000),
    ),
  ),
  yellowOnBlack(
    'Yellow on black',
    'Bright yellow text on black, always dark. For low vision and glare.',
    light: _yellowOnBlack,
    dark: _yellowOnBlack,
    alwaysDark: true,
  );

  const ColourPalette(this.title, this.description,
      {required this.light, required this.dark, this.alwaysDark = false});

  final String title;
  final String description;
  final PaletteColours light;
  final PaletteColours dark;

  /// Ignores the light / dark appearance setting.
  final bool alwaysDark;
}

const _yellowOnBlack = PaletteColours(
  primary: Color(0xFFFFE600),
  secondary: Color(0xFFFFFFFF),
  tertiary: Color(0xFF7FDBFF),
  error: Color(0xFFFF9E6B),
  surface: Color(0xFF000000),
  text: Color(0xFFFFF176),
);

/// How big text and controls are, chosen in Settings. Text sizes multiply
/// the phone's own text size setting.
enum DisplaySize {
  normal('Normal', 'Compact. More fits on the screen.',
      textFactor: 0.85, controlHeight: 52, iconSize: 24, cardHeightRatio: 0.72, headerHeight: 56, gap: 10),
  large('Large', 'Bigger text and buttons.',
      textFactor: 1.0, controlHeight: 64, iconSize: 28, cardHeightRatio: 1.0, headerHeight: 64, gap: 14),
  larger('Larger', 'Largest text and buttons, for low vision.',
      textFactor: 1.2, controlHeight: 76, iconSize: 32, cardHeightRatio: 1.1, headerHeight: 72, gap: 16);

  const DisplaySize(this.title, this.description,
      {required this.textFactor,
      required this.controlHeight,
      required this.iconSize,
      required this.cardHeightRatio,
      required this.headerHeight,
      required this.gap});

  final String title;
  final String description;
  final double textFactor;

  /// Minimum height of buttons (always above the 48 dp tap target).
  final double controlHeight;
  final double iconSize;

  /// Home card height as a fraction of its width (1 = square).
  final double cardHeightRatio;
  final double headerHeight;
  final double gap;

  static DisplaySize of(BuildContext context) =>
      Theme.of(context).extension<DisplaySizing>()?.size ?? DisplaySize.large;
}

/// Makes the [DisplaySize] available to widgets through the theme.
class DisplaySizing extends ThemeExtension<DisplaySizing> {
  const DisplaySizing(this.size);
  final DisplaySize size;

  @override
  DisplaySizing copyWith({DisplaySize? size}) => DisplaySizing(size ?? this.size);

  @override
  DisplaySizing lerp(DisplaySizing? other, double t) => t < 0.5 ? this : (other ?? this);
}

/// The phone's text scaling multiplied by [factor]; keeps Android's
/// non-linear scaling of large fonts.
class ScaledTextScaler extends TextScaler {
  const ScaledTextScaler(this.base, this.factor);
  final TextScaler base;
  final double factor;

  @override
  double scale(double fontSize) => base.scale(fontSize) * factor;

  @override
  // ignore: deprecated_member_use
  double get textScaleFactor => base.textScaleFactor * factor;

  @override
  bool operator ==(Object other) => other is ScaledTextScaler && other.base == base && other.factor == factor;

  @override
  int get hashCode => Object.hash(base, factor);
}

/// WCAG contrast ratio between two colours (1 to 21).
double contrastRatio(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  return (la > lb ? la + 0.05 : lb + 0.05) / (la > lb ? lb + 0.05 : la + 0.05);
}

/// Text colour for a background: light text on dark colours, dark text on
/// light ones.
Color onColour(Color background) =>
    contrastRatio(background, Colors.white) >= contrastRatio(background, _ink) ? Colors.white : _ink;

const _ink = Color(0xFF0E1726);

Color _mix(Color top, double amount, Color base) => Color.alphaBlend(top.withValues(alpha: amount), base);

ColorScheme buildColourScheme(ColourPalette palette, Brightness brightness) {
  final dark = palette.alwaysDark || brightness == Brightness.dark;
  final c = dark ? palette.dark : palette.light;
  final text = c.text ?? onColour(c.surface);
  final card = dark ? _mix(c.primary, 0.06, c.surface) : _mix(Colors.white, 0.7, c.surface);
  // Containers are tinted backgrounds; their text is picked for contrast.
  Color container(Color k) => dark ? _mix(k, 0.30, c.surface) : _mix(k, 0.16, Colors.white);
  final primaryContainer = container(c.primary);
  final secondaryContainer = container(c.secondary);
  final tertiaryContainer = container(c.tertiary);
  final errorContainer = container(c.error);
  return ColorScheme(
    brightness: dark ? Brightness.dark : Brightness.light,
    primary: c.primary,
    onPrimary: onColour(c.primary),
    primaryContainer: primaryContainer,
    onPrimaryContainer: c.text ?? onColour(primaryContainer),
    secondary: c.secondary,
    onSecondary: onColour(c.secondary),
    secondaryContainer: secondaryContainer,
    onSecondaryContainer: c.text ?? onColour(secondaryContainer),
    tertiary: c.tertiary,
    onTertiary: onColour(c.tertiary),
    tertiaryContainer: tertiaryContainer,
    onTertiaryContainer: c.text ?? onColour(tertiaryContainer),
    error: c.error,
    onError: onColour(c.error),
    errorContainer: errorContainer,
    onErrorContainer: c.text ?? onColour(errorContainer),
    surface: c.surface,
    onSurface: text,
    onSurfaceVariant: _mix(text, 0.82, c.surface),
    surfaceContainerLowest: dark ? c.surface : Colors.white,
    surfaceContainerLow: card,
    surfaceContainer: _mix(c.primary, dark ? 0.10 : 0.05, c.surface),
    surfaceContainerHigh: _mix(c.primary, dark ? 0.14 : 0.08, c.surface),
    surfaceContainerHighest: _mix(c.primary, dark ? 0.18 : 0.11, c.surface),
    outline: _mix(text, 0.62, c.surface),
    outlineVariant: _mix(text, 0.24, c.surface),
    inverseSurface: text,
    onInverseSurface: c.surface,
    inversePrimary: c.surface,
    shadow: Colors.black,
    scrim: Colors.black,
  );
}

/// Material 3 themes with large touch targets and high-contrast,
/// colour-blind-safe colours. The system text scale is always honoured.
ThemeData buildTheme(Brightness brightness,
    {ColourPalette palette = ColourPalette.blueOrange, DisplaySize size = DisplaySize.large}) {
  final scheme = buildColourScheme(palette, brightness);
  final dark = scheme.brightness == Brightness.dark;

  final minButton = Size(64, size.controlHeight);
  final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(18));
  const textStyle = TextStyle(fontSize: 18, fontWeight: FontWeight.w700, letterSpacing: 0.2);

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    extensions: [DisplaySizing(size)],
    visualDensity: size == DisplaySize.normal ? const VisualDensity(horizontal: -1, vertical: -1) : VisualDensity.standard,
    materialTapTargetSize: MaterialTapTargetSize.padded,
    textTheme: Typography.material2021(platform: TargetPlatform.android)
        .englishLike
        .apply(fontSizeFactor: 1.15)
        .merge((dark ? Typography.whiteMountainView : Typography.blackMountainView))
        .apply(bodyColor: scheme.onSurface, displayColor: scheme.onSurface),
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.primary,
      foregroundColor: scheme.onPrimary,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 2,
      centerTitle: false,
      iconTheme: IconThemeData(color: scheme.onPrimary, size: size.iconSize),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(minimumSize: minButton, shape: shape, textStyle: textStyle, elevation: 1),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: minButton,
        shape: shape,
        textStyle: textStyle,
        side: BorderSide(color: scheme.primary, width: 2),
        foregroundColor: scheme.primary,
        backgroundColor: scheme.surfaceContainerLowest,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(minimumSize: const Size(48, 48), textStyle: textStyle),
    ),
    cardTheme: CardThemeData(
      color: scheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: scheme.outlineVariant, width: 1.5),
      ),
      margin: const EdgeInsets.symmetric(vertical: 6),
    ),
    listTileTheme: ListTileThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      iconColor: scheme.primary,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerLowest,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: scheme.outline, width: 1.5),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: scheme.primary, width: 3),
      ),
    ),
    switchTheme: SwitchThemeData(
      // On / off is shown by the thumb icon as well as colour.
      thumbIcon: WidgetStateProperty.resolveWith(
          (s) => Icon(s.contains(WidgetState.selected) ? Icons.check : Icons.close, size: 18)),
    ),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant, thickness: 1.5),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    // Orange focus rings stand out from the UI for every common type of
    // colour blindness.
    focusColor: Palette.orange.withValues(alpha: 0.45),
  );
}
