import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/diagnostic_service.dart';
import '../services/fiches_service.dart';
import '../services/fond_carte.dart';
import '../services/historique_service.dart';
import '../services/lieux_service.dart';
import '../services/parcelle_service.dart';
import '../services/prevention_service.dart';
import '../services/serveur_service.dart';
import '../theme/app_theme.dart';
import 'mes_parcelles_screen.dart';
import 'reseau_screen.dart';
import 'scan/prescan_screen.dart';
import 'scan/resultat_screen.dart';

/// Couches que le producteur peut afficher ou masquer (pastilles en haut de la carte).
enum Couche { parcelles, sentinelles, diagnostics, foyers, lieux }

enum _Type { parcelle, tracee, arbre, diagnostic, foyer, lieu }

typedef _Arbre = (Culture, int, LatLng, ResultatSentinelle?, String?); // culture, numéro, point, résultat, repère

/// Un élément touchable de la carte.
class _Element {
  _Element(this.type, this.point, this.donnee, {this.titre = ''});

  final _Type type;
  final LatLng point;
  final Object donnee;
  final String titre;
}

/// Carte interactive : fond moderne (plan ou satellite), filtres en pastilles, fiche qui monte du bas,
/// zoom animé, regroupement des points proches, boutons flottants (ma position, ma parcelle, boussole).
class CarteScreen extends StatefulWidget {
  const CarteScreen({super.key, this.focus});

  /// Point à rejoindre (ex. un arbre repère) : la carte guide le producteur jusqu'à lui.
  final (double, double)? focus;

  @override
  State<CarteScreen> createState() => _CarteScreenState();
}

class _CarteScreenState extends State<CarteScreen> with TickerProviderStateMixin {
  static const _rayonKm = 10.0;
  static const _centreCi = LatLng(7.54, -5.55);

  final _serveur = ServeurService.instance;
  final _carte = MapController();
  final LayerHitNotifier<ParcelleTracee> _toucheParcelle = ValueNotifier(null);
  final Set<Couche> _visibles = {...Couche.values};
  Parcelle? _parcelle;
  List<ParcelleTracee> _tracees = [];
  List<_Arbre> _arbres = [];
  List<(EntreeHistorique, String)> _diagnostics = [];
  List<(Foyer, String)> _foyers = [];
  List<Lieu> _lieux = [];
  bool _membre = false;
  bool _chargement = true;
  bool _foyersIndisponibles = false;
  bool _tuilesEnErreur = false;
  bool _satellite = false;
  double _zoom = 12;
  double _rotation = 0;
  _Element? _selection;
  LatLng? _cible; // point à rejoindre à pied
  String? _cibleNom;
  StreamSubscription<Position>? _flux;
  LatLng? _ici;
  AnimationController? _anim;

  @override
  void initState() {
    super.initState();
    final f = widget.focus;
    if (f != null) {
      _cible = LatLng(f.$1, f.$2);
      _cibleNom = 'l’arbre repère';
    }
    SharedPreferences.getInstance().then((p) {
      if (mounted && FondCarte.satelliteDisponible) setState(() => _satellite = p.getBool('carte_satellite') ?? false);
    });
    _charger();
    _suivrePosition(demander: f != null);
  }

