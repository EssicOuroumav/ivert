import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// « Ce n'est pas ça » : le producteur ou l'agent corrige un diagnostic.
/// Les corrections restent sur le téléphone. Elles serviront, avec l'accord du producteur,
/// à améliorer le prochain modèle (photos mal reconnues = photos les plus utiles).
class Correction {
  const Correction({required this.entreeId, required this.classeIa, required this.classeCorrigee, required this.date});

  factory Correction.fromJson(Map<String, dynamic> j) => Correction(
        entreeId: j['id'] as int,
        classeIa: j['ia'] as String,
        classeCorrigee: j['corrige'] as String,
        date: DateTime.parse(j['date'] as String),
      );

  final int entreeId;
  final String classeIa;

  /// Classe choisie par la personne : une maladie, « sain », « autre » (pas la bonne plante)
  /// ou « inconnu » (« je ne sais pas, mais ce n'est pas ça »).
  final String classeCorrigee;
  final DateTime date;

  Map<String, dynamic> toJson() => {'id': entreeId, 'ia': classeIa, 'corrige': classeCorrigee, 'date': date.toIso8601String()};
}

class CorrectionsService {
  CorrectionsService._();

  static final instance = CorrectionsService._();
  static const _cle = 'corrections';

  Future<Map<int, Correction>> toutes() async {
    final brut = (await SharedPreferences.getInstance()).getString(_cle);
    if (brut == null) return {};
    return {
      for (final j in jsonDecode(brut) as List) (j['id'] as int): Correction.fromJson(j as Map<String, dynamic>),
    };
  }

  Future<Correction?> pour(int? entreeId) async => entreeId == null ? null : (await toutes())[entreeId];

  Future<void> enregistrer(Correction c) async {
    final t = await toutes();
    t[c.entreeId] = c;
    await (await SharedPreferences.getInstance()).setString(_cle, jsonEncode([for (final x in t.values) x.toJson()]));
  }

  Future<void> retirer(int entreeId) async {
    final t = await toutes()..remove(entreeId);
    await (await SharedPreferences.getInstance()).setString(_cle, jsonEncode([for (final x in t.values) x.toJson()]));
  }
}
