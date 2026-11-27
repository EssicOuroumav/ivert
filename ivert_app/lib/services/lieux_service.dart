import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Un lieu utile autour de la parcelle, tiré d'OpenStreetMap (données ouvertes, ODbL).
class Lieu {
  const Lieu({required this.nom, required this.type, required this.lat, required this.lon});

  factory Lieu.fromJson(Map<String, dynamic> j) => Lieu(
        nom: j['nom'] as String,
        type: j['type'] as String,
        lat: (j['lat'] as num).toDouble(),
        lon: (j['lon'] as num).toDouble(),
      );

  final String nom;
  final String type; // boutique | marche | cooperative
  final double lat;
  final double lon;

  Map<String, dynamic> toJson() => {'nom': nom, 'type': type, 'lat': lat, 'lon': lon};

  String get libelle => switch (type) {
        'boutique' => 'Boutique agricole',
        'marche' => 'Marché',
        _ => 'Coopérative',
      };
}

/// Boutiques agricoles, marchés et coopératives proches, via l'API Overpass d'OpenStreetMap.
/// Gardés 7 jours sur le téléphone. La couverture d'OpenStreetMap en zone rurale est encore partielle :
/// la liste des points de vente agréés et des agents ANADER viendra des partenaires.
class LieuxService {
  LieuxService._();

  static final instance = LieuxService._();
  static const _cle = 'lieux_cache';
  static const _validite = Duration(days: 7);

  Future<List<Lieu>> autour(double lat, double lon, {double rayonKm = 30}) async {
    final prefs = await SharedPreferences.getInstance();
    final brut = prefs.getString(_cle);
    List<Lieu>? cache;
    if (brut != null) {
      final j = jsonDecode(brut) as Map<String, dynamic>;
      final memeZone = ((j['lat'] as num) - lat).abs() < 0.05 && ((j['lon'] as num) - lon).abs() < 0.05;
      if (memeZone) {
        cache = [for (final l in j['lieux'] as List) Lieu.fromJson(l as Map<String, dynamic>)];
        if (DateTime.now().difference(DateTime.parse(j['recu'] as String)) < _validite) return cache;
      }
    }
    final r = (rayonKm * 1000).round();
    final la = lat.toStringAsFixed(4), lo = lon.toStringAsFixed(4);
    final requete = '[out:json][timeout:20];('
        'node["shop"="agrarian"](around:$r,$la,$lo);'
        'node["shop"="garden_centre"](around:$r,$la,$lo);'
        'node["amenity"="marketplace"](around:$r,$la,$lo);'
        'node["office"="cooperative"](around:$r,$la,$lo);'
        ');out 80;';
    try {
      // Le serveur principal est souvent saturé (502/504) : on essaie un miroir ensuite
      http.Response? rep;
      for (final adresse in const ['https://overpass-api.de/api/interpreter', 'https://overpass.kumi.systems/api/interpreter']) {
        try {
          final r = await http.post(
            Uri.parse(adresse),
            headers: {'User-Agent': 'IVERT/1.0 (ci.ivert.ivert; prototype)'},
            body: {'data': requete},
          ).timeout(const Duration(seconds: 25));
          if (r.statusCode == 200) {
            rep = r;
            break;
          }
          debugPrint('Lieux OpenStreetMap : $adresse a répondu ${r.statusCode}');
        } catch (e) {
          debugPrint('Lieux OpenStreetMap : $adresse injoignable ($e)');
        }
      }
      if (rep == null) return cache ?? const [];
      final lieux = <Lieu>[];
      for (final e in (jsonDecode(utf8.decode(rep.bodyBytes)) as Map<String, dynamic>)['elements'] as List) {
        final tags = (e['tags'] as Map?)?.cast<String, dynamic>() ?? const {};
        final type = tags['shop'] != null
            ? 'boutique'
            : tags['amenity'] == 'marketplace'
                ? 'marche'
                : 'cooperative';
        lieux.add(Lieu(
          nom: (tags['name'] as String?) ?? (type == 'marche' ? 'Marché' : 'Sans nom'),
          type: type,
          lat: (e['lat'] as num).toDouble(),
          lon: (e['lon'] as num).toDouble(),
        ));
      }
      await prefs.setString(_cle, jsonEncode({
        'lat': lat,
        'lon': lon,
        'recu': DateTime.now().toIso8601String(),
        'lieux': [for (final l in lieux) l.toJson()],
      }));
      return lieux;
    } catch (e) {
      debugPrint('Lieux OpenStreetMap indisponibles : $e');
      return cache ?? const [];
    }
  }
}
