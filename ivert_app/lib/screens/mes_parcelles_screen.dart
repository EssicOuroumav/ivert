import 'package:flutter/material.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

import '../services/parcelle_service.dart';
import '../theme/app_theme.dart';
import '../widgets/communs.dart';
import 'parcelle_screen.dart';
import 'trace_screen.dart';

/// Mes parcelles : la parcelle de référence (localité ou GPS) et les parcelles tracées, avec leur surface.
class MesParcellesScreen extends StatefulWidget {
  const MesParcellesScreen({super.key});

  @override
  State<MesParcellesScreen> createState() => _MesParcellesScreenState();
}

class _MesParcellesScreenState extends State<MesParcellesScreen> {
  Parcelle? _reference;
  List<ParcelleTracee> _tracees = [];

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    final r = await ParcelleService.instance.lire();
    final t = await ParcelleService.instance.tracees();
    if (mounted) {
      setState(() {
        _reference = r;
        _tracees = t;
      });
    }
  }

  Future<void> _ouvrir(Widget ecran) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ecran));
    _charger();
  }

  bool _estReference(ParcelleTracee t) {
    final r = _reference;
    if (r == null || !r.aGps) return false;
    final (la, lo) = t.centre;
    return (r.latitude - la).abs() < 1e-6 && (r.longitude - lo).abs() < 1e-6;
  }

  Future<void> _supprimer(ParcelleTracee t) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Supprimer « ${t.nom} » ?'),
        content: const Text('Le contour sera effacé de ce téléphone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annuler')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Supprimer')),
        ],
      ),
    );
    if (ok != true) return;
    await ParcelleService.instance.supprimerTracee(t.id);
    _charger();
  }

  @override
  Widget build(BuildContext context) {
    final r = _reference;
    final total = _tracees.fold<double>(0, (s, t) => s + t.surfaceHa);
    return Scaffold(
      appBar: AppBar(title: const Text('Mes parcelles')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
        children: [
          const TitreSection('Parcelle de référence'),
          Carte(
            onTap: () => _ouvrir(const ParcelleScreen()),
            child: Row(
              children: [
                const Icon(Iconsax.location_copy, color: IvertColors.vert),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(r == null ? 'Aucune parcelle choisie' : r.localite.nom,
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                      Text(
                        r == null
                            ? 'Elle sert à la météo, aux alertes et à la carte.'
                            : '${r.localite.region} · ${r.aGps ? 'position GPS' : 'centre de la localité'} · météo et alertes',
                        style: const TextStyle(fontSize: 12, color: IvertColors.brunDoux),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Text('Modifier', style: TextStyle(fontWeight: FontWeight.w700, color: IvertColors.vert)),
              ],
            ),
          ),
          const SizedBox(height: 20),
          TitreSection(_tracees.isEmpty ? 'Tracer une parcelle' : 'Parcelles tracées · ${total.toStringAsFixed(2)} ha au total'),
          for (final t in _tracees)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Carte(
                onTap: () async {
                  await ParcelleService.instance.activer(t);
                  _charger();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('« ${t.nom} » sert maintenant à la météo et aux alertes.')),
                    );
                  }
                },
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(color: IvertColors.vertFond, borderRadius: BorderRadius.circular(12)),
                      child: const Icon(Iconsax.map_1_copy, color: IvertColors.vert),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(t.nom, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                          Text(
                            '${t.culture == 'cacao' ? 'Cacao' : 'Anacarde'} · ${t.surfaceHa.toStringAsFixed(2)} ha · ${t.points.length} points',
                            style: const TextStyle(fontSize: 12, color: IvertColors.brunDoux),
                          ),
                          if (_estReference(t)) ...[
                            const SizedBox(height: 4),
                            const Pastille('Référence pour la météo'),
                          ],
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => _supprimer(t),
                      icon: const Icon(Iconsax.trash_copy, color: IvertColors.brunDoux),
                      tooltip: 'Supprimer',
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: () => _ouvrir(const TraceScreen(enMarchant: true)),
            icon: const Icon(Iconsax.routing_2_copy),
            label: const Text('Tracer en marchant (GPS)'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () => _ouvrir(const TraceScreen(enMarchant: false)),
            icon: const Icon(Iconsax.finger_cricle_copy),
            label: const Text('Tracer sur la carte'),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          ),
          const SizedBox(height: 14),
          const Text(
            'En marchant, la surface est précise à quelques mètres près selon le GPS du téléphone. '
            'Les contours restent sur ce téléphone : ils ne sont jamais envoyés.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11.5, height: 1.4, color: IvertColors.brunDoux),
          ),
        ],
      ),
    );
  }
}
