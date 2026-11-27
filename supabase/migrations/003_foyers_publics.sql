-- =============================================================================
-- IVERT · Migration 003 : foyers visibles sans compte (lecture seule, limitée)
-- À coller dans Supabase → SQL Editor → Run, APRÈS les migrations 001 et 002.
--
-- Pourquoi : un foyer est déjà anonyme (au moins 3 producteurs, position arrondie à ≈ 1 km,
-- jamais de nom ni de numéro). Le montrer à tous protège plus de producteurs dès le premier jour.
-- Se connecter ne sert plus qu'à PARTAGER ses propres diagnostics.
--
-- Garde-fous :
--   - aucune lecture directe de la table pour les visiteurs : seulement cette fonction ;
--   - colonnes limitées (pas d'id, pas de dates de validation) ;
--   - rayon plafonné à 20 km, 50 foyers au plus, point obligatoirement en Côte d'Ivoire ;
--   - foyers rejetés jamais montrés.
-- Relancer ce fichier est sans danger (create or replace).
-- =============================================================================

create or replace function public.foyers_publics(p_lat float8, p_lon float8, p_rayon_km float8 default 10)
returns table (
  culture text,
  maladie text,
  lat numeric,
  lon numeric,
  nb_comptes integer,
  dernier_le date,
  statut text
)
language sql stable security definer set search_path = '' as $$
  select f.culture, f.maladie, f.lat, f.lon, f.nb_comptes, f.dernier_le, f.statut
  from public.foyers f
  where f.statut <> 'rejete'
    and p_lat between 4.0 and 11.0
    and p_lon between -9.0 and -2.0
    and public.distance_km(p_lat, p_lon, f.lat::float8, f.lon::float8) <= least(greatest(p_rayon_km, 0), 20)
  order by public.distance_km(p_lat, p_lon, f.lat::float8, f.lon::float8)
  limit 50;
$$;

revoke execute on function public.foyers_publics(float8, float8, float8) from public;
grant  execute on function public.foyers_publics(float8, float8, float8) to anon, authenticated;

-- Vérification : doit renvoyer 0 ligne tant qu'aucun foyer n'existe (et aucune erreur)
select * from public.foyers_publics(5.79, -6.61, 10);
