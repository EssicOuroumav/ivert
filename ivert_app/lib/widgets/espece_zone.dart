import '../services/parcelle_service.dart';

/// Texte « espèce probable selon la zone » pour la pourriture brune du cacao.
/// Les deux espèces ont les mêmes symptômes : seule une analyse en laboratoire les distingue.
String? texteEspeceZone(Localite l) => switch (l.phytophthora) {
      Phytophthora.megakarya =>
        'Zone de ${l.nom} : Phytophthora megakarya, l’espèce la plus agressive, y est dominante. Les traitements doivent être plus rapprochés : suivez le conseiller ANADER.',
      Phytophthora.mixte =>
        'Zone de ${l.nom} : Phytophthora megakarya (plus agressif) y est signalé avec P. palmivora. Restez vigilant après chaque pluie.',
      Phytophthora.palmivora =>
        'Zone de ${l.nom} : Phytophthora palmivora y est dominant d’après les études récentes ; P. megakarya progresse d’est en ouest.',
      null => null,
    };
