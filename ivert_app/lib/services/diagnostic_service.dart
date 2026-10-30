import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

enum Culture {
  cacao('Cacao', 'Theobroma cacao'),
  anacarde('Anacarde', 'Anacardium occidentale');

  const Culture(this.label, this.latin);

  final String label;
  final String latin;
}

/// Niveau de réponse montré à l'utilisateur.
enum Niveau {
  /// La photo ne ressemble pas à la culture choisie : aucun diagnostic.
  horsSujet,

  /// L'IA est sûre d'elle.
  certain,

  /// Hypothèse principale nette mais à confirmer (sur le terrain ou par un expert).
  probable,

  /// Trop d'hésitation : reprendre la photo.
  incertain,
}

/// Résultat d'une analyse : probabilités par classe (triées) et ressemblance aux empreintes de la culture.
class Diagnostic {
  Diagnostic({
    required this.culture,
    required this.probas,
    required this.ressemblance,
    required this.seuils,
    required this.dureeMs,
  });

  final Culture culture;
  final List<MapEntry<String, double>> probas; // décroissant
  final double ressemblance; // similarité cosinus à l'empreinte la plus proche
  final Seuils seuils;
  final int dureeMs;

  String get classe => horsSujet ? 'autre' : probas.first.key;
  double get confiance => probas.first.value;
  bool get horsSujet => ressemblance < seuils.ressemblance;
  Niveau get niveau => horsSujet ? Niveau.horsSujet : seuils.niveau(confiance);
}

class Seuils {
  const Seuils({required this.certain, required this.probable, required this.ressemblance});

  factory Seuils.fromJson(Map<String, dynamic> j) => Seuils(
        certain: (j['seuil_certain'] as num).toDouble(),
        probable: (j['seuil_probable'] as num).toDouble(),
        ressemblance: (j['seuil_ressemblance'] as num).toDouble(),
      );

  final double certain;
  final double probable;
  final double ressemblance;

  Niveau niveau(double confiance) => confiance >= certain
      ? Niveau.certain
      : confiance >= probable
          ? Niveau.probable
          : Niveau.incertain;
}

/// Inférence hors ligne avec les modèles TFLite embarqués (aucune connexion requise).
///
/// Entrée des modèles : [1, 224, 224, 3] float32, RGB 0-255 (normalisation incluse dans le modèle),
/// image redimensionnée sans recadrage, comme à l'entraînement.
/// Sortie : [1, nbClasses + dim] = probabilités puis empreinte L2-normalisée de la photo.
/// Le rejet « ce n'est pas du cacao / de l'anacarde » compare cette empreinte aux prototypes
/// des vraies photos d'entraînement (`assets/models/prototypes_CULTURE.bin`) : aucune autre culture n'est apprise.
class DiagnosticService {
  DiagnosticService._();

  static final instance = DiagnosticService._();
  static const _taille = 224;
  static const version = 'v3';

  final Map<Culture, Interpreter> _modeles = {};
  final Map<Culture, List<String>> _labels = {};
  final Map<Culture, Seuils> _seuils = {};
  final Map<Culture, Float32List> _prototypes = {};
  final Map<Culture, int> _dim = {};

  /// Seuils d'une culture (pour réafficher un diagnostic enregistré).
  Future<Seuils> seuils(Culture c) async {
    await _charger(c);
    return _seuils[c]!;
  }

  /// Chargé à la demande (pas au démarrage) pour économiser la RAM des téléphones d'entrée de gamme.
  Future<void> _charger(Culture c) async {
    if (_modeles.containsKey(c)) return;
    final options = InterpreterOptions()..threads = math.min(4, Platform.numberOfProcessors);
    final texte = await rootBundle.loadString('assets/models/labels_${c.name}.txt');
    _labels[c] = texte.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
    final config = jsonDecode(await rootBundle.loadString('assets/models/config_${c.name}.json')) as Map<String, dynamic>;
    _seuils[c] = Seuils.fromJson(config);
    _dim[c] = config['dim'] as int;
    final octets = await rootBundle.load('assets/models/prototypes_${c.name}.bin');
    // Copie alignée (float32 little-endian, [N, dim]) : la vue directe sur le tampon peut être mal alignée
    final copie = Uint8List.fromList(octets.buffer.asUint8List(octets.offsetInBytes, octets.lengthInBytes));
    final prototypes = copie.buffer.asFloat32List();
    final dim = _dim[c]!;
    if (prototypes.isEmpty || prototypes.length % dim != 0) {
      throw StateError('prototypes_${c.name}.bin incohérent : ${prototypes.length} valeurs pour dim $dim');
    }
    _prototypes[c] = prototypes;
    final modele = await Interpreter.fromAsset('assets/models/${c.name}_$version.tflite', options: options);
    final attendu = _labels[c]!.length + dim;
    final sortie = modele.getOutputTensor(0).shape;
    if (sortie.length != 2 || sortie[1] != attendu) {
      modele.close();
      throw StateError('Modèle ${c.name} : sortie $sortie, attendu [1, $attendu]');
    }
    _modeles[c] = modele;
  }

  Future<Diagnostic> analyser(Culture culture, File photo) async {
    final debut = DateTime.now();
    await _charger(culture);
    final entree = await compute(_pretraiter, await photo.readAsBytes());
    final labels = _labels[culture]!;
    final dim = _dim[culture]!;
    final taille = labels.length + dim;
    final sortie = List.filled(taille, 0.0).reshape([1, taille]);
    _modeles[culture]!.run(entree.reshape([1, _taille, _taille, 3]), sortie);
    final brut = (sortie[0] as List).map((v) => (v as num).toDouble()).toList();

    final probas = <MapEntry<String, double>>[
      for (var i = 0; i < labels.length; i++) MapEntry(labels[i], brut[i]),
    ]..sort((a, b) => b.value.compareTo(a.value));
    return Diagnostic(
      culture: culture,
      probas: probas,
      ressemblance: _ressemblance(_prototypes[culture]!, brut.sublist(labels.length), dim),
      seuils: _seuils[culture]!,
      dureeMs: DateTime.now().difference(debut).inMilliseconds,
    );
  }

  /// Similarité cosinus maximale entre l'empreinte (déjà normalisée) et les prototypes (normalisés).
  static double _ressemblance(Float32List prototypes, List<double> empreinte, int dim) {
    var meilleure = -1.0;
    for (var debut = 0; debut + dim <= prototypes.length; debut += dim) {
      var s = 0.0;
      for (var j = 0; j < dim; j++) {
        s += prototypes[debut + j] * empreinte[j];
      }
      if (s > meilleure) meilleure = s;
    }
    return meilleure;
  }

  void liberer() {
    for (final m in _modeles.values) {
      m.close();
    }
    _modeles.clear();
  }
}

/// Exécuté dans un isolate : décodage, orientation EXIF, redimensionnement 224×224, RGB float.
Float32List _pretraiter(Uint8List octets) {
  final decodee = img.decodeImage(octets);
  if (decodee == null) throw const FormatException('Image illisible');
  final orientee = img.bakeOrientation(decodee);
  final petite = img.copyResize(orientee,
      width: DiagnosticService._taille,
      height: DiagnosticService._taille,
      interpolation: img.Interpolation.linear);
  final tampon = Float32List(DiagnosticService._taille * DiagnosticService._taille * 3);
  var i = 0;
  for (final p in petite) {
    tampon[i++] = p.r.toDouble();
    tampon[i++] = p.g.toDouble();
    tampon[i++] = p.b.toDouble();
  }
  return tampon;
}
