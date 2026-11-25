import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'diagnostic_service.dart';

/// Calendrier de prévention (assets/data/calendrier.json), consultable hors ligne.
class CalendrierService {
  CalendrierService._();

  static final instance = CalendrierService._();
  Map<String, dynamic>? _donnees;

  Future<List<String>> gestes(Culture culture, int mois) async {
    _donnees ??= jsonDecode(await rootBundle.loadString('assets/data/calendrier.json')) as Map<String, dynamic>;
    final c = _donnees![culture.name] as Map<String, dynamic>;
    return [for (final g in c['$mois'] as List) g as String];
  }
}

/// Résultat d'un arbre sentinelle pour une semaine.
class ResultatSentinelle {
  const ResultatSentinelle({required this.classe, required this.niveau, required this.entreeId});

  factory ResultatSentinelle.fromJson(Map<String, dynamic> j) => ResultatSentinelle(
        classe: j['classe'] as String,
        niveau: Niveau.values.byName(j['niveau'] as String),
        entreeId: j['id'] as int?,
      );

  final String classe;
  final Niveau niveau;
  final int? entreeId;

  Map<String, dynamic> toJson() => {'classe': classe, 'niveau': niveau.name, 'id': entreeId};

  /// Une alerte = une maladie affirmée ou probable (pas « sain », pas hors sujet ni incertain).
  bool get alerte => classe != 'sain' && (niveau == Niveau.certain || niveau == Niveau.probable);
}

/// Tournée hebdomadaire d'arbres repères : on scanne quelques arbres par semaine au lieu de tous.
class SentinelleService {
  SentinelleService._();

  static final instance = SentinelleService._();
  static const _nombreDefaut = 10;

  /// Clé de semaine ISO, ex. « 2026-W48 ».
  static String semaine(DateTime d) {
    final jeudi = d.add(Duration(days: 4 - (d.weekday)));
    final premierJanvier = DateTime(jeudi.year);
    final numero = 1 + jeudi.difference(premierJanvier).inDays ~/ 7;
    return '${jeudi.year}-W${numero.toString().padLeft(2, '0')}';
  }

  Future<int> nombre(Culture c) async =>
      (await SharedPreferences.getInstance()).getInt('sentinelles_nb_${c.name}') ?? _nombreDefaut;

  Future<void> fixerNombre(Culture c, int n) async =>
      (await SharedPreferences.getInstance()).setInt('sentinelles_nb_${c.name}', n.clamp(5, 30));

  /// Résultats de la semaine : numéro d'arbre → résultat.
  Future<Map<int, ResultatSentinelle>> tournee(Culture c, String sem) async {
    final brut = (await SharedPreferences.getInstance()).getString('sentinelles_${c.name}_$sem');
    if (brut == null) return {};
    final j = jsonDecode(brut) as Map<String, dynamic>;
    return {for (final e in j.entries) int.parse(e.key): ResultatSentinelle.fromJson(e.value as Map<String, dynamic>)};
  }

  Future<void> enregistrer(Culture c, int arbre, ResultatSentinelle r, {DateTime? quand}) async {
    final sem = semaine(quand ?? DateTime.now());
    final actuel = await tournee(c, sem);
    actuel[arbre] = r;
    await (await SharedPreferences.getInstance()).setString(
      'sentinelles_${c.name}_$sem',
      jsonEncode({for (final e in actuel.entries) '${e.key}': e.value.toJson()}),
    );
  }
}
