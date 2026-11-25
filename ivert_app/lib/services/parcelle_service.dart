import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Espèce de pourriture brune dominante connue pour une zone.
enum Phytophthora { megakarya, mixte, palmivora }

class Localite {
  Localite.fromJson(Map<String, dynamic> j)
      : id = j['id'] as String,
        nom = j['nom'] as String,
        region = j['region'] as String,
        lat = (j['lat'] as num).toDouble(),
        lon = (j['lon'] as num).toDouble(),
        phytophthora = Phytophthora.values.asNameMap()[j['phytophthora'] as String?];

  final String id;
  final String nom;
  final String region;
  final double lat;
  final double lon;
  final Phytophthora? phytophthora;
}

/// Emplacement de la parcelle : une localité choisie (par défaut) et, en option, la position GPS.
class Parcelle {
  const Parcelle({required this.localite, this.lat, this.lon});

  final Localite localite;
  final double? lat; // GPS, si le producteur l'a autorisé
  final double? lon;

  bool get aGps => lat != null && lon != null;
  double get latitude => lat ?? localite.lat;
  double get longitude => lon ?? localite.lon;
}

/// Profil de la parcelle, gardé sur le téléphone uniquement.
class ParcelleService {
  ParcelleService._();

  static final instance = ParcelleService._();
  List<Localite>? _localites;

  Future<List<Localite>> localites() async {
    if (_localites != null) return _localites!;
    final j = jsonDecode(await rootBundle.loadString('assets/data/localites.json')) as Map<String, dynamic>;
    _localites = [for (final l in j['localites'] as List) Localite.fromJson(l as Map<String, dynamic>)]
      ..sort((a, b) => a.nom.compareTo(b.nom));
    return _localites!;
  }

  Future<Parcelle?> lire() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString('parcelle_localite');
    if (id == null) return null;
    final liste = await localites();
    final loc = liste.where((l) => l.id == id).firstOrNull;
    if (loc == null) return null;
    return Parcelle(localite: loc, lat: prefs.getDouble('parcelle_lat'), lon: prefs.getDouble('parcelle_lon'));
  }

  Future<void> enregistrer(Localite localite, {double? lat, double? lon}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('parcelle_localite', localite.id);
    if (lat != null && lon != null) {
      await prefs.setDouble('parcelle_lat', lat);
      await prefs.setDouble('parcelle_lon', lon);
    } else {
      await prefs.remove('parcelle_lat');
      await prefs.remove('parcelle_lon');
    }
  }

  /// Demande la position GPS (avec l'autorisation du producteur) et renvoie la localité la plus proche.
  /// Lance une [StateError] lisible si le GPS est coupé ou refusé.
  Future<(Localite, Position)> positionGps() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw StateError('La localisation du téléphone est désactivée.');
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      throw StateError('Autorisation de localisation refusée.');
    }
    final pos = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium, timeLimit: Duration(seconds: 20)),
    );
    return (plusProche(await localites(), pos.latitude, pos.longitude), pos);
  }

  /// Localité la plus proche d'un point (distance sur la sphère).
  static Localite plusProche(List<Localite> liste, double lat, double lon) {
    double d(Localite l) {
      const r = 6371.0;
      final p1 = lat * math.pi / 180, p2 = l.lat * math.pi / 180;
      final dp = (l.lat - lat) * math.pi / 180, dl = (l.lon - lon) * math.pi / 180;
      final a = math.sin(dp / 2) * math.sin(dp / 2) + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) * math.sin(dl / 2);
      return 2 * r * math.asin(math.sqrt(a));
    }

    return liste.reduce((a, b) => d(a) <= d(b) ? a : b);
  }
}
