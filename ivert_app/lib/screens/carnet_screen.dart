import 'dart:io';

import 'package:flutter/material.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import 'package:intl/intl.dart';

import 'package:share_plus/share_plus.dart';

import '../services/corrections_service.dart';
import '../services/diagnostic_service.dart';
import '../services/fiches_service.dart';
import '../services/historique_service.dart';
import '../services/parcelle_service.dart';
import '../theme/app_theme.dart';
import '../widgets/communs.dart';
import 'scan/resultat_screen.dart';

/// Filtre d'état du carnet.
enum FiltreEtat { tous, malades, sains, aVerifier }

/// Carnet de santé (Figma « 14 · Historique Diagnostics ») : diagnostics enregistrés sur le téléphone,
/// avec filtres, bilan des 30 derniers jours, regroupement par mois et partage d'un rapport.
class CarnetScreen extends StatefulWidget {
  const CarnetScreen({super.key, required this.onScan});

  final Future<void> Function() onScan;

  @override
  State<CarnetScreen> createState() => CarnetScreenState();
}

class CarnetScreenState extends State<CarnetScreen> {
  List<EntreeHistorique>? _entrees;
  Map<String, String> _noms = {}; // "culture/classe" -> nom de la maladie
  Map<int, Correction> _corrections = {};
  Culture? _culture;
  FiltreEtat _etat = FiltreEtat.tous;

  @override
  void initState() {
    super.initState();
    recharger();
  }

  Future<void> recharger() async {
    final tout = await HistoriqueService.instance.tout();
    final noms = <String, String>{};
    for (final c in Culture.values) {
      for (final (classe, f) in await FichesService.instance.maladies(c)) {
        noms['${c.name}/$classe'] = f.nom;
      }
    }
    final corrections = await CorrectionsService.instance.toutes();
    if (mounted) {
      setState(() {
        _entrees = tout;
        _noms = noms;
        _corrections = corrections;
      });
    }
  }

  static bool estMalade(EntreeHistorique e) =>
      (e.niveau == Niveau.certain || e.niveau == Niveau.probable) && e.classe != 'sain' && e.classe != 'autre';
  static bool estSain(EntreeHistorique e) => e.niveau == Niveau.certain && e.classe == 'sain';

  bool _garde(EntreeHistorique e) {
    if (_culture != null && e.culture != _culture) return false;
    return switch (_etat) {
      FiltreEtat.tous => true,
      FiltreEtat.malades => estMalade(e),
      FiltreEtat.sains => estSain(e),
      FiltreEtat.aVerifier => !estMalade(e) && !estSain(e),
    };
  }

  String _nom(EntreeHistorique e) => switch (e.niveau) {
        Niveau.horsSujet => 'Photo non analysée',
        Niveau.incertain => 'Diagnostic incertain',
        _ when e.classe == 'sain' => 'Plant sain',
        Niveau.probable => 'Probable : ${_noms['${e.culture.name}/${e.classe}'] ?? e.classe}',
        Niveau.certain => _noms['${e.culture.name}/${e.classe}'] ?? e.classe,
      };

  /// Rapport texte à envoyer (WhatsApp, SMS, e-mail) à l'agent ANADER ou à la coopérative. Sans photo.
  Future<void> _partager(List<EntreeHistorique> liste) async {
    final p = await ParcelleService.instance.lire();
    final f = DateFormat('d MMM yyyy', 'fr_FR');
    final lignes = [
      'Carnet de santé IVERT${p == null ? '' : ' · ${p.localite.nom} (${p.localite.region})'}',
      'Rapport du ${f.format(DateTime.now())} · ${liste.length} diagnostic${liste.length > 1 ? 's' : ''}',
      '',
      for (final e in liste)
        '• ${DateFormat('d MMM', 'fr_FR').format(e.date)} · ${e.culture.label} · ${_nom(e)}'
            '${e.niveau == Niveau.certain && e.classe != 'sain' && e.classe != 'autre' ? ' (confiance élevée)' : ''}'
            '${_corrections[e.id] != null ? ' · corrigé par le producteur' : ''}',
      '',
      'Diagnostics indicatifs faits avec l’application IVERT, à confirmer par un agent ANADER.',
    ];
    await SharePlus.instance.share(ShareParams(text: lignes.join('\n'), subject: 'Carnet de santé IVERT'));
  }

