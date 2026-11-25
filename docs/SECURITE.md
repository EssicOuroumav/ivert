# IVERT : revue de sécurité à la conception (serveur Supabase)

Périmètre : le serveur des **alertes de voisinage** et de la **carte des foyers** (voir `PLAN-SERVEUR.md`).
Le diagnostic, le carnet et la prévention restent sur le téléphone et ne sont pas concernés.
Date : 25/11/2026. Statut : **conception, aucun code serveur écrit**. À mettre à jour à chaque lot, avec preuves.

## 1. Ce qu'il faut protéger

| Actif | Où | Pourquoi |
|---|---|---|
| Numéros de téléphone des producteurs | Supabase Auth (`auth.users`) | Donnée personnelle ; démarchage, arnaques Mobile Money si fuite |
| Emplacement des parcelles | Table `signalements` (arrondi ≈ 1 km) | Donnée personnelle et économique (vols de récolte) |
| **Fiabilité des alertes** | Table `foyers` | Une fausse alerte peut provoquer panique, traitements inutiles ou arrachages d'arbres sains |
| **Coût des SMS** | Fournisseur SMS relié à Supabase Auth | Chaque code envoyé est facturé : un robot peut vider le budget (« SMS pumping ») |
| Clé `secret` / `service_role` | Tableau de bord Supabase, fonctions serveur | Tous les droits sur la base |
| Rôle administrateur (validation des foyers) | `app_metadata` du compte | Peut publier ou retirer une alerte |

## 2. Frontières de confiance

| Frontière | Vraie barrière | Test prévu |
|---|---|---|
| Téléphone → API Supabase (clé publique) | **RLS** sur chaque table ; la clé publique ne protège rien | Script `rls-smoke` avec deux comptes de test (A ne lit ni ne modifie rien de B) |
| Téléphone → envoi du code SMS | Limites d'Auth Supabase + numéros **+225 uniquement** | Rafale de demandes : refus au-delà de la limite |
| Base → calcul des foyers | Fonction SQL `security definer`, exécutable par la clé de service seulement | Un compte normal ne peut ni l'appeler ni écrire dans `foyers` |
| Serveur → notifications (Firebase) | Clé Firebase côté serveur uniquement | Recherche de la clé dans l'APK : absente |
| Dépôt GitHub **public** | `.env*` ignoré, aucune clé dans le code | `git ls-files` + recherche de motifs de clés avant chaque envoi |

## 3. Points d'entrée publics (sans session)

| Point d'entrée | Qui l'appelle | Protection prévue | Limite |
|---|---|---|---|
| Demande de code SMS (`/auth/v1/otp`) | L'app, avant connexion | +225 seulement, limite d'envoi Auth, délai entre deux codes | Réglage Supabase (à fixer, ex. 1 par minute et 5 par heure par numéro) |
| Vérification du code (`/auth/v1/verify`) | L'app | Code à 6 chiffres, expiration courte, limite de tentatives Supabase | Réglage Supabase |
| Tables via l'API (`/rest/v1/…`) | N'importe qui avec la clé publique | **RLS : aucune lecture ni écriture sans connexion** | — |
| Fonctions serveur (Edge Functions) | Planificateur Supabase seulement | Pas d'appel public, ou secret vérifié | — |

Aucune autre route publique n'est prévue.

## 4. Cas d'abus

- [x] **SMS pumping (coût)** : un robot demande des milliers de codes vers des numéros surtaxés. → Numéros **+225** seulement, limites d'Auth basses, **plafond de dépense** chez le fournisseur SMS, alerte de consommation. **Risque principal.**
- [x] **Devinette du code** : limite de tentatives et expiration de Supabase Auth ; à vérifier dans les réglages.
- [x] **Faux signalements / faux foyers** : un utilisateur (ou plusieurs comptes) invente des cas pour créer une alerte.
  → Seuls les diagnostics **certain** ou **probable** sont envoyés ; **maximum N signalements par compte et par jour** (verrou en base) ; un foyer exige **au moins 3 comptes différents** ; affiché comme **« foyer signalé, non confirmé »** tant qu'un agent ANADER ou CNRA ne l'a pas validé ; **jamais de consigne d'arrachage** dans une alerte, seulement « inspectez vos arbres et contactez l'ANADER ».
