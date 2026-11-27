import 'package:flutter/material.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import 'package:intl/intl.dart';

import '../services/diagnostic_service.dart';
import '../services/meteo_service.dart';
import '../services/parcelle_service.dart';
import '../services/prevention_service.dart';
import '../services/rappel_service.dart';
import '../theme/app_theme.dart';
import '../widgets/carte_voisinage.dart';
import '../widgets/communs.dart';
import '../widgets/espece_zone.dart';
import 'carte_screen.dart';
import 'parcelle_screen.dart';
import 'scan/prescan_screen.dart';

/// Prévention : alerte météo pourriture brune, espèce probable de la zone,
/// tournée d'arbres sentinelles et gestes du mois.
class PreventionScreen extends StatefulWidget {
  const PreventionScreen({super.key});

  @override
  State<PreventionScreen> createState() => _PreventionScreenState();
}

class _PreventionScreenState extends State<PreventionScreen> {
  Culture _culture = Culture.cacao;
  Parcelle? _parcelle;
  MeteoJours? _meteo;
  bool _chargementMeteo = false;
  Map<int, ResultatSentinelle> _tournee = {};
  Map<int, ResultatSentinelle> _tourneePrecedente = {};
  Map<int, String> _reperes = {};
  ReglageRappel? _rappel;
  int _nbSentinelles = 10;
  List<String> _gestes = [];

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger({bool forcerMeteo = false}) async {
    final p = await ParcelleService.instance.lire();
    final sem = SentinelleService.semaine(DateTime.now());
    final tournee = await SentinelleService.instance.tournee(_culture, sem);
    final precedente = await SentinelleService.instance
        .tournee(_culture, SentinelleService.semaine(DateTime.now().subtract(const Duration(days: 7))));
    final reperes = await SentinelleService.instance.reperes(_culture);
    final rappel = await RappelService.instance.lire();
    final nb = await SentinelleService.instance.nombre(_culture);
    final gestes = await CalendrierService.instance.gestes(_culture, DateTime.now().month);
    if (!mounted) return;
    setState(() {
      _parcelle = p;
      _tournee = tournee;
      _tourneePrecedente = precedente;
      _reperes = reperes;
      _rappel = rappel;
      _nbSentinelles = nb;
      _gestes = gestes;
    });
    if (p != null) {
      setState(() => _chargementMeteo = true);
      final m = await MeteoService.instance.meteo(p, forcer: forcerMeteo);
      if (mounted) {
        setState(() {
          _meteo = m;
          _chargementMeteo = false;
        });
      }
    }
  }

