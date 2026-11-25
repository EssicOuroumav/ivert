// Test sur appareil du parcours « arbre sentinelle » : vrai modèle, vraie base locale, sans galerie.
// Une photo de test est poussée par adb dans files/test_sentinelle/ (via run-as).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ivert/services/diagnostic_service.dart';
import 'package:ivert/services/historique_service.dart';
import 'package:ivert/services/prevention_service.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test('Scan d’un arbre sentinelle : diagnostic, carnet et tournée', () async {
    final dossier = Directory('${(await getApplicationSupportDirectory()).path}/test_sentinelle');
    final photo = dossier.listSync().whereType<File>().first;

    final d = await DiagnosticService.instance.analyser(Culture.cacao, photo);
    final entree = await HistoriqueService.instance.enregistrer(d, photo);
    await SentinelleService.instance.enregistrer(
        Culture.cacao, 1, ResultatSentinelle(classe: d.classe, niveau: d.niveau, entreeId: entree.id));

    final tournee = await SentinelleService.instance.tournee(Culture.cacao, SentinelleService.semaine(DateTime.now()));
    // ignore: avoid_print
    print('IVERT sentinelle classe=${d.classe} niveau=${d.niveau.name} alerte=${tournee[1]!.alerte} '
        'confiance=${(d.confiance * 100).round()}% id=${entree.id}');
    expect(tournee[1]!.entreeId, entree.id);
    expect((await HistoriqueService.instance.tout()).any((e) => e.id == entree.id), isTrue);
  }, timeout: const Timeout(Duration(minutes: 5)));
}
