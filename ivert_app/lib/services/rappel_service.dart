import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Réglage du rappel de tournée sentinelle.
class ReglageRappel {
  const ReglageRappel({required this.actif, required this.jour, required this.heure});

  final bool actif;
  final int jour; // 1 = lundi … 7 = dimanche
  final int heure; // 5 à 19 h

  static const jours = ['lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi', 'dimanche'];
  String get libelle => 'chaque ${jours[jour - 1]} à $heure h';
}

/// Rappel hebdomadaire de la tournée sentinelle : une notification sur le téléphone,
/// sans internet ni serveur. Heure d'Abidjan (UTC, sans heure d'été).
class RappelService {
  RappelService._();

  static final instance = RappelService._();
  static const _id = 4801;
  final _notifs = FlutterLocalNotificationsPlugin();
  bool _pret = false;

  Future<void> _initialiser() async {
    if (_pret) return;
    tzdata.initializeTimeZones();
    await _notifs.initialize(
      const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')),
    );
    _pret = true;
  }

  Future<ReglageRappel> lire() async {
    final p = await SharedPreferences.getInstance();
    return ReglageRappel(
      actif: p.getBool('rappel_actif') ?? false,
      jour: p.getInt('rappel_jour') ?? 1,
      heure: p.getInt('rappel_heure') ?? 7,
    );
  }

  /// Active ou modifie le rappel. Renvoie `false` si le producteur refuse les notifications.
  Future<bool> programmer(int jour, int heure) async {
    await _initialiser();
    final android = _notifs.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    final autorise = await android?.requestNotificationsPermission() ?? true;
    if (!autorise) return false;
    await _notifs.cancel(_id);
    await _notifs.zonedSchedule(
      _id,
      'Tournée sentinelle de la semaine',
      'C’est le jour de scanner vos arbres repères : environ 15 minutes pour protéger votre parcelle.',
      prochaine(jour, heure, tz.TZDateTime.now(tz.getLocation('Africa/Abidjan'))),
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'tournee_sentinelle',
          'Tournée sentinelle',
          channelDescription: 'Rappel hebdomadaire pour scanner les arbres repères',
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
    );
    final p = await SharedPreferences.getInstance();
    await p.setBool('rappel_actif', true);
    await p.setInt('rappel_jour', jour);
    await p.setInt('rappel_heure', heure);
    return true;
  }

  Future<void> desactiver() async {
    await _initialiser();
    await _notifs.cancel(_id);
    await (await SharedPreferences.getInstance()).setBool('rappel_actif', false);
  }

  /// Prochaine date (strictement après [maintenant]) qui tombe le [jour] de la semaine à [heure] h.
  static tz.TZDateTime prochaine(int jour, int heure, tz.TZDateTime maintenant) {
    var d = tz.TZDateTime(maintenant.location, maintenant.year, maintenant.month, maintenant.day, heure);
    while (d.weekday != jour || !d.isAfter(maintenant)) {
      d = d.add(const Duration(days: 1));
    }
    return d;
  }
}
