import 'package:flutter/material.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import 'package:intl/intl.dart';

import '../services/meteo_service.dart';
import '../services/parcelle_service.dart';

/// Barre verte de l'accueil : la météo de la parcelle en un coup d'œil, et s'il est
/// raisonnable de traiter maintenant (pas de pluie dans les 6 prochaines heures).
/// Les faits ici ; le conseil (risque de maladie) est dans la carte juste en dessous.
class EnteteMeteo extends StatefulWidget {
  const EnteteMeteo({super.key, required this.version, required this.onParcelle});

  final int version;
  final VoidCallback onParcelle;

  @override
  State<EnteteMeteo> createState() => _EnteteMeteoState();
}

class _EnteteMeteoState extends State<EnteteMeteo> {
  Parcelle? _parcelle;
  MeteoJours? _meteo;
  bool _charge = false;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  @override
  void didUpdateWidget(EnteteMeteo ancien) {
    super.didUpdateWidget(ancien);
    if (ancien.version != widget.version) _charger();
  }

  Future<void> _charger() async {
    final p = await ParcelleService.instance.lire();
    final m = p == null ? null : await MeteoService.instance.meteo(p);
    if (mounted) {
      setState(() {
        _parcelle = p;
        _meteo = m;
        _charge = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    const blanc = TextStyle(color: Colors.white);
    final p = _parcelle;
    final m = _meteo;
    final maintenant = DateTime.now().toUtc(); // heure d'Abidjan = UTC
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Bonjour 👋', style: blanc.copyWith(fontSize: 22, fontWeight: FontWeight.w800)),
            const Spacer(),
            if (p != null)
              InkWell(
                onTap: widget.onParcelle,
                borderRadius: BorderRadius.circular(20),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  child: Row(children: [
                    const Icon(Iconsax.location_copy, color: Colors.white, size: 16),
                    const SizedBox(width: 4),
                    Text(p.localite.nom, style: blanc.copyWith(fontSize: 13, fontWeight: FontWeight.w600)),
                  ]),
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        if (p == null)
          InkWell(
            onTap: widget.onParcelle,
            child: Text('Indiquez votre parcelle pour voir la météo et le bon moment pour traiter →',
                style: blanc.copyWith(fontSize: 13, color: const Color(0xDDFFFFFF))),
          )
        else if (m == null)
          Text(_charge ? 'Météo indisponible : connectez-vous une fois à internet.' : 'Récupération de la météo…',
              style: blanc.copyWith(fontSize: 13, color: const Color(0xDDFFFFFF)))
        else ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (m.tempActuelle != null)
                Text('${m.tempActuelle!.round()}°', style: blanc.copyWith(fontSize: 34, fontWeight: FontWeight.w800, height: 1)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Pluie aujourd’hui : ${(m.pluieDuJour(DateFormat('yyyy-MM-dd').format(maintenant)) ?? 0).toStringAsFixed(0)} mm'
                  '${m.humidite.isNotEmpty ? ' · humidité ${_humiditeDuJour(m, maintenant).round()} %' : ''}',
                  style: blanc.copyWith(fontSize: 13, color: const Color(0xEEFFFFFF)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _traitement(m, maintenant),
          if (DateTime.now().difference(m.recue).inHours >= 6)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('Météo du ${DateFormat('d MMM à HH:mm', 'fr_FR').format(m.recue)} (hors connexion)',
                  style: blanc.copyWith(fontSize: 11, color: const Color(0xBBFFFFFF))),
            ),
        ],
      ],
    );
  }

  double _humiditeDuJour(MeteoJours m, DateTime maintenant) {
    final i = m.dates.indexOf(DateFormat('yyyy-MM-dd').format(maintenant));
    return i < 0 || i >= m.humidite.length ? 0 : m.humidite[i];
  }

  Widget _traitement(MeteoJours m, DateTime maintenant) {
    final (IconData icone, String texte, Color fond) = switch (MeteoService.fenetreTraitement(m, maintenant)) {
      FenetreTraitement.favorable => (Iconsax.tick_circle, 'Bon moment pour traiter : pas de pluie prévue dans les 6 h', const Color(0x33FFFFFF)),
      FenetreTraitement.pluieProche => (Iconsax.cloud_drizzle, 'Pluie prévue dans les 6 h : reportez le traitement', const Color(0x55B85A00)),
      FenetreTraitement.nuit => (Iconsax.moon, 'Traitement : attendez demain matin', const Color(0x33FFFFFF)),
      FenetreTraitement.inconnue => (Iconsax.info_circle, 'Traitement : météo des prochaines heures inconnue', const Color(0x22FFFFFF)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: fond, borderRadius: BorderRadius.circular(12)),
      child: Row(children: [
        Icon(icone, color: Colors.white, size: 18),
        const SizedBox(width: 8),
        Expanded(child: Text(texte, style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600))),
      ]),
    );
  }
}
