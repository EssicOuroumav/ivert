# Valider ou rejeter un foyer (pour le propriétaire)

Un **foyer** apparaît automatiquement quand au moins 3 producteurs différents signalent la même maladie
à moins de 3 km, sur 15 jours. Il est d'abord **« signalé, non confirmé »**. C'est toi qui décides.

## Où les voir
Supabase → projet → **Table Editor** → table **`foyers`**.
Colonnes utiles : `culture`, `maladie`, `lat` / `lon` (position arrondie à ≈ 1 km), `nb_comptes`, `dernier_le`, `statut`.

Pour situer un foyer : colle `lat,lon` (ex. `5.79,-6.61`) dans Google Maps.

## Décider
1. Avant de confirmer, **vérifie sur le terrain** ou par un agent ANADER / CNRA (appel, visite, photos).
2. Dans la ligne du foyer, change `statut` :
   - `confirme` : la maladie est vérifiée. Les producteurs à moins de 10 km voient « Confirmé ».
   - `rejete` : fausse alerte. Le foyer n'est plus affiché à personne.
   - `non_confirme` : en attente (valeur par défaut).
3. Mets la date du jour dans `valide_le`, puis **Save**.

## À savoir
- Le calcul automatique (toutes les 15 minutes) **garde ton choix** : il ne remet jamais un foyer confirmé ou rejeté en « non confirmé ».
- Un foyer **non confirmé** disparaît tout seul s'il ne remplit plus les conditions (moins de 3 producteurs sur 15 jours).
- Un foyer **confirmé ou rejeté** disparaît 30 jours après son dernier signalement.
- Tu ne vois **jamais** qui a signalé : seulement le nombre de producteurs. C'est voulu (`docs/SECURITE.md`).
- Une alerte ne doit **jamais** demander d'arracher des arbres : la décision d'arrachage revient à l'ANADER / au Conseil Café-Cacao.