  @override
  void dispose() {
    _flux?.cancel();
    _anim?.dispose();
    _toucheParcelle.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------- données

  Future<void> _charger() async {
    setState(() {
      _chargement = true;
      _foyersIndisponibles = false;
    });
    final p = await ParcelleService.instance.lire();
    final tracees = await ParcelleService.instance.tracees();
    final sem = SentinelleService.semaine(DateTime.now());
    final arbres = <_Arbre>[];
    for (final c in Culture.values) {
      final pos = await SentinelleService.instance.positions(c);
      final tournee = await SentinelleService.instance.tournee(c, sem);
      final reperes = await SentinelleService.instance.reperes(c);
      for (final e in pos.entries) {
        arbres.add((c, e.key, LatLng(e.value.$1, e.value.$2), tournee[e.key], reperes[e.key]));
      }
    }
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
    final c = _cible;
    if (c != null) {
      _allerA(c, 18);
    } else if (p != null) {
      _allerA(LatLng(p.latitude, p.longitude), tracees.isEmpty ? 12 : 15);
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

  /// Ma position en direct (point bleu). Ne demande l'autorisation que si [demander].
  Future<void> _suivrePosition({bool demander = false}) async {
    if (_flux != null) return;
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied && demander) perm = await Geolocator.requestPermission();
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

  // ---------------------------------------------------------------- mouvements

  /// Déplacement animé (0,6 s) vers [cible], au niveau de zoom [zoom].
  void _allerA(LatLng cible, double zoom) {
    _anim?.dispose();
    final cam = _carte.camera;
    final lat = Tween(begin: cam.center.latitude, end: cible.latitude);
    final lon = Tween(begin: cam.center.longitude, end: cible.longitude);
    final z = Tween(begin: cam.zoom, end: zoom);
    final ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    final courbe = CurvedAnimation(parent: ctrl, curve: Curves.easeInOutCubic);
    ctrl.addListener(() => _carte.move(LatLng(lat.evaluate(courbe), lon.evaluate(courbe)), z.evaluate(courbe)));
    _anim = ctrl..forward();
  }

  void _selectionner(_Element e) {
    setState(() => _selection = e);
    _allerA(e.point, math.max(_carte.camera.zoom, e.type == _Type.lieu || e.type == _Type.foyer ? 14 : 16));
  }

  Future<void> _maPosition() async {
    await _suivrePosition(demander: true);
    final ici = _ici;
    if (ici != null) {
      _allerA(ici, 17);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Position introuvable : activez la localisation du téléphone et autorisez IVERT.'),
      ));
    }
  }

  void _maParcelle() {
    final p = _parcelle;
    if (p == null) {
      _ouvrir(const MesParcellesScreen());
      return;
    }
    _allerA(LatLng(p.latitude, p.longitude), _tracees.isEmpty ? 13 : 16);
  }

  Future<void> _basculerSatellite() async {
    setState(() => _satellite = !_satellite);
    await (await SharedPreferences.getInstance()).setBool('carte_satellite', _satellite);
  }

  Future<void> _ouvrir(Widget ecran) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ecran));
    _charger();
  }

  void _yAller(_Element e, String nom) {
    setState(() {
      _cible = e.point;
      _cibleNom = nom;
      _selection = null;
    });
    _suivrePosition(demander: true);
    final ici = _ici;
    if (ici != null) {
      _carte.fitCamera(
        CameraFit.bounds(bounds: LatLngBounds(ici, e.point), padding: const EdgeInsets.fromLTRB(60, 160, 60, 120)),
      );
    }
  }

  // ---------------------------------------------------------------- regroupement

  List<_Element> get _points => [
        if (_visibles.contains(Couche.diagnostics))
          for (final (e, nom) in _diagnostics) _Element(_Type.diagnostic, LatLng(e.lat!, e.lon!), e, titre: nom),
        if (_visibles.contains(Couche.lieux))
          for (final l in _lieux) _Element(_Type.lieu, LatLng(l.lat, l.lon), l, titre: l.nom),
        if (_visibles.contains(Couche.sentinelles))
          for (final a in _arbres) _Element(_Type.arbre, a.$3, a, titre: 'Arbre repère ${a.$2}'),
        if (_visibles.contains(Couche.foyers))
          for (final (f, nom) in _foyers) _Element(_Type.foyer, LatLng(f.lat, f.lon), f, titre: nom),
      ];

  /// Regroupe les points trop proches à l'écran (cases de ≈ 56 px). Aucun regroupement de près (zoom ≥ 17).
  static List<List<_Element>> _regrouper(List<_Element> points, double zoom) {
    if (zoom >= 17) return [for (final p in points) [p]];
    final taille = 56 * 360 / (256 * math.pow(2, zoom));
    final cases = <String, List<_Element>>{};
    for (final p in points) {
      final cle = '${(p.point.latitude / taille).floor()}:${(p.point.longitude / taille).floor()}';
      (cases[cle] ??= []).add(p);
    }
    return cases.values.toList();
  }

  static LatLng _centreDe(List<_Element> g) => LatLng(
        g.map((e) => e.point.latitude).reduce((a, b) => a + b) / g.length,
        g.map((e) => e.point.longitude).reduce((a, b) => a + b) / g.length,
      );

  // ---------------------------------------------------------------- affichage

  @override
  Widget build(BuildContext context) {
    final p = _parcelle;
    final centre = p == null ? _centreCi : LatLng(p.latitude, p.longitude);
    final groupes = _regrouper(_points, _zoom);
    final bas = MediaQuery.paddingOf(context).bottom;
    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _carte,
            options: MapOptions(
              initialCenter: centre,
              initialZoom: p == null ? 6.5 : 12,
              minZoom: 5,
              maxZoom: 19,
              onTap: (_, _) => setState(() => _selection = null),
              onPositionChanged: (cam, _) {
                if ((cam.zoom - _zoom).abs() > 0.2 || (cam.rotation - _rotation).abs() > 1) {
                  setState(() {
                    _zoom = cam.zoom;
                    _rotation = cam.rotation;
                  });
                }
              },
            ),
            children: [
              FondCarte.couche(
                satellite: _satellite,
                surErreur: (_, _, _) {
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
                    color: const Color(0x0C2C6B2F),
                    borderColor: const Color(0x992C6B2F),
                    borderStrokeWidth: 1.5,
                  ),
                ]),
              if (_visibles.contains(Couche.parcelles) && _tracees.isNotEmpty)
                GestureDetector(
                  onTap: () {
                    final t = _toucheParcelle.value?.hitValues.firstOrNull;
                    if (t == null) return;
                    final (la, lo) = t.centre;
                    _selectionner(_Element(_Type.tracee, LatLng(la, lo), t, titre: t.nom));
                  },
                  child: PolygonLayer<ParcelleTracee>(
                    hitNotifier: _toucheParcelle,
                    polygons: [
                      for (final t in _tracees)
                        Polygon(
                          points: [for (final (la, lo) in t.points) LatLng(la, lo)],
                          hitValue: t,
                          color: _selection?.donnee == t ? const Color(0x772E6B3A) : const Color(0x4D2E6B3A),
                          borderColor: _satellite ? Colors.white : IvertColors.vert,
                          borderStrokeWidth: 2.5,
                          label: t.nom,
                          labelStyle: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: _satellite ? Colors.white : IvertColors.brun,
                          ),
                        ),
                    ],
                  ),
                ),
              if (_ici != null && _cible != null)
                PolylineLayer(polylines: [
                  Polyline(
                    points: [_ici!, _cible!],
                    color: const Color(0xFF1E88E5),
                    strokeWidth: 4,
                    pattern: StrokePattern.dashed(segments: const [12, 8]),
                  ),
                ]),
              MarkerLayer(
                rotate: true,
                markers: [
                  for (final g in groupes)
                    if (g.length > 1)
                      Marker(
                        point: _centreDe(g),
                        width: 46,
                        height: 46,
                        child: GestureDetector(
                          onTap: () => _allerA(_centreDe(g), math.min(_zoom + 2, 18)),
                          child: _Bulle(nombre: g.length, couleur: _couleur(g.first)),
                        ),
                      )
                    else
                      Marker(
                        point: g.first.point,
                        width: _selection?.donnee == g.first.donnee ? 50 : 38,
                        height: _selection?.donnee == g.first.donnee ? 50 : 38,
                        child: GestureDetector(
                          onTap: () => _selectionner(g.first),
                          child: _Rond(
                            couleur: _couleur(g.first),
                            icone: _icone(g.first),
                            texte: g.first.type == _Type.arbre ? '${(g.first.donnee as _Arbre).$2}' : null,
                            libelle: g.first.titre,
                            choisi: _selection?.donnee == g.first.donnee,
                          ),
                        ),
                      ),
                  if (_cible != null && widget.focus == null)
                    Marker(
                      point: _cible!,
                      width: 36,
                      height: 36,
                      child: const Icon(Icons.flag, color: Color(0xFF1E88E5), size: 34),
                    ),
                  if (_ici != null)
                    Marker(
                      point: _ici!,
                      width: 26,
                      height: 26,
                      child: Semantics(
                        label: 'Ma position',
                        child: Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E88E5),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 3.5),
                            boxShadow: const [BoxShadow(color: Color(0x551E88E5), blurRadius: 10, spreadRadius: 4)],
                          ),
                        ),
                      ),
                    ),
                  if (p != null && _visibles.contains(Couche.parcelles))
                    Marker(
                      point: centre,
                      width: 46,
                      height: 46,
                      child: GestureDetector(
                        onTap: () => _selectionner(_Element(_Type.parcelle, centre, p, titre: p.localite.nom)),
                        child: _Rond(
                          couleur: IvertColors.vert,
                          icone: Iconsax.home_2,
                          libelle: 'Ma parcelle',
                          choisi: _selection?.type == _Type.parcelle,
                        ),
                      ),
                    ),
                ],
              ),
              FondCarte.mention(satellite: _satellite),
            ],
          ),
          // Haut : retour, résumé, pastilles de filtre
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(children: [
                      _BoutonRond(icone: Iconsax.arrow_left_2, libelle: 'Retour', onTap: () => Navigator.of(context).pop()),
                      const SizedBox(width: 8),
                      Expanded(child: _bandeau()),
                    ]),
                    const SizedBox(height: 8),
                    SizedBox(height: 42, child: _pastilles()),
                  ],
                ),
              ),
            ),
          ),
          // Droite : boutons flottants
          Positioned(
            right: 12,
            bottom: (_selection == null ? 28 : 236) + bas,
            child: Column(children: [
              if (_rotation.abs() > 1) ...[
                _BoutonRond(
                  libelle: 'Remettre le nord en haut',
                  onTap: () => _carte.rotate(0),
                  enfant: Transform.rotate(
                    angle: -_rotation * math.pi / 180,
                    child: const Icon(Icons.navigation, color: Color(0xFFD32F2F)),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              if (FondCarte.satelliteDisponible) ...[
                _BoutonRond(
                  icone: _satellite ? Iconsax.map_1 : Iconsax.global,
                  libelle: _satellite ? 'Vue plan' : 'Vue satellite',
                  onTap: _basculerSatellite,
                ),
                const SizedBox(height: 10),
              ],
              _BoutonRond(icone: Iconsax.home_2, libelle: 'Ma parcelle', onTap: _maParcelle),
              const SizedBox(height: 10),
              _BoutonRond(icone: Iconsax.gps, libelle: 'Ma position', onTap: _maPosition, couleur: const Color(0xFF1E88E5)),
            ]),
          ),
          // Bas : fiche de l'élément touché
          Positioned(
            left: 12,
            right: 12,
            bottom: 16 + bas,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              transitionBuilder: (enfant, a) => SlideTransition(
                position: Tween(begin: const Offset(0, 0.4), end: Offset.zero).animate(a),
                child: FadeTransition(opacity: a, child: enfant),
              ),
              child: _selection == null
                  ? const SizedBox.shrink()
                  : KeyedSubtree(key: ValueKey(_selection!.donnee), child: _fiche(_selection!)),
            ),
          ),
        ],
      ),
    );
  }

  Color _couleur(_Element e) {
    switch (e.type) {
      case _Type.diagnostic:
        final d = e.donnee as EntreeHistorique;
        if (d.classe == 'sain' && d.niveau == Niveau.certain) return IvertColors.vert;
        if (d.niveau == Niveau.certain && d.classe != 'autre') return IvertColors.rouge;
        if (d.niveau == Niveau.probable && d.classe != 'sain') return IvertColors.orange;
        return IvertColors.brunDoux;
      case _Type.arbre:
        final r = (e.donnee as _Arbre).$4;
        if (r == null) return IvertColors.brunDoux;
        if (r.alerte) return IvertColors.rouge;
        if (r.aRefaire) return IvertColors.orange;
        return IvertColors.vert;
      case _Type.foyer:
        return (e.donnee as Foyer).confirme ? IvertColors.rouge : IvertColors.orange;
      case _Type.lieu:
        return const Color(0xFF5B4FA0);
      case _Type.parcelle:
      case _Type.tracee:
        return IvertColors.vert;
    }
  }

  IconData? _icone(_Element e) => switch (e.type) {
        _Type.diagnostic => Iconsax.scan,
        _Type.foyer => Iconsax.danger,
        _Type.lieu => switch ((e.donnee as Lieu).type) {
            'marche' => Iconsax.shop,
            'boutique' => Iconsax.bag_2,
            _ => Iconsax.people,
          },
        _ => null,
      };

  Widget _bandeau() {
    final p = _parcelle;
    final cible = _cible;
    final String texte;
    Widget? action;
    if (cible != null) {
      final ici = _ici;
      final m = ici == null ? null : const Distance().as(LengthUnit.Meter, ici, cible);
      final nom = _cibleNom ?? 'la destination';
      texte = ici == null
          ? 'Recherche de votre position… activez la localisation pour être guidé.'
          : m! < 8
              ? 'Vous êtes arrivé à $nom (moins de 8 m).'
              : 'Vers $nom : ${m < 1000 ? '${m.round()} m' : '${(m / 1000).toStringAsFixed(1)} km'}, '
                  'direction ${CarteScreenDirection.direction(ici, cible)}.';
      action = TextButton(
        onPressed: () => setState(() {
          _cible = null;
          _cibleNom = null;
        }),
        child: const Text('Arrêter'),
      );
    } else if (p == null) {
      texte = 'Indiquez ou tracez votre parcelle pour la voir sur la carte.';
      action = TextButton(onPressed: () => _ouvrir(const MesParcellesScreen()), child: const Text('Choisir'));
    } else {
      final n = _foyers.length;
      texte = _chargement
          ? 'Recherche des foyers proches…'
          : _foyersIndisponibles
              ? 'Foyers indisponibles pour l’instant (connexion).'
              : n == 0
                  ? 'Aucun foyer de maladie à moins de 10 km.'
                  : '$n foyer${n > 1 ? 's' : ''} de maladie à moins de 10 km.';
      if (!_membre && _serveur.configure && !_chargement) {
        action = TextButton(onPressed: () => _ouvrir(const ReseauScreen()), child: const Text('Partager'));
      }
    }
    return Material(
      elevation: 4,
      shadowColor: const Color(0x33000000),
      borderRadius: BorderRadius.circular(22),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 6, 6),
        child: Row(children: [
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(texte, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, height: 1.3)),
                if (_tuilesEnErreur)
                  const Text('Hors connexion : seules les zones déjà vues s’affichent.',
                      style: TextStyle(fontSize: 11.5, color: IvertColors.orange)),
              ],
            ),
          ),
          ?action,
        ]),
      ),
    );
  }

  Widget _pastilles() {
    final comptes = {
      Couche.parcelles: _tracees.length + (_parcelle == null ? 0 : 1),
      Couche.sentinelles: _arbres.length,
      Couche.diagnostics: _diagnostics.length,
      Couche.foyers: _foyers.length,
      Couche.lieux: _lieux.length,
    };
    const libelles = {
      Couche.parcelles: ('Parcelles', IvertColors.vert),
      Couche.sentinelles: ('Arbres', IvertColors.brunDoux),
      Couche.diagnostics: ('Diagnostics', IvertColors.rouge),
      Couche.foyers: ('Foyers', IvertColors.orange),
      Couche.lieux: ('Lieux', Color(0xFF5B4FA0)),
    };
    return ListView(
      scrollDirection: Axis.horizontal,
      children: [
        for (final c in Couche.values)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              showCheckmark: false,
              backgroundColor: Colors.white,
              selectedColor: Colors.white,
              elevation: 2,
              shadowColor: const Color(0x33000000),
              side: BorderSide(color: _visibles.contains(c) ? libelles[c]!.$2 : IvertColors.bord, width: 1.5),
              avatar: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: _visibles.contains(c) ? libelles[c]!.$2 : IvertColors.beige,
                  shape: BoxShape.circle,
                ),
              ),
              label: Text(
                '${libelles[c]!.$1} ${comptes[c]}',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: _visibles.contains(c) ? IvertColors.brun : IvertColors.brunDoux,
                ),
              ),
              selected: _visibles.contains(c),
              onSelected: (v) => setState(() {
                v ? _visibles.add(c) : _visibles.remove(c);
                if (!v) _selection = null;
              }),
            ),
          ),
      ],
    );
  }

  /// Fiche qui monte du bas : détails de l'élément touché et actions.
  Widget _fiche(_Element e) {
    late final String titre;
    late final String sousTitre;
    String? texte;
    Widget? image;
    var actions = <Widget>[];
    switch (e.type) {
      case _Type.parcelle:
        final p = e.donnee as Parcelle;
        final total = _tracees.fold<double>(0, (s, t) => s + t.surfaceHa);
        titre = 'Ma parcelle · ${p.localite.nom}';
        sousTitre = '${p.localite.region} · ${p.aGps ? 'position GPS' : 'centre de la localité'}';
        texte = _tracees.isEmpty
            ? 'Tracez le contour de vos parcelles pour connaître leur surface.'
            : '${_tracees.length} parcelle${_tracees.length > 1 ? 's' : ''} tracée${_tracees.length > 1 ? 's' : ''} · '
                '${total.toStringAsFixed(2)} ha au total. Rayon d’alerte : 10 km.';
        actions = [FilledButton.tonal(onPressed: () => _ouvrir(const MesParcellesScreen()), child: const Text('Mes parcelles'))];
      case _Type.tracee:
        final t = e.donnee as ParcelleTracee;
        titre = t.nom;
        sousTitre = '${t.culture == 'cacao' ? 'Cacao' : 'Anacarde'} · ${t.surfaceHa.toStringAsFixed(2)} ha';
        texte = 'Contour de ${t.points.length} points, tracé le ${DateFormat('d MMM yyyy', 'fr_FR').format(t.creeLe)}.';
        actions = [FilledButton.tonal(onPressed: () => _ouvrir(const MesParcellesScreen()), child: const Text('Mes parcelles'))];
      case _Type.arbre:
        final (c, n, _, r, repere) = e.donnee as _Arbre;
        titre = 'Arbre repère $n · ${c.label}';
        sousTitre = r == null
            ? 'Pas encore scanné cette semaine'
            : r.alerte
                ? 'À surveiller cette semaine'
                : r.aRefaire
                    ? 'Photo à refaire cette semaine'
                    : 'Sain cette semaine';
        texte = repere == null ? null : 'Repère : $repere';
        actions = [
          FilledButton.icon(
            onPressed: () => _ouvrir(PrescanScreen(cultureImposee: c, arbreSentinelle: n)),
            icon: const Icon(Iconsax.scan, size: 18),
            label: const Text('Scanner'),
          ),
          OutlinedButton.icon(
            onPressed: () => _yAller(e, 'l’arbre $n'),
            icon: const Icon(Iconsax.routing_2, size: 18),
            label: const Text('Y aller'),
          ),
        ];
      case _Type.diagnostic:
        final d = e.donnee as EntreeHistorique;
        titre = e.titre;
        sousTitre = '${d.culture.label} · ${DateFormat('d MMM yyyy, HH:mm', 'fr_FR').format(d.date)}';
        image = ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.file(
            File(d.photo),
            width: 64,
            height: 64,
            fit: BoxFit.cover,
            cacheWidth: 192,
            errorBuilder: (_, _, _) => Container(width: 64, height: 64, color: IvertColors.beige),
          ),
        );
        actions = [
          FilledButton.tonal(
            onPressed: () => _ouvrir(ResultatScreen.depuisHistorique(entree: d)),
            child: const Text('Voir le résultat'),
          ),
          OutlinedButton.icon(
            onPressed: () => _yAller(e, 'ce diagnostic'),
            icon: const Icon(Iconsax.routing_2, size: 18),
            label: const Text('Y aller'),
          ),
        ];
      case _Type.foyer:
        final f = e.donnee as Foyer;
        final p = _parcelle;
        final km = p == null ? null : ParcelleService.distanceKm(p.latitude, p.longitude, f.lat, f.lon);
        titre = '${e.titre} · ${f.culture.label}';
        sousTitre = '${f.confirme ? 'Confirmé' : 'Signalé, non confirmé'} · ${f.nbComptes} producteurs'
            '${km == null ? '' : ' · ${km < 1 ? 'moins d’1' : km.round()} km'}';
        texte = 'Position arrondie à ≈ 1 km. Inspectez vos arbres et contactez l’ANADER. '
            'N’arrachez jamais sans consigne officielle.';
      case _Type.lieu:
        final l = e.donnee as Lieu;
        titre = l.nom;
        sousTitre = '${l.libelle} · OpenStreetMap';
        actions = [
          OutlinedButton.icon(
            onPressed: () => _yAller(e, l.nom),
            icon: const Icon(Iconsax.routing_2, size: 18),
            label: const Text('Y aller'),
          ),
        ];
    }
    return Material(
      elevation: 8,
      shadowColor: const Color(0x44000000),
      borderRadius: BorderRadius.circular(24),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 6, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(color: IvertColors.bord, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (image != null) ...[image, const SizedBox(width: 12)] else
                  Container(
                    width: 12,
                    height: 12,
                    margin: const EdgeInsets.only(top: 5, right: 10),
                    decoration: BoxDecoration(color: _couleur(e), shape: BoxShape.circle),
                  ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(titre, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 2),
                      Text(sousTitre, style: const TextStyle(fontSize: 12.5, color: IvertColors.brunDoux)),
                      if (texte != null) ...[
                        const SizedBox(height: 6),
                        Text(texte, style: const TextStyle(fontSize: 12.5, height: 1.4)),
                      ],
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => setState(() => _selection = null),
                  icon: const Icon(Icons.close, size: 20),
                  tooltip: 'Fermer',
                ),
              ],
            ),
            if (actions.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 8, children: actions),
            ],
          ],
        ),
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

