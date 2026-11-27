import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Qualité d'une photo avant l'analyse : une photo floue ou mal éclairée donne un mauvais diagnostic.
class QualitePhoto {
  const QualitePhoto({required this.nettete, required this.luminosite});

  /// Variance du laplacien sur l'image réduite à 256 px de large.
  /// Mesuré le 27/11/2026 sur 20 photos d'entraînement : nettes ≥ 63, floutées ≤ 10,5.
  final double nettete;

  /// Luminosité moyenne, de 0 (noir) à 255 (blanc).
  final double luminosite;

  static const seuilFlou = 25.0;
  static const seuilSombre = 45.0;
  static const seuilSurexpose = 225.0;

  bool get floue => nettete < seuilFlou;
  bool get sombre => luminosite < seuilSombre;
  bool get surexposee => luminosite > seuilSurexpose;
  bool get bonne => !floue && !sombre && !surexposee;

  /// Ce qui ne va pas, en mots simples (vide si la photo est bonne).
  List<String> get problemes => [
        if (floue) 'La photo semble floue : tenez le téléphone immobile et touchez l’écran sur la feuille pour faire la mise au point.',
        if (sombre) 'La photo est trop sombre : placez-vous à la lumière du jour, sans contre-jour.',
        if (surexposee) 'La photo est trop claire : évitez le soleil direct sur la feuille.',
      ];

  static Future<QualitePhoto> mesurer(File photo) async => compute(_mesurer, await photo.readAsBytes());

  /// Calcul pur (testable), exécuté hors du fil principal.
  static QualitePhoto mesurerOctets(Uint8List octets) => _mesurer(octets);
}

QualitePhoto _mesurer(Uint8List octets) {
  final source = img.decodeImage(octets);
  if (source == null) return const QualitePhoto(nettete: 0, luminosite: 0);
  final g = img.grayscale(img.copyResize(img.bakeOrientation(source), width: 256));
  final l = List.generate(g.height, (y) => List.generate(g.width, (x) => g.getPixel(x, y).r.toDouble()));
  var somme = 0.0, sommeCarres = 0.0, n = 0, lum = 0.0;
  for (var y = 0; y < g.height; y++) {
    for (var x = 0; x < g.width; x++) {
      lum += l[y][x];
      if (y == 0 || x == 0 || y == g.height - 1 || x == g.width - 1) continue;
      final v = l[y][x - 1] + l[y][x + 1] + l[y - 1][x] + l[y + 1][x] - 4 * l[y][x];
      somme += v;
      sommeCarres += v * v;
      n++;
    }
  }
  final moyenne = n == 0 ? 0.0 : somme / n;
  final variance = n == 0 ? 0.0 : sommeCarres / n - moyenne * moyenne;
  return QualitePhoto(nettete: variance, luminosite: lum / (g.width * g.height));
}
