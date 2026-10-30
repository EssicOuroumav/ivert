import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Carte blanche à bord fin, style Figma.
class Carte extends StatelessWidget {
  const Carte({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.onTap, this.couleur});

  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  final Color? couleur;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: couleur ?? Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(IvertRadius.carte),
        side: const BorderSide(color: IvertColors.bord),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(onTap: onTap, child: Padding(padding: padding, child: child)),
    );
  }
}

/// État vide : remplace les données fictives de la maquette par une invitation à agir.
class EtatVide extends StatelessWidget {
  const EtatVide({super.key, required this.icone, required this.titre, required this.texte, this.action});

  final IconData icone;
  final String titre;
  final String texte;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: const BoxDecoration(color: IvertColors.vertFond, shape: BoxShape.circle),
            child: Icon(icone, size: 32, color: IvertColors.vert),
          ),
          const SizedBox(height: 16),
          Text(titre,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: IvertColors.brun)),
          const SizedBox(height: 6),
          Text(texte,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, height: 1.4, color: IvertColors.brunDoux)),
          if (action != null) ...[const SizedBox(height: 20), action!],
        ],
      ),
    );
  }
}

class Pastille extends StatelessWidget {
  const Pastille(this.texte, {super.key, this.fond = IvertColors.vertPale, this.couleur = IvertColors.vert});

  final String texte;
  final Color fond;
  final Color couleur;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: fond, borderRadius: BorderRadius.circular(12)),
      child: Text(texte, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: couleur)),
    );
  }
}

class TitreSection extends StatelessWidget {
  const TitreSection(this.texte, {super.key});

  final String texte;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, top: 4),
      child: Text(texte.toUpperCase(),
          style: const TextStyle(
              fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.6, color: IvertColors.brunDoux)),
    );
  }
}
