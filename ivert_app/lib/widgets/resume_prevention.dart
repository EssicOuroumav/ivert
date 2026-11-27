import 'package:flutter/material.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import 'package:intl/intl.dart';

import '../services/diagnostic_service.dart';
import '../services/meteo_service.dart';
import '../services/parcelle_service.dart';
import '../services/prevention_service.dart';
import '../services/serveur_service.dart';
import '../theme/app_theme.dart';
import 'communs.dart';

/// Résumé de la prévention sur l'accueil : alerte de voisinage, risque météo du jour
/// et avancement de la tournée sentinelle. Chaque bloc ouvre l'écran détaillé.
class ResumePrevention extends StatefulWidget {
  const ResumePrevention({super.key, required this.version, required this.onPrevention, required this.onCarte});

  /// Change à chaque retour sur l'accueil pour recharger les données.
  final int version;
  final VoidCallback onPrevention;
  final VoidCallback onCarte;

  @override
  State<ResumePrevention> createState() => _ResumePreventionState();
}

class _ResumePreventionState extends State<ResumePrevention> {
  Parcelle? _parcelle;
  RisquePourriture? _risque;
  RisqueAnthracnose? _risqueAnacarde;
  bool _meteoChargee = false;
  final Map<Culture, (int, int)> _sentinelles = {}; // faits, total
  int _foyers = 0;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  @override
  void didUpdateWidget(ResumePrevention ancien) {
    super.didUpdateWidget(ancien);
    if (ancien.version != widget.version) _charger();
  }

