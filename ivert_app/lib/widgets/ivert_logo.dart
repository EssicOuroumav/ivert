import 'package:flutter/material.dart';

/// Logo IVERT : même recadrage que le calque « fo 1 » de Figma
/// (image source affichée à 208,96 % × 200 %, décalée de −34,29 % en hauteur).
class IvertLogo extends StatelessWidget {
  const IvertLogo({super.key, this.largeur = 134});

  final double largeur;

  @override
  Widget build(BuildContext context) {
    final hauteur = largeur * 140 / 134;
    return SizedBox(
      width: largeur,
      height: hauteur,
      child: ClipRect(
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            Positioned(
              left: 0,
              top: -0.3429 * hauteur,
              width: 2.0896 * largeur,
              height: 2 * hauteur,
              child: Image.asset('assets/images/logo_source.png', fit: BoxFit.fill),
            ),
          ],
        ),
      ),
    );
  }
}
