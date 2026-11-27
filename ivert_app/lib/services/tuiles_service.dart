import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Fond de carte avec mémoire sur le téléphone : chaque zone déjà affichée reste visible sans réseau.
///
/// Règle d'OpenStreetMap : on garde les tuiles consultées, mais on ne télécharge pas des zones entières
/// à l'avance (téléchargement en masse interdit sur leur serveur public). Le téléchargement d'une zone
/// complète viendra avec un fournisseur qui l'autorise (MapTiler…), au pilote.
class TuilesEnCache extends TileProvider {
  TuilesEnCache();

  static const _agent = 'IVERT/1.0 (ci.ivert.ivert; prototype)';
  static const _validite = Duration(days: 30);
  static Directory? _dossier;
  static final _client = http.Client();

  static Future<Directory> dossier() async {
    if (_dossier != null) return _dossier!;
    final base = await getApplicationSupportDirectory();
    _dossier = await Directory(p.join(base.path, 'tuiles')).create(recursive: true);
    return _dossier!;
  }

  /// Nombre de tuiles gardées et place occupée (Mo), pour l'afficher au producteur.
  static Future<(int, double)> taille() async {
    final d = await dossier();
    var n = 0, octets = 0;
    await for (final f in d.list(recursive: true)) {
      if (f is File) {
        n++;
        octets += await f.length();
      }
    }
    return (n, octets / 1e6);
  }

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) =>
      _TuileImage(getTileUrl(coordinates, options), '${coordinates.z}/${coordinates.x}/${coordinates.y}');
}

@immutable
class _TuileImage extends ImageProvider<_TuileImage> {
  const _TuileImage(this.url, this.cle);

  final String url;
  final String cle; // z/x/y

  @override
  Future<_TuileImage> obtainKey(ImageConfiguration configuration) => SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(_TuileImage key, ImageDecoderCallback decode) =>
      OneFrameImageStreamCompleter(_charger(decode));

  Future<ImageInfo> _charger(ImageDecoderCallback decode) async {
    final fichier = File(p.join((await TuilesEnCache.dossier()).path, '$cle.png'));
    Uint8List? octets;
    final existe = await fichier.exists();
    final recente = existe && DateTime.now().difference(await fichier.lastModified()) < TuilesEnCache._validite;
    if (!recente) {
      try {
        final r = await TuilesEnCache._client
            .get(Uri.parse(url), headers: {'User-Agent': TuilesEnCache._agent})
            .timeout(const Duration(seconds: 15));
        if (r.statusCode == 200 && r.bodyBytes.isNotEmpty) {
          octets = r.bodyBytes;
          await fichier.parent.create(recursive: true);
          await fichier.writeAsBytes(octets, flush: true);
        }
      } catch (_) {
        // Pas de réseau : on se rabat sur la copie gardée, même ancienne
      }
    }
    if (octets == null && existe) octets = await fichier.readAsBytes();
    if (octets == null) throw StateError('Tuile indisponible hors connexion : $cle');
    final codec = await decode(await ui.ImmutableBuffer.fromUint8List(octets));
    return ImageInfo(image: (await codec.getNextFrame()).image);
  }

  @override
  bool operator ==(Object other) => other is _TuileImage && other.cle == cle && other.url == url;

  @override
  int get hashCode => Object.hash(url, cle);
}
