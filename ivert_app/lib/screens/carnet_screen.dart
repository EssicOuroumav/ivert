import 'dart:io';

import 'package:flutter/material.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import 'package:intl/intl.dart';

import '../services/diagnostic_service.dart';
import '../services/fiches_service.dart';
import '../services/historique_service.dart';
import '../theme/app_theme.dart';
import '../widgets/communs.dart';
import 'scan/resultat_screen.dart';

/// Carnet de santé (Figma « 14 · Historique Diagnostics ») : diagnostics enregistrés sur le téléphone.
class CarnetScreen extends StatefulWidget {
  const CarnetScreen({super.key, required this.onScan});

  final Future<void> Function() onScan;

  @override
  State<CarnetScreen> createState() => CarnetScreenState();
}

class CarnetScreenState extends State<CarnetScreen> {
  List<EntreeHistorique>? _entrees;

  @override
  void initState() {
    super.initState();
    recharger();
  }

  Future<void> recharger() async {
    final tout = await HistoriqueService.instance.tout();
    if (mounted) setState(() => _entrees = tout);
  }

  @override
  Widget build(BuildContext context) {
    final entrees = _entrees;
    return Scaffold(
      appBar: AppBar(title: const Text('Carnet de santé')),
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
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 120),
                    itemCount: entrees.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (_, i) => LigneHistorique(entree: entrees[i], onChange: recharger),
                  ),
                ),
    );
  }
}

class LigneHistorique extends StatelessWidget {
  const LigneHistorique({super.key, required this.entree, required this.onChange});

  final EntreeHistorique entree;
  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<FicheMaladie?>(
      future: FichesService.instance.fiche(entree.culture, entree.classe),
      builder: (context, snap) {
        final fiche = snap.data;
        final titre = switch (entree.niveau) {
          Niveau.horsSujet => 'Non reconnu',
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
            await Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => ResultatScreen.depuisHistorique(entree: entree),
            ));
            onChange();
          },
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.file(File(entree.photo),
                    width: 56,
                    height: 56,
                    fit: BoxFit.cover,
                    cacheWidth: 168,
                    errorBuilder: (_, _, _) =>
                        Container(width: 56, height: 56, color: IvertColors.beige, child: const Icon(Iconsax.image_copy))),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(titre,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: couleur)),
                    const SizedBox(height: 2),
                    Text(
                      '${entree.culture.label} · ${DateFormat('d MMM yyyy, HH:mm', 'fr_FR').format(entree.date)}',
                      style: const TextStyle(fontSize: 12, color: IvertColors.brunDoux),
                    ),
                  ],
                ),
              ),
              Text('${(entree.confiance * 100).round()} %',
                  style: TextStyle(fontWeight: FontWeight.w800, color: couleur)),
              const SizedBox(width: 4),
              const Icon(Iconsax.arrow_right_3_copy, size: 18, color: IvertColors.brunDoux),
            ],
          ),
        );
      },
    );
  }
}
