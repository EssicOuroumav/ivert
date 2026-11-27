import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:ivert/screens/carte_screen.dart';
import 'package:ivert/services/diagnostic_service.dart';
import 'package:ivert/services/fiches_service.dart';
import 'package:ivert/services/qualite_photo.dart';
import 'package:latlong2/latlong.dart';

/// Damier noir et blanc (très net), éventuellement flouté et assombri.
img.Image damier({double flou = 0, int luminosite = 255}) {
  final im = img.Image(width: 400, height: 300);
  for (var y = 0; y < im.height; y++) {
    for (var x = 0; x < im.width; x++) {
      final v = ((x ~/ 10 + y ~/ 10) % 2 == 0) ? luminosite : 0;
      im.setPixelRgb(x, y, v, v, v);
    }
  }
  return flou > 0 ? img.gaussianBlur(im, radius: flou.round()) : im;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Qualité photo : une photo nette passe, une photo floue ou sombre est signalée', () {
    final nette = QualitePhoto.mesurerOctets(img.encodeJpg(damier()));
    expect(nette.bonne, isTrue, reason: 'netteté ${nette.nettete}, luminosité ${nette.luminosite}');
    final floue = QualitePhoto.mesurerOctets(img.encodeJpg(damier(flou: 12)));
    expect(floue.floue, isTrue, reason: 'netteté ${floue.nettete}');
    final sombre = QualitePhoto.mesurerOctets(img.encodeJpg(damier(luminosite: 40)));
    expect(sombre.sombre, isTrue, reason: 'luminosité ${sombre.luminosite}');
    expect(sombre.problemes, isNotEmpty);
  });

  test('Deux photos concordantes renforcent le résultat, deux photos divergentes l’affaiblissent', () {
    const s = Seuils(certain: 0.8, probable: 0.5, ressemblance: 0.3);
    Diagnostic d(Map<String, double> p, double r) => Diagnostic(
          culture: Culture.cacao,
          probas: p.entries.toList()..sort((a, b) => b.value.compareTo(a.value)),
          ressemblance: r,
          seuils: s,
          dureeMs: 100,
        );
    final a = d({'pourriture_brune': 0.7, 'sain': 0.3}, 0.5);
    final b = d({'pourriture_brune': 0.95, 'sain': 0.05}, 0.2);
    final c = Diagnostic.combiner(a, b);
    expect(c.nbPhotos, 2);
    expect(c.classe, 'pourriture_brune');
    expect(c.confiance, closeTo(0.825, 1e-9));
    expect(c.niveau, Niveau.certain); // 0,7 « probable » confirmé par une 2e photo nette
    expect(c.ressemblance, 0.5);
    final divergent = Diagnostic.combiner(a, d({'sain': 0.9, 'pourriture_brune': 0.1}, 0.5));
    expect(divergent.niveau, isNot(Niveau.certain));
  });

  test('Recherche par symptôme : les accents et la casse sont ignorés', () async {
    expect(sansAccents('Tâche brûlée'), 'Tache brulee');
    final gommose = (await FichesService.instance.fiche(Culture.anacarde, 'gommose'))!;
    expect(FichesService.correspond(gommose, 'GOMME ambree'), isTrue);
    expect(FichesService.correspond(gommose, 'cochenille'), isFalse);
    final maladies = await FichesService.instance.maladies(Culture.cacao);
    expect(maladies.map((m) => m.$1), containsAll(['pourriture_brune', 'swollen_shoot', 'anthracnose']));
    expect(maladies.any((m) => m.$1 == 'sain' || m.$1 == 'autre'), isFalse);
  });

  test('Direction vers un arbre repère', () {
    const ici = LatLng(5.78, -6.60);
    expect(CarteScreenDirection.direction(ici, const LatLng(5.79, -6.60)), 'nord');
    expect(CarteScreenDirection.direction(ici, const LatLng(5.78, -6.59)), 'est');
    expect(CarteScreenDirection.direction(ici, const LatLng(5.77, -6.61)), 'sud-ouest');
  });
}
