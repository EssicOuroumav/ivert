import 'package:flutter_test/flutter_test.dart';
import 'package:ivert/services/diagnostic_service.dart';
import 'package:ivert/services/meteo_service.dart';
import 'package:ivert/services/parcelle_service.dart';
import 'package:ivert/services/prevention_service.dart';

/// 22 jours (14 passés + aujourd'hui + 7 à venir) avec une pluie et une humidité constantes.
MeteoJours meteo({required double pluie, required double humidite}) {
  final debut = DateTime(2026, 11, 10);
  final dates = [
    for (var i = 0; i < 22; i++)
      debut.add(Duration(days: i)).toIso8601String().substring(0, 10),
  ];
  return MeteoJours(
    dates: dates,
    pluie: List.filled(22, pluie),
    humidite: List.filled(22, humidite),
    tempMax: List.filled(22, 30),
    recue: DateTime(2026, 11, 24),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Risque de pourriture brune', () {
    test('pluie régulière et air humide : risque élevé', () {
      final r = MeteoService.risque(meteo(pluie: 6, humidite: 88), '2026-11-24');
      expect(r.pluiePassee, 84); // 14 jours × 6 mm
      expect(r.pluiePrevue, 42); // 7 jours × 6 mm
      expect(r.niveau, NiveauRisque.eleve);
    });

    test('quelques pluies, humidité moyenne : risque modéré', () {
      final r = MeteoService.risque(meteo(pluie: 2, humidite: 75), '2026-11-24');
      expect(r.niveau, NiveauRisque.modere);
    });

    test('saison sèche : risque faible', () {
      final r = MeteoService.risque(meteo(pluie: 0, humidite: 55), '2026-11-24');
      expect(r.niveau, NiveauRisque.faible);
    });

    test('bruine quotidienne en zone humide (cas réel de Soubré) : pas « élevé »', () {
      // 21 jours de 1 à 3 mm, humidité 85 % : 33 mm en 14 jours
      final pluies = [1.0, 2.7, 2.2, 2.7, 1.6, 3.8, 3.1, 3.3, 1.6, 0.5, 3.4, 5.9, 0.7, 0.8, 0.8, 0.7, 1.1, 5.2, 4.6, 0.3, 0.0, 0.0];
      final base = meteo(pluie: 0, humidite: 85);
      final m = MeteoJours(dates: base.dates, pluie: pluies, humidite: base.humidite, tempMax: base.tempMax, recue: base.recue);
      expect(MeteoService.risque(m, '2026-11-24').niveau, NiveauRisque.modere);
    });

    test('beaucoup de pluie mais air sec : jamais élevé', () {
      final r = MeteoService.risque(meteo(pluie: 10, humidite: 60), '2026-11-24');
      expect(r.niveau, isNot(NiveauRisque.eleve));
    });
  });

  test('Localité la plus proche du GPS', () async {
    final liste = await ParcelleService.instance.localites();
    expect(ParcelleService.plusProche(liste, 5.80, -6.60).id, 'soubre');
    expect(ParcelleService.plusProche(liste, 9.45, -5.62).id, 'korhogo');
    expect(liste.firstWhere((l) => l.id == 'abengourou').phytophthora, Phytophthora.megakarya);
  });

  test('Semaine ISO de la tournée sentinelle', () {
    expect(SentinelleService.semaine(DateTime(2026, 11, 24)), '2026-W48');
    expect(SentinelleService.semaine(DateTime(2026, 1, 1)), '2026-W01');
  });

  test('Calendrier : des gestes pour chaque mois et chaque culture', () async {
    for (final c in Culture.values) {
      for (var mois = 1; mois <= 12; mois++) {
        expect(await CalendrierService.instance.gestes(c, mois), isNotEmpty, reason: '${c.name} mois $mois');
      }
    }
  });

  test('Arbre sentinelle : une maladie probable est une alerte, « sain » non', () {
    expect(const ResultatSentinelle(classe: 'swollen_shoot', niveau: Niveau.probable, entreeId: 1).alerte, isTrue);
    expect(const ResultatSentinelle(classe: 'sain', niveau: Niveau.certain, entreeId: 1).alerte, isFalse);
    expect(const ResultatSentinelle(classe: 'autre', niveau: Niveau.horsSujet, entreeId: 1).alerte, isFalse);
  });
}
