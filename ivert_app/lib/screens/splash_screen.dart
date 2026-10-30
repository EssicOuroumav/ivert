import 'package:flutter/material.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
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

  static const _slides = [
    (Iconsax.scan_copy, 'Diagnostic en moins d\'une minute',
        'Photographiez une feuille ou une cabosse : l\'IA reconnaît la maladie, même sans connexion internet.'),
    (Iconsax.note_2_copy, 'Des conseils adaptés',
        'Pour chaque maladie : les gestes de terrain, les traitements homologués et quand appeler un expert.'),
    (Iconsax.profile_2user_copy, 'Experts ANADER',
        'Pour les cas difficiles, demandez bientôt une visite d\'un expert directement depuis l\'application.'),
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
    return Padding(
      key: const ValueKey('presentation'),
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(onPressed: _terminer, child: const Text('Passer')),
          ),
          Expanded(
            child: PageView(
              controller: _pages,
              onPageChanged: (i) => setState(() => _page = i),
              children: [
                for (final (icone, titre, texte) in _slides)
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 140,
                        height: 140,
                        decoration: const BoxDecoration(color: IvertColors.vertFond, shape: BoxShape.circle),
                        child: Icon(icone, size: 64, color: IvertColors.vert),
                      ),
                      const SizedBox(height: 40),
                      Text(titre,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: IvertColors.brun)),
                      const SizedBox(height: 12),
                      Text(texte,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 15, height: 1.45, color: IvertColors.brunDoux)),
                    ],
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
          FilledButton(
            onPressed: derniere
                ? _terminer
                : () => _pages.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeOut),
            child: Text(derniere ? 'C\'est parti' : 'Suivant'),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
