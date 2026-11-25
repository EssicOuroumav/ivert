import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'parcelle_service.dart';

enum NiveauRisque { faible, modere, eleve }

/// Météo journalière d'une parcelle : 14 jours passés + 7 jours de prévision.
class MeteoJours {
  MeteoJours({required this.dates, required this.pluie, required this.humidite, required this.tempMax, required this.recue});

  factory MeteoJours.fromJson(Map<String, dynamic> j) => MeteoJours(
        dates: [for (final d in j['dates'] as List) d as String],
        pluie: [for (final v in j['pluie'] as List) (v as num?)?.toDouble() ?? 0],
        humidite: [for (final v in j['humidite'] as List) (v as num?)?.toDouble() ?? 0],
        tempMax: [for (final v in j['tempMax'] as List) (v as num?)?.toDouble() ?? 0],
        recue: DateTime.parse(j['recue'] as String),
      );

  final List<String> dates; // AAAA-MM-JJ
  final List<double> pluie; // mm
  final List<double> humidite; // %
  final List<double> tempMax; // °C
  final DateTime recue;

  Map<String, dynamic> toJson() =>
      {'dates': dates, 'pluie': pluie, 'humidite': humidite, 'tempMax': tempMax, 'recue': recue.toIso8601String()};
}

class RisquePourriture {
  const RisquePourriture({
    required this.niveau,
    required this.pluiePassee,
    required this.pluiePrevue,
    required this.humiditePrevue,
    required this.joursHumides,
  });

  final NiveauRisque niveau;
  final double pluiePassee; // mm sur 14 jours
  final double pluiePrevue; // mm sur 7 jours
  final double humiditePrevue; // % moyen sur 7 jours
  final int joursHumides; // jours de pluie (≥ 1 mm) sur les 21 jours
}

/// Risque indicatif de pourriture brune du cacao à partir de la météo.
///
/// Règle simple tirée des études ivoiriennes (SCIRP 2025, JEAI 2025, Afrique Science) : les symptômes
/// apparaissent moins de 15 jours après les pluies, et l'incidence suit la pluie et l'humidité.
/// Les seuils ci-dessous sont des valeurs de départ, **à calibrer avec le CNRA pendant le pilote**.
class MeteoService {
  MeteoService._();

  static final instance = MeteoService._();
  static const _cle = 'meteo_cache';
  static const _validite = Duration(hours: 6);

  /// Météo de la parcelle : réseau si possible, sinon dernière météo enregistrée (peut être `null`).
  Future<MeteoJours?> meteo(Parcelle p, {bool forcer = false}) async {
    final prefs = await SharedPreferences.getInstance();
    final cache = _lireCache(prefs, p);
    if (!forcer && cache != null && DateTime.now().difference(cache.recue) < _validite) return cache;
    try {
      final url = Uri.parse('https://api.open-meteo.com/v1/forecast'
          '?latitude=${p.latitude.toStringAsFixed(3)}&longitude=${p.longitude.toStringAsFixed(3)}'
          '&daily=precipitation_sum,relative_humidity_2m_mean,temperature_2m_max'
          '&past_days=14&forecast_days=8&timezone=Africa%2FAbidjan');
      final r = await http.get(url).timeout(const Duration(seconds: 15));
      if (r.statusCode != 200) return cache;
      final d = (jsonDecode(r.body) as Map<String, dynamic>)['daily'] as Map<String, dynamic>;
      final m = MeteoJours(
        dates: [for (final t in d['time'] as List) t as String],
        pluie: [for (final v in d['precipitation_sum'] as List) (v as num?)?.toDouble() ?? 0],
        humidite: [for (final v in d['relative_humidity_2m_mean'] as List) (v as num?)?.toDouble() ?? 0],
        tempMax: [for (final v in d['temperature_2m_max'] as List) (v as num?)?.toDouble() ?? 0],
        recue: DateTime.now(),
      );
      await prefs.setString(_cle, jsonEncode({...m.toJson(), 'lat': p.latitude, 'lon': p.longitude}));
      return m;
    } catch (_) {
      return cache; // hors connexion : on garde la dernière météo connue
    }
  }

  MeteoJours? _lireCache(SharedPreferences prefs, Parcelle p) {
    final brut = prefs.getString(_cle);
    if (brut == null) return null;
    final j = jsonDecode(brut) as Map<String, dynamic>;
    // Cache d'une autre parcelle : ignoré
    if (((j['lat'] as num) - p.latitude).abs() > 0.01 || ((j['lon'] as num) - p.longitude).abs() > 0.01) return null;
    return MeteoJours.fromJson(j);
  }

  /// Calcule le risque pour [aujourdhui] (AAAA-MM-JJ) : 14 jours avant, 7 jours après.
  static RisquePourriture risque(MeteoJours m, String aujourdhui) {
    var i = m.dates.indexOf(aujourdhui);
    if (i < 0) i = m.dates.length - 8 < 0 ? 0 : m.dates.length - 8;
    double somme(List<double> l, int debut, int fin) {
      var s = 0.0;
      for (var k = debut.clamp(0, l.length); k < fin.clamp(0, l.length); k++) {
        s += l[k];
      }
      return s;
    }

    final passee = somme(m.pluie, i - 14, i);
    final prevue = somme(m.pluie, i, i + 7);
    final nbPrevus = (i + 7).clamp(0, m.humidite.length) - i.clamp(0, m.humidite.length);
    final humidite = nbPrevus > 0 ? somme(m.humidite, i, i + 7) / nbPrevus : 0.0;
    var humides = 0;
    for (var k = (i - 14).clamp(0, m.pluie.length); k < (i + 7).clamp(0, m.pluie.length); k++) {
      if (m.pluie[k] >= 1) humides++;
    }

    final NiveauRisque niveau;
    if ((passee >= 60 || prevue >= 40 || humides >= 10) && humidite >= 80) {
      niveau = NiveauRisque.eleve;
    } else if ((passee >= 25 || prevue >= 15 || humides >= 5) && humidite >= 70) {
      niveau = NiveauRisque.modere;
    } else {
      niveau = NiveauRisque.faible;
    }
    return RisquePourriture(
      niveau: niveau,
      pluiePassee: passee,
      pluiePrevue: prevue,
      humiditePrevue: humidite,
      joursHumides: humides,
    );
  }
}
