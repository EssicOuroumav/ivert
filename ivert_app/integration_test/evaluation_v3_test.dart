// Évaluation sur téléphone, avec le vrai moteur de l'app, du rejet « ce n'est pas du cacao / de l'anacarde ».
// Images poussées par adb dans files/eval/<culture>/<groupe>__<source>__<fichier>.jpg (via run-as), où
// groupe = « cible » (vraies photos de test de la culture) ou « hors » (photos hors sujet).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ivert/services/diagnostic_service.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test('Rejet par ressemblance mesuré sur le téléphone', () async {
    final racine = '${(await getApplicationSupportDirectory()).path}/eval';
    for (final culture in Culture.values) {
      final dossier = Directory('$racine/${culture.name}');
      if (!dossier.existsSync()) continue;
      final photos = dossier.listSync().whereType<File>().toList()..sort((a, b) => a.path.compareTo(b.path));
      final total = <String, int>{};
      final rejetes = <String, int>{};
      final niveaux = <String, int>{};
      for (final photo in photos) {
        final nom = photo.uri.pathSegments.last;
        final parts = nom.split('__');
        final cle = '${parts[0]}/${parts[1]}';
        final d = await DiagnosticService.instance.analyser(culture, photo);
        total[cle] = (total[cle] ?? 0) + 1;
        if (d.horsSujet) rejetes[cle] = (rejetes[cle] ?? 0) + 1;
        if (parts[0] == 'cible') niveaux[d.niveau.name] = (niveaux[d.niveau.name] ?? 0) + 1;
        if (parts[1] == 'photos_utilisateur') {
          // ignore: avoid_print
          print('IVERT ${culture.name} PHOTO $nom ressemblance=${d.ressemblance.toStringAsFixed(3)} '
              'seuil=${d.seuils.ressemblance.toStringAsFixed(3)} niveau=${d.niveau.name} classe=${d.classe} '
              'confiance=${(d.confiance * 100).toStringAsFixed(0)}%');
        }
      }
      for (final cle in total.keys.toList()..sort()) {
        final n = total[cle]!;
        final r = rejetes[cle] ?? 0;
        // ignore: avoid_print
        print('IVERT ${culture.name} $cle : rejetées ${(100 * r / n).toStringAsFixed(1)}% ($r/$n)');
      }
      // ignore: avoid_print
      print('IVERT ${culture.name} niveaux des vraies photos : $niveaux');
    }
  }, timeout: const Timeout(Duration(minutes: 30)));
}
