import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import '../services/fiches_service.dart';
import '../services/parcelle_service.dart';
import '../services/serveur_service.dart';
import '../theme/app_theme.dart';
import '../widgets/communs.dart';
import 'parcelle_screen.dart';
import 'reseau_screen.dart';

/// Carte interactive : ma parcelle, le rayon d'alerte de 10 km et les foyers proches.
/// Fond OpenStreetMap (gratuit, connexion nécessaire pour les tuiles). Au pilote, passer à un
/// fournisseur avec clé (MapTiler…) : le serveur public d'OpenStreetMap n'est pas fait pour un
/// grand nombre d'utilisateurs. Cette carte servira aussi au suivi des livraisons de la boutique.
class CarteScreen extends StatefulWidget {
  const CarteScreen({super.key});

  @override
  State<CarteScreen> createState() => _CarteScreenState();
}

class _CarteScreenState extends State<CarteScreen> {
  static const _rayonKm = 10.0;
  static const _centreCi = LatLng(7.54, -5.55); // Côte d'Ivoire, si aucune parcelle

  final _serveur = ServeurService.instance;
  final _carte = MapController();
  Parcelle? _parcelle;
  bool _membre = false;
  bool _chargement = true;
  List<(Foyer, String)> _foyers = [];
  String? _erreur;
  bool _tuilesEnErreur = false;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    setState(() {
      _chargement = true;
      _erreur = null;
    });
    final p = await ParcelleService.instance.lire();
    var membre = false;
    final foyers = <(Foyer, String)>[];
    try {
      membre = _serveur.connecte && await _serveur.consentement() != null;
      if (membre && p != null) {
        for (final f in await _serveur.foyersProches(p, rayonKm: _rayonKm)) {
          foyers.add((f, (await FichesService.instance.fiche(f.culture, f.maladie))?.nom ?? f.maladie));
        }
      }
    } catch (_) {
      _erreur = 'Foyers indisponibles hors connexion.';
    }
    if (!mounted) return;
    setState(() {
      _parcelle = p;
      _membre = membre;
      _foyers = foyers;
      _chargement = false;
    });
    if (p != null) _carte.move(LatLng(p.latitude, p.longitude), 11);
  }

  Future<void> _choisirParcelle() async {
    final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const ParcelleScreen()));
    if (ok == true) _charger();
  }

  Future<void> _rejoindre() async {
    final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const ReseauScreen()));
    if (ok == true) _charger();
  }

  void _detailFoyer(Foyer f, String nom) {
    final p = _parcelle;
    final km = p == null ? null : ParcelleService.distanceKm(p.latitude, p.longitude, f.lat, f.lon);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (c) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$nom · ${f.culture.label}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(
              '${km == null ? '' : 'À environ ${km < 1 ? 'moins d’1' : km.round()} km de votre parcelle · '}'
              '${f.nbComptes} producteurs · dernier signalement le ${DateFormat('d MMM', 'fr_FR').format(f.dernierLe)}',
              style: const TextStyle(fontSize: 13, color: IvertColors.brunDoux),
            ),
            const SizedBox(height: 10),
            Pastille(
              f.confirme ? 'Confirmé' : 'Signalé, non confirmé',
              fond: f.confirme ? IvertColors.rougePale : IvertColors.creme,
              couleur: f.confirme ? IvertColors.rouge : IvertColors.orange,
            ),
            const SizedBox(height: 12),
            const Text(
              'Position arrondie à environ 1 km. Inspectez vos arbres, scannez au moindre doute et contactez l’ANADER. '
              'N’arrachez jamais sans consigne officielle.',
              style: TextStyle(fontSize: 13, height: 1.45),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = _parcelle;
    final centre = p == null ? _centreCi : LatLng(p.latitude, p.longitude);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Carte'),
        actions: [IconButton(onPressed: _charger, icon: const Icon(Iconsax.refresh_copy), tooltip: 'Actualiser')],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _carte,
            options: MapOptions(
              initialCenter: centre,
              initialZoom: p == null ? 6.5 : 11,
              minZoom: 5,
              maxZoom: 17,
              interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'ci.ivert.ivert',
                // Sans internet, les tuiles échouent : on le dit au lieu d'un fond gris muet
                errorTileCallback: (_, _, _) {
                  if (_tuilesEnErreur) return;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) setState(() => _tuilesEnErreur = true);
                  });
                },
              ),
              if (p != null)
                CircleLayer(
                  circles: [
                    CircleMarker(
                      point: centre,
                      radius: _rayonKm * 1000,
                      useRadiusInMeter: true,
                      color: const Color(0x142C6B2F),
                      borderColor: IvertColors.vert,
                      borderStrokeWidth: 1.5,
                    ),
                  ],
                ),
              MarkerLayer(
                markers: [
                  for (final (f, nom) in _foyers)
                    Marker(
                      point: LatLng(f.lat, f.lon),
                      width: 44,
                      height: 44,
                      child: Semantics(
                        button: true,
                        label: 'Foyer : $nom',
                        child: GestureDetector(
                          onTap: () => _detailFoyer(f, nom),
                          child: _Pastille(
                            couleur: f.confirme ? IvertColors.rouge : IvertColors.orange,
                            icone: Iconsax.danger,
                          ),
                        ),
                      ),
                    ),
                  if (p != null)
                    Marker(
                      point: centre,
                      width: 44,
                      height: 44,
                      child: Semantics(
                        label: 'Ma parcelle',
                        child: const _Pastille(couleur: IvertColors.vert, icone: Iconsax.home_2),
                      ),
                    ),
                ],
              ),
              const SimpleAttributionWidget(source: Text('OpenStreetMap contributors')),
            ],
          ),
          Positioned(left: 12, right: 12, top: 12, child: _bandeau()),
        ],
      ),
    );
  }

  Widget _bandeau() {
    final Widget contenu;
    if (_chargement) {
      contenu = const Row(
        children: [
          SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
          SizedBox(width: 10),
          Text('Chargement…'),
        ],
      );
    } else if (_parcelle == null) {
      contenu = Row(
        children: [
          const Expanded(
            child: Text('Indiquez votre parcelle pour la voir sur la carte.', style: TextStyle(fontSize: 13)),
          ),
          TextButton(onPressed: _choisirParcelle, child: const Text('Choisir')),
        ],
      );
    } else if (!_serveur.configure || !_membre) {
      contenu = Row(
        children: [
          const Expanded(
            child: Text('Rejoignez le réseau d’alerte pour voir les foyers proches.', style: TextStyle(fontSize: 13)),
          ),
          if (_serveur.configure) TextButton(onPressed: _rejoindre, child: const Text('Rejoindre')),
        ],
      );
    } else {
      final n = _foyers.length;
      contenu = Text(
        _erreur ??
            (n == 0
                ? 'Aucun foyer signalé à moins de 10 km de ${_parcelle!.localite.nom}.'
                : '$n foyer${n > 1 ? 's' : ''} à moins de 10 km. Touchez un point pour le détail.'),
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      );
    }
    return Material(
      elevation: 3,
      borderRadius: BorderRadius.circular(16),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            contenu,
            if (_tuilesEnErreur)
              const Padding(
                padding: EdgeInsets.only(top: 6, right: 6),
                child: Text(
                  'Fond de carte indisponible : connectez-vous à internet. Votre parcelle et les foyers restent affichés.',
                  style: TextStyle(fontSize: 12, height: 1.35, color: IvertColors.orange),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Pastille extends StatelessWidget {
  const _Pastille({required this.couleur, required this.icone});

  final Color couleur;
  final IconData icone;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: couleur,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 6, offset: Offset(0, 2))],
      ),
      child: Icon(icone, color: Colors.white, size: 20),
    );
  }
}
