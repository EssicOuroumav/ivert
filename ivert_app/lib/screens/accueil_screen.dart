import 'package:flutter/material.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

import '../services/historique_service.dart';
import '../theme/app_theme.dart';
import '../widgets/communs.dart';
import 'bientot_screen.dart';
import 'carnet_screen.dart';

/// Accueil (Figma « 08 · Dashboard ») sans données fictives : un nouvel utilisateur
/// voit des invitations à agir, puis ses vrais diagnostics.
class AccueilScreen extends StatefulWidget {
  const AccueilScreen({super.key, required this.onScan, required this.onOuvrirCarnet});

  final Future<void> Function() onScan;
  final VoidCallback onOuvrirCarnet;

  @override
  State<AccueilScreen> createState() => _AccueilScreenState();
}

class _AccueilScreenState extends State<AccueilScreen> {
  List<EntreeHistorique> _recents = [];

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    final tout = await HistoriqueService.instance.tout();
    if (mounted) setState(() => _recents = tout.take(3).toList());
  }

  Future<void> _scanner() async {
    await widget.onScan();
    _charger();
  }

  void _bientot(String titre, IconData icone, String texte) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => BientotScreen(titre: titre, icone: icone, texte: texte),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _charger,
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          _entete(context),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 120),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FilledButton.icon(
                  onPressed: _scanner,
                  icon: const Icon(Iconsax.camera_copy, size: 22),
                  label: const Text('Scanner une plante'),
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(58)),
                ),
                const SizedBox(height: 8),
                const Text('Fonctionne sans connexion · résultat en quelques secondes',
                    textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: IvertColors.brunDoux)),
                const SizedBox(height: 24),
                GridView.count(
                  crossAxisCount: 2,
                  padding: EdgeInsets.zero,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 1.35,
                  children: [
                    _Tuile(Iconsax.note_2_copy, 'Carnet santé', 'Mes diagnostics', widget.onOuvrirCarnet),
                    _Tuile(Iconsax.profile_2user_copy, 'Expert ANADER', 'Visite terrain',
                        () => _bientot('Expert ANADER', Iconsax.profile_2user_copy,
                            'La réservation d\'une visite d\'expert ANADER arrive bientôt. En attendant, rapprochez-vous de l\'agent ANADER de votre zone.')),
                    _Tuile(Iconsax.shop_copy, 'Boutique', 'Intrants certifiés',
                        () => _bientot('Boutique', Iconsax.shop_copy,
                            'La boutique d\'intrants certifiés arrive bientôt.')),
                    _Tuile(Iconsax.danger_copy, 'Alertes', 'Près de chez vous',
                        () => _bientot('Alertes', Iconsax.danger_copy,
                            'Les alertes de maladies dans votre zone arriveront avec la prochaine version.')),
                  ],
                ),
                const SizedBox(height: 24),
                const TitreSection('Derniers diagnostics'),
                if (_recents.isEmpty)
                  const Carte(
                    child: EtatVide(
                      icone: Iconsax.scan_copy,
                      titre: 'Aucun diagnostic pour l\'instant',
                      texte: 'Votre premier scan apparaîtra ici.',
                    ),
                  )
                else
                  for (final e in _recents)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: LigneHistorique(entree: e, onChange: _charger),
                    ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _entete(BuildContext context) {
    return Container(
      color: IvertColors.vert,
      padding: EdgeInsets.fromLTRB(20, MediaQuery.paddingOf(context).top + 20, 20, 24),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Bonjour 👋', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: Colors.white)),
          SizedBox(height: 4),
          Text('Prenez soin de votre cacao et de votre anacarde.',
              style: TextStyle(fontSize: 13, color: Color(0xCCFFFFFF))),
        ],
      ),
    );
  }
}

class _Tuile extends StatelessWidget {
  const _Tuile(this.icone, this.titre, this.sousTitre, this.onTap);

  final IconData icone;
  final String titre;
  final String sousTitre;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Carte(
      onTap: onTap,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: IvertColors.vertFond, borderRadius: BorderRadius.circular(10)),
            child: Icon(icone, color: IvertColors.vert, size: 20),
          ),
          const Spacer(),
          Text(titre,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          Text(sousTitre,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: IvertColors.brunDoux)),
        ],
      ),
    );
  }
}