  @override
  Widget build(BuildContext context) {
    final entrees = _entrees;
    final filtrees = entrees?.where(_garde).toList() ?? const <EntreeHistorique>[];
    return Scaffold(
      appBar: AppBar(
        title: const Text('Carnet de santé'),
        actions: [
          if (filtrees.isNotEmpty)
            IconButton(
              onPressed: () => _partager(filtrees),
              icon: const Icon(Iconsax.share_copy),
              tooltip: 'Partager le rapport',
            ),
        ],
      ),
      body: entrees == null
          ? const Center(child: CircularProgressIndicator())
          : entrees.isEmpty
          ? Center(
              child: EtatVide(
                icone: Iconsax.note_2_copy,
                titre: 'Votre carnet est vide',
                texte: 'Chaque diagnostic est enregistré ici, avec la photo et la date, même sans connexion.',
                action: FilledButton.icon(
                  onPressed: () async {
                    await widget.onScan();
                    recharger();
                  },
                  icon: const Icon(Iconsax.scan_copy),
                  label: const Text('Faire mon premier scan'),
                ),
              ),
            )
          : RefreshIndicator(
              onRefresh: recharger,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
                children: [
                  _bilan(entrees),
                  const SizedBox(height: 14),
                  SegmentedButton<Culture?>(
                    segments: [
                      const ButtonSegment(value: null, label: Text('Tout')),
                      for (final c in Culture.values) ButtonSegment(value: c, label: Text(c.label)),
                    ],
                    selected: {_culture},
                    onSelectionChanged: (s) => setState(() => _culture = s.first),
                  ),
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, children: [
                    for (final (f, t) in const [
                      (FiltreEtat.tous, 'Tous'),
                      (FiltreEtat.malades, 'Malades'),
                      (FiltreEtat.sains, 'Sains'),
                      (FiltreEtat.aVerifier, 'À vérifier'),
                    ])
                      ChoiceChip(label: Text(t), selected: _etat == f, onSelected: (_) => setState(() => _etat = f)),
                  ]),
                  const SizedBox(height: 8),
                  if (filtrees.isEmpty)
                    const Carte(
                      child: Text('Aucun diagnostic pour ce filtre.',
                          style: TextStyle(fontSize: 13, color: IvertColors.brunDoux)),
                    ),
                  for (final (i, e) in filtrees.indexed) ...[
                    if (i == 0 || DateFormat('yyyyMM').format(filtrees[i - 1].date) != DateFormat('yyyyMM').format(e.date))
                      Padding(
                        padding: const EdgeInsets.only(top: 10, bottom: 6),
                        child: TitreSection(DateFormat('MMMM yyyy', 'fr_FR').format(e.date)),
                      ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: LigneHistorique(entree: e, onChange: recharger, corrige: _corrections[e.id] != null),
                    ),
                  ],
                ],
              ),
            ),
    );
  }

  /// Bilan des 30 derniers jours : nombre de diagnostics, malades, sains, maladies les plus vues.
  Widget _bilan(List<EntreeHistorique> tout) {
    final depuis = DateTime.now().subtract(const Duration(days: 30));
    final recents = tout.where((e) => e.date.isAfter(depuis)).toList();
    final malades = recents.where(estMalade).toList();
    final sains = recents.where(estSain).length;
    final parMaladie = <String, int>{};
    for (final e in malades) {
      final n = _noms['${e.culture.name}/${e.classe}'] ?? e.classe;
      parMaladie[n] = (parMaladie[n] ?? 0) + 1;
    }
    final top = parMaladie.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final max = top.isEmpty ? 1 : top.first.value;
    return Carte(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('30 derniers jours', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: IvertColors.brunDoux)),
          const SizedBox(height: 8),
          Row(children: [
            _chiffre('${recents.length}', 'diagnostics', IvertColors.brun),
            _chiffre('${malades.length}', 'malades', IvertColors.rouge),
            _chiffre('$sains', 'sains', IvertColors.vert),
          ]),
          if (top.isNotEmpty) ...[
            const SizedBox(height: 12),
            for (final m in top.take(3))
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(children: [
                  Expanded(flex: 5, child: Text(m.key, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis)),
                  Expanded(
                    flex: 4,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: m.value / max,
                        minHeight: 8,
                        color: IvertColors.orange,
                        backgroundColor: IvertColors.beige,
                      ),
                    ),
                  ),
                  SizedBox(width: 28, child: Text(' ${m.value}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700))),
                ]),
              ),
          ],
        ],
      ),
    );
  }

  Widget _chiffre(String valeur, String libelle, Color couleur) => Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(valeur, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: couleur)),
          Text(libelle, style: const TextStyle(fontSize: 12, color: IvertColors.brunDoux)),
        ]),
      );
}

class LigneHistorique extends StatelessWidget {
  const LigneHistorique({super.key, required this.entree, required this.onChange, this.corrige = false});

  final EntreeHistorique entree;
  final VoidCallback onChange;

  /// Le producteur a corrigé ce diagnostic (« Ce n'est pas ça »).
  final bool corrige;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<FicheMaladie?>(
      future: FichesService.instance.fiche(entree.culture, entree.classe),
      builder: (context, snap) {
        final fiche = snap.data;
        final titre = switch (entree.niveau) {
          Niveau.horsSujet => 'Photo non analysée',
          Niveau.incertain => 'Diagnostic incertain',
          Niveau.probable => 'Probable : ${fiche?.nom ?? entree.classe}',
          Niveau.certain => fiche?.nom ?? entree.classe,
        };
        final couleur = entree.niveau == Niveau.incertain || entree.niveau == Niveau.horsSujet
            ? IvertColors.brunDoux
            : switch (fiche?.niveau) {
                'critique' => IvertColors.rouge,
                'eleve' || 'modere' => IvertColors.orange,
                _ => IvertColors.vert,
              };
        return Carte(
          padding: const EdgeInsets.all(10),
          onTap: () async {
            await Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => ResultatScreen.depuisHistorique(entree: entree)));
            onChange();
          },
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.file(
                  File(entree.photo),
                  width: 56,
                  height: 56,
                  fit: BoxFit.cover,
                  cacheWidth: 168,
                  errorBuilder: (_, _, _) =>
                      Container(width: 56, height: 56, color: IvertColors.beige, child: const Icon(Iconsax.image_copy)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titre,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: couleur),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${entree.culture.label} · ${DateFormat('d MMM yyyy, HH:mm', 'fr_FR').format(entree.date)}'
                      '${corrige ? ' · corrigé' : ''}',
                      style: const TextStyle(fontSize: 12, color: IvertColors.brunDoux),
                    ),
                  ],
                ),
              ),
              // Pas de pourcentage : le titre dit déjà « Probable », « incertain » ou « non analysée »
              const SizedBox(width: 4),
              const Icon(Iconsax.arrow_right_3_copy, size: 18, color: IvertColors.brunDoux),
            ],
          ),
        );
      },
    );
  }
}
