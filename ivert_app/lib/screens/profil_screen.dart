import 'package:flutter/material.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

import '../theme/app_theme.dart';
import '../widgets/communs.dart';

class ProfilScreen extends StatelessWidget {
  const ProfilScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Profil')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 120),
        children: [
          const Carte(
            child: EtatVide(
              icone: Iconsax.profile_circle_copy,
              titre: 'Pas encore de compte',
              texte: 'La création de compte (numéro de téléphone + code SMS) et le profil de vos parcelles arrivent avec la prochaine version. Vos diagnostics restent enregistrés sur ce téléphone.',
            ),
          ),
          const SizedBox(height: 20),
          const TitreSection('Modèles IA installés'),
          for (final (culture, precision) in [('Cacao', '87,9 %'), ('Anacarde', '95,9 %')])
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Carte(
                child: Row(
                  children: [
                    const Icon(Iconsax.cpu_copy, color: IvertColors.vert),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('$culture · version 2', style: const TextStyle(fontWeight: FontWeight.w700)),
                          Text('Précision mesurée : $precision · hors ligne',
                              style: const TextStyle(fontSize: 12, color: IvertColors.brunDoux)),
                        ],
                      ),
                    ),
                    const Pastille('Prêt'),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 20),
          const TitreSection('À propos'),
          const Carte(
            child: Text(
              'IVERT aide au diagnostic mais ne remplace pas l\'avis d\'un agronome. Les fiches conseils sont à valider par le CNRA / l\'ANADER.\n\nDonnées d\'entraînement : CocoaSwolSet (ESATIC/INPHB, CC BY 4.0), CCMT (CC BY 4.0), Cacao Diseases (CC BY-SA 4.0), Cocoa Diseases YOLOv4 (ODbL), Cashew Leaf Dataset (CC BY 4.0).',
              style: TextStyle(fontSize: 12, height: 1.5, color: IvertColors.brunDoux),
            ),
          ),
        ],
      ),
    );
  }
}
