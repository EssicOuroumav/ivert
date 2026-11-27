import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import '../services/diagnostic_service.dart';
import '../services/fiches_service.dart';
import '../services/historique_service.dart';
import '../services/lieux_service.dart';
import '../services/parcelle_service.dart';
import '../services/prevention_service.dart';
import '../services/serveur_service.dart';
import '../services/tuiles_service.dart';
import '../theme/app_theme.dart';
import '../widgets/communs.dart';
import 'mes_parcelles_screen.dart';
import 'reseau_screen.dart';
import 'scan/resultat_screen.dart';

/// Couches que le producteur peut afficher ou masquer.
enum Couche { parcelles, sentinelles, diagnostics, foyers, lieux }

/// Carte interactive : mes parcelles, mes arbres repères, les foyers proches et les lieux utiles.
/// Fond OpenStreetMap gardé sur le téléphone (zones déjà vues visibles hors connexion).
/// Au pilote : fournisseur avec clé (MapTiler…). Servira aussi au suivi des livraisons de la boutique.
class CarteScreen extends StatefulWidget {
  const CarteScreen({super.key, this.focus});

  /// Point à montrer en gros plan (ex. un arbre repère), sinon la parcelle.
  final (double, double)? focus;

  @override
  State<CarteScreen> createState() => _CarteScreenState();
}

class _CarteScreenState extends State<CarteScreen> {
  static const _rayonKm = 10.0;
  static const _centreCi = LatLng(7.54, -5.55);

  final _serveur = ServeurService.instance;
  final _carte = MapController();
  final Set<Couche> _visibles = {...Couche.values};
  Parcelle? _parcelle;
  List<ParcelleTracee> _tracees = [];
  List<(Culture, int, LatLng, ResultatSentinelle?)> _arbres = [];
  List<(Foyer, String)> _foyers = [];
  List<Lieu> _lieux = [];
  bool _membre = false;
  bool _chargement = true;
  bool _foyersIndisponibles = false;
  bool _tuilesEnErreur = false;
  List<(EntreeHistorique, String)> _diagnostics = []; // diagnostic localisé, nom affiché
  StreamSubscription<Position>? _flux;
  LatLng? _ici; // ma position en direct (si la localisation est autorisée)

  @override
  void initState() {
    super.initState();
    _charger();
    _suivrePosition();
  }

  @override
  void dispose() {
    _flux?.cancel();
    super.dispose();
  }

