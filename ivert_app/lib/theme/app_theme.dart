import 'package:flutter/material.dart';

/// Couleurs reprises de la maquette Figma IVERT.
class IvertColors {
  IvertColors._();

  static const vert = Color(0xFF2C6B2F);
  static const vertClair = Color(0xFF4CAF50);
  static const vertPale = Color(0xFFD1EBD3);
  static const vertFond = Color(0xFFE8F5E9);
  static const brun = Color(0xFF3E2A1A);
  static const brunDoux = Color(0xFF7A6A56);
  static const creme = Color(0xFFFAF3E0);
  static const beige = Color(0xFFEDE8DE);
  static const orange = Color(0xFFB85A00);
  static const rouge = Color(0xFF8B1A1A);
  static const rougePale = Color(0xFFF9EBEB);
  static const bleu = Color(0xFF3781DA);
  static const bord = Color(0x1F3E2A1A); // rgba(62,42,26,0.12)
  static const fond = Color(0xFFF7F6F2);
}

class IvertRadius {
  IvertRadius._();

  static const carte = 16.0;
  static const bloc = 24.0;
  static const bouton = 28.0;
}

ThemeData ivertTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: IvertColors.vert,
      primary: IvertColors.vert,
      surface: Colors.white,
    ),
    scaffoldBackgroundColor: IvertColors.fond,
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(bodyColor: IvertColors.brun, displayColor: IvertColors.brun),
    appBarTheme: const AppBarTheme(
      backgroundColor: IvertColors.vert,
      foregroundColor: Colors.white,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Colors.white),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: IvertColors.vert,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(54),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(IvertRadius.bouton)),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: IvertColors.vert,
        minimumSize: const Size.fromHeight(50),
        side: const BorderSide(color: IvertColors.vert, width: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(IvertRadius.bouton)),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
      ),
    ),
  );
}
