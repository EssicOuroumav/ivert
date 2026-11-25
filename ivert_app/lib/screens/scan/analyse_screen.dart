import 'dart:io';

import 'package:flutter/material.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

import '../../services/diagnostic_service.dart';
import '../../services/historique_service.dart';
import '../../services/prevention_service.dart';
import '../../services/serveur_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/communs.dart';
import 'resultat_screen.dart';

/// Traitement IA (Figma « 12 · Traitement IA ») : analyse sur le téléphone puis résultat.
class AnalyseScreen extends StatefulWidget {
  const AnalyseScreen({super.key, required this.culture, required this.photo, this.arbreSentinelle});

  final Culture culture;
  final File photo;
  final int? arbreSentinelle;

  @override
  State<AnalyseScreen> createState() => _AnalyseScreenState();
}

class _AnalyseScreenState extends State<AnalyseScreen> {
  String? _erreur;

  @override
  void initState() {
    super.initState();
    _analyser();
  }

  Future<void> _analyser() async {
    setState(() => _erreur = null);
    try {
      final d = await DiagnosticService.instance.analyser(widget.culture, widget.photo);
      final entree = await HistoriqueService.instance.enregistrer(d, widget.photo);
      if (widget.arbreSentinelle != null) {
        await SentinelleService.instance.enregistrer(widget.culture, widget.arbreSentinelle!,
            ResultatSentinelle(classe: d.classe, niveau: d.niveau, entreeId: entree.id));
      }
      // Partage anonyme si le producteur a rejoint le réseau ; jamais bloquant
      ServeurService.instance.signalerSiAutorise(d).catchError((_) {});
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => ResultatScreen(diagnostic: d, entree: entree),
      ));
    } catch (e) {
      if (mounted) setState(() => _erreur = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Analyse · ${widget.culture.label}')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(IvertRadius.bloc),
                  child: Image.file(widget.photo, fit: BoxFit.cover, width: double.infinity),
                ),
              ),
              const SizedBox(height: 28),
              if (_erreur == null) ...[
                const SizedBox(
                    width: 36, height: 36, child: CircularProgressIndicator(strokeWidth: 3, color: IvertColors.vert)),
                const SizedBox(height: 16),
                const Text('Analyse en cours…', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                const Text('Le modèle IA fonctionne sur votre téléphone, sans internet.',
                    textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: IvertColors.brunDoux)),
              ] else
                EtatVide(
                  icone: Iconsax.warning_2_copy,
                  titre: 'L\'analyse n\'a pas pu aboutir',
                  texte: 'Essayez avec une autre photo. Détail : $_erreur',
                  action: FilledButton(onPressed: _analyser, child: const Text('Réessayer')),
                ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}
