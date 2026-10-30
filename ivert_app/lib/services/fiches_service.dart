import 'dart:convert';

import 'package:flutter/services.dart';

import 'diagnostic_service.dart';

class Conseil {
  Conseil.fromJson(Map<String, dynamic> j)
      : titre = j['titre'] as String,
        badge = j['badge'] as String,
        texte = j['texte'] as String;

  final String titre;
  final String badge;
  final String texte;
}

/// Fiche maladie embarquée (assets/data/maladies.json), consultable hors ligne.
class FicheMaladie {
  FicheMaladie.fromJson(Map<String, dynamic> j)
      : nom = j['nom'] as String,
        agent = j['agent'] as String,
        type = j['type'] as String,
        niveau = j['niveau'] as String,
        description = j['description'] as String,
        noteLocale = j['note_locale'] as String,
        conseils = [for (final c in j['conseils'] as List) Conseil.fromJson(c as Map<String, dynamic>)];

  final String nom;
  final String agent;
  final String type;
  final String niveau; // aucun | modere | eleve | critique
  final String description;
  final String noteLocale;
  final List<Conseil> conseils;

  bool get estSain => type == 'sain';
}

class FichesService {
  FichesService._();

  static final instance = FichesService._();
  Map<String, dynamic>? _donnees;

  Future<FicheMaladie?> fiche(Culture culture, String classe) async {
    _donnees ??= jsonDecode(await rootBundle.loadString('assets/data/maladies.json')) as Map<String, dynamic>;
    final j = (_donnees![culture.name] as Map<String, dynamic>?)?[classe];
    return j == null ? null : FicheMaladie.fromJson(j as Map<String, dynamic>);
  }
}