  /// Ma position en direct, pour retrouver un arbre repère en marchant.
  /// Ne demande l'autorisation que si l'on cherche un arbre ; sinon, seulement si elle est déjà donnée.
  Future<void> _suivrePosition() async {
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied && widget.focus != null) perm = await Geolocator.requestPermission();
      if (perm != LocationPermission.always && perm != LocationPermission.whileInUse) return;
      if (!await Geolocator.isLocationServiceEnabled()) return;
      _flux = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.best, distanceFilter: 2),
      ).listen((pos) {
        if (mounted) setState(() => _ici = LatLng(pos.latitude, pos.longitude));
      });
    } catch (_) {
      // Pas de GPS : la carte fonctionne sans « ma position »
    }
  }

  static String direction(LatLng de, LatLng vers) => CarteScreenDirection.direction(de, vers);

  Future<void> _charger() async {
    setState(() {
      _chargement = true;
      _foyersIndisponibles = false;
    });
    final p = await ParcelleService.instance.lire();
    final tracees = await ParcelleService.instance.tracees();
    final sem = SentinelleService.semaine(DateTime.now());
    final arbres = <(Culture, int, LatLng, ResultatSentinelle?)>[];
    for (final c in Culture.values) {
      final pos = await SentinelleService.instance.positions(c);
      final tournee = await SentinelleService.instance.tournee(c, sem);
      for (final e in pos.entries) {
        arbres.add((c, e.key, LatLng(e.value.$1, e.value.$2), tournee[e.key]));
      }
    }
    // Mes diagnostics localisés (le GPS est pris au moment du scan, si autorisé)
    final diagnostics = <(EntreeHistorique, String)>[];
    for (final e in (await HistoriqueService.instance.tout()).where((e) => e.aPosition)) {
      final nom = e.niveau == Niveau.horsSujet
          ? 'Photo non analysée'
          : e.niveau == Niveau.incertain
              ? 'Diagnostic incertain'
              : (await FichesService.instance.fiche(e.culture, e.classe))?.nom ?? e.classe;
      diagnostics.add((e, nom));
    }
    if (!mounted) return;
    setState(() {
      _parcelle = p;
      _tracees = tracees;
      _arbres = arbres;
      _diagnostics = diagnostics;
    });
    final f = widget.focus;
    if (f != null) {
      _carte.move(LatLng(f.$1, f.$2), 18);
    } else if (p != null) {
      _carte.move(LatLng(p.latitude, p.longitude), tracees.isEmpty ? 11 : 15);
    }

    // Réseau : foyers (visibles par tous) et lieux OpenStreetMap, sans bloquer l'affichage
    final foyers = <(Foyer, String)>[];
    var membre = false;
    var indisponibles = false;
    try {
      membre = _serveur.connecte && await _serveur.consentement() != null;
      if (p != null) {
        for (final f in await _serveur.foyersProches(p, rayonKm: _rayonKm)) {
          foyers.add((f, (await FichesService.instance.fiche(f.culture, f.maladie))?.nom ?? f.maladie));
        }
      }
    } catch (_) {
      indisponibles = true;
    }
    final lieux = p == null ? <Lieu>[] : await LieuxService.instance.autour(p.latitude, p.longitude);
    if (!mounted) return;
    setState(() {
      _foyers = foyers;
      _membre = membre;
      _foyersIndisponibles = indisponibles;
      _lieux = lieux;
      _chargement = false;
    });
  }

  void _recentrer() {
    final p = _parcelle;
    if (p != null) _carte.move(LatLng(p.latitude, p.longitude), _tracees.isEmpty ? 11 : 15);
  }

  Future<void> _ouvrir(Widget ecran) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ecran));
    _charger();
  }

  void _feuille(String titre, String sousTitre, String texte, {Widget? pastille}) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (c) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(titre, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(sousTitre, style: const TextStyle(fontSize: 13, color: IvertColors.brunDoux)),
            if (pastille != null) ...[const SizedBox(height: 10), pastille],
            const SizedBox(height: 12),
            Text(texte, style: const TextStyle(fontSize: 13, height: 1.45)),
          ],
        ),
      ),
    );
  }

  void _detailFoyer(Foyer f, String nom) {
    final p = _parcelle;
    final km = p == null ? null : ParcelleService.distanceKm(p.latitude, p.longitude, f.lat, f.lon);
    _feuille(
      '$nom · ${f.culture.label}',
      '${km == null ? '' : 'À environ ${km < 1 ? 'moins d’1' : km.round()} km · '}'
          '${f.nbComptes} producteurs · dernier signalement le ${DateFormat('d MMM', 'fr_FR').format(f.dernierLe)}',
      'Position arrondie à environ 1 km. Inspectez vos arbres, scannez au moindre doute et contactez l’ANADER. '
          'N’arrachez jamais sans consigne officielle.',
      pastille: Pastille(f.confirme ? 'Confirmé' : 'Signalé, non confirmé',
          fond: f.confirme ? IvertColors.rougePale : IvertColors.creme,
          couleur: f.confirme ? IvertColors.rouge : IvertColors.orange),
    );
  }

  void _choisirCouches() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final (couche, titre, detail) in [
                (Couche.parcelles, 'Mes parcelles', 'Contours tracés et rayon d’alerte de 10 km'),
                (Couche.sentinelles, 'Mes arbres repères', 'Vert : sain · rouge : à surveiller · orange : à refaire · gris : à scanner'),
                (Couche.foyers, 'Foyers de maladie', 'Signalés par au moins 3 producteurs, à moins de 10 km'),
                (Couche.diagnostics, 'Mes diagnostics', 'Lieu de chaque scan : rouge malade, orange à confirmer, vert sain'),
                (Couche.lieux, 'Lieux utiles', 'Marchés, boutiques agricoles, coopératives (OpenStreetMap)'),
              ])
                SwitchListTile(
                  value: _visibles.contains(couche),
                  title: Text(titre, style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(detail, style: const TextStyle(fontSize: 12)),
                  onChanged: (v) {
                    set(() => v ? _visibles.add(couche) : _visibles.remove(couche));
                    setState(() {});
                  },
                ),
            ],
          ),
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
        actions: [
          IconButton(onPressed: _choisirCouches, icon: const Icon(Iconsax.layer_copy), tooltip: 'Couches'),
          IconButton(onPressed: _charger, icon: const Icon(Iconsax.refresh_copy), tooltip: 'Actualiser'),
        ],
      ),
      floatingActionButton: p == null
          ? null
          : FloatingActionButton.small(
              onPressed: _recentrer,
              tooltip: 'Revenir sur ma parcelle',
              backgroundColor: Colors.white,
              child: const Icon(Iconsax.gps_copy, color: IvertColors.vert),
            ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _carte,
            options: MapOptions(
              initialCenter: centre,
              initialZoom: p == null ? 6.5 : 11,
              minZoom: 5,
              maxZoom: 18,
              interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'ci.ivert.ivert',
                tileProvider: TuilesEnCache(),
                errorTileCallback: (_, _, _) {
                  if (_tuilesEnErreur) return;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) setState(() => _tuilesEnErreur = true);
                  });
                },
              ),
              if (p != null && _visibles.contains(Couche.parcelles))
                CircleLayer(circles: [
                  CircleMarker(
                    point: centre,
                    radius: _rayonKm * 1000,
                    useRadiusInMeter: true,
                    color: const Color(0x0F2C6B2F),
                    borderColor: IvertColors.vert,
                    borderStrokeWidth: 1.5,
                  ),
                ]),
              if (_visibles.contains(Couche.parcelles) && _tracees.isNotEmpty)
                PolygonLayer(polygons: [
                  for (final t in _tracees)
                    Polygon(
                      points: [for (final (la, lo) in t.points) LatLng(la, lo)],
                      color: const Color(0x552E6B3A),
                      borderColor: IvertColors.vert,
                      borderStrokeWidth: 2.5,
                      label: '${t.nom}\n${t.surfaceHa.toStringAsFixed(2)} ha',
                      labelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: IvertColors.brun),
                    ),
                ]),
              if (_ici != null && widget.focus != null)
                PolylineLayer(polylines: [
                  Polyline(
                    points: [_ici!, LatLng(widget.focus!.$1, widget.focus!.$2)],
                    color: Colors.blue,
                    strokeWidth: 3,
                    pattern: StrokePattern.dashed(segments: const [10, 8]),
                  ),
                ]),
              MarkerLayer(markers: [
                if (_visibles.contains(Couche.diagnostics))
                  for (final (e, nom) in _diagnostics)
                    Marker(
                      point: LatLng(e.lat!, e.lon!),
                      width: 28,
                      height: 28,
                      child: GestureDetector(
                        onTap: () => _ouvrir(ResultatScreen.depuisHistorique(entree: e)),
                        child: _Rond(
                          couleur: e.classe == 'sain' && e.niveau == Niveau.certain
                              ? IvertColors.vert
                              : e.niveau == Niveau.certain && e.classe != 'autre'
                                  ? IvertColors.rouge
                                  : e.niveau == Niveau.probable && e.classe != 'sain'
                                      ? IvertColors.orange
                                      : IvertColors.brunDoux,
                          icone: Iconsax.scan,
                          taille: 14,
                          libelle: 'Diagnostic : $nom',
                        ),
                      ),
                    ),
                if (_visibles.contains(Couche.lieux))
                  for (final l in _lieux)
                    Marker(
                      point: LatLng(l.lat, l.lon),
                      width: 32,
                      height: 32,
                      child: GestureDetector(
                        onTap: () => _feuille(l.nom, l.libelle, 'Lieu issu d’OpenStreetMap (données ouvertes). '
                            'La liste des points de vente agréés et des agents ANADER viendra des partenaires.'),
                        child: _Rond(
                          couleur: const Color(0xFF5B4FA0),
                          icone: l.type == 'marche' ? Iconsax.shop : (l.type == 'boutique' ? Iconsax.bag_2 : Iconsax.people),
                          taille: 16,
                          libelle: '${l.libelle} : ${l.nom}',
                        ),
                      ),
                    ),
                if (_visibles.contains(Couche.sentinelles))
                  for (final (c, n, pt, r) in _arbres)
                    Marker(
                      point: pt,
                      width: 34,
                      height: 34,
                      child: GestureDetector(
                        onTap: () => _feuille(
                          'Arbre repère $n · ${c.label}',
                          r == null
                              ? 'Pas encore scanné cette semaine'
                              : (r.alerte ? 'À surveiller cette semaine' : (r.aRefaire ? 'À rescanner cette semaine' : 'Sain cette semaine')),
                          'Retrouvez cet arbre chaque semaine et scannez-le dans Prévention. '
                              'Sa position a été prise au moment du scan.',
                        ),
                        child: _Rond(
                          couleur: r == null
                              ? IvertColors.brunDoux
                              : (r.alerte ? IvertColors.rouge : (r.aRefaire ? IvertColors.orange : IvertColors.vert)),
                          texte: '$n',
                          libelle: 'Arbre repère $n',
                        ),
                      ),
                    ),
                if (_visibles.contains(Couche.foyers))
                  for (final (f, nom) in _foyers)
                    Marker(
                      point: LatLng(f.lat, f.lon),
                      width: 44,
                      height: 44,
                      child: GestureDetector(
                        onTap: () => _detailFoyer(f, nom),
                        child: _Rond(
                          couleur: f.confirme ? IvertColors.rouge : IvertColors.orange,
                          icone: Iconsax.danger,
                          libelle: 'Foyer : $nom',
                        ),
                      ),
                    ),
                if (_ici != null)
                  Marker(
                    point: _ici!,
                    width: 24,
                    height: 24,
                    child: Semantics(
                      label: 'Ma position',
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.blue,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 3),
                          boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 4)],
                        ),
                      ),
                    ),
                  ),
                if (p != null)
                  Marker(
                    point: centre,
                    width: 44,
                    height: 44,
                    child: GestureDetector(
                      onTap: () => _ouvrir(const MesParcellesScreen()),
                      child: const _Rond(couleur: IvertColors.vert, icone: Iconsax.home_2, libelle: 'Ma parcelle'),
                    ),
                  ),
              ]),
              const SimpleAttributionWidget(source: Text('OpenStreetMap contributors')),
            ],
          ),
          Positioned(left: 12, right: 12, top: 12, child: _bandeau()),
          Positioned(left: 12, bottom: 34, child: _legende()),
        ],
      ),
    );
  }

  Widget _bandeau() {
    final p = _parcelle;
    final Widget contenu;
    final f = widget.focus;
    if (f != null) {
      // Retrouver un arbre repère : distance et direction depuis ma position
      final cible = LatLng(f.$1, f.$2);
      final ici = _ici;
      final m = ici == null ? null : const Distance().as(LengthUnit.Meter, ici, cible);
      contenu = Text(
        ici == null
            ? 'Recherche de votre position… Activez la localisation pour être guidé jusqu’à l’arbre.'
            : m! < 8
                ? 'Vous êtes à l’arbre (à moins de 8 m). Cherchez son ruban ou son numéro.'
                : 'Arbre à ${m.round()} m, direction ${direction(ici, cible)}. Suivez la ligne bleue.',
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
      );
    } else if (p == null) {
      contenu = Row(children: [
        const Expanded(child: Text('Indiquez ou tracez votre parcelle pour la voir sur la carte.', style: TextStyle(fontSize: 13))),
        TextButton(onPressed: () => _ouvrir(const MesParcellesScreen()), child: const Text('Mes parcelles')),
      ]);
    } else {
      final n = _foyers.length;
      contenu = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _chargement
                ? 'Recherche des foyers proches…'
                : _foyersIndisponibles
                    ? 'Foyers indisponibles pour l’instant (connexion).'
                    : n == 0
                        ? 'Aucun foyer de maladie à moins de 10 km de ${p.localite.nom}.'
                        : '$n foyer${n > 1 ? 's' : ''} de maladie à moins de 10 km. Touchez un point.',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
          if (!_membre && _serveur.configure && !_chargement)
            Row(children: [
              const Expanded(
                child: Text('Partagez vos diagnostics pour prévenir vos voisins.',
                    style: TextStyle(fontSize: 12, color: IvertColors.brunDoux)),
              ),
              TextButton(onPressed: () => _ouvrir(const ReseauScreen()), child: const Text('Partager')),
            ]),
          if (_tuilesEnErreur)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text('Hors connexion : seules les zones déjà vues s’affichent.',
                  style: TextStyle(fontSize: 12, color: IvertColors.orange)),
            ),
        ],
      );
    }
    return Material(
      elevation: 3,
      borderRadius: BorderRadius.circular(16),
      color: Colors.white,
      child: Padding(padding: const EdgeInsets.fromLTRB(14, 10, 8, 10), child: contenu),
    );
  }

  Widget _legende() {
    Widget ligne(Color c, String t) => Padding(
          padding: const EdgeInsets.only(bottom: 3),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 12, height: 12, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
            const SizedBox(width: 6),
            Text(t, style: const TextStyle(fontSize: 11)),
          ]),
        );
    return Material(
      elevation: 2,
      borderRadius: BorderRadius.circular(12),
      color: const Color(0xF2FFFFFF),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 12, 5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            ligne(IvertColors.vert, 'Ma parcelle · arbre sain'),
            ligne(IvertColors.rouge, 'Foyer confirmé · arbre à surveiller'),
            ligne(IvertColors.orange, 'Foyer signalé'),
            ligne(IvertColors.brunDoux, 'Arbre à scanner'),
            ligne(const Color(0xFF5B4FA0), 'Marché, boutique, coopérative'),
            if (_ici != null) ligne(Colors.blue, 'Ma position'),
          ],
        ),
      ),
    );
  }
}

