// Vérification mécanique du format v3 (modèle + empreintes + config), indépendante de la qualité du modèle.
// Images poussées par adb dans files/test_mecanique/ (via run-as).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ivert/services/diagnostic_service.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test('Format v3 : sorties, empreintes et seuils cohérents', () async {
    final dossier = Directory('${(await getApplicationSupportDirectory()).path}/test_mecanique');
    final photos = dossier.listSync().whereType<File>().toList()..sort((a, b) => a.path.compareTo(b.path));
    expect(photos, isNotEmpty);
    final seuils = await DiagnosticService.instance.seuils(Culture.cacao);
    expect(seuils.probable, lessThanOrEqualTo(seuils.certain));
    for (final photo in photos) {
      final d = await DiagnosticService.instance.analyser(Culture.cacao, photo);
      final somme = d.probas.fold<double>(0, (s, p) => s + p.value);
      // ignore: avoid_print
      print('IVERT ${photo.uri.pathSegments.last} ressemblance=${d.ressemblance.toStringAsFixed(4)} '
          'seuil=${seuils.ressemblance.toStringAsFixed(4)} niveau=${d.niveau.name} classe=${d.classe} '
          'somme=${somme.toStringAsFixed(4)} ${d.dureeMs}ms');
      expect(d.probas.length, 4);
      expect(somme, closeTo(1.0, 0.01));
      expect(d.ressemblance, inInclusiveRange(-1.0001, 1.0001));
    }
  }, timeout: const Timeout(Duration(minutes: 5)));
}