  Future<void> _charger() async {
    final p = await ParcelleService.instance.lire();
    final sem = SentinelleService.semaine(DateTime.now());
    final sentinelles = <Culture, (int, int)>{};
    for (final c in Culture.values) {
      sentinelles[c] = (
        (await SentinelleService.instance.tournee(c, sem)).length,
        await SentinelleService.instance.nombre(c),
      );
    }
    if (!mounted) return;
    setState(() {
      _parcelle = p;
      _sentinelles
        ..clear()
        ..addAll(sentinelles);
    });
    if (p == null) return;
    final m = await MeteoService.instance.meteo(p);
    if (!mounted) return;
    setState(() {
      _meteoChargee = true;
      final jour = DateFormat('yyyy-MM-dd').format(DateTime.now());
      _risque = m == null ? null : MeteoService.risque(m, jour);
      _risqueAnacarde = m == null ? null : MeteoService.risqueAnthracnose(m, jour, DateTime.now().month);
    });
    final serveur = ServeurService.instance;
    try {
      // Les foyers sont visibles par tous, même sans partager ses diagnostics
      final n = (await serveur.foyersProches(p)).length;
      if (mounted) setState(() => _foyers = n);
    } catch (_) {
      // Hors connexion : pas de bandeau, l'écran Prévention explique la situation
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_foyers > 0) ...[
          Carte(
            couleur: IvertColors.rougePale,
            onTap: widget.onCarte,
            child: Row(
              children: [
                const Icon(Iconsax.danger_copy, color: IvertColors.rouge),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '$_foyers foyer${_foyers > 1 ? 's' : ''} de maladie signalé${_foyers > 1 ? 's' : ''} à moins de 10 km. '
                    'Inspectez vos arbres.',
                    style: const TextStyle(fontSize: 13, height: 1.4, fontWeight: FontWeight.w700),
                  ),
                ),
                const Icon(Iconsax.arrow_right_3_copy, size: 18, color: IvertColors.rouge),
              ],
            ),
          ),
          const SizedBox(height: 10),
        ],
        _risqueMeteo(),
        if (_risqueAnacarde != null) ...[
          const SizedBox(height: 10),
          _risqueAnacardeCarte(_risqueAnacarde!),
        ],
        const SizedBox(height: 10),
        _tournee(),
      ],
    );
  }

  Widget _risqueMeteo() {
    final p = _parcelle;
    final r = _risque;
    final (Color couleur, Color fond, String titre, String detail) = switch ((p, r)) {
      (null, _) => (
        IvertColors.brunDoux,
        IvertColors.beige,
        'Risque météo',
        'Indiquez votre parcelle pour connaître le risque de pourriture brune.',
      ),
      (_, null) => (
        IvertColors.brunDoux,
        IvertColors.beige,
        'Risque météo',
        _meteoChargee ? 'Météo indisponible : connectez-vous une fois à internet.' : 'Récupération de la météo…',
      ),
      (_, RisquePourriture(niveau: NiveauRisque.eleve)) => (
        IvertColors.rouge,
        IvertColors.rougePale,
        'Risque élevé',
        'Faites la récolte sanitaire cette semaine.',
      ),
      (_, RisquePourriture(niveau: NiveauRisque.modere)) => (
        IvertColors.orange,
        IvertColors.creme,
        'Risque modéré',
        'Inspectez les cabosses après chaque pluie.',
      ),
      _ => (IvertColors.vert, IvertColors.vertPale, 'Risque faible', 'Peu de pluie : surveillance habituelle.'),
    };
    return Carte(
      onTap: widget.onPrevention,
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: fond, borderRadius: BorderRadius.circular(12)),
            child: Icon(Iconsax.cloud_drizzle_copy, color: couleur),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p == null || r == null ? titre : '$titre · pourriture brune',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: couleur),
                ),
                const SizedBox(height: 2),
                Text(
                  r == null
                      ? detail
                      : '$detail ${p!.localite.nom} : ${r.pluiePassee.round()} mm en 14 j, humidité ${r.humiditePrevue.round()} %.',
                  style: const TextStyle(fontSize: 12, height: 1.35, color: IvertColors.brunDoux),
                ),
              ],
            ),
          ),
          const Icon(Iconsax.arrow_right_3_copy, size: 18, color: IvertColors.brunDoux),
        ],
      ),
    );
  }

  Widget _risqueAnacardeCarte(RisqueAnthracnose r) {
    final (Color couleur, Color fond, String titre, String detail) = switch (r.niveau) {
      NiveauRisque.eleve => (IvertColors.rouge, IvertColors.rougePale, 'Risque élevé', 'Protégez les fleurs et les jeunes pousses.'),
      NiveauRisque.modere => (IvertColors.orange, IvertColors.creme, 'Risque modéré', 'Surveillez les fleurs et les jeunes feuilles.'),
      NiveauRisque.faible => (
          IvertColors.vert,
          IvertColors.vertPale,
          'Risque faible',
          r.floraison ? 'Peu d’humidité : surveillance habituelle.' : 'Hors floraison : surveillance habituelle.'
        ),
    };
    return Carte(
      onTap: widget.onPrevention,
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: fond, borderRadius: BorderRadius.circular(12)),
            child: Icon(Iconsax.tree_copy, color: couleur),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$titre · anthracnose de l’anacarde',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: couleur)),
                const SizedBox(height: 2),
                Text('$detail Humidité ${r.humidite.round()} %${r.floraison ? ' · période de floraison' : ''}.',
                    style: const TextStyle(fontSize: 12, height: 1.35, color: IvertColors.brunDoux)),
              ],
            ),
          ),
          const Icon(Iconsax.arrow_right_3_copy, size: 18, color: IvertColors.brunDoux),
        ],
      ),
    );
  }

  Widget _tournee() {
    String ligne(Culture c) {
      final (faits, total) = _sentinelles[c] ?? (0, 10);
      return '${c.label} $faits / $total';
    }

    return Carte(
      onTap: widget.onPrevention,
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: IvertColors.vertFond, borderRadius: BorderRadius.circular(12)),
            child: const Icon(Iconsax.tree_copy, color: IvertColors.vert),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Tournée sentinelle de la semaine',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 2),
                Text(
                  'Arbres repères scannés : ${ligne(Culture.cacao)} · ${ligne(Culture.anacarde)}',
                  style: const TextStyle(fontSize: 12, height: 1.35, color: IvertColors.brunDoux),
                ),
              ],
            ),
          ),
          const Icon(Iconsax.arrow_right_3_copy, size: 18, color: IvertColors.brunDoux),
        ],
      ),
    );
  }
}
