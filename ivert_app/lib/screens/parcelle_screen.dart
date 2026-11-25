import 'package:flutter/material.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

import '../services/parcelle_service.dart';
import '../theme/app_theme.dart';
import '../widgets/communs.dart';

/// Emplacement de la parcelle : localité dans une liste (par défaut), GPS en option.
class ParcelleScreen extends StatefulWidget {
  const ParcelleScreen({super.key});

  @override
  State<ParcelleScreen> createState() => _ParcelleScreenState();
}

class _ParcelleScreenState extends State<ParcelleScreen> {
  List<Localite> _localites = [];
  Localite? _choisie;
  double? _lat;
  double? _lon;
  String _filtre = '';
  bool _gpsEnCours = false;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    final liste = await ParcelleService.instance.localites();
    final p = await ParcelleService.instance.lire();
    if (!mounted) return;
    setState(() {
      _localites = liste;
      _choisie = p?.localite;
      _lat = p?.lat;
      _lon = p?.lon;
    });
  }

  Future<void> _gps() async {
    setState(() => _gpsEnCours = true);
    try {
      final (loc, pos) = await ParcelleService.instance.positionGps();
      if (!mounted) return;
      setState(() {
        _choisie = loc;
        _lat = pos.latitude;
        _lon = pos.longitude;
      });
    } catch (e) {
      if (!mounted) return;
      final message = e is StateError ? e.message : 'Position introuvable. Choisissez votre localité dans la liste.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) setState(() => _gpsEnCours = false);
    }
  }

  Future<void> _enregistrer() async {
    final loc = _choisie;
    if (loc == null) return;
    await ParcelleService.instance.enregistrer(loc, lat: _lat, lon: _lon);
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final f = _filtre.toLowerCase();
    final visibles =
        _localites.where((l) => f.isEmpty || l.nom.toLowerCase().contains(f) || l.region.toLowerCase().contains(f));
    return Scaffold(
      appBar: AppBar(title: const Text('Ma parcelle')),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Où se trouve votre parcelle ? Elle sert à la météo et aux conseils de votre zone.',
                      style: TextStyle(fontSize: 13, height: 1.4, color: IvertColors.brunDoux)),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _gpsEnCours ? null : _gps,
                    icon: _gpsEnCours
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Iconsax.gps_copy),
                    label: Text(_lat != null ? 'Position GPS enregistrée · actualiser' : 'Utiliser ma position GPS (facultatif)'),
                  ),
                  if (_lat != null) ...[
                    const SizedBox(height: 6),
                    TextButton(
                      onPressed: () => setState(() {
                        _lat = null;
                        _lon = null;
                      }),
                      child: const Text('Ne pas garder ma position GPS'),
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextField(
                    onChanged: (v) => setState(() => _filtre = v),
                    decoration: InputDecoration(
                      hintText: 'Rechercher une ville ou une région',
                      prefixIcon: const Icon(Iconsax.search_normal_copy),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(IvertRadius.carte),
                          borderSide: const BorderSide(color: IvertColors.bord)),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                children: [
                  for (final l in visibles)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Carte(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        couleur: l.id == _choisie?.id ? IvertColors.vertFond : null,
                        onTap: () => setState(() {
                          _choisie = l;
                          // Une localité choisie à la main ne correspond plus forcément au GPS
                          if (_lat != null && ParcelleService.plusProche(_localites, _lat!, _lon!).id != l.id) {
                            _lat = null;
                            _lon = null;
                          }
                        }),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(l.nom, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                                  Text(l.region, style: const TextStyle(fontSize: 12, color: IvertColors.brunDoux)),
                                ],
                              ),
                            ),
                            Icon(l.id == _choisie?.id ? Icons.check_circle : Icons.radio_button_unchecked,
                                color: l.id == _choisie?.id ? IvertColors.vert : IvertColors.bord),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: FilledButton(
                onPressed: _choisie == null ? null : _enregistrer,
                child: Text(_choisie == null ? 'Choisissez une localité' : 'Enregistrer : ${_choisie!.nom}'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
