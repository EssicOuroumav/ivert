import 'package:flutter/material.dart';

import '../widgets/communs.dart';

/// Module prévu mais pas encore branché (backend à venir) : pas de fausses données.
class BientotScreen extends StatelessWidget {
  const BientotScreen({super.key, required this.titre, required this.icone, required this.texte});

  final String titre;
  final IconData icone;
  final String texte;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(titre)),
      body: Center(child: EtatVide(icone: icone, titre: 'Bientôt disponible', texte: texte)),
    );
  }
}
