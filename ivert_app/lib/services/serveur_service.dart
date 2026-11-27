import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'diagnostic_service.dart';
import 'parcelle_service.dart';

/// Adresse et clé PUBLIQUE du projet Supabase, fournies à la compilation :
///   flutter run --dart-define-from-file=.env.test
/// Sans elles, l'app fonctionne entièrement hors ligne et masque les alertes de voisinage.
const _url = String.fromEnvironment('SUPABASE_URL');
const _cle = String.fromEnvironment('SUPABASE_ANON_KEY');

/// Un foyer : au moins 3 producteurs ont signalé la même maladie près d'ici (calculé par le serveur).
class Foyer {
  Foyer.fromJson(Map<String, dynamic> j)
      : culture = Culture.values.byName(j['culture'] as String),
        maladie = j['maladie'] as String,
        lat = (j['lat'] as num).toDouble(),
        lon = (j['lon'] as num).toDouble(),
        nbComptes = j['nb_comptes'] as int,
        dernierLe = DateTime.parse(j['dernier_le'] as String),
        confirme = j['statut'] == 'confirme';

  final Culture culture;
  final String maladie;
  final double lat;
  final double lon;
  final int nbComptes;
  final DateTime dernierLe;
  final bool confirme;
}

/// Lien avec le serveur des alertes de voisinage (Supabase).
/// Règles : docs/SECURITE.md. Rien n'est envoyé sans connexion ET consentement ;
/// jamais de photo ; position arrondie à 0,01° (≈ 1 km) avant l'envoi.
class ServeurService {
  ServeurService._();

  static final instance = ServeurService._();
  static const _cleFile = 'signalements_en_attente';

  bool get configure => _url.isNotEmpty && _cle.isNotEmpty;
  bool _pret = false;

  SupabaseClient get _db => Supabase.instance.client;

  Future<void> initialiser() async {
    if (!configure || _pret) return;
    await Supabase.initialize(url: _url, publishableKey: _cle);
    _pret = true;
  }

  bool get connecte => _pret && _db.auth.currentSession != null;

  /// Numéro ivoirien à 10 chiffres → format international (+225…). `null` si invalide.
  static String? numeroInternational(String saisie) {
    final chiffres = saisie.replaceAll(RegExp(r'\D'), '');
    final local = chiffres.startsWith('225') && chiffres.length == 13 ? chiffres.substring(3) : chiffres;
    return RegExp(r'^0[157]\d{8}$').hasMatch(local) ? '+225$local' : null;
  }

  Future<void> envoyerCode(String numero) => _db.auth.signInWithOtp(phone: numero, shouldCreateUser: true);

  Future<void> verifierCode(String numero, String code) =>
      _db.auth.verifyOTP(phone: numero, token: code.trim(), type: OtpType.sms);

  Future<void> deconnecter() => _db.auth.signOut();

  /// Consentement au partage : `null` si non donné (ou pas de profil).
  Future<DateTime?> consentement() async {
    if (!connecte) return null;
    final r = await _db.from('profils').select('consentement_le').maybeSingle();
    final v = r?['consentement_le'] as String?;
    return v == null ? null : DateTime.parse(v);
  }

  Future<void> donnerConsentement({String? localite}) => _db.from('profils').upsert({
        'id': _db.auth.currentUser!.id,
        'localite': localite,
        'consentement_le': DateTime.now().toUtc().toIso8601String(),
        'maj_le': DateTime.now().toUtc().toIso8601String(),
      });

  /// Retire le consentement et efface tous mes signalements du serveur.
  Future<void> retirerConsentement() async {
    await _db.from('signalements').delete().eq('user_id', _db.auth.currentUser!.id);
    await _db.from('profils').update({'consentement_le': null, 'maj_le': DateTime.now().toUtc().toIso8601String()}).eq(
        'id', _db.auth.currentUser!.id);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_cleFile);
  }

  /// Après un diagnostic : met le signalement en file (envoyé plus tard si hors connexion).
  /// Seuls les diagnostics « certain » ou « probable » d'une maladie sont partagés.
  Future<void> signalerSiAutorise(Diagnostic d) async {
    if (!connecte) return;
    if (d.niveau != Niveau.certain && d.niveau != Niveau.probable) return;
    if (d.classe == 'sain' || d.classe == 'autre') return;
    final p = await ParcelleService.instance.lire();
    if (p == null) return;
    final aujourdhui = DateTime.now();
    final element = {
      'culture': d.culture.name,
      'maladie': d.classe,
      'niveau': d.niveau.name,
      'lat': arrondir(p.latitude),
      'lon': arrondir(p.longitude),
      'observe_le':
          '${aujourdhui.year}-${aujourdhui.month.toString().padLeft(2, '0')}-${aujourdhui.day.toString().padLeft(2, '0')}',
    };
    final prefs = await SharedPreferences.getInstance();
    final file = [...?prefs.getStringList(_cleFile), jsonEncode(element)];
    await prefs.setStringList(_cleFile, file);
    await envoyerEnAttente();
  }

  /// Arrondi à 0,01° (≈ 1,1 km), comme l'impose la base.
  static double arrondir(double v) => (v * 100).round() / 100;

  Future<int> nombreEnAttente() async =>
      ((await SharedPreferences.getInstance()).getStringList(_cleFile) ?? const []).length;

  /// Envoie la file. Erreur réseau : on garde pour plus tard. Doublon, données trop anciennes,
  /// limite journalière ou consentement retiré : le serveur refuse définitivement, on retire de la file.
  Future<int> envoyerEnAttente() async {
    if (!connecte) return 0;
    final prefs = await SharedPreferences.getInstance();
    final file = prefs.getStringList(_cleFile) ?? const [];
    final restants = <String>[];
    var envoyes = 0;
    for (final brut in file) {
      try {
        await _db.from('signalements').insert(jsonDecode(brut) as Map<String, dynamic>);
        envoyes++;
      } on PostgrestException catch (e) {
        debugPrint('Signalement refusé par le serveur (${e.code}), retiré de la file');
      } catch (_) {
        restants.add(brut); // pas de réseau : on réessaiera
      }
    }
    await prefs.setStringList(_cleFile, restants);
    return envoyes;
  }

  /// Foyers à moins de [rayonKm] km de la parcelle (10 km par défaut, décision du propriétaire).
  /// Visibles par tous, même sans compte (migration 003) : un foyer est déjà anonyme.
  Future<List<Foyer>> foyersProches(Parcelle p, {double rayonKm = 10}) async {
    if (!_pret) return const [];
    final r = await _db.rpc('foyers_publics',
        params: {'p_lat': p.latitude, 'p_lon': p.longitude, 'p_rayon_km': rayonKm}) as List;
    return [for (final f in r) Foyer.fromJson(f as Map<String, dynamic>)];
  }
}
