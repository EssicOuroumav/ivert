import 'package:flutter/material.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

import '../services/fiches_service.dart';
import '../theme/app_theme.dart';
import 'communs.dart';

/// Contenu d'une fiche maladie : photo de référence, symptômes, causes, « Que faire ? »
/// (gestes naturels / produits, étape par étape) et prévention.
/// Utilisé par l'écran de résultat et par la bibliothèque des maladies.
class FicheDetail extends StatefulWidget {
  const FicheDetail({super.key, required this.fiche, this.probable = false, this.photoReference = true});

  final FicheMaladie fiche;

  /// Diagnostic « à confirmer » : la section des symptômes invite à vérifier.
  final bool probable;

  /// Afficher la photo de référence des symptômes (si la fiche en a une).
  final bool photoReference;

  @override
  State<FicheDetail> createState() => _FicheDetailState();
}

class _FicheDetailState extends State<FicheDetail> {
  bool _ongletProduits = false; // « Que faire ? » : gestes naturels d'abord

  @override
  Widget build(BuildContext context) {
    final f = widget.fiche;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
      if (widget.photoReference && f.photo != null) ...[
        const SizedBox(height: 18),
        const TitreSection('À quoi ça ressemble'),
        ClipRRect(
          borderRadius: BorderRadius.circular(IvertRadius.carte),
          child: AspectRatio(aspectRatio: 3 / 2, child: Image.asset(f.photo!, fit: BoxFit.cover)),
        ),
        if (f.credit != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(f.credit!, style: const TextStyle(fontSize: 10.5, color: IvertColors.brunDoux)),
          ),
      ],
      if (f.symptomes.isNotEmpty) ...[
        const SizedBox(height: 18),
        TitreSection(widget.probable ? 'Vérifiez ces symptômes' : 'Symptômes'),
        Carte(child: _liste(f.symptomes, Iconsax.search_status_copy)),
      ],
      if (f.causes.isNotEmpty) ...[
        const SizedBox(height: 18),
        const TitreSection('Pourquoi ça arrive'),
        Carte(child: Text(f.causes, style: const TextStyle(fontSize: 13, height: 1.45))),
      ],
      if (f.naturel.isNotEmpty || f.intrants.isNotEmpty || f.sansIntrant != null) ...[
        const SizedBox(height: 18),
        const TitreSection('Que faire ?'),
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: false, icon: Icon(Iconsax.tree_copy, size: 18), label: Text('Gestes naturels')),
            ButtonSegment(value: true, icon: Icon(Iconsax.box_copy, size: 18), label: Text('Produits')),
          ],
          selected: {_ongletProduits},
          onSelectionChanged: (s) => setState(() => _ongletProduits = s.first),
        ),
        const SizedBox(height: 10),
        if (!_ongletProduits)
          for (final (i, s) in f.naturel.indexed) _solution(s, ouverte: i == 0)
        else ...[
          if (f.intrants.isEmpty)
            Carte(
              couleur: IvertColors.rougePale,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Iconsax.danger_copy, color: IvertColors.rouge),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      f.sansIntrant ?? 'Aucun produit n’est conseillé pour ce problème.',
                      style: const TextStyle(fontSize: 13, height: 1.45),
                    ),
                  ),
                ],
              ),
            )
          else ...[
            _securite(),
            const SizedBox(height: 8),
            for (final (i, s) in f.intrants.indexed) _solution(s, ouverte: i == 0),
          ],
        ],
      ],
      if (f.prevention.isNotEmpty) ...[
        const SizedBox(height: 18),
        const TitreSection('Pour éviter que ça revienne'),
        Carte(child: _liste(f.prevention, Iconsax.shield_tick_copy)),
      ],
      if (f.conseils.isNotEmpty) ...[
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
      ],
      ],
    );
  }

  Widget _liste(List<String> lignes, IconData icone) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final l in lignes)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Icon(icone, size: 18, color: IvertColors.vert),
                ),
                const SizedBox(width: 10),
                Expanded(child: Text(l, style: const TextStyle(fontSize: 13, height: 1.45))),
              ],
            ),
          ),
      ],
    );
  }

  /// Une solution dépliable : ce que c'est, puis « Comment faire » en étapes numérotées.
  Widget _solution(Solution s, {required bool ouverte}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Carte(
        padding: EdgeInsets.zero,
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            initiallyExpanded: ouverte,
            tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            title: Text(s.titre, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
            subtitle: s.matiere == null
                ? null
                : Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'Matière active : ${s.matiere}',
                      style: const TextStyle(fontSize: 12, color: IvertColors.brunDoux),
                    ),
                  ),
            children: [
              Text(s.texte, style: const TextStyle(fontSize: 13, height: 1.45)),
              if (s.etapes.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text('Comment faire', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                for (final (i, e) in s.etapes.indexed)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 22,
                          height: 22,
                          alignment: Alignment.center,
                          decoration: const BoxDecoration(color: IvertColors.vertFond, shape: BoxShape.circle),
                          child: Text(
                            '${i + 1}',
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                              color: IvertColors.vert,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(child: Text(e, style: const TextStyle(fontSize: 13, height: 1.45))),
                      ],
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Rappel de sécurité affiché avant tout produit.
  Widget _securite() {
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
          Icon(Iconsax.security_safe_copy, color: IvertColors.orange, size: 20),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Produit homologué en Côte d’Ivoire uniquement. La dose est celle de l’étiquette et du conseiller ANADER. '
              'Portez gants, masque, lunettes, bottes et vêtements couvrants ; éloignez les enfants ; '
              'ne réutilisez jamais un emballage vide.',
              style: TextStyle(fontSize: 12.5, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

}