  Future<void> _choisirParcelle() async {
    final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const ParcelleScreen()));
    if (ok == true) _charger(forcerMeteo: true);
  }

  Future<void> _scannerArbre(int n) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PrescanScreen(cultureImposee: _culture, arbreSentinelle: n),
    ));
    await _charger();
  }

  /// Tournée guidée : l'app propose les arbres restants un par un (non scannés ou à refaire).
  Future<void> _tourneeGuidee() async {
    for (var n = 1; n <= _nbSentinelles; n++) {
      final r = _tournee[n];
      if (r != null && !r.aRefaire) continue;
      if (!mounted) return;
      final choix = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (c) => AlertDialog(
          title: Text('Arbre $n'),
          content: Text(
            '${_reperes[n] != null ? 'Repère : ${_reperes[n]}\n\n' : ''}'
            'Placez-vous devant l’arbre n° $n, puis photographiez une feuille ou une cabosse.'
            '${r != null ? '\n\nLa photo de cette semaine n’a pas pu être analysée : refaites-la.' : ''}',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, 'stop'), child: const Text('Arrêter')),
            TextButton(onPressed: () => Navigator.pop(c, 'passer'), child: const Text('Passer')),
            FilledButton(onPressed: () => Navigator.pop(c, 'scan'), child: const Text('Scanner')),
          ],
        ),
      );
      if (choix == 'stop' || choix == null) break;
      if (choix == 'scan') await _scannerArbre(n);
    }
    if (!mounted) return;
    final (sains, alertes, refaire) = SentinelleService.bilan(_tournee);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Tournée : ${_tournee.length} / $_nbSentinelles arbres · $sains sain${sains > 1 ? 's' : ''}'
          '${alertes > 0 ? ' · $alertes à surveiller' : ''}${refaire > 0 ? ' · $refaire à refaire' : ''}'),
    ));
  }

  /// Fiche d'un arbre déjà scanné : historique, repère, rescanner, voir sur la carte.
  Future<void> _ficheArbre(int n) async {
    final histo = await SentinelleService.instance.historique(_culture, n);
    final pos = (await SentinelleService.instance.positions(_culture))[n];
    if (!mounted) return;
    final r = _tournee[n];
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (c) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Arbre repère $n · ${_culture.label}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(_reperes[n] ?? 'Pas encore de repère : ajoutez-en un pour le retrouver facilement.',
                style: const TextStyle(fontSize: 13, color: IvertColors.brunDoux)),
            const SizedBox(height: 12),
            Text(
              r == null
                  ? 'Pas encore scanné cette semaine.'
                  : r.alerte
                      ? 'À surveiller cette semaine : inspectez les arbres voisins et montrez-le à un agent ANADER.'
                      : r.aRefaire
                          ? 'Photo de cette semaine inutilisable : rescannez l’arbre.'
                          : 'Sain cette semaine.',
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: r == null
                    ? IvertColors.brun
                    : r.alerte
                        ? IvertColors.rouge
                        : r.aRefaire
                            ? IvertColors.orange
                            : IvertColors.vert,
              ),
            ),
            const SizedBox(height: 14),
            const Text('8 dernières semaines', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Row(children: [
              for (final (sem, res) in histo)
                Expanded(
                  child: Column(children: [
                    Container(
                      height: 22,
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      decoration: BoxDecoration(
                        color: res == null
                            ? IvertColors.beige
                            : res.alerte
                                ? IvertColors.rouge
                                : res.aRefaire
                                    ? IvertColors.orange
                                    : IvertColors.vert,
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text('S${sem.substring(sem.length - 2)}', style: const TextStyle(fontSize: 10, color: IvertColors.brunDoux)),
                  ]),
                ),
            ]),
            const SizedBox(height: 4),
            const Text('Vert : sain · rouge : à surveiller · orange : à refaire · gris : non scanné',
                style: TextStyle(fontSize: 11, color: IvertColors.brunDoux)),
            const SizedBox(height: 16),
            Wrap(spacing: 8, runSpacing: 8, children: [
              FilledButton.icon(
                onPressed: () => Navigator.pop(c, 'scan'),
                icon: const Icon(Iconsax.scan_copy, size: 18),
                label: Text(r == null ? 'Scanner' : 'Rescanner'),
              ),
              OutlinedButton.icon(
                onPressed: () => Navigator.pop(c, 'repere'),
                icon: const Icon(Iconsax.edit_2_copy, size: 18),
                label: const Text('Repère'),
              ),
              if (pos != null)
                OutlinedButton.icon(
                  onPressed: () => Navigator.pop(c, 'carte'),
                  icon: const Icon(Iconsax.map_copy, size: 18),
                  label: const Text('Sur la carte'),
                ),
            ]),
          ],
        ),
      ),
    );
    if (!mounted) return;
    switch (action) {
      case 'scan':
        await _scannerArbre(n);
      case 'repere':
        final ctrl = TextEditingController(text: _reperes[n] ?? '');
        final texte = await showDialog<String>(
          context: context,
          builder: (c) => AlertDialog(
            title: Text('Repère de l’arbre $n'),
            content: TextField(
              controller: ctrl,
              autofocus: true,
              decoration: const InputDecoration(hintText: 'Ex. : près du marigot, ruban rouge'),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c), child: const Text('Annuler')),
              FilledButton(onPressed: () => Navigator.pop(c, ctrl.text), child: const Text('Enregistrer')),
            ],
          ),
        );
        if (texte != null) {
          await SentinelleService.instance.fixerRepere(_culture, n, texte);
          await _charger();
        }
      case 'carte':
        await Navigator.of(context).push(MaterialPageRoute(builder: (_) => CarteScreen(focus: pos)));
    }
  }

  Future<void> _reglerRappel(bool activer) async {
    if (!activer) {
      await RappelService.instance.desactiver();
      await _charger();
      return;
    }
    final actuel = _rappel ?? const ReglageRappel(actif: false, jour: 1, heure: 7);
    var jour = actuel.jour;
    var heure = actuel.heure;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: const Text('Rappel de la tournée'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<int>(
              initialValue: jour,
              decoration: const InputDecoration(labelText: 'Jour'),
              items: [
                for (var j = 1; j <= 7; j++) DropdownMenuItem(value: j, child: Text(ReglageRappel.jours[j - 1])),
              ],
              onChanged: (v) => set(() => jour = v ?? jour),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              initialValue: heure,
              decoration: const InputDecoration(labelText: 'Heure'),
              items: [for (var h = 5; h <= 19; h++) DropdownMenuItem(value: h, child: Text('$h h'))],
              onChanged: (v) => set(() => heure = v ?? heure),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annuler')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Activer')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final autorise = await RappelService.instance.programmer(jour, heure);
    if (!mounted) return;
    if (!autorise) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Notifications refusées : autorisez-les dans les réglages du téléphone pour recevoir le rappel.'),
      ));
    }
    await _charger();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Prévention')),
      body: RefreshIndicator(
        onRefresh: () => _charger(forcerMeteo: true),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
          children: [
            SegmentedButton<Culture>(
              segments: [for (final c in Culture.values) ButtonSegment(value: c, label: Text(c.label))],
              selected: {_culture},
              onSelectionChanged: (s) {
                setState(() {
                  _culture = s.first;
                  _meteo = null;
                });
                _charger();
              },
            ),
            const SizedBox(height: 16),
            _carteParcelle(),
            const SizedBox(height: 18),
            CarteVoisinage(parcelle: _parcelle),
            if (_culture == Culture.cacao) ...[
              const TitreSection('Risque de pourriture brune'),
              _carteRisque(),
              const SizedBox(height: 18),
            ] else ...[
              const TitreSection('Risque d’anthracnose'),
              _carteRisqueAnacarde(),
              const SizedBox(height: 18),
            ],
            const TitreSection('Tournée sentinelle de la semaine'),
            _carteSentinelles(),
            const SizedBox(height: 18),
            TitreSection('À faire en ${DateFormat('MMMM', 'fr_FR').format(DateTime.now())}'),
            _carteGestes(),
            const SizedBox(height: 16),
            const Text(
              'Conseils indicatifs, à valider par un agronome CNRA / ANADER. Suivez toujours l’étiquette des produits homologués.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: IvertColors.brunDoux),
            ),
          ],
        ),
      ),
    );
  }

  Widget _carteParcelle() {
    final p = _parcelle;
    return Carte(
      onTap: _choisirParcelle,
      child: Row(
        children: [
          const Icon(Iconsax.location_copy, color: IvertColors.vert),
          const SizedBox(width: 12),
          Expanded(
            child: p == null
                ? const Text('Indiquez où se trouve votre parcelle', style: TextStyle(fontWeight: FontWeight.w700))
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(p.localite.nom, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                      Text('${p.localite.region}${p.aGps ? ' · position GPS' : ''}',
                          style: const TextStyle(fontSize: 12, color: IvertColors.brunDoux)),
                    ],
                  ),
          ),
          Text(p == null ? 'Choisir' : 'Modifier',
              style: const TextStyle(fontWeight: FontWeight.w700, color: IvertColors.vert)),
        ],
      ),
    );
  }

  Widget _carteRisque() {
    final p = _parcelle;
    if (p == null) {
      return const Carte(
        child: Text('Choisissez votre parcelle pour recevoir le risque météo de votre zone.',
            style: TextStyle(fontSize: 13, color: IvertColors.brunDoux)),
      );
    }
    final m = _meteo;
    if (m == null) {
      return Carte(
        child: _chargementMeteo
            ? const Row(children: [
                SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                SizedBox(width: 12),
                Text('Récupération de la météo…'),
              ])
            : const Text(
                'Météo indisponible : connectez-vous une fois à internet. L’alerte restera ensuite visible hors connexion.',
                style: TextStyle(fontSize: 13, color: IvertColors.brunDoux)),
      );
    }
    final r = MeteoService.risque(m, DateFormat('yyyy-MM-dd').format(DateTime.now()));
    final (couleur, fond, titre, conseil) = switch (r.niveau) {
      NiveauRisque.eleve => (
          IvertColors.rouge,
          IvertColors.rougePale,
          'Risque élevé',
          'Faites la récolte sanitaire cette semaine (retirer toute cabosse tachée) et demandez au conseiller s’il faut un traitement préventif homologué.'
        ),
      NiveauRisque.modere => (
          IvertColors.orange,
          IvertColors.creme,
          'Risque modéré',
          'Inspectez les cabosses après chaque pluie et gardez la plantation aérée.'
        ),
      NiveauRisque.faible => (
          IvertColors.vert,
          IvertColors.vertPale,
          'Risque faible',
          'Peu de pluie : continuez la surveillance habituelle.'
        ),
    };
    final espece = texteEspeceZone(p.localite);
    final age = DateTime.now().difference(m.recue);
    return Carte(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Iconsax.cloud_drizzle_copy, color: IvertColors.brun),
              const SizedBox(width: 8),
              Expanded(child: Text(titre, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: couleur))),
              Pastille('Indicatif', fond: fond, couleur: couleur),
            ],
          ),
          const SizedBox(height: 10),
          Text(conseil, style: const TextStyle(fontSize: 13, height: 1.45)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Pastille('Pluie 14 j : ${r.pluiePassee.round()} mm', fond: IvertColors.beige, couleur: IvertColors.brun),
              Pastille('Prévue 7 j : ${r.pluiePrevue.round()} mm', fond: IvertColors.beige, couleur: IvertColors.brun),
              Pastille('Humidité : ${r.humiditePrevue.round()} %', fond: IvertColors.beige, couleur: IvertColors.brun),
            ],
          ),
          if (espece != null) ...[
            const SizedBox(height: 12),
            Text(espece, style: const TextStyle(fontSize: 12, height: 1.4, color: IvertColors.brunDoux)),
          ],
          const SizedBox(height: 8),
          Text(
            'Météo du ${DateFormat('d MMM à HH:mm', 'fr_FR').format(m.recue)}'
            '${age.inHours >= 24 ? ' (hors connexion : actualisez dès que possible)' : ''} · Open-Meteo',
            style: const TextStyle(fontSize: 11, color: IvertColors.brunDoux),
          ),
        ],
      ),
    );
  }

  Widget _carteRisqueAnacarde() {
    final m = _meteo;
    if (_parcelle == null || m == null) {
      return Carte(
        child: Text(
          _parcelle == null
              ? 'Choisissez votre parcelle pour recevoir le risque météo de votre zone.'
              : (_chargementMeteo ? 'Récupération de la météo…' : 'Météo indisponible : connectez-vous une fois à internet.'),
          style: const TextStyle(fontSize: 13, color: IvertColors.brunDoux),
        ),
      );
    }
    final r = MeteoService.risqueAnthracnose(m, DateFormat('yyyy-MM-dd').format(DateTime.now()), DateTime.now().month);
    final (couleur, fond, titre, conseil) = switch (r.niveau) {
      NiveauRisque.eleve => (
          IvertColors.rouge,
          IvertColors.rougePale,
          'Risque élevé',
          'Humidité forte pendant la floraison : retirez les rameaux malades et demandez au conseiller s’il faut protéger les fleurs avec un produit homologué.'
        ),
      NiveauRisque.modere => (
          IvertColors.orange,
          IvertColors.creme,
          'Risque modéré',
          'Inspectez les fleurs et les jeunes feuilles deux fois par semaine.'
        ),
      NiveauRisque.faible => (
          IvertColors.vert,
          IvertColors.vertPale,
          'Risque faible',
          r.floraison ? 'Temps plutôt sec : continuez la surveillance habituelle.' : 'Hors période de floraison (novembre à mars) : surveillance habituelle.'
        ),
    };
    return Carte(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Iconsax.cloud_drizzle_copy, color: IvertColors.brun),
              const SizedBox(width: 8),
              Expanded(child: Text(titre, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: couleur))),
              Pastille('Indicatif', fond: fond, couleur: couleur),
            ],
          ),
          const SizedBox(height: 10),
          Text(conseil, style: const TextStyle(fontSize: 13, height: 1.45)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Pastille('Humidité 7 j : ${r.humidite.round()} %', fond: IvertColors.beige, couleur: IvertColors.brun),
              Pastille('Jours de pluie : ${r.joursHumides}', fond: IvertColors.beige, couleur: IvertColors.brun),
              Pastille(r.floraison ? 'Floraison' : 'Hors floraison', fond: IvertColors.beige, couleur: IvertColors.brun),
            ],
          ),
          const SizedBox(height: 8),
          Text('Météo du ${DateFormat('d MMM à HH:mm', 'fr_FR').format(m.recue)} · Open-Meteo',
              style: const TextStyle(fontSize: 11, color: IvertColors.brunDoux)),
        ],
      ),
    );
  }

  Widget _carteSentinelles() {
    final faits = _tournee.length;
    final (sains, alertes, refaire) = SentinelleService.bilan(_tournee);
    final (sainsAvant, alertesAvant, _) = SentinelleService.bilan(_tourneePrecedente);
    final restants = [
      for (var n = 1; n <= _nbSentinelles; n++)
        if (_tournee[n] == null || _tournee[n]!.aRefaire) n,
    ];
    final rappel = _rappel;
    return Carte(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$faits / $_nbSentinelles arbres scannés cette semaine',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(
            faits == 0
                ? 'Choisissez $_nbSentinelles arbres répartis dans la parcelle, marquez-les (ruban, numéro) et scannez-les chaque semaine.'
                : '$sains sain${sains > 1 ? 's' : ''} · $alertes à surveiller · $refaire à refaire'
                    '${_tourneePrecedente.isEmpty ? '' : '   (semaine dernière : $sainsAvant sain${sainsAvant > 1 ? 's' : ''}, $alertesAvant à surveiller)'}',
            style: const TextStyle(fontSize: 12, height: 1.4, color: IvertColors.brunDoux),
          ),
          if (alertes > 0) ...[
            const SizedBox(height: 4),
            Text(
              '$alertes arbre${alertes > 1 ? 's' : ''} à surveiller : inspectez ses voisins et montrez-le à un agent ANADER.',
              style: const TextStyle(fontSize: 12, height: 1.4, color: IvertColors.rouge, fontWeight: FontWeight.w600),
            ),
          ],
          const SizedBox(height: 12),
          if (restants.isNotEmpty)
            FilledButton.icon(
              onPressed: _tourneeGuidee,
              icon: const Icon(Iconsax.routing_2_copy, size: 20),
              label: Text(faits == 0 ? 'Commencer la tournée' : 'Continuer la tournée (${restants.length} restant${restants.length > 1 ? 's' : ''})'),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(46)),
            )
          else
            const Row(children: [
              Icon(Iconsax.tick_circle, color: IvertColors.vert, size: 20),
              SizedBox(width: 8),
              Expanded(child: Text('Tournée de la semaine terminée.', style: TextStyle(fontWeight: FontWeight.w700))),
            ]),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var n = 1; n <= _nbSentinelles; n++)
                _BoutonArbre(
                  numero: n,
                  resultat: _tournee[n],
                  onTap: () => _tournee[n] == null ? _scannerArbre(n) : _ficheArbre(n),
                  onLongPress: () => _ficheArbre(n),
                ),
            ],
          ),
          const SizedBox(height: 6),
          const Text('Touchez un arbre scanné pour voir son historique, son repère ou le rescanner.',
              style: TextStyle(fontSize: 11, color: IvertColors.brunDoux)),
          const Divider(height: 20),
          Row(
            children: [
              const Icon(Iconsax.notification_copy, size: 20, color: IvertColors.vert),
              const SizedBox(width: 10),
              Expanded(
                child: InkWell(
                  onTap: rappel?.actif == true ? () => _reglerRappel(true) : null,
                  child: Text(
                    rappel?.actif == true ? 'Rappel ${rappel!.libelle}' : 'Rappel de tournée désactivé',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              Switch(value: rappel?.actif == true, onChanged: _reglerRappel),
            ],
          ),
          Row(
            children: [
              const Text('Nombre d’arbres repères', style: TextStyle(fontSize: 12, color: IvertColors.brunDoux)),
              const Spacer(),
              IconButton(
                onPressed: _nbSentinelles <= 5
                    ? null
                    : () async {
                        await SentinelleService.instance.fixerNombre(_culture, _nbSentinelles - 5);
                        _charger();
                      },
                icon: const Icon(Icons.remove_circle_outline),
                tooltip: 'Moins d’arbres',
              ),
              Text('$_nbSentinelles', style: const TextStyle(fontWeight: FontWeight.w700)),
              IconButton(
                onPressed: _nbSentinelles >= 30
                    ? null
                    : () async {
                        await SentinelleService.instance.fixerNombre(_culture, _nbSentinelles + 5);
                        _charger();
                      },
                icon: const Icon(Icons.add_circle_outline),
                tooltip: 'Plus d’arbres',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _carteGestes() {
    return Carte(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final g in _gestes)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 2),
                    child: Icon(Iconsax.tick_circle_copy, size: 18, color: IvertColors.vert),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Text(g, style: const TextStyle(fontSize: 13, height: 1.45))),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _BoutonArbre extends StatelessWidget {
  const _BoutonArbre({required this.numero, required this.resultat, required this.onTap, required this.onLongPress});

  final int numero;
  final ResultatSentinelle? resultat;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final r = resultat;
    final (Color fond, Color texte, String libelle, IconData? icone) = r == null
        ? (Colors.white, IvertColors.brun, 'Arbre $numero, à scanner', null)
        : r.alerte
            ? (IvertColors.rougePale, IvertColors.rouge, 'Arbre $numero, à surveiller', Iconsax.danger_copy)
            : r.aRefaire
                ? (IvertColors.creme, IvertColors.orange, 'Arbre $numero, à refaire', Iconsax.refresh_copy)
                : (IvertColors.vertPale, IvertColors.vert, 'Arbre $numero, sain', Iconsax.tick_circle_copy);
    return Semantics(
      button: true,
      label: libelle,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 52,
          height: 52,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: fond,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: r == null ? IvertColors.bord : texte),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('$numero', style: TextStyle(fontWeight: FontWeight.w800, color: texte)),
              if (icone != null) Icon(icone, size: 14, color: texte),
            ],
          ),
        ),
      ),
    );
  }
}
