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

/// Une parcelle tracée (en marchant autour avec le GPS, ou en touchant la carte).
class ParcelleTracee {
  ParcelleTracee({required this.id, required this.nom, required this.culture, required this.points, required this.creeLe});

  factory ParcelleTracee.fromJson(Map<String, dynamic> j) => ParcelleTracee(
        id: j['id'] as String,
        nom: j['nom'] as String,
        culture: j['culture'] as String,
        points: [
          for (final p in j['points'] as List) (((p as List)[0] as num).toDouble(), (p[1] as num).toDouble()),
        ],
        creeLe: DateTime.parse(j['creeLe'] as String),
      );

  final String id;
  final String nom;
  final String culture; // cacao | anacarde
  final List<(double, double)> points; // (lat, lon), dans l'ordre du tracé
  final DateTime creeLe;

  Map<String, dynamic> toJson() => {
        'id': id,
        'nom': nom,
        'culture': culture,
        'points': [for (final (la, lo) in points) [la, lo]],
        'creeLe': creeLe.toIso8601String(),
      };

  double get surfaceHa => ParcelleService.surfaceHa(points);
  (double, double) get centre => ParcelleService.centre(points);
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

  static const _cleTracees = 'parcelles_tracees';

  Future<List<ParcelleTracee>> tracees() async {
    final brut = (await SharedPreferences.getInstance()).getString(_cleTracees);
    if (brut == null) return [];
    return [for (final j in jsonDecode(brut) as List) ParcelleTracee.fromJson(j as Map<String, dynamic>)];
  }

  /// Ajoute une parcelle tracée et en fait la parcelle de référence (météo, alertes, carte).
  Future<ParcelleTracee> ajouterTracee(String nom, String culture, List<(double, double)> points) async {
    final t = ParcelleTracee(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      nom: nom,
      culture: culture,
      points: points,
      creeLe: DateTime.now(),
    );
    final liste = [...await tracees(), t];
    await (await SharedPreferences.getInstance()).setString(_cleTracees, jsonEncode([for (final x in liste) x.toJson()]));
    final (la, lo) = t.centre;
    await enregistrer(plusProche(await localites(), la, lo), lat: la, lon: lo);
    return t;
  }

  Future<void> supprimerTracee(String id) async {
    final liste = (await tracees()).where((t) => t.id != id).toList();
    await (await SharedPreferences.getInstance()).setString(_cleTracees, jsonEncode([for (final x in liste) x.toJson()]));
  }

  /// Fait d'une parcelle tracée la parcelle de référence.
  Future<void> activer(ParcelleTracee t) async {
    final (la, lo) = t.centre;
    await enregistrer(plusProche(await localites(), la, lo), lat: la, lon: lo);
  }

  /// Centre (moyenne des sommets) d'un contour.
  static (double, double) centre(List<(double, double)> pts) {
    if (pts.isEmpty) return (0, 0);
    var la = 0.0, lo = 0.0;
    for (final (a, b) in pts) {
      la += a;
      lo += b;
    }
    return (la / pts.length, lo / pts.length);
  }

  /// Surface d'un contour en hectares (projection locale en mètres, formule du lacet).
  /// Précise à quelques % pour une parcelle de quelques hectares ; la précision du GPS compte davantage.
  static double surfaceHa(List<(double, double)> pts) {
    if (pts.length < 3) return 0;
    final (la0, _) = centre(pts);
    const mParDegre = 111320.0;
    final kx = mParDegre * math.cos(la0 * math.pi / 180);
    var s = 0.0;
    for (var i = 0; i < pts.length; i++) {
      final (la1, lo1) = pts[i];
      final (la2, lo2) = pts[(i + 1) % pts.length];
      s += (lo1 * kx) * (la2 * mParDegre) - (lo2 * kx) * (la1 * mParDegre);
    }
    return s.abs() / 2 / 10000;
  }

  /// Distance en km entre deux points (formule de haversine).
  static double distanceKm(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371.0;
    final p1 = lat1 * math.pi / 180, p2 = lat2 * math.pi / 180;
    final dp = (lat2 - lat1) * math.pi / 180, dl = (lon2 - lon1) * math.pi / 180;
    final a = math.sin(dp / 2) * math.sin(dp / 2) + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) * math.sin(dl / 2);
    return 2 * r * math.asin(math.min(1, math.sqrt(a)));
  }

  /// Localité la plus proche d'un point.
  static Localite plusProche(List<Localite> liste, double lat, double lon) {
    double d(Localite l) => distanceKm(lat, lon, l.lat, l.lon);
    return liste.reduce((a, b) => d(a) <= d(b) ? a : b);
  }
}
