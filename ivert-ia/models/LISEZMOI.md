# Modèles IVERT

| Dossier | Statut | Contenu |
|---|---|---|
| `cacao_v2/`, `anacarde_v2/` | **Version de secours** (en service dans l'app jusqu'à la v3) | fp16 (app) + dyn (léger), labels, fiche du modèle |
| `cacao_v3/`, `anacarde_v3/` | À venir (Colab) | + empreintes `prototypes_*.bin` et `config_*.json` pour le rejet |
| `historique/` | Archive | Fiches et labels de la v1 (scores, classes) — fichiers .tflite v1 supprimés |

Historique des scores (jeu de test) :
- v1 : cacao 92,6 % (3 classes, sans anthracnose ni rejet), anacarde 95,1 % (5 classes)
- v2 : cacao 87,9 % (+ anthracnose, + classe de refus), anacarde 95,9 % (+ classe de refus)
