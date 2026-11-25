import 'package:flutter/material.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/parcelle_service.dart';
import '../services/serveur_service.dart';
import '../theme/app_theme.dart';
import '../widgets/communs.dart';

/// Rejoindre le réseau d'alerte : numéro + code SMS, puis consentement explicite.
/// Rend `true` quand le producteur est connecté ET a donné son accord.
class ReseauScreen extends StatefulWidget {
  const ReseauScreen({super.key});

  @override
  State<ReseauScreen> createState() => _ReseauScreenState();
}

enum _Etape { numero, code, consentement }

class _ReseauScreenState extends State<ReseauScreen> {
  final _numero = TextEditingController();
  final _code = TextEditingController();
  late _Etape _etape = ServeurService.instance.connecte ? _Etape.consentement : _Etape.numero;
  String? _international;
  bool _accord = false;
  bool _occupe = false;
  String? _erreur;

  @override
  void dispose() {
    _numero.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _faire(Future<void> Function() action) async {
    setState(() {
      _occupe = true;
      _erreur = null;
    });
    try {
      await action();
    } on AuthException catch (e) {
      setState(() => _erreur = _messageAuth(e));
    } catch (_) {
      setState(() => _erreur = 'Connexion impossible. Vérifiez votre réseau et réessayez.');
    } finally {
      if (mounted) setState(() => _occupe = false);
    }
  }

  String _messageAuth(AuthException e) {
    final m = e.message.toLowerCase();
    if (m.contains('expired') || m.contains('invalid')) return 'Code incorrect ou expiré. Redemandez un code.';
    if (m.contains('rate') || m.contains('too many') || e.statusCode == '429') {
      return 'Trop de demandes. Patientez quelques minutes avant de redemander un code.';
    }
    if (m.contains('phone') && m.contains('disabled') || m.contains('provider')) {
      return 'La connexion par SMS n’est pas encore activée sur le serveur.';
    }
    return 'Connexion refusée. Réessayez dans un instant.';
  }

  Future<void> _envoyerCode() async {
    final n = ServeurService.numeroInternational(_numero.text);
    if (n == null) {
      setState(() => _erreur = 'Entrez un numéro ivoirien à 10 chiffres (ex. 07 01 02 03 04).');
      return;
    }
    await _faire(() async {
      await ServeurService.instance.envoyerCode(n);
      setState(() {
        _international = n;
        _etape = _Etape.code;
      });
    });
  }

  Future<void> _verifier() async {
    if (_code.text.trim().length < 6) {
      setState(() => _erreur = 'Entrez le code à 6 chiffres reçu par SMS.');
      return;
    }
    await _faire(() async {
      await ServeurService.instance.verifierCode(_international!, _code.text);
      if (await ServeurService.instance.consentement() != null) {
        if (mounted) Navigator.of(context).pop(true);
        return;
      }
      setState(() => _etape = _Etape.consentement);
    });
  }

  Future<void> _consentir() async {
    await _faire(() async {
      final p = await ParcelleService.instance.lire();
      await ServeurService.instance.donnerConsentement(localite: p?.localite.nom);
      await ServeurService.instance.envoyerEnAttente();
      if (mounted) Navigator.of(context).pop(true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Réseau d’alerte')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            ...switch (_etape) {
              _Etape.numero => _vueNumero(),
              _Etape.code => _vueCode(),
              _Etape.consentement => _vueConsentement(),
            },
            if (_erreur != null) ...[
              const SizedBox(height: 12),
              Text(_erreur!, style: const TextStyle(fontSize: 13, color: IvertColors.rouge)),
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> _vueNumero() => [
        const Text('Prévenez vos voisins, soyez prévenu',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        const Text(
          'Quand plusieurs producteurs signalent la même maladie près de chez vous, IVERT vous alerte. '
          'Connectez-vous avec votre numéro de téléphone : vous recevrez un code par SMS.',
          style: TextStyle(fontSize: 13, height: 1.45, color: IvertColors.brunDoux),
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _numero,
          keyboardType: TextInputType.phone,
          autofillHints: const [AutofillHints.telephoneNumberNational],
          decoration: _champ('Numéro de téléphone', prefixe: '+225 '),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _occupe ? null : _envoyerCode,
          child: Text(_occupe ? 'Envoi…' : 'Recevoir le code'),
        ),
      ];

  List<Widget> _vueCode() => [
        const Text('Entrez le code reçu', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Text('Un code à 6 chiffres a été envoyé au $_international.',
            style: const TextStyle(fontSize: 13, color: IvertColors.brunDoux)),
        const SizedBox(height: 20),
        TextField(
          controller: _code,
          keyboardType: TextInputType.number,
          maxLength: 6,
          autofillHints: const [AutofillHints.oneTimeCode],
          decoration: _champ('Code à 6 chiffres'),
        ),
        const SizedBox(height: 8),
        FilledButton(onPressed: _occupe ? null : _verifier, child: Text(_occupe ? 'Vérification…' : 'Valider')),
        TextButton(
          onPressed: _occupe
              ? null
              : () => setState(() {
                    _etape = _Etape.numero;
                    _code.clear();
                  }),
          child: const Text('Changer de numéro ou redemander un code'),
        ),
      ];

  List<Widget> _vueConsentement() => [
        const Text('Votre accord', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        const Carte(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Ligne(Iconsax.tick_circle_copy, 'Partagé : la culture, la maladie trouvée et la date.'),
              _Ligne(Iconsax.location_copy, 'Position arrondie à environ 1 km, jamais l’emplacement exact.'),
              _Ligne(Iconsax.close_circle_copy, 'Jamais partagé : vos photos, votre nom, votre numéro.'),
              _Ligne(Iconsax.people_copy, 'Les autres voient seulement des foyers d’au moins 3 producteurs.'),
              _Ligne(Iconsax.trash_copy, 'Vous pouvez retirer votre accord à tout moment : vos signalements sont alors effacés.'),
            ],
          ),
        ),
        const SizedBox(height: 12),
        CheckboxListTile(
          value: _accord,
          onChanged: (v) => setState(() => _accord = v ?? false),
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          title: const Text('J’accepte de partager mes diagnostics de maladie, de façon anonyme, pour alerter les producteurs proches.',
              style: TextStyle(fontSize: 13, height: 1.4)),
        ),
        const SizedBox(height: 8),
        FilledButton(onPressed: !_accord || _occupe ? null : _consentir, child: const Text('Rejoindre le réseau')),
      ];

  InputDecoration _champ(String label, {String? prefixe}) => InputDecoration(
        labelText: label,
        prefixText: prefixe,
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(IvertRadius.carte), borderSide: const BorderSide(color: IvertColors.bord)),
      );
}

class _Ligne extends StatelessWidget {
  const _Ligne(this.icone, this.texte);

  final IconData icone;
  final String texte;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icone, size: 18, color: IvertColors.vert),
            const SizedBox(width: 10),
            Expanded(child: Text(texte, style: const TextStyle(fontSize: 13, height: 1.4))),
          ],
        ),
      );
}
