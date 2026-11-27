import 'package:flutter_test/flutter_test.dart';
import 'package:ivert/services/diagnostic_service.dart';
import 'package:ivert/services/meteo_service.dart';
import 'package:ivert/services/parcelle_service.dart';
import 'package:ivert/services/prevention_service.dart';
import 'package:ivert/services/rappel_service.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:ivert/services/serveur_service.dart';

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

  group('Réseau d’alerte', () {
    test('numéros ivoiriens à 10 chiffres seulement', () {
      expect(ServeurService.numeroInternational('07 01 02 03 04'), '+2250701020304');
      expect(ServeurService.numeroInternational('+225 05 01 02 03 04'), '+2250501020304');
      expect(ServeurService.numeroInternational('0101020304'), '+2250101020304');
      expect(ServeurService.numeroInternational('01020304'), isNull); // ancien format à 8 chiffres
      expect(ServeurService.numeroInternational('+33 6 12 34 56 78'), isNull); // hors Côte d'Ivoire
      expect(ServeurService.numeroInternational('0901020304'), isNull);
    });

    test('position arrondie à 0,01° avant l’envoi (comme la base)', () {
      expect(ServeurService.arrondir(5.78912), 5.79);
      expect(ServeurService.arrondir(-6.61234), -6.61);
    });

    test('sans serveur configuré, l’app reste hors ligne', () {
      expect(ServeurService.instance.configure, isFalse);
      expect(ServeurService.instance.connecte, isFalse);
    });
  });

  group('Nouvelles fonctions', () {
    test('Surface d’un carré de 100 m de côté ≈ 1 ha', () {
      const d = 100 / 111320; // 100 m en degrés de latitude
      final k = d / 0.99511; // cos(5,7°) : un degré de longitude est un peu plus court
      final pts = [(5.7, -6.6), (5.7 + d, -6.6), (5.7 + d, -6.6 + k), (5.7, -6.6 + k)];
      expect(ParcelleService.surfaceHa(pts), closeTo(1.0, 0.02));
      expect(ParcelleService.surfaceHa(pts.take(2).toList()), 0);
    });

    MeteoJours avecHeures(List<double> pluieHeures, List<double> proba) => MeteoJours(
          dates: const ['2026-11-26'],
          pluie: const [0],
          humidite: const [80],
          tempMax: const [31],
          recue: DateTime.now(),
          heures: [for (var h = 8; h < 20; h++) '2026-11-26T${h.toString().padLeft(2, '0')}:00'],
          pluieHeures: pluieHeures,
          probaHeures: proba,
        );

    test('Fenêtre de traitement : favorable, pluie proche, nuit', () {
      final sec = avecHeures(List.filled(12, 0), List.filled(12, 5));
      expect(MeteoService.fenetreTraitement(sec, DateTime.utc(2026, 11, 26, 9)), FenetreTraitement.favorable);
      final pluvieux = avecHeures([0, 0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0], List.filled(12, 70));
      expect(MeteoService.fenetreTraitement(pluvieux, DateTime.utc(2026, 11, 26, 9)), FenetreTraitement.pluieProche);
      expect(MeteoService.fenetreTraitement(sec, DateTime.utc(2026, 11, 26, 21)), FenetreTraitement.nuit);
    });

    test('Anthracnose de l’anacarde : élevé en floraison humide, faible hors floraison', () {
      final humide = meteo(pluie: 10, humidite: 90);
      expect(MeteoService.risqueAnthracnose(humide, '2026-11-24', 12).niveau, NiveauRisque.eleve);
      expect(MeteoService.risqueAnthracnose(humide, '2026-11-24', 7).niveau, NiveauRisque.faible);
      final sec = meteo(pluie: 0, humidite: 60);
      expect(MeteoService.risqueAnthracnose(sec, '2026-11-24', 1).niveau, NiveauRisque.faible);
    });
  });

  group('Tournée sentinelle', () {
    test('Un résultat incertain ou non analysé est « à refaire », jamais « sain »', () {
      const incertain = ResultatSentinelle(classe: 'pourriture_brune', niveau: Niveau.incertain, entreeId: 1);
      const horsSujet = ResultatSentinelle(classe: 'autre', niveau: Niveau.horsSujet, entreeId: 2);
      const malade = ResultatSentinelle(classe: 'swollen_shoot', niveau: Niveau.probable, entreeId: 3);
      const sain = ResultatSentinelle(classe: 'sain', niveau: Niveau.certain, entreeId: 4);
      expect(incertain.aRefaire && !incertain.sain && !incertain.alerte, isTrue);
      expect(horsSujet.aRefaire && !horsSujet.sain, isTrue);
      expect(malade.alerte && !malade.sain, isTrue);
      expect(sain.sain && !sain.aRefaire && !sain.alerte, isTrue);
      expect(SentinelleService.bilan({1: incertain, 2: horsSujet, 3: malade, 4: sain}), (1, 1, 2));
    });

    test('Prochain rappel : le bon jour, à la bonne heure, toujours dans le futur', () {
      tzdata.initializeTimeZones();
      final abidjan = tz.getLocation('Africa/Abidjan');
      final jeudi = tz.TZDateTime(abidjan, 2026, 11, 26, 10); // jeudi 26/11/2026, 10 h
      final lundi = RappelService.prochaine(1, 7, jeudi);
      expect((lundi.weekday, lundi.day, lundi.hour), (DateTime.monday, 30, 7));
      // Le jour même mais l'heure passée : la semaine suivante
      final jeudiSuivant = RappelService.prochaine(4, 7, jeudi);
      expect(jeudiSuivant.day, 3);
      // Le jour même, heure à venir : aujourd'hui
      expect(RappelService.prochaine(4, 17, jeudi).day, 26);
    });
  });
}
