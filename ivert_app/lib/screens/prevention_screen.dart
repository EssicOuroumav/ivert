import 'package:flutter/material.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import 'package:intl/intl.dart';

import '../services/diagnostic_service.dart';
import '../services/meteo_service.dart';
import '../services/parcelle_service.dart';
import '../services/prevention_service.dart';
import '../theme/app_theme.dart';
import '../widgets/communs.dart';
import '../widgets/espece_zone.dart';
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
    final nb = await SentinelleService.instance.nombre(_culture);
    final gestes = await CalendrierService.instance.gestes(_culture, DateTime.now().month);
    if (!mounted) return;
    setState(() {
      _parcelle = p;
      _tournee = tournee;
      _nbSentinelles = nb;
      _gestes = gestes;
    });
    if (p != null && _culture == Culture.cacao) {
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
    _charger();
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
            if (_culture == Culture.cacao) ...[
              const TitreSection('Risque de pourriture brune'),
              _carteRisque(),
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

  Widget _carteSentinelles() {
    final faits = _tournee.length;
    final alertes = _tournee.values.where((r) => r.alerte).length;
    return Carte(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$faits / $_nbSentinelles arbres scannés cette semaine',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(
            alertes == 0
                ? 'Choisissez des arbres repères répartis dans la parcelle et scannez-les chaque semaine.'
                : '$alertes arbre${alertes > 1 ? 's' : ''} à surveiller : inspectez ses voisins et montrez-le à un agent ANADER.',
            style: TextStyle(fontSize: 12, height: 1.4, color: alertes == 0 ? IvertColors.brunDoux : IvertColors.rouge),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var n = 1; n <= _nbSentinelles; n++) _BoutonArbre(numero: n, resultat: _tournee[n], onTap: () => _scannerArbre(n)),
            ],
          ),
          const SizedBox(height: 8),
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
  const _BoutonArbre({required this.numero, required this.resultat, required this.onTap});

  final int numero;
  final ResultatSentinelle? resultat;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final r = resultat;
    final (fond, texte, libelle) = r == null
        ? (Colors.white, IvertColors.brun, 'Arbre $numero, à scanner')
        : r.alerte
            ? (IvertColors.rougePale, IvertColors.rouge, 'Arbre $numero, à surveiller')
            : (IvertColors.vertPale, IvertColors.vert, 'Arbre $numero, scanné');
    return Semantics(
      button: true,
      label: libelle,
      child: InkWell(
        onTap: onTap,
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
              if (r != null) Icon(r.alerte ? Iconsax.danger_copy : Iconsax.tick_circle_copy, size: 14, color: texte),
            ],
          ),
        ),
      ),
    );
  }
}
