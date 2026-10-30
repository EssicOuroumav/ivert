// Test sur appareil : les vrais modèles TFLite analysent des photos du jeu de test
// (jamais vues à l'entraînement). Les images sont poussées au préalable par adb dans
// /data/data/ci.ivert.ivert/files/test_images/ (via run-as) sous le nom <culture>__<classe>__<fichier>.jpg
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ivert/services/diagnostic_service.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test('Les modèles reconnaissent les photos de test sur le téléphone', () async {
    final dossier = Directory('${(await getApplicationSupportDirectory()).path}/test_images');
    final photos = dossier.listSync().whereType<File>().where((f) => f.path.endsWith('.jpg')).toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    expect(photos, isNotEmpty, reason: 'pousser les images avec adb avant le test');

    var justes = 0;
    final durees = <int>[];
    for (final photo in photos) {
      final nom = photo.uri.pathSegments.last;
      final parts = nom.split('__');
      final culture = Culture.values.byName(parts[0]);
      final attendu = parts[1];
      final d = await DiagnosticService.instance.analyser(culture, photo);
      durees.add(d.dureeMs);
      // hors_sujet : photo d'une autre plante, doit être rejetée par ressemblance
      final ok = attendu == 'hors_sujet' ? d.horsSujet : d.classe == attendu;
      if (ok) justes++;
      // ignore: avoid_print
      print('IVERT ${ok ? "OK " : "ERR"} $culture attendu=$attendu prédit=${d.classe} '
          'confiance=${(d.confiance * 100).toStringAsFixed(1)}% ressemblance=${d.ressemblance.toStringAsFixed(3)} niveau=${d.niveau.name} ${d.dureeMs}ms');
      final somme = d.probas.fold<double>(0, (s, p) => s + p.value);
      expect(somme, closeTo(1.0, 0.01), reason: 'les probabilités doivent sommer à 1');
    }
    durees.sort();
    // ignore: avoid_print
    print('IVERT BILAN $justes/${photos.length} justes, durée médiane ${durees[durees.length ~/ 2]} ms');
    expect(justes / photos.length, greaterThanOrEqualTo(0.75));
  }, timeout: const Timeout(Duration(minutes: 10)));
}
