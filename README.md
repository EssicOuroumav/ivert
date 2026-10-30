# IVERT : diagnostic IA hors ligne du cacao et de l'anacarde

Application mobile (Flutter, Android d'abord) qui reconnaît les maladies du cacao et de l'anacarde
à partir d'une photo, **sans connexion internet**, grâce à des modèles TensorFlow Lite embarqués.

| Dossier | Contenu |
|---|---|
| `ivert_app/` | Application Flutter (écrans d'après les maquettes Figma, diagnostic hors ligne, carnet de santé) |
| `ivert-ia/` | Préparation des données, notebook d'entraînement (Google Colab), modèles livrés et fiches |
| `ivert-ia/data/SOURCES.md` | Jeux de données utilisés, licences et liens (les photos ne sont pas dans le dépôt : ≈ 19 Go) |
| `ivert-ia/COLLECTE_PHOTOS.md` | Protocole de collecte de photos de terrain |

Modèles actuels (v3) : cacao (pourriture brune, swollen shoot, anthracnose, sain) et
anacarde (anthracnose, gommose, mineuse, rouille rouge, sain), avec rejet des photos qui ne
ressemblent pas à la culture.

⚠️ Les fiches maladies (`ivert_app/assets/data/maladies.json`) sont à valider par un agronome
(CNRA / ANADER) avant toute diffusion. L'outil aide au diagnostic et ne remplace pas un expert.
