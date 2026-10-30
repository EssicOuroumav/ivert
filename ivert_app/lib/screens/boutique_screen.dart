import 'package:flutter/material.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

import '../widgets/communs.dart';

class BoutiqueScreen extends StatelessWidget {
  const BoutiqueScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Boutique')),
      body: const Center(
        child: EtatVide(
          icone: Iconsax.shop_copy,
          titre: 'Boutique bientôt disponible',
          texte: 'Vous pourrez commander ici des intrants certifiés (fongicides, engrais, semences) avec paiement Mobile Money.',
        ),
      ),
    );
  }
}
