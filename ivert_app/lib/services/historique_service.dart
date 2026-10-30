import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'diagnostic_service.dart';

class EntreeHistorique {
  EntreeHistorique({
    this.id,
    required this.date,
    required this.culture,
    required this.classe,
    required this.confiance,
    required this.niveau,
    required this.photo,
  });

  factory EntreeHistorique.fromMap(Map<String, Object?> m) => EntreeHistorique(
        id: m['id'] as int,
        date: DateTime.fromMillisecondsSinceEpoch(m['date'] as int),
        culture: Culture.values.byName(m['culture'] as String),
        classe: m['classe'] as String,
        confiance: m['confiance'] as double,
        niveau: Niveau.values.asNameMap()[m['niveau'] as String?] ??
            ((m['fiable'] as int) == 1 ? Niveau.certain : Niveau.incertain),
        photo: m['photo'] as String,
      );

  final int? id;
  final DateTime date;
  final Culture culture;
  final String classe;
  final double confiance;
  final Niveau niveau;
  final String photo;

  Map<String, Object?> toMap() => {
        'date': date.millisecondsSinceEpoch,
        'culture': culture.name,
        'classe': classe,
        'confiance': confiance,
        'fiable': niveau == Niveau.certain ? 1 : 0,
        'niveau': niveau.name,
        'photo': photo,
        'modele': '${culture.name}_${DiagnosticService.version}',
      };
}

/// Historique des diagnostics, stocké uniquement sur le téléphone.
class HistoriqueService {
  HistoriqueService._();

  static final instance = HistoriqueService._();
  Database? _db;

  Future<Database> get _base async => _db ??= await openDatabase(
        p.join(await getDatabasesPath(), 'ivert.db'),
        version: 2,
        onUpgrade: (db, ancienne, _) async {
          if (ancienne < 2) await db.execute('ALTER TABLE diagnostics ADD COLUMN niveau TEXT');
        },
        onCreate: (db, _) => db.execute('''
          CREATE TABLE diagnostics (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            date INTEGER NOT NULL,
            culture TEXT NOT NULL,
            classe TEXT NOT NULL,
            confiance REAL NOT NULL,
            fiable INTEGER NOT NULL,
            photo TEXT NOT NULL,
            modele TEXT NOT NULL,
            niveau TEXT
          )'''),
      );

  /// Copie la photo dans le dossier de l'app (la photo d'origine peut être supprimée de la galerie).
  Future<EntreeHistorique> enregistrer(Diagnostic d, File photo) async {
    final dossier = Directory(p.join((await getApplicationDocumentsDirectory()).path, 'diagnostics'));
    await dossier.create(recursive: true);
    final copie = await photo.copy(p.join(dossier.path, '${DateTime.now().millisecondsSinceEpoch}.jpg'));
    final entree = EntreeHistorique(
      date: DateTime.now(),
      culture: d.culture,
      classe: d.classe,
      confiance: d.confiance,
      niveau: d.niveau,
      photo: copie.path,
    );
    final id = await (await _base).insert('diagnostics', entree.toMap());
    return EntreeHistorique.fromMap({...entree.toMap(), 'id': id});
  }

  Future<List<EntreeHistorique>> tout() async {
    final lignes = await (await _base).query('diagnostics', orderBy: 'date DESC');
    return lignes.map(EntreeHistorique.fromMap).toList();
  }

  Future<void> supprimer(EntreeHistorique e) async {
    await (await _base).delete('diagnostics', where: 'id = ?', whereArgs: [e.id]);
    final f = File(e.photo);
    if (await f.exists()) await f.delete();
  }
}
