import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';

import 'tuiles_service.dart';

/// Clé PUBLIQUE MapTiler, fournie à la compilation (fichier .env.test, jamais sur GitHub) :
///   flutter build apk --dart-define-from-file=.env.test
/// Sans clé, la carte utilise le fond OpenStreetMap standard (sans satellite).
const _cleMapTiler = String.fromEnvironment('MAPTILER_KEY');

/// Fond de carte : MapTiler (plan moderne + satellite) si la clé est présente, sinon OpenStreetMap.
class FondCarte {
  const FondCarte._();

  static bool get satelliteDisponible => _cleMapTiler.isNotEmpty;

  static String attribution({required bool satellite}) =>
      _cleMapTiler.isNotEmpty ? '© MapTiler © OpenStreetMap' : '© OpenStreetMap';

  static TileLayer couche({bool satellite = false, ErrorTileCallBack? surErreur}) {
    if (_cleMapTiler.isNotEmpty) {
      return TileLayer(
        urlTemplate: satellite
            ? 'https://api.maptiler.com/maps/hybrid/256/{z}/{x}/{y}.jpg?key=$_cleMapTiler'
            : 'https://api.maptiler.com/maps/streets-v2/256/{z}/{x}/{y}@2x.png?key=$_cleMapTiler',
        userAgentPackageName: 'ci.ivert.ivert',
        tileProvider: TuilesEnCache(style: satellite ? 'maptiler-hybride' : 'maptiler-plan'),
        maxNativeZoom: satellite ? 20 : 19,
        errorTileCallback: surErreur,
      );
    }
    // Sans clé : OpenStreetMap (CARTO exige désormais une clé, constaté le 27/11/2026)
    return TileLayer(
      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
      userAgentPackageName: 'ci.ivert.ivert',
      tileProvider: TuilesEnCache(style: 'osm'),
      maxNativeZoom: 19,
      errorTileCallback: surErreur,
    );
  }

  /// Mention obligatoire des sources de la carte.
  static Widget mention({required bool satellite}) =>
      SimpleAttributionWidget(source: Text(attribution(satellite: satellite)));
}