- [x] **Ré-identification d'une parcelle** : position arrondie à **0,01° (≈ 1,1 km)** dans l'app **et** contrôlée en base (contrainte) ; la carte n'affiche que des foyers d'au moins 3 comptes, jamais un signalement isolé ni un identifiant de compte.
- [x] **IDOR** : chaque ligne porte `user_id = auth.uid()` ; RLS empêche de lire ou modifier les lignes d'un autre. Identifiants en UUID.
- [x] **Inondation de l'API** : limite par compte en base pour les signalements ; quotas du plan Supabase ; surveillance de l'usage.
- [x] **Données personnelles** : consentement explicite avant le premier envoi, retiré à tout moment ; **suppression du compte = suppression de ses signalements** ; durée de conservation des signalements limitée (proposition : 12 mois) ; aucune photo envoyée.
- [x] **Code livré** : seule la clé publique est dans l'APK ; la clé secrète n'est jamais dans l'app ni dans le dépôt.
- [x] **Chaîne d'approvisionnement** : dépendances Flutter à jour, dépôt public sans secret, Supabase sans connexion GitHub.
- [ ] **Usurpation de position** (GPS truqué) : non bloquable côté téléphone ; atténué par le seuil de 3 comptes et la validation humaine. Risque accepté.
- [ ] **CSRF, cookies, redirections, fichiers** : sans objet (application mobile, pas de navigateur, pas de dépôt de fichiers).

## 5. Menaces (STRIDE)

| Menace | Protection prévue | Risque restant |
|---|---|---|
| Usurpation | Connexion par code SMS ; RLS par `auth.uid()` | Vol de téléphone ou de carte SIM |
| Falsification | Écriture des foyers réservée au serveur ; limite par compte ; seuil de 3 comptes | Plusieurs complices avec plusieurs puces |
| Répudiation | Date et compte de chaque signalement conservés (non affichés) | — |
| Divulgation | RLS ; position arrondie ; carte sans identité | Fuite côté Supabase ou fournisseur SMS |
| Déni de service | Limites Auth et par compte ; plafond SMS | Quotas du plan gratuit |
| Élévation de privilèges | Rôle admin dans `app_metadata` (modifiable seulement par la clé secrète) | Compte admin compromis : activer la double authentification sur le compte Supabase |

## 6. Constats (à transformer en actions du plan)

- **F1 (élevé)** : coût SMS sans plafond. Correction : +225 uniquement, limites Auth, plafond de dépense chez le fournisseur. Test : rafale de demandes refusée.
- **F2 (élevé)** : fausses alertes possibles. Correction : seuil de 3 comptes, limite par compte, statut « non confirmé », validation humaine, aucune consigne d'arrachage. Test : 3 signalements du même compte ne créent pas de foyer.
- **F3 (moyen)** : position trop précise. Correction : arrondi dans l'app et contrainte en base. Test : une insertion avec 5 décimales est refusée.
- **F4 (moyen)** : données conservées sans fin. Correction : purge des signalements de plus de 12 mois, suppression complète à la demande.
- **F5 (moyen)** : compte Supabase sans double authentification. Correction : l'activer sur le compte IVERT (Account → Security).

## 7. Décisions du propriétaire (25/11/2026)

| Question | Décision |
|---|---|
| Seuil d'un foyer | **3 comptes différents**, même culture et même maladie, à moins de **3 km**, sur **15 jours** |
| Rayon d'alerte des voisins | **10 km** |
| Validation d'un foyer | **Le propriétaire** au départ, depuis le tableau de bord ; un agent ANADER / CNRA ensuite |
| Conservation des signalements | **12 mois**, puis suppression automatique |
| Budget SMS mensuel | À fixer avant d'activer les vrais SMS (numéros de test sans SMS pendant le développement) |
| Cadre légal (loi ivoirienne de 2013, ARTCI) | **À vérifier avec un juriste ou l'incubateur** avant le pilote |

## 8. Ce que cette revue n'a pas couvert

Essai d'intrusion externe ; réglages réels de limites d'Auth Supabase (à relever dans le tableau de bord) ;
tarifs SMS réels vers la Côte d'Ivoire ; comportement de Firebase ; avis juridique.
