import 'dart:convert';

import 'package:flutter/services.dart';

import 'diagnostic_service.dart';

/// Conseil court (fiches « plant sain » et « photo non analysée »).
class Conseil {
  Conseil.fromJson(Map<String, dynamic> j)
    : titre = j['titre'] as String,
      badge = j['badge'] as String,
      texte = j['texte'] as String;

  final String titre;
  final String badge;
  final String texte;
}

/// Une solution concrète : ce que c'est, et comment faire, étape par étape.
/// [matiere] n'est rempli que pour un intrant (matière active, jamais de marque ni de dose).
class Solution {
  Solution.fromJson(Map<String, dynamic> j)
    : titre = j['titre'] as String,
      texte = j['texte'] as String,
      matiere = j['matiere'] as String?,
      etapes = [for (final e in (j['etapes'] as List? ?? const [])) e as String];

  final String titre;
  final String texte;
  final String? matiere;
  final List<String> etapes;
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
      symptomes = _textes(j['symptomes']),
      causes = j['causes'] as String? ?? '',
      naturel = _solutions(j['naturel']),
      intrants = _solutions(j['intrants']),
      sansIntrant = j['sans_intrant'] as String?,
      prevention = _textes(j['prevention']),
      conseils = [for (final c in (j['conseils'] as List? ?? const [])) Conseil.fromJson(c as Map<String, dynamic>)],
      photo = j['photo'] as String?,
      credit = j['credit'] as String?;

  static List<String> _textes(Object? v) => [for (final e in (v as List? ?? const [])) e as String];
  static List<Solution> _solutions(Object? v) => [
    for (final e in (v as List? ?? const [])) Solution.fromJson(e as Map<String, dynamic>),
  ];

  final String nom;
  final String agent;
  final String type;
  final String niveau; // aucun | modere | eleve | critique
  final String description;
  final String noteLocale;
  final List<String> symptomes;
  final String causes;
  final List<Solution> naturel;
  final List<Solution> intrants;

  /// Quand aucun produit ne soigne (virus) : on le dit clairement.
  final String? sansIntrant;
  final List<String> prevention;
  final List<Conseil> conseils;

  /// Photo des symptômes (licence libre, voir [credit]) ; `null` si aucune photo sûre n'est disponible.
  final String? photo;
  final String? credit;

  bool get estSain => type == 'sain';

  /// Vraie maladie ou ravageur (ni « sain », ni « photo non analysée »).
  bool get estMaladie => type != 'sain' && type != 'autre';

  /// Texte où chercher un symptôme (sans accents, en minuscules).
  String get texteRecherche => sansAccents([nom, agent, description, causes, ...symptomes].join(' ').toLowerCase());
}

/// Pour chercher « tache » et trouver « tâche ».
String sansAccents(String s) {
  const de = 'àâäáãéèêëíìîïóòôöõúùûüçœ';
  const vers = 'aaaaaeeeeiiiiooooouuuuco';
  final b = StringBuffer();
  for (final c in s.split('')) {
    final i = de.indexOf(c);
    b.write(i < 0 ? c : vers[i]);
  }
  return b.toString();
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

  /// Toutes les maladies d'une culture (sans « sain » ni « photo non analysée »), dans l'ordre du fichier.
  Future<List<(String, FicheMaladie)>> maladies(Culture culture) async {
    _donnees ??= jsonDecode(await rootBundle.loadString('assets/data/maladies.json')) as Map<String, dynamic>;
    final c = _donnees![culture.name] as Map<String, dynamic>;
    return [
      for (final e in c.entries)
        if (FicheMaladie.fromJson(e.value as Map<String, dynamic>).estMaladie)
          (e.key, FicheMaladie.fromJson(e.value as Map<String, dynamic>)),
    ];
  }

  /// Filtre par mots : chaque mot de [requete] doit apparaître dans la fiche (accents ignorés).
  static bool correspond(FicheMaladie f, String requete) {
    final mots = sansAccents(requete.toLowerCase()).split(RegExp(r'\s+')).where((m) => m.length > 1);
    final texte = f.texteRecherche;
    return mots.every(texte.contains);
  }
}
