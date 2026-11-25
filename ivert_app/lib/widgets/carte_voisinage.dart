import 'package:flutter/material.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import 'package:intl/intl.dart';

import '../screens/reseau_screen.dart';
import '../services/fiches_service.dart';
import '../services/parcelle_service.dart';
import '../services/serveur_service.dart';
import '../theme/app_theme.dart';
import 'communs.dart';

/// Carte « Alertes de voisinage » de l'écran Prévention.
/// Masquée si l'app est compilée sans serveur (mode 100 % hors ligne).
class CarteVoisinage extends StatefulWidget {
  const CarteVoisinage({super.key, required this.parcelle});

  final Parcelle? parcelle;

  @override
  State<CarteVoisinage> createState() => _CarteVoisinageState();
}

class _CarteVoisinageState extends State<CarteVoisinage> {
  final _serveur = ServeurService.instance;
  bool _chargement = true;
  bool _membre = false; // connecté ET consentement donné
  List<(Foyer, String, double)> _foyers = []; // foyer, nom de la maladie, distance
  int _enAttente = 0;
  String? _erreur;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  @override
  void didUpdateWidget(CarteVoisinage ancien) {
    super.didUpdateWidget(ancien);
    if (ancien.parcelle?.localite.id != widget.parcelle?.localite.id) _charger();
  }

  Future<void> _charger() async {
    setState(() {
      _chargement = true;
      _erreur = null;
    });
    try {
      final membre = _serveur.connecte && await _serveur.consentement() != null;
      final foyers = <(Foyer, String, double)>[];
      final p = widget.parcelle;
      if (membre) {
        await _serveur.envoyerEnAttente();
        if (p != null) {
          for (final f in await _serveur.foyersProches(p)) {
            final nom = (await FichesService.instance.fiche(f.culture, f.maladie))?.nom ?? f.maladie;
            foyers.add((f, nom, ParcelleService.distanceKm(p.latitude, p.longitude, f.lat, f.lon)));
          }
        }
      }
      final attente = await _serveur.nombreEnAttente();
      if (!mounted) return;
      setState(() {
        _membre = membre;
        _foyers = foyers;
        _enAttente = attente;
      });
    } catch (_) {
      if (mounted) setState(() => _erreur = 'Alertes indisponibles hors connexion. Tirez vers le bas pour actualiser.');
    } finally {
      if (mounted) setState(() => _chargement = false);
    }
  }

  Future<void> _rejoindre() async {
    final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const ReseauScreen()));
    if (ok == true) _charger();
  }

  Future<void> _quitter() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Quitter le réseau d’alerte ?'),
        content: const Text('Vos signalements seront effacés du serveur et vous ne recevrez plus d’alertes.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annuler')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Quitter')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _serveur.retirerConsentement();
      await _serveur.deconnecter();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Connexion nécessaire pour quitter le réseau. Réessayez.')));
      }
    }
    _charger();
  }

  @override
  Widget build(BuildContext context) {
    if (!_serveur.configure) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const TitreSection('Alertes de voisinage'),
          Carte(child: _contenu()),
        ],
      ),
    );
  }

  Widget _contenu() {
    if (_chargement) {
      return const Row(children: [
        SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
        SizedBox(width: 12),
        Text('Recherche des foyers proches…'),
      ]);
    }
    if (!_membre) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Soyez prévenu quand une maladie apparaît près de chez vous.',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          const Text(
            'Vos diagnostics, partagés de façon anonyme, alertent aussi vos voisins. Rien n’est partagé sans votre accord.',
            style: TextStyle(fontSize: 12, height: 1.4, color: IvertColors.brunDoux),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _rejoindre,
            icon: const Icon(Iconsax.people_copy),
            label: const Text('Rejoindre le réseau d’alerte'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_erreur != null)
          Text(_erreur!, style: const TextStyle(fontSize: 12, color: IvertColors.brunDoux))
        else if (widget.parcelle == null)
          const Text('Choisissez votre parcelle pour voir les foyers proches.',
              style: TextStyle(fontSize: 13, color: IvertColors.brunDoux))
        else if (_foyers.isEmpty)
          const Row(children: [
            Icon(Iconsax.tick_circle_copy, color: IvertColors.vert),
            SizedBox(width: 10),
            Expanded(child: Text('Aucun foyer signalé à moins de 10 km.', style: TextStyle(fontSize: 14))),
          ])
        else
          for (final (f, nom, km) in _foyers) _LigneFoyer(foyer: f, nom: nom, km: km),
        if (_enAttente > 0) ...[
          const SizedBox(height: 8),
          Text('$_enAttente signalement${_enAttente > 1 ? 's' : ''} en attente de réseau.',
              style: const TextStyle(fontSize: 12, color: IvertColors.brunDoux)),
        ],
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(onPressed: _quitter, child: const Text('Quitter le réseau')),
        ),
      ],
    );
  }
}

class _LigneFoyer extends StatelessWidget {
  const _LigneFoyer({required this.foyer, required this.nom, required this.km});

  final Foyer foyer;
  final String nom;
  final double km;

  @override
  Widget build(BuildContext context) {
    final couleur = foyer.confirme ? IvertColors.rouge : IvertColors.orange;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Iconsax.danger_copy, color: couleur),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$nom · ${foyer.culture.label}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                Text(
                  'À environ ${km < 1 ? 'moins d’1' : km.round()} km · ${foyer.nbComptes} producteurs · '
                  'dernier signalement le ${DateFormat('d MMM', 'fr_FR').format(foyer.dernierLe)}',
                  style: const TextStyle(fontSize: 12, color: IvertColors.brunDoux),
                ),
                const SizedBox(height: 4),
                Pastille(foyer.confirme ? 'Confirmé' : 'Signalé, non confirmé',
                    fond: foyer.confirme ? IvertColors.rougePale : IvertColors.creme, couleur: couleur),
                const SizedBox(height: 4),
                const Text('Inspectez vos arbres et contactez l’ANADER en cas de doute.',
                    style: TextStyle(fontSize: 12, height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
