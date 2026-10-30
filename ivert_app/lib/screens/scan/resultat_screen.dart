import 'dart:io';

import 'package:flutter/material.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

import '../../services/diagnostic_service.dart';
import '../../services/fiches_service.dart';
import '../../services/historique_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/communs.dart';
import '../bientot_screen.dart';

/// Résultat (Figma « 13 · Résultat Diagnostic »), avec les vraies sorties du modèle.
/// Sous le seuil de confiance, aucun nom de maladie n'est affirmé.
class ResultatScreen extends StatefulWidget {
  const ResultatScreen({super.key, required Diagnostic this.diagnostic, required this.entree});

  const ResultatScreen.depuisHistorique({super.key, required this.entree}) : diagnostic = null;

  final Diagnostic? diagnostic;
  final EntreeHistorique entree;

  @override
  State<ResultatScreen> createState() => _ResultatScreenState();
}

class _ResultatScreenState extends State<ResultatScreen> {
  FicheMaladie? _fiche;

  EntreeHistorique get _e => widget.entree;

  @override
  void initState() {
    super.initState();
    FichesService.instance.fiche(_e.culture, _e.classe).then((f) {
      if (mounted) setState(() => _fiche = f);
    });
  }

  Future<void> _supprimer() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Supprimer ce diagnostic ?'),
        content: const Text('La photo et le résultat seront effacés de ce téléphone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annuler')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Supprimer')),
        ],
      ),
    );
    if (ok != true) return;
    await HistoriqueService.instance.supprimer(_e);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final fiche = _fiche;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Résultat du diagnostic'),
        actions: [
          if (widget.diagnostic == null)
            IconButton(onPressed: _supprimer, icon: const Icon(Iconsax.trash_copy), tooltip: 'Supprimer'),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(IvertRadius.bloc),
            child: AspectRatio(
              aspectRatio: 16 / 10,
              child: Image.file(File(_e.photo),
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Container(color: IvertColors.beige)),
            ),
          ),
          const SizedBox(height: 14),
          if (fiche != null)
            ...switch (_e.niveau) {
              Niveau.horsSujet => [_horsSujet(fiche)],
              Niveau.incertain => [_incertain()],
              Niveau.probable => [_aConfirmer(), const SizedBox(height: 10), ..._certain(fiche)],
              Niveau.certain => _certain(fiche),
            },
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const BientotScreen(
                titre: 'Expert ANADER',
                icone: Iconsax.call_copy,
                texte: 'La demande de visite d\'expert ANADER arrive bientôt. En attendant, contactez l\'agent ANADER de votre zone.',
              ),
            )),
            icon: const Icon(Iconsax.call_copy),
            label: const Text('Demander une visite d\'expert ANADER'),
          ),
          const SizedBox(height: 16),
          const Text(
            'IVERT aide au diagnostic mais ne remplace pas l\'avis d\'un agronome. Conseils à valider par le CNRA / l\'ANADER.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: IvertColors.brunDoux),
          ),
        ],
      ),
    );
  }

  /// La photo n'est pas du cacao / de l'anacarde : on refuse de diagnostiquer.
  Widget _horsSujet(FicheMaladie f) {
    return Carte(
      couleur: IvertColors.creme,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Iconsax.close_circle_copy, color: IvertColors.orange),
              const SizedBox(width: 8),
              Expanded(child: Text(f.nom, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
            ],
          ),
          const SizedBox(height: 8),
          Text(f.description, style: const TextStyle(fontSize: 13, height: 1.45)),
          const SizedBox(height: 8),
          Text(f.conseils.first.texte,
              style: const TextStyle(fontSize: 13, height: 1.45, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  /// Hypothèse nette mais pas assez sûre pour être affirmée : on la montre, à confirmer.
  Widget _aConfirmer() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: IvertColors.creme,
        borderRadius: BorderRadius.circular(IvertRadius.carte),
        border: Border.all(color: const Color(0x33B85A00)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Iconsax.info_circle_copy, color: IvertColors.orange, size: 20),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Diagnostic probable, à confirmer : l\'IA penche pour cette maladie sans en être certaine. '
              'Vérifiez les symptômes ci-dessous, refaites une photo de plus près ou montrez la plante à un agent ANADER.',
              style: TextStyle(fontSize: 12.5, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _incertain() {
    return Carte(
      couleur: IvertColors.creme,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Iconsax.info_circle_copy, color: IvertColors.orange),
              SizedBox(width: 8),
              Text('Diagnostic incertain', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'L\'IA n\'est pas assez sûre d\'elle (${(_e.confiance * 100).round()} %) pour donner un résultat fiable. '
            'Reprenez la photo de plus près, avec une bonne lumière, en cadrant une seule feuille ou une seule cabosse. '
            'Si le doute persiste, montrez la plante à un agent ANADER.',
            style: const TextStyle(fontSize: 13, height: 1.45),
          ),
          if (widget.diagnostic != null) ...[
            const SizedBox(height: 12),
            _probas(widget.diagnostic!),
          ],
        ],
      ),
    );
  }

  List<Widget> _certain(FicheMaladie f) {
    final (couleur, fond, libelle) = switch (f.niveau) {
      'critique' => (IvertColors.rouge, IvertColors.rougePale, 'Critique'),
      'eleve' => (IvertColors.orange, IvertColors.creme, 'Sérieux'),
      'modere' => (IvertColors.orange, IvertColors.creme, 'Modéré'),
      _ => (IvertColors.vert, IvertColors.vertPale, 'Sain'),
    };
    return [
      Carte(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(f.nom, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
                      if (f.agent.isNotEmpty)
                        Text(f.agent,
                            style: const TextStyle(
                                fontSize: 12, fontStyle: FontStyle.italic, color: IvertColors.brunDoux)),
                    ],
                  ),
                ),
                Pastille(libelle, fond: fond, couleur: couleur),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                const Text('Confiance de l\'IA', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                const Spacer(),
                Text('${(_e.confiance * 100).round()} %',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: couleur)),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                  value: _e.confiance, minHeight: 7, color: couleur, backgroundColor: IvertColors.beige),
            ),
            const SizedBox(height: 14),
            Text(f.description, style: const TextStyle(fontSize: 13, height: 1.45)),
            if (f.noteLocale.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: IvertColors.vertFond, borderRadius: BorderRadius.circular(12)),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Iconsax.location_copy, size: 18, color: IvertColors.vert),
                    const SizedBox(width: 8),
                    Expanded(child: Text(f.noteLocale, style: const TextStyle(fontSize: 12, height: 1.4))),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      const SizedBox(height: 18),
      TitreSection(f.estSain ? 'Recommandation' : 'Que faire ?'),
      for (final c in f.conseils)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Carte(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Pastille(c.badge),
                const SizedBox(height: 8),
                Text(c.titre, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(c.texte, style: const TextStyle(fontSize: 13, height: 1.45, color: IvertColors.brun)),
              ],
            ),
          ),
        ),
    ];
  }

  Widget _probas(Diagnostic d) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Hypothèses de l\'IA', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        // La classe interne « autre » n'est jamais montrée à l'utilisateur
        for (final p in d.probas.where((p) => p.key != 'autre').take(3))
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: [
                Expanded(
                  child: FutureBuilder<FicheMaladie?>(
                    future: FichesService.instance.fiche(d.culture, p.key),
                    builder: (_, snap) => Text(snap.data?.nom ?? p.key.replaceAll('_', ' '),
                        style: const TextStyle(fontSize: 12)),
                  ),
                ),
                Text('${(p.value * 100).round()} %', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
      ],
    );
  }
}
