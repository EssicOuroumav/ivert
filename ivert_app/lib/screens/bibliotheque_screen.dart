import 'package:flutter/material.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

import '../services/diagnostic_service.dart';
import '../services/fiches_service.dart';
import '../theme/app_theme.dart';
import '../widgets/communs.dart';
import '../widgets/fiche_detail.dart';

/// Bibliothèque des maladies : toutes les fiches, consultables sans scanner, avec recherche par symptôme.
class BibliothequeScreen extends StatefulWidget {
  const BibliothequeScreen({super.key});

  @override
  State<BibliothequeScreen> createState() => _BibliothequeScreenState();
}

class _BibliothequeScreenState extends State<BibliothequeScreen> {
  final _recherche = TextEditingController();
  Map<Culture, List<(String, FicheMaladie)>> _fiches = {};
  Culture? _culture; // null = les deux cultures

  @override
  void initState() {
    super.initState();
    _charger();
  }

  @override
  void dispose() {
    _recherche.dispose();
    super.dispose();
  }

  Future<void> _charger() async {
    final f = {for (final c in Culture.values) c: await FichesService.instance.maladies(c)};
    if (mounted) setState(() => _fiches = f);
  }

  @override
  Widget build(BuildContext context) {
    final q = _recherche.text.trim();
    final resultats = <(Culture, String, FicheMaladie)>[
      for (final c in Culture.values)
        if (_culture == null || _culture == c)
          for (final (classe, f) in _fiches[c] ?? const <(String, FicheMaladie)>[])
            if (q.isEmpty || FichesService.correspond(f, q)) (c, classe, f),
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('Maladies et ravageurs')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
        children: [
          TextField(
            controller: _recherche,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'Chercher un symptôme : tache brune, gomme, feuille jaune…',
              prefixIcon: const Icon(Iconsax.search_normal_copy),
              suffixIcon: q.isEmpty
                  ? null
                  : IconButton(
                      onPressed: () => setState(_recherche.clear),
                      icon: const Icon(Icons.close),
                      tooltip: 'Effacer',
                    ),
            ),
          ),
          const SizedBox(height: 12),
          SegmentedButton<Culture?>(
            segments: [
              const ButtonSegment(value: null, label: Text('Tout')),
              for (final c in Culture.values) ButtonSegment(value: c, label: Text(c.label)),
            ],
            selected: {_culture},
            onSelectionChanged: (s) => setState(() => _culture = s.first),
          ),
          const SizedBox(height: 16),
          if (resultats.isEmpty)
            Carte(
              child: Text(
                q.isEmpty
                    ? 'Chargement des fiches…'
                    : 'Aucune fiche ne correspond à « $q ». Essayez un autre mot, ou scannez la plante.',
                style: const TextStyle(fontSize: 13, color: IvertColors.brunDoux),
              ),
            )
          else
            for (final (c, classe, f) in resultats)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Carte(
                  padding: const EdgeInsets.all(10),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => FicheScreen(culture: c, classe: classe, fiche: f),
                  )),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: f.photo != null
                            ? Image.asset(f.photo!, width: 64, height: 64, fit: BoxFit.cover, cacheWidth: 192)
                            : Container(
                                width: 64,
                                height: 64,
                                color: IvertColors.vertFond,
                                child: const Icon(Iconsax.health_copy, color: IvertColors.vert),
                              ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(f.nom, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                            const SizedBox(height: 2),
                            Text(
                              '${c.label} · ${switch (f.type) { 'virus' => 'virus', 'ravageur' => 'ravageur', _ => 'maladie' }}'
                              ' · ${switch (f.niveau) { 'critique' => 'critique', 'eleve' => 'sérieux', _ => 'modéré' }}',
                              style: const TextStyle(fontSize: 12, color: IvertColors.brunDoux),
                            ),
                            if (f.symptomes.isNotEmpty)
                              Text(
                                f.symptomes.first,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 12, color: IvertColors.brun),
                              ),
                          ],
                        ),
                      ),
                      const Icon(Iconsax.arrow_right_3_copy, size: 18, color: IvertColors.brunDoux),
                    ],
                  ),
                ),
              ),
          const SizedBox(height: 8),
          const Text(
            'Fiches rédigées à partir de sources publiques (CNRA, ANADER, études ivoiriennes), à valider par un agronome. '
            'En cas de doute, scannez la plante ou montrez-la à un agent ANADER.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: IvertColors.brunDoux),
          ),
        ],
      ),
    );
  }
}

/// Une fiche maladie consultée depuis la bibliothèque (sans diagnostic).
class FicheScreen extends StatelessWidget {
  const FicheScreen({super.key, required this.culture, required this.classe, required this.fiche});

  final Culture culture;
  final String classe;
  final FicheMaladie fiche;

  @override
  Widget build(BuildContext context) {
    final f = fiche;
    return Scaffold(
      appBar: AppBar(title: Text(f.nom, overflow: TextOverflow.ellipsis)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        children: [
          Carte(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(f.nom, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
                if (f.agent.isNotEmpty)
                  Text(f.agent,
                      style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: IvertColors.brunDoux)),
                const SizedBox(height: 4),
                Text(culture.label, style: const TextStyle(fontSize: 12, color: IvertColors.brunDoux)),
                const SizedBox(height: 12),
                Text(f.description, style: const TextStyle(fontSize: 13, height: 1.45)),
                if (f.noteLocale.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(f.noteLocale, style: const TextStyle(fontSize: 12, height: 1.4, color: IvertColors.brunDoux)),
                ],
              ],
            ),
          ),
          FicheDetail(fiche: f),
        ],
      ),
    );
  }
}
