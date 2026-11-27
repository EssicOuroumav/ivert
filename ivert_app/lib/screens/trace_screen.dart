import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import 'package:latlong2/latlong.dart';

import '../services/parcelle_service.dart';
import '../services/fond_carte.dart';
import '../theme/app_theme.dart';

/// Tracer le contour d'une parcelle : en marchant autour avec le GPS, ou en touchant la carte.
class TraceScreen extends StatefulWidget {
  const TraceScreen({super.key, required this.enMarchant});

  final bool enMarchant;

  @override
  State<TraceScreen> createState() => _TraceScreenState();
}

class _TraceScreenState extends State<TraceScreen> {
  final _carte = MapController();
  final List<LatLng> _points = [];
  StreamSubscription<Position>? _flux;
  LatLng? _ici;
  double? _precision;
  String? _erreur;
  bool _pret = false;
  LatLng _centre = const LatLng(7.54, -5.55);

  @override
  void initState() {
    super.initState();
    _demarrer();
  }

  Future<void> _demarrer() async {
    final p = await ParcelleService.instance.lire();
    if (p != null) _centre = LatLng(p.latitude, p.longitude);
    if (mounted) setState(() => _pret = true);
    if (!widget.enMarchant) return;
    try {
      await ParcelleService.instance.positionGps(); // vérifie et demande l'autorisation
      _flux = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.best, distanceFilter: 3),
      ).listen((pos) {
        final pt = LatLng(pos.latitude, pos.longitude);
        setState(() {
          _ici = pt;
          _precision = pos.accuracy;
          // On n'ajoute un point que si la position est assez précise (moins de 15 m)
          if (pos.accuracy <= 15) _points.add(pt);
        });
        _carte.move(pt, 18);
      }, onError: (Object e) => setState(() => _erreur = 'GPS indisponible : $e'));
    } on StateError catch (e) {
      setState(() => _erreur = e.message);
    }
  }

  @override
  void dispose() {
    _flux?.cancel();
    super.dispose();
  }

  List<(double, double)> get _pts => [for (final p in _points) (p.latitude, p.longitude)];

  Future<void> _terminer() async {
    _flux?.pause();
    final nom = TextEditingController(text: 'Parcelle ${DateTime.now().day}/${DateTime.now().month}');
    var culture = 'cacao';
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: const Text('Enregistrer la parcelle'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Surface : ${ParcelleService.surfaceHa(_pts).toStringAsFixed(2)} ha'),
              const SizedBox(height: 12),
              TextField(controller: nom, decoration: const InputDecoration(labelText: 'Nom de la parcelle')),
              const SizedBox(height: 12),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'cacao', label: Text('Cacao')),
                  ButtonSegment(value: 'anacarde', label: Text('Anacarde')),
                ],
                selected: {culture},
                onSelectionChanged: (s) => set(() => culture = s.first),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Continuer')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Enregistrer')),
          ],
        ),
      ),
    );
    if (ok != true) {
      _flux?.resume();
      return;
    }
    await ParcelleService.instance.ajouterTracee(nom.text.trim().isEmpty ? 'Ma parcelle' : nom.text.trim(), culture, _pts);
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final surface = ParcelleService.surfaceHa(_pts);
    return Scaffold(
      appBar: AppBar(title: Text(widget.enMarchant ? 'Tracer en marchant' : 'Tracer sur la carte')),
      body: !_pret
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                FlutterMap(
                  mapController: _carte,
                  options: MapOptions(
                    initialCenter: _centre,
                    initialZoom: 16,
                    maxZoom: 19,
                    interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
                    onTap: widget.enMarchant ? null : (_, pt) => setState(() => _points.add(pt)),
                  ),
                  children: [
                    FondCarte.couche(satellite: FondCarte.satelliteDisponible),
                    if (_points.length >= 3)
                      PolygonLayer(polygons: [
                        Polygon(
                          points: _points,
                          color: const Color(0x332E6B3A),
                          borderColor: IvertColors.vert,
                          borderStrokeWidth: 2.5,
                        ),
                      ])
                    else if (_points.length == 2)
                      PolylineLayer(polylines: [Polyline(points: _points, color: IvertColors.vert, strokeWidth: 2.5)]),
                    MarkerLayer(markers: [
                      for (final p in _points)
                        Marker(
                          point: p,
                          width: 14,
                          height: 14,
                          child: Container(
                            decoration: BoxDecoration(
                              color: IvertColors.vert,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                          ),
                        ),
                      if (_ici != null)
                        Marker(
                          point: _ici!,
                          width: 22,
                          height: 22,
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.blue,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 3),
                            ),
                          ),
                        ),
                    ]),
                    FondCarte.mention(satellite: FondCarte.satelliteDisponible),
                  ],
                ),
                Positioned(
                  left: 12,
                  right: 12,
                  top: 12,
                  child: Material(
                    elevation: 3,
                    borderRadius: BorderRadius.circular(16),
                    color: Colors.white,
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _erreur ??
                                (widget.enMarchant
                                    ? 'Faites le tour de la parcelle à pied, en longeant la limite. Un point est ajouté tous les 3 m.'
                                    : 'Touchez la carte à chaque coin de la parcelle, dans l’ordre.'),
                            style: TextStyle(fontSize: 13, height: 1.4, color: _erreur == null ? IvertColors.brun : IvertColors.rouge),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${_points.length} point${_points.length > 1 ? 's' : ''}'
                            '${_points.length >= 3 ? ' · ${surface.toStringAsFixed(2)} ha' : ''}'
                            '${_precision != null ? ' · précision GPS ${_precision!.round()} m' : ''}',
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: 24,
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(backgroundColor: Colors.white, minimumSize: const Size.fromHeight(50)),
                          onPressed: _points.isEmpty ? null : () => setState(_points.removeLast),
                          icon: const Icon(Iconsax.undo_copy),
                          label: const Text('Annuler le point'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                          onPressed: _points.length < 3 ? null : _terminer,
                          icon: const Icon(Iconsax.tick_circle_copy),
                          label: const Text('Terminer'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
