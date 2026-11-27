import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

import '../../services/corrections_service.dart';
import '../../services/diagnostic_service.dart';
import '../../services/fiches_service.dart';
import '../../services/historique_service.dart';
import '../../services/parcelle_service.dart';
import '../../widgets/espece_zone.dart';
import '../../theme/app_theme.dart';
import '../../widgets/communs.dart';
import '../../widgets/fiche_detail.dart';
import '../bientot_screen.dart';
import 'prescan_screen.dart';

/// Résultat (Figma « 13 · Résultat Diagnostic »), avec les vraies sorties du modèle.
/// Sous le seuil de confiance, aucun nom de maladie n'est affirmé.
class ResultatScreen extends StatefulWidget {
  const ResultatScreen({super.key, required Diagnostic this.diagnostic, required this.entree});

  const ResultatScreen.depuisHistorique({super.key, required this.entree}) : diagnostic = null;

  final Diagnostic? diagnostic;
  final EntreeHistorique entree;

  @override
  State<ResultatScreen> createState() => _ResultatScreenState();
}

class _ResultatScreenState extends State<ResultatScreen> {
  FicheMaladie? _fiche;
  String? _especeZone; // pourriture brune : espèce probable dans la zone de la parcelle
  final _voix = FlutterTts();
  bool _lecture = false;
  Correction? _correction;
  String? _nomCorrection;

  @override
  void dispose() {
    _voix.stop();
    super.dispose();
  }

  /// Lit la fiche à voix haute (moteur vocal du téléphone, fonctionne sans internet si la voix
  /// française est installée). Pour les producteurs qui lisent difficilement.
  Future<void> _lireOuArreter() async {
    if (_lecture) {
      await _voix.stop();
      setState(() => _lecture = false);
      return;
    }
    final f = _fiche;
    if (f == null) return;
    final morceaux = <String>[];
    if (_e.niveau == Niveau.horsSujet) {
      morceaux.addAll([f.description, if (f.conseils.isNotEmpty) f.conseils.first.texte]);
    } else if (_e.niveau == Niveau.incertain) {
      morceaux.add('Diagnostic incertain. Reprenez la photo de plus près, avec une bonne lumière. '
          'Si le doute persiste, montrez la plante à un agent ANADER.');
    } else {
      morceaux.add(_e.niveau == Niveau.probable ? 'Diagnostic probable, à confirmer : ${f.nom}.' : '${f.nom}.');
      morceaux.add(f.description);
      if (f.symptomes.isNotEmpty) morceaux.add('Symptômes : ${f.symptomes.join(' ')}');
      if (f.causes.isNotEmpty) morceaux.add('Pourquoi ça arrive : ${f.causes}');
      for (final sol in f.naturel) {
        morceaux.add('${sol.titre}. ${sol.texte}');
        for (final (i, e) in sol.etapes.indexed) {
          morceaux.add('Étape ${i + 1} : $e');
        }
      }
      if (f.intrants.isNotEmpty) {
        morceaux.add('Produits : uniquement homologués, à la dose de l’étiquette et du conseiller ANADER, '
            'avec gants, masque et bottes.');
        for (final sol in f.intrants) {
          morceaux.add('${sol.titre}. ${sol.texte}');
        }
      } else if (f.sansIntrant != null) {
        morceaux.add(f.sansIntrant!);
      }
      for (final c in f.conseils) {
        morceaux.add('${c.titre}. ${c.texte}');
      }
    }
    await _voix.setLanguage('fr-FR');
    await _voix.setSpeechRate(0.45);
    await _voix.awaitSpeakCompletion(true);
    setState(() => _lecture = true);
    for (final m in morceaux) {
      if (!_lecture || !mounted) break;
      await _voix.speak(m);
    }
    if (mounted) setState(() => _lecture = false);
  }

  EntreeHistorique get _e => widget.entree;

