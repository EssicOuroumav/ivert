import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ivert/screens/splash_screen.dart';
import 'package:ivert/services/diagnostic_service.dart';
import 'package:ivert/services/fiches_service.dart';
import 'package:ivert/theme/app_theme.dart';
import 'package:ivert/widgets/floating_nav.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Le splash affiche le slogan et le bouton Commencer', (tester) async {
    await tester.pumpWidget(MaterialApp(theme: ivertTheme(), home: const SplashScreen()));
    expect(find.textContaining('Intelligence Artificielle Médicale'), findsOneWidget);
    expect(find.text('Commencer →'), findsOneWidget);
  });

  testWidgets('La barre flottante change d\'onglet et déclenche le scan', (tester) async {
    var index = 0;
    var scans = 0;
    await tester.pumpWidget(MaterialApp(
      home: StatefulBuilder(
        builder: (context, setState) => Scaffold(
          bottomNavigationBar: FloatingNav(
            index: index,
            onTap: (i) => setState(() => index = i),
            onScan: () => scans++,
          ),
        ),
      ),
    ));
    expect(find.text('Accueil'), findsOneWidget); // seul l'onglet actif affiche son libellé
    expect(find.text('Carnet'), findsNothing);
    await tester.tap(find.bySemanticsLabel('Carnet'));
    await tester.pumpAndSettle();
    expect(index, 2);
    expect(find.text('Carnet'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Scanner une plante'));
    expect(scans, 1);
  });

  test('Chaque classe des modèles a une fiche maladie', () async {
    final labels = {
      Culture.cacao: ['anthracnose', 'autre', 'pourriture_brune', 'sain', 'swollen_shoot'],
      Culture.anacarde: ['anthracnose', 'autre', 'gommose', 'mineuse', 'rouille_rouge', 'sain'],
    };
    for (final entry in labels.entries) {
      for (final classe in entry.value) {
        final fiche = await FichesService.instance.fiche(entry.key, classe);
        expect(fiche, isNotNull, reason: '${entry.key.name}/$classe');
        expect(fiche!.conseils, isNotEmpty);
      }
    }
  });

  test('Les fichiers de labels correspondent aux fiches', () async {
    for (final c in Culture.values) {
      final texte = await rootBundleLabels(c);
      for (final classe in texte) {
        expect(await FichesService.instance.fiche(c, classe), isNotNull, reason: '${c.name}/$classe');
      }
    }
  });
}

Future<List<String>> rootBundleLabels(Culture c) async {
  final texte = await DefaultAssetBundleLoader.load('assets/models/labels_${c.name}.txt');
  return texte.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
}

class DefaultAssetBundleLoader {
  static Future<String> load(String chemin) => rootBundle.loadString(chemin);
}
