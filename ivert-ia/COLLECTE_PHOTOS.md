# IVERT : protocole de collecte de photos de terrain

Objectif : 200 à 300 photos **par culture** (cacao, anacarde), prises en Côte d'Ivoire, sur l'arbre.
Ces photos apprennent à l'IA à quoi ressemblent vraiment nos vergers.

## 1. Classement (un dossier par cas)

```
IVERT_photos/
  cacao/
    sain/
    pourriture_brune/
    swollen_shoot/
    anthracnose/
    doute/              ← malade, mais maladie inconnue ou incertaine
  anacarde/
    sain/
    anthracnose/
    gommose/
    mineuse/
    rouille_rouge/
    noix_pommes/        ← noix et pommes de cajou (saines ou abîmées), précisez dans le nom du fichier
    doute/
```

Si possible, faites **confirmer la maladie par un agent ANADER / CNRA**. Au moindre doute, mettez la photo dans `doute/` : une photo mal classée fait plus de mal que pas de photo.

## 2. Combien

| Par culture | Minimum | Idéal |
|---|---|---|
| Sain | 60 | 100 |
| Chaque maladie | 40 | 80 |
| Noix / pommes de cajou | 40 | 80 |

Variez les **arbres** (pas 50 photos du même arbre), les **parcelles** et, si possible, les **zones** (Soubré, San-Pédro, Bondoukou, Korhogo…).

## 3. Comment photographier

- **Sur l'arbre**, dans son environnement réel. Pas de feuille cueillie posée sur une table.
- **Un seul sujet** (une feuille, une cabosse, une portion de tronc, une grappe de noix) qui **remplit la photo**, à 20-40 cm.
- **Net** : touchez l'écran pour faire la mise au point, ne bougez pas.
- **Lumières variées** : matin, midi, soleil, ombre, temps couvert. Évitez seulement le contre-jour total et la nuit.
- **Plusieurs stades** : début de maladie (petites taches) et stade avancé. Les **débuts de maladie** sont les plus précieux.
- **Plusieurs organes** : feuilles jeunes et adultes, cabosses vertes et mûres, tiges, tronc (gommose).
- Pas de doigts, de visages ni d'objets devant le sujet. Les photos ne doivent montrer aucune personne.

## 4. Envoi

- Gardez les photos **originales** (pas de capture d'écran, pas de photo envoyée par WhatsApp qui les compresse).
- Déposez le dossier `IVERT_photos/` dans Google Drive (dossier `IVERT`) ou sur le Mac.
- Notez à part, si possible : la **localité** et la **date** de chaque série.

## 5. Facultatif : photos de contrôle

Quelques photos (20 à 50) d'**autres plantes du verger** (papayer, bananier, palmier, mauvaises herbes) dans un dossier `controle/`.
Elles ne servent **pas** à l'apprentissage : uniquement à vérifier que l'app les rejette bien.
