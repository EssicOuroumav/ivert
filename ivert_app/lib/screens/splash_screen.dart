import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/app_theme.dart';
import '../widgets/ivert_logo.dart';
import 'home_shell.dart';

/// Écran d'accueil (Figma « 01 · Splash Screen ») puis présentation au premier lancement.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  final _pages = PageController();
  int _page = 0;
  bool _presentation = false;

  // Illustrations et titres repris des maquettes Figma « 02 · 03 · 04 · Onboarding ».
  // Les textes annoncent seulement ce que l'app fait déjà, ou disent « bientôt ».
  static const _slides = [
    ('assets/images/onboarding_diagnostic.jpg', Alignment.center, 'Diagnostic IA\nen moins d\'1 minute',
        'Un modèle IA dédié par culture, cacao et anacarde. Le diagnostic fonctionne sur votre téléphone, même sans connexion.'),
    ('assets/images/onboarding_boutique.png', Alignment.bottomCenter, 'Marketplace de\nproduits certifiés',
        'Bientôt : commandez les traitements recommandés après votre diagnostic.'),
    ('assets/images/onboarding_expert.jpg', Alignment.topCenter, 'Experts ANADER\nà domicile',
        'Bientôt : réservez une visite terrain avec un technicien certifié, rapport et prescriptions inclus.'),
  ];

  Future<void> _terminer() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('presentation_vue', true);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const HomeShell()));
  }

  Future<void> _commencer() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('presentation_vue') ?? false) {
      await _terminer();
    } else {
      setState(() => _presentation = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: _presentation ? _presentationVue() : _splashVue(),
        ),
      ),
    );
  }

  Widget _splashVue() {
    return Padding(
      key: const ValueKey('splash'),
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        children: [
          const Spacer(flex: 3),
          const IvertLogo(largeur: 150),
          const SizedBox(height: 20),
          const Text('Intelligence Artificielle Médicale\npour l\'agriculture en Afrique',
              textAlign: TextAlign.center, style: TextStyle(fontSize: 14, height: 1.4, color: IvertColors.brun)),
          const Spacer(flex: 3),
          FilledButton(onPressed: _commencer, child: const Text('Commencer →')),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _presentationVue() {
    final derniere = _page == _slides.length - 1;
    return Column(
      key: const ValueKey('presentation'),
      children: [
        Expanded(
          child: Stack(
            children: [
              PageView(
                controller: _pages,
                onPageChanged: (i) => setState(() => _page = i),
                children: [
                  for (final (image, cadrage, titre, texte) in _slides)
                    LayoutBuilder(
                      builder: (context, c) => Column(
                        children: [
                          SizedBox(
                            height: c.maxHeight * 0.55,
                            width: double.infinity,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                Image.asset(image, fit: BoxFit.cover, alignment: cadrage),
                                // Fondu vers le blanc, comme dans la maquette
                                const DecoratedBox(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      stops: [0.55, 0.8, 1],
                                      colors: [Color(0x00FFFFFF), Color(0xCCFFFFFF), Colors.white],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 28),
                            child: Column(
                              children: [
                                Text(titre,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                        fontSize: 26, height: 1.2, fontWeight: FontWeight.w800, color: IvertColors.vert)),
                                const SizedBox(height: 12),
                                Text(texte,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(fontSize: 15, height: 1.45, color: IvertColors.brunDoux)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              Positioned(
                top: 4,
                right: 12,
                child: TextButton(
                  onPressed: _terminer,
                  style: TextButton.styleFrom(backgroundColor: const Color(0xB3FFFFFF)),
                  child: const Text('Passer →'),
                ),
              ),
            ],
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < _slides.length; i++)
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: i == _page ? 24 : 8,
                height: 8,
                decoration: BoxDecoration(
                  color: i == _page ? IvertColors.vert : IvertColors.beige,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
          ],
        ),
        const SizedBox(height: 28),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: FilledButton(
            onPressed: derniere
                ? _terminer
                : () => _pages.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeOut),
            child: Text(derniere ? 'C\'est parti →' : 'Suivant →'),
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}
