import 'dart:io';

import 'package:flutter/material.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import 'package:image_picker/image_picker.dart';

import '../../services/diagnostic_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/communs.dart';
import 'analyse_screen.dart';

/// Pré-scan (Figma « 09 · Pré-Scan ») : choix de la culture puis de la photo.
/// Seules les cultures réellement couvertes par un modèle sont proposées.
class PrescanScreen extends StatefulWidget {
  const PrescanScreen({super.key});

  @override
  State<PrescanScreen> createState() => _PrescanScreenState();
}

class _PrescanScreenState extends State<PrescanScreen> {
  Culture _culture = Culture.cacao;
  final _picker = ImagePicker();

  static const _maladies = {
    Culture.cacao: 'Pourriture brune · Swollen shoot · Anthracnose',
    Culture.anacarde: 'Anthracnose · Gommose · Mineuse · Rouille rouge',
  };
  static const _conseils = {
    Culture.cacao: 'Photographiez une feuille ou une cabosse en entier, bien éclairée, de près.',
    Culture.anacarde: 'Photographiez une feuille ou la zone du tronc atteinte, posée sur un fond clair si possible.',
  };

  Future<void> _photo(ImageSource source) async {
    final x = await _picker.pickImage(source: source, maxWidth: 1600, imageQuality: 92);
    if (x == null || !mounted) return;
    await Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => AnalyseScreen(culture: _culture, photo: File(x.path)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scanner une plante')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const TitreSection('Étape 1 · Quelle culture ?'),
            for (final c in Culture.values)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _CarteCulture(
                  culture: c,
                  maladies: _maladies[c]!,
                  choisie: c == _culture,
                  onTap: () => setState(() => _culture = c),
                ),
              ),
            const SizedBox(height: 12),
            const TitreSection('Étape 2 · La photo'),
            Carte(
              couleur: IvertColors.creme,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Iconsax.lamp_on_copy, color: IvertColors.orange),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(_conseils[_culture]!,
                        style: const TextStyle(fontSize: 13, height: 1.4, color: IvertColors.brun)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () => _photo(ImageSource.camera),
              icon: const Icon(Iconsax.camera_copy),
              label: const Text('Prendre une photo'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => _photo(ImageSource.gallery),
              icon: const Icon(Iconsax.gallery_copy),
              label: const Text('Choisir dans la galerie'),
            ),
            const SizedBox(height: 16),
            const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Iconsax.wifi_square_copy, size: 16, color: IvertColors.brunDoux),
                SizedBox(width: 6),
                Text('Analyse sur le téléphone, sans connexion',
                    style: TextStyle(fontSize: 12, color: IvertColors.brunDoux)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CarteCulture extends StatelessWidget {
  const _CarteCulture({required this.culture, required this.maladies, required this.choisie, required this.onTap});

  final Culture culture;
  final String maladies;
  final bool choisie;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: choisie ? IvertColors.vertFond : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(IvertRadius.carte),
        side: BorderSide(color: choisie ? IvertColors.vert : IvertColors.bord, width: choisie ? 2 : 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(IvertRadius.carte),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: choisie ? Colors.white : IvertColors.vertFond,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Iconsax.tree_copy, color: IvertColors.vert),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(culture.label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                    Text(culture.latin,
                        style: const TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: IvertColors.brunDoux)),
                    const SizedBox(height: 4),
                    Text(maladies, style: const TextStyle(fontSize: 12, color: IvertColors.brunDoux)),
                    const SizedBox(height: 6),
                    const Row(
                      children: [
                        Icon(Icons.circle, size: 8, color: IvertColors.vertClair),
                        SizedBox(width: 4),
                        Text('Prêt · hors ligne',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: IvertColors.vert)),
                      ],
                    ),
                  ],
                ),
              ),
              Icon(choisie ? Icons.check_circle : Icons.radio_button_unchecked,
                  color: choisie ? IvertColors.vert : IvertColors.bord, size: 26),
            ],
          ),
        ),
      ),
    );
  }
}