  @override
  void initState() {
    super.initState();
    FichesService.instance.fiche(_e.culture, _e.classe).then((f) {
      if (mounted) setState(() => _fiche = f);
    });
    _chargerCorrection();
    if (_e.classe == 'pourriture_brune') {
      ParcelleService.instance.lire().then((p) {
        if (mounted && p != null) setState(() => _especeZone = texteEspeceZone(p.localite));
      });
    }
  }

  Future<void> _chargerCorrection() async {
    final c = await CorrectionsService.instance.pour(_e.id);
    final nom = c == null ? null : await _libelle(c.classeCorrigee);
    if (mounted) {
      setState(() {
        _correction = c;
        _nomCorrection = nom;
      });
    }
  }

  Future<String> _libelle(String classe) async => switch (classe) {
        'inconnu' => 'je ne sais pas, mais ce n’est pas ça',
        'autre' => 'ce n’est pas du ${_e.culture == Culture.cacao ? 'cacao' : 'anacarde'}',
        _ => (await FichesService.instance.fiche(_e.culture, classe))?.nom ?? classe,
      };

  /// « Ce n'est pas ça » : la personne choisit la bonne réponse. Gardé sur le téléphone.
  Future<void> _signalerErreur() async {
    final id = _e.id;
    if (id == null) return;
    final maladies = await FichesService.instance.maladies(_e.culture);
    if (!mounted) return;
    final choix = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (c) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text('Qu’a réellement cette plante ?', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text('Votre réponse reste sur ce téléphone et aidera à améliorer IVERT.',
                    style: TextStyle(fontSize: 12.5, color: IvertColors.brunDoux)),
              ),
              for (final (classe, f) in maladies)
                if (classe != _e.classe)
                  ListTile(title: Text(f.nom), onTap: () => Navigator.pop(c, classe)),
              if (_e.classe != 'sain') ListTile(title: const Text('Plant sain'), onTap: () => Navigator.pop(c, 'sain')),
              ListTile(
                title: Text('Ce n’est pas du ${_e.culture == Culture.cacao ? 'cacao' : 'anacarde'}'),
                onTap: () => Navigator.pop(c, 'autre'),
              ),
              ListTile(
                title: const Text('Je ne sais pas, mais ce n’est pas ça'),
                onTap: () => Navigator.pop(c, 'inconnu'),
              ),
            ],
          ),
        ),
      ),
    );
    if (choix == null) return;
    await CorrectionsService.instance.enregistrer(
      Correction(entreeId: id, classeIa: _e.classe, classeCorrigee: choix, date: DateTime.now()),
    );
    await _chargerCorrection();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Merci : votre correction est enregistrée. Montrez la plante à un agent ANADER pour confirmer.'),
      ));
    }
  }

  /// Douteux : refaire une photo du même arbre et combiner les deux résultats.
  Future<void> _deuxiemePhoto() async {
    await Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => PrescanScreen(cultureImposee: _e.culture, confirmerAvec: widget.diagnostic),
    ));
  }

  Future<void> _supprimer() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Supprimer ce diagnostic ?'),
        content: const Text('La photo et le résultat seront effacés de ce téléphone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annuler')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Supprimer')),
        ],
      ),
    );
    if (ok != true) return;
    await HistoriqueService.instance.supprimer(_e);
    if (_e.id != null) await CorrectionsService.instance.retirer(_e.id!);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final fiche = _fiche;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Résultat du diagnostic'),
        actions: [
          IconButton(
            onPressed: _fiche == null ? null : _lireOuArreter,
            icon: Icon(_lecture ? Iconsax.stop_circle_copy : Iconsax.volume_high_copy),
            tooltip: _lecture ? 'Arrêter la lecture' : 'Écouter la fiche',
          ),
          if (widget.diagnostic == null)
            IconButton(onPressed: _supprimer, icon: const Icon(Iconsax.trash_copy), tooltip: 'Supprimer'),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(IvertRadius.bloc),
            child: AspectRatio(
              aspectRatio: 16 / 10,
              child: Image.file(
                File(_e.photo),
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Container(color: IvertColors.beige),
              ),
            ),
          ),
          const SizedBox(height: 14),
          if (fiche != null)
            ...switch (_e.niveau) {
              Niveau.horsSujet => [_horsSujet(fiche)],
              Niveau.incertain => [_incertain()],
              Niveau.probable => [_aConfirmer(), const SizedBox(height: 10), ..._certain(fiche)],
              Niveau.certain => _certain(fiche),
            },
          if (widget.diagnostic != null && widget.diagnostic!.nbPhotos > 1) ...[
            const SizedBox(height: 12),
            Carte(
              couleur: IvertColors.vertFond,
              child: Row(children: [
                const Icon(Iconsax.gallery_tick_copy, color: IvertColors.vert),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Résultat combiné de ${widget.diagnostic!.nbPhotos} photos du même arbre.',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ),
              ]),
            ),
          ],
          if (widget.diagnostic != null &&
              widget.diagnostic!.nbPhotos == 1 &&
              (_e.niveau == Niveau.probable || _e.niveau == Niveau.incertain)) ...[
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _deuxiemePhoto,
              icon: const Icon(Iconsax.camera_copy),
              label: const Text('Confirmer avec une 2e photo du même arbre'),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
            ),
            const SizedBox(height: 4),
            const Text(
              'Photographiez une autre feuille ou une autre cabosse du même arbre : les deux résultats sont combinés.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11.5, color: IvertColors.brunDoux),
            ),
          ],
          if (_correction != null) ...[
            const SizedBox(height: 12),
            Carte(
              couleur: IvertColors.creme,
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Iconsax.edit_2_copy, color: IvertColors.orange),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Vous avez corrigé ce diagnostic : ${_nomCorrection ?? ''}.',
                    style: const TextStyle(fontSize: 13, height: 1.4, fontWeight: FontWeight.w600),
                  ),
                ),
              ]),
            ),
          ],
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const BientotScreen(
                  titre: 'Expert ANADER',
                  icone: Iconsax.call_copy,
                  texte:
                      'La demande de visite d\'expert ANADER arrive bientôt. En attendant, contactez l\'agent ANADER de votre zone.',
                ),
              ),
            ),
            icon: const Icon(Iconsax.call_copy),
            label: const Text('Demander une visite d\'expert ANADER'),
          ),
          if (_e.id != null)
            TextButton.icon(
              onPressed: _signalerErreur,
              icon: const Icon(Iconsax.message_question_copy, size: 18),
              label: Text(_correction == null ? 'Ce n’est pas ça ? Signaler une erreur' : 'Modifier ma correction'),
            ),
          const SizedBox(height: 16),
          const Text(
            'IVERT aide au diagnostic mais ne remplace pas l\'avis d\'un agronome. Conseils à valider par le CNRA / l\'ANADER.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: IvertColors.brunDoux),
          ),
        ],
      ),
    );
  }

  /// La photo n'est pas du cacao / de l'anacarde : on refuse de diagnostiquer.
  Widget _horsSujet(FicheMaladie f) {
    return Carte(
      couleur: IvertColors.creme,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Iconsax.close_circle_copy, color: IvertColors.orange),
              const SizedBox(width: 8),
              Expanded(
                child: Text(f.nom, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(f.description, style: const TextStyle(fontSize: 13, height: 1.45)),
          const SizedBox(height: 8),
          if (f.conseils.isNotEmpty)
            Text(
              f.conseils.first.texte,
              style: const TextStyle(fontSize: 13, height: 1.45, fontWeight: FontWeight.w600),
            ),
        ],
      ),
    );
  }

  /// Hypothèse nette mais pas assez sûre pour être affirmée : on la montre, à confirmer.
  Widget _aConfirmer() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: IvertColors.creme,
        borderRadius: BorderRadius.circular(IvertRadius.carte),
        border: Border.all(color: const Color(0x33B85A00)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Iconsax.info_circle_copy, color: IvertColors.orange, size: 20),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Diagnostic probable, à confirmer : l\'IA penche pour cette maladie sans en être certaine. '
              'Vérifiez les symptômes ci-dessous, refaites une photo de plus près ou montrez la plante à un agent ANADER.',
              style: TextStyle(fontSize: 12.5, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _incertain() {
    return Carte(
      couleur: IvertColors.creme,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Iconsax.info_circle_copy, color: IvertColors.orange),
              SizedBox(width: 8),
              Text('Diagnostic incertain', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'L\'IA n\'est pas assez sûre d\'elle pour donner un résultat fiable. '
            'Reprenez la photo de plus près, avec une bonne lumière, en cadrant une seule feuille ou une seule cabosse. '
            'Si le doute persiste, montrez la plante à un agent ANADER.',
            style: const TextStyle(fontSize: 13, height: 1.45),
          ),
          if (widget.diagnostic != null) ...[const SizedBox(height: 12), _probas(widget.diagnostic!)],
        ],
      ),
    );
  }

  List<Widget> _certain(FicheMaladie f) {
    final (couleur, fond, libelle) = switch (f.niveau) {
      'critique' => (IvertColors.rouge, IvertColors.rougePale, 'Critique'),
      'eleve' => (IvertColors.orange, IvertColors.creme, 'Sérieux'),
      'modere' => (IvertColors.orange, IvertColors.creme, 'Modéré'),
      _ => (IvertColors.vert, IvertColors.vertPale, 'Sain'),
    };
    return [
      Carte(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(f.nom, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
                      if (f.agent.isNotEmpty)
                        Text(
                          f.agent,
                          style: const TextStyle(
                            fontSize: 12,
                            fontStyle: FontStyle.italic,
                            color: IvertColors.brunDoux,
                          ),
                        ),
                    ],
                  ),
                ),
                Pastille(libelle, fond: fond, couleur: couleur),
              ],
            ),
            const SizedBox(height: 14),
            // Pas de pourcentage : la certitude interne du modèle (parfois « 100 % ») n'est pas
            // une garantie. On affiche un niveau en mots et la fiabilité mesurée en test.
            Row(
              children: [
                const Text('Confiance de l\'IA', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                const Spacer(),
                Text(
                  _e.niveau == Niveau.certain ? 'Élevée' : 'Moyenne, à confirmer',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: couleur),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'En test, IVERT donne la bonne réponse '
              '${_e.culture == Culture.cacao ? '86 fois sur 100 pour le cacao' : '95 fois sur 100 pour l’anacarde'}. '
              'En cas de doute, montrez la plante à un agent ANADER.',
              style: const TextStyle(fontSize: 11.5, height: 1.4, color: IvertColors.brunDoux),
            ),
            const SizedBox(height: 14),
            Text(f.description, style: const TextStyle(fontSize: 13, height: 1.45)),
            if (f.noteLocale.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: IvertColors.vertFond, borderRadius: BorderRadius.circular(12)),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Iconsax.location_copy, size: 18, color: IvertColors.vert),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(_especeZone ?? f.noteLocale, style: const TextStyle(fontSize: 12, height: 1.4)),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      FicheDetail(fiche: f, probable: _e.niveau == Niveau.probable),
    ];
  }

  Widget _probas(Diagnostic d) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Hypothèses de l\'IA', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        // La classe interne « autre » n'est jamais montrée à l'utilisateur
        for (final p in d.probas.where((p) => p.key != 'autre').take(3))
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: [
                Expanded(
                  child: FutureBuilder<FicheMaladie?>(
                    future: FichesService.instance.fiche(d.culture, p.key),
                    builder: (_, snap) =>
                        Text(snap.data?.nom ?? p.key.replaceAll('_', ' '), style: const TextStyle(fontSize: 12)),
                  ),
                ),
                Text('${(p.value * 100).round()} %', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
      ],
    );
  }
}
