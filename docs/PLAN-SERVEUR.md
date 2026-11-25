# IVERT : serveur Supabase pour les alertes de voisinage et la carte des foyers

Décisions du propriétaire (25/11/2026) : **Supabase**, compte **au nom d'IVERT**, connexion par
**numéro de téléphone + code SMS**, position partagée **arrondie au village (≈ 1 km)**.

## Ce que fait le serveur
1. Le producteur se connecte (numéro + code SMS) et accepte explicitement le partage.
2. Après un diagnostic **certain ou probable**, l'app envoie : culture, maladie, niveau, date,
   position arrondie à ≈ 1 km. **Jamais la photo, jamais la position exacte.**
3. Hors connexion, l'envoi attend dans une file locale et part dès qu'il y a du réseau.
4. Le serveur regroupe les signalements proches (rayon et durée à régler, ex. 3 cas de swollen shoot
   à moins de 3 km en 15 jours) : c'est un **foyer**.
5. Les producteurs à moins de X km d'un foyer reçoivent une alerte (notification Firebase Cloud Messaging).
6. L'app affiche la carte des foyers, sans aucun nom ni numéro.

## Règles appliquées (dépôt `starter`)
- **Deux projets séparés** : `ivert-test` et `ivert-prod`, sans repli de l'un vers l'autre.
- **Sécurité par ligne (RLS) sur toutes les tables dès la première migration** ; écriture des foyers
  réservée au serveur.
- **Clé `service_role` jamais dans l'app** ni dans le dépôt ; seule la clé publique (anon) va dans l'app.
- Migrations SQL numérotées dans `supabase/migrations/`, appliquées par le propriétaire dans le SQL Editor,
  **avant** de publier le code qui les utilise.
- Comptes de test créés et supprimés par script ; aucune donnée de test laissée en production.
- Revue de sécurité à la conception (`docs/SECURITE.md`) avant le code.

## Données (première version)
| Table | Contenu | Qui lit | Qui écrit |
|---|---|---|---|
| `profils` | identifiant, localité, consentement + date | le producteur lui-même | le producteur lui-même |
| `signalements` | culture, maladie, niveau, date, case de ≈ 1 km (pas de coordonnées exactes) | personne en direct | le producteur (les siens), limité en nombre par jour |
| `foyers` | culture, maladie, case, nombre de cas, période | tous les connectés | le serveur seulement |

## Ce que le propriétaire doit faire (l'assistant ne crée aucun compte)
1. Créer une adresse e-mail dédiée au projet (ex. contact IVERT) partagée avec une 2e personne de confiance.
2. Créer le compte Supabase avec cette adresse, puis **deux projets** : `ivert-test` et `ivert-prod`,
   région **eu-west (Paris ou Irlande)**, la plus proche de la Côte d'Ivoire.
3. Garder les mots de passe de base de données dans un gestionnaire de mots de passe.
4. Donner à l'assistant uniquement l'**URL** du projet de test et sa clé **anon** (publique),
   en les collant dans le fichier `ivert_app/.env.test` (ignoré par Git), jamais dans la conversation.
5. Plus tard : compte SMS (ex. Twilio) et projet Firebase pour les notifications. Pendant le développement,
   Supabase permet des **numéros de test** avec un code fixe, sans SMS payant.

## Coûts
- Supabase : gratuit pour le prototype et le pilote (2 projets gratuits), puis ≈ 25 $/mois.
- SMS : payants à chaque connexion (prix du fournisseur vers la Côte d'Ivoire, à vérifier).
- Firebase Cloud Messaging : gratuit.

## Étapes de développement (après accord)
1. Revue de sécurité `docs/SECURITE.md`.
2. Migration 001 : tables, RLS, fonction de calcul des foyers ; test de sécurité rejouable.
3. App : écran de connexion (numéro + code), consentement, file d'envoi hors ligne.
4. App : carte et liste des foyers proches ; alerte dans l'écran Prévention.
5. Notifications Firebase.
6. Tests sur le projet de test avec des numéros de test, puis pilote.