class _Rond extends StatelessWidget {
  const _Rond({required this.couleur, this.icone, this.texte, this.taille = 20, required this.libelle});

  final Color couleur;
  final IconData? icone;
  final String? texte;
  final double taille;
  final String libelle;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: libelle,
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: couleur,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2.5),
          boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 5, offset: Offset(0, 2))],
        ),
        child: icone != null
            ? Icon(icone, color: Colors.white, size: taille)
            : Text(texte ?? '', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
      ),
    );
  }
}

/// Calcul de direction, séparé pour pouvoir le tester.
class CarteScreenDirection {
  /// Direction en mots (nord, nord-est…) de [de] vers [vers].
  static String direction(LatLng de, LatLng vers) {
    final la1 = de.latitude * math.pi / 180, la2 = vers.latitude * math.pi / 180;
    final dl = (vers.longitude - de.longitude) * math.pi / 180;
    final y = math.sin(dl) * math.cos(la2);
    final x = math.cos(la1) * math.sin(la2) - math.sin(la1) * math.cos(la2) * math.cos(dl);
    final cap = (math.atan2(y, x) * 180 / math.pi + 360) % 360;
    const noms = ['nord', 'nord-est', 'est', 'sud-est', 'sud', 'sud-ouest', 'ouest', 'nord-ouest'];
    return noms[((cap + 22.5) % 360 ~/ 45)];
  }
}
