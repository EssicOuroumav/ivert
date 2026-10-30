# Analyse des sources de photos proposées (17/10/2026)

## 1. « Registre de collecte » (texte collé) : inutilisable

- Les ~25 entrées n'ont **aucune adresse réelle** : chaque lien est un texte « Lien Photo » vide.
- Le total est de 25 photos environ, très loin du quota de 200 à 300 par culture.
- Affirmation fausse : PlantVillage ne contient **ni cacao ni anacarde** (vérifié le 16/10).
- La mention « aucune image générée par IA » n'est appuyée par aucune source vérifiable.

## 2. Réponse Perplexity (fichier .md) : rien de nouveau, sauf une piste

- Le fichier annoncé `output/IVERT_liens_photos_cacao_anacarde.md` **n'a pas été fourni** : il n'existe pas sur le Mac.
- Les sources citées sont **déjà utilisées** par IVERT :
  - CCMT (anacarde, Ghana) ;
  - CocoaSwolSet (v1 citée, nous avons la v2) ;
  - « Cacao Disease » Kaggle (zaldyjr), qui est la source de l'article arXiv 2504.12992 ;
  - « Cocoa Diseases YOLOv4 » (serranosebas), utilisée en validation par l'article arXiv 2401.01247.
- Frontiers 2026 (fpls.2026.1815033) : utilise seulement CCMT anacarde, que nous avons déjà.
- CocoaDetectDB : images en 112×112 px, trop petites ; aucun lien de téléchargement trouvé.
- arXiv 2401.01247 : environ 500 photos de terrain en Équateur, **non publiées**.
- Requêtes `site:anader.ci`, `site:cnra.ci`, `site:firca.ci` : ce sont des pistes de recherche, pas des jeux de photos téléchargeables.

## 3. Nouvelle source vérifiée : iNaturalist (photos de terrain réelles)

| | Observations « qualité recherche », licence compatible usage commercial (CC0, CC BY, CC BY-SA) | Photos estimées | Côte d'Ivoire |
|---|---|---|---|
| Cacao (*Theobroma cacao*, taxon 64340) | 392 | ~760 | 1 |
| Anacarde (*Anacardium occidentale*, taxon 122988) | 296 | ~570 | 1 |

- Ce sont des photos sur l'arbre, dans des environnements variés : feuilles, cabosses, fleurs, **pommes et noix de cajou**.
- Elles ne sont **pas étiquetées par maladie** : la plupart montrent des plantes sans diagnostic.
  - **Usage prévu** : apprendre à reconnaître « c'est bien du cacao / de l'anacarde » (empreintes de ressemblance), pour corriger le faux rejet des vraies photos de terrain.
  - **Pas d'usage** comme photos « saines » sans vérification.
- Les photos sous licence NC (non commerciale) sont exclues : environ 3 500 pour le cacao, 2 100 pour l'anacarde.
- Attribution obligatoire : auteur + licence pour chaque photo (fournies par l'API).

Wikimedia Commons : environ 140 photos d'anacarde (fruits, noix). Licences à vérifier une par une. Aucune catégorie dédiée aux maladies.

## 4. Conclusion

Aucune source publique ne fournit 200 à 300 photos **étiquetées par maladie, prises en Côte d'Ivoire**.
- iNaturalist corrige le manque de **variété des photos de terrain**.
- Les maladies (et surtout les débuts de maladie) restent à collecter sur le terrain (voir `../COLLECTE_PHOTOS.md`).

## 5. Téléchargement iNaturalist effectué (17/10/2026)

- Script : `scripts/inaturalist_download.py` ; attributions (auteur, licence, lien) dans `data/raw/inaturalist/<culture>/attributions.csv`.
- Reçu : cacao 763, anacarde 647 photos ; licences CC0 / CC BY / CC BY-SA uniquement ; 0 fichier corrompu ; 3 doublons exacts (écartés automatiquement à la préparation).
- **Revue visuelle de chaque photo** (planches numérotées) :
  - écartées (dossiers `*_exclues/`) : cacao 11 (fèves en séchage, personnes au premier plan, plant en pot emballé), anacarde 6 (herbier, noir et blanc, voiture, pomme coupée sur papier) ;
  - gardées : cacao 752, anacarde 641 (feuilles, cabosses, fleurs, troncs, **pommes et noix de cajou** sur l'arbre) ;
  - **symptômes visibles, à faire confirmer par un agronome** avant tout étiquetage : cacao 10, anacarde 11 (liste dans `revue_<culture>.csv`).
- Origine : surtout Amérique latine, Inde, Philippines, Brésil ; 1 seule photo de Côte d'Ivoire par culture.