/// Point de la carte : rond coloré avec une icône ou un numéro.
class _Rond extends StatelessWidget {
  const _Rond({required this.couleur, this.icone, this.texte, required this.libelle, this.choisi = false});

  final Color couleur;
  final IconData? icone;
  final String? texte;
  final String libelle;
  final bool choisi;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: libelle,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: couleur,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: choisi ? 4 : 3),
          boxShadow: [
            BoxShadow(
              color: choisi ? couleur.withValues(alpha: 0.5) : const Color(0x40000000),
              blurRadius: choisi ? 14 : 6,
              spreadRadius: choisi ? 3 : 0,
            ),
          ],
        ),
        child: texte != null
            ? Text(texte!, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14))
            : Icon(icone ?? Iconsax.location, color: Colors.white, size: choisi ? 22 : 18),
      ),
    );
  }
}

/// Groupe de points proches : bulle avec le nombre d'éléments.
class _Bulle extends StatelessWidget {
  const _Bulle({required this.nombre, required this.couleur});

  final int nombre;
  final Color couleur;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$nombre éléments, toucher pour zoomer',
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          border: Border.all(color: couleur, width: 4),
          boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 8)],
        ),
        child: Text('$nombre', style: TextStyle(color: couleur, fontWeight: FontWeight.w900, fontSize: 16)),
      ),
    );
  }
}

/// Bouton rond flottant (retour, ma position, ma parcelle, satellite, boussole).
class _BoutonRond extends StatelessWidget {
  const _BoutonRond({this.icone, this.enfant, required this.libelle, required this.onTap, this.couleur = IvertColors.vert});

  final IconData? icone;
  final Widget? enfant;
  final String libelle;
  final VoidCallback onTap;
  final Color couleur;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: libelle,
      child: Material(
        color: Colors.white,
        shape: const CircleBorder(),
        elevation: 4,
        shadowColor: const Color(0x44000000),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(width: 48, height: 48, child: Center(child: enfant ?? Icon(icone, color: couleur))),
        ),
      ),
    );
  }
}
