# IVERT : modèles IA (cacao & anacarde)

## Arborescence

```
data/raw/          jeux téléchargés, intacts (une source = un dossier)
data/clean/        jeu propre découpé train/val/test + <culture>.zip pour Colab
data/labels_map.csv  correspondance dossier source → (culture, classe, organe)
data/SOURCES.md    liens + licences de chaque source
scripts/           audit, téléchargement, préparation, génération des notebooks
notebooks/         notebooks d'entraînement (Colab / Kaggle)
models/            modèles .tflite livrés (à déposer ici après Colab)
reports/           rapports d'audit et journaux
```

## Commandes (depuis `ivert-ia/`)

```bash
.venv/bin/python -I scripts/audit_data.py data/raw
```

```bash
.venv/bin/python -I scripts/prepare_dataset.py --culture anacarde --zip
```

## Entraîner sur Google Colab (gratuit, GPU)

1. Dans Google Drive, crée un dossier `IVERT`, puis déposes-y `data/clean/anacarde.zip` (et `cacao.zip`).
2. Ouvre https://colab.research.google.com → Importer → `notebooks/train_classify.ipynb`.
3. Exécution → Modifier le type d'exécution → **GPU T4**.
4. Première cellule : `CULTURE = "anacarde"` et `SMOKE = True`, puis Exécution → Tout exécuter. Autorise l'accès à Drive.
5. Si tout passe (environ 5 min), mets `SMOKE = False` et relance tout (environ 30 à 60 min).
6. Le fichier `ivert_anacarde_classify_v3.zip` se télécharge : dépose-le dans `models/` et dis-le-moi.
7. Recommence avec `CULTURE = "cacao"`.
