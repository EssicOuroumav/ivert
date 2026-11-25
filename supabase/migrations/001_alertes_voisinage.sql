-- =============================================================================
-- IVERT · Migration 001 : alertes de voisinage et carte des foyers
-- À coller dans Supabase → SQL Editor → Run, d'abord sur le projet « ivert test ».
-- Décisions et menaces : docs/SECURITE.md. Plan : docs/PLAN-SERVEUR.md.
--
-- Principes :
--   - RLS sur chaque table, droits accordés un par un (aucun accès automatique).
--   - Position arrondie à 0,01° (≈ 1,1 km) par la base elle-même.
--   - Un foyer = 3 comptes différents, même culture et même maladie,
--     à moins de 3 km, sur 15 jours. Statut « non confirmé » jusqu'à validation.
--   - Les foyers ne sont écrits que par la fonction serveur, jamais par l'app.
-- =============================================================================

begin;

-- -----------------------------------------------------------------------------
-- 1. Profils : consentement au partage, un par compte
-- -----------------------------------------------------------------------------
create table public.profils (
  id              uuid primary key references auth.users (id) on delete cascade,
  localite        text check (char_length(localite) <= 60),
  consentement_le timestamptz,          -- null = pas de partage
  cree_le         timestamptz not null default now(),
  maj_le          timestamptz not null default now()
);

alter table public.profils enable row level security;

create policy "profil : lecture du sien" on public.profils
  for select to authenticated using (id = (select auth.uid()));
create policy "profil : création du sien" on public.profils
  for insert to authenticated with check (id = (select auth.uid()));
create policy "profil : modification du sien" on public.profils
  for update to authenticated using (id = (select auth.uid())) with check (id = (select auth.uid()));
create policy "profil : suppression du sien" on public.profils
  for delete to authenticated using (id = (select auth.uid()));

-- -----------------------------------------------------------------------------
-- 2. Signalements : diagnostics partagés (jamais de photo, position arrondie)
-- -----------------------------------------------------------------------------
create table public.signalements (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null default auth.uid() references auth.users (id) on delete cascade,
  culture     text not null,
  maladie     text not null,
  niveau      text not null check (niveau in ('certain', 'probable')),
  -- numeric(4,2) / (5,2) : la base arrondit elle-même à 2 décimales (≈ 1,1 km)
  lat         numeric(4,2) not null check (lat between 4.0 and 11.0),     -- Côte d'Ivoire
  lon         numeric(5,2) not null check (lon between -9.0 and -2.0),
  observe_le  date not null default current_date,
  cree_le     timestamptz not null default now(),
  constraint maladie_connue check (
    (culture = 'cacao'    and maladie in ('pourriture_brune', 'swollen_shoot', 'anthracnose'))
    or (culture = 'anacarde' and maladie in ('anthracnose', 'gommose', 'mineuse', 'rouille_rouge'))
  ),
  constraint observation_recente check (observe_le between current_date - 15 and current_date),
  -- Un même producteur ne compte qu'une fois par maladie, par case et par jour
  constraint un_par_jour unique (user_id, culture, maladie, lat, lon, observe_le)
);

create index signalements_recents on public.signalements (culture, maladie, observe_le);
create index signalements_par_compte on public.signalements (user_id, cree_le);

alter table public.signalements enable row level security;

-- Chacun ne voit que ses propres signalements ; personne ne voit ceux des autres.
create policy "signalement : lecture des siens" on public.signalements
  for select to authenticated using (user_id = (select auth.uid()));
-- Envoi seulement par un compte qui a donné son consentement.
create policy "signalement : envoi avec consentement" on public.signalements
  for insert to authenticated with check (
    user_id = (select auth.uid())
    and exists (
      select 1 from public.profils p
      where p.id = (select auth.uid()) and p.consentement_le is not null
    )
  );
create policy "signalement : suppression des siens" on public.signalements
  for delete to authenticated using (user_id = (select auth.uid()));
-- Pas de modification : un signalement se supprime, il ne se réécrit pas.

-- Limite anti-abus : 20 signalements par compte sur 24 heures (verrou en base)
create function public.limiter_signalements() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  -- Sérialise les envois d'un même compte : pas de dépassement par envois simultanés
  perform pg_advisory_xact_lock(hashtextextended(new.user_id::text, 0));
  if (select count(*) from public.signalements s
      where s.user_id = new.user_id and s.cree_le > now() - interval '24 hours') >= 20 then
    raise exception 'Limite atteinte : 20 signalements par 24 heures' using errcode = 'P0001';
  end if;
  return new;
end;
$$;

create trigger signalements_limite
  before insert on public.signalements
  for each row execute function public.limiter_signalements();

-- -----------------------------------------------------------------------------
-- 3. Foyers : calculés par le serveur, lisibles par tous les comptes connectés
-- -----------------------------------------------------------------------------
create table public.foyers (
  id          uuid primary key default gen_random_uuid(),
  culture     text not null,
  maladie     text not null,
  lat         numeric(4,2) not null,
  lon         numeric(5,2) not null,
  nb_comptes  integer not null check (nb_comptes >= 3),
  premier_le  date not null,
  dernier_le  date not null,
  statut      text not null default 'non_confirme'
              check (statut in ('non_confirme', 'confirme', 'rejete')),
  valide_le   timestamptz,
  maj_le      timestamptz not null default now(),
  constraint un_foyer_par_case unique (culture, maladie, lat, lon)
);

alter table public.foyers enable row level security;

-- Lecture pour les comptes connectés ; les foyers rejetés ne sont pas affichés.
create policy "foyers : lecture" on public.foyers
  for select to authenticated using (statut <> 'rejete');
-- Aucune politique d'écriture : seuls le serveur et le tableau de bord écrivent.

-- -----------------------------------------------------------------------------
-- 4. Distance et calcul des foyers
-- -----------------------------------------------------------------------------
create function public.distance_km(lat1 float8, lon1 float8, lat2 float8, lon2 float8)
returns float8 language sql immutable parallel safe set search_path = '' as $$
  select 6371 * 2 * asin(least(1, sqrt(
    power(sin(radians(lat2 - lat1) / 2), 2)
    + cos(radians(lat1)) * cos(radians(lat2)) * power(sin(radians(lon2 - lon1) / 2), 2)
  )));
$$;

-- Recalcule les foyers à partir des signalements des 15 derniers jours.
-- Pour chaque case signalée : nombre de comptes différents à moins de 3 km.
-- Les cases voisines qui décrivent le même foyer sont fusionnées : on garde la case
-- qui a le plus de comptes (à égalité, la plus au sud-ouest).
create function public.recalculer_foyers() returns integer
language plpgsql security definer set search_path = '' as $$
declare
  nb integer;
begin
  -- Table de travail : supprimée si un calcul précédent a eu lieu dans la même transaction
  drop table if exists pg_temp.candidats;
  create temporary table candidats on commit drop as
  with cases as (
    select distinct culture, maladie, lat, lon
    from public.signalements
    where observe_le >= current_date - 15
  )
  select c.culture, c.maladie, c.lat, c.lon,
         count(distinct s.user_id)::integer as nb_comptes,
         min(s.observe_le) as premier_le,
         max(s.observe_le) as dernier_le
  from cases c
  join public.signalements s
    on s.culture = c.culture and s.maladie = c.maladie
   and s.observe_le >= current_date - 15
   and public.distance_km(c.lat::float8, c.lon::float8, s.lat::float8, s.lon::float8) <= 3
  group by c.culture, c.maladie, c.lat, c.lon
  having count(distinct s.user_id) >= 3;

  -- Garde un seul représentant par groupe de cases à moins de 3 km
  delete from pg_temp.candidats a
  using pg_temp.candidats b
  where a.culture = b.culture and a.maladie = b.maladie
    and (a.lat, a.lon) <> (b.lat, b.lon)
    and public.distance_km(a.lat::float8, a.lon::float8, b.lat::float8, b.lon::float8) <= 3
    and (b.nb_comptes > a.nb_comptes
         or (b.nb_comptes = a.nb_comptes and (b.lat, b.lon) < (a.lat, a.lon)));

  -- Ajoute ou met à jour (le statut choisi par le validateur est conservé)
  insert into public.foyers (culture, maladie, lat, lon, nb_comptes, premier_le, dernier_le, maj_le)
  select culture, maladie, lat, lon, nb_comptes, premier_le, dernier_le, now() from pg_temp.candidats
  on conflict (culture, maladie, lat, lon) do update
    set nb_comptes = excluded.nb_comptes,
        premier_le = least(public.foyers.premier_le, excluded.premier_le),
        dernier_le = excluded.dernier_le,
        maj_le     = now();
  get diagnostics nb = row_count;

  -- Retire les foyers non confirmés qui ne remplissent plus les conditions,
  -- et les foyers confirmés sans nouveau signalement depuis 30 jours
  delete from public.foyers f
  where (f.statut = 'non_confirme'
         and not exists (select 1 from pg_temp.candidats c
                         where c.culture = f.culture and c.maladie = f.maladie
                           and c.lat = f.lat and c.lon = f.lon))
     or (f.statut <> 'non_confirme' and f.dernier_le < current_date - 30);

  return nb;
end;
$$;

-- Supprime les signalements de plus de 12 mois (décision du propriétaire)
create function public.purger_signalements() returns integer
language plpgsql security definer set search_path = '' as $$
declare
  nb integer;
begin
  delete from public.signalements where cree_le < now() - interval '12 months';
  get diagnostics nb = row_count;
  return nb;
end;
$$;

-- Foyers à moins de N km d'un point (lu par l'app, sous les règles RLS de l'appelant)
create function public.foyers_proches(p_lat float8, p_lon float8, p_rayon_km float8 default 10)
returns setof public.foyers
language sql stable security invoker set search_path = '' as $$
  select f.* from public.foyers f
  where public.distance_km(p_lat, p_lon, f.lat::float8, f.lon::float8) <= least(p_rayon_km, 50)
  order by public.distance_km(p_lat, p_lon, f.lat::float8, f.lon::float8);
$$;

-- -----------------------------------------------------------------------------
-- 5. Droits : rien pour les visiteurs anonymes, le strict nécessaire pour les comptes
-- -----------------------------------------------------------------------------
revoke all on public.profils, public.signalements, public.foyers from anon, authenticated;
grant select, insert, update, delete on public.profils to authenticated;
grant select, insert, delete on public.signalements to authenticated;
grant select on public.foyers to authenticated;

revoke execute on function public.limiter_signalements() from public, anon, authenticated;
revoke execute on function public.recalculer_foyers()    from public, anon, authenticated;
revoke execute on function public.purger_signalements()  from public, anon, authenticated;
grant  execute on function public.recalculer_foyers()    to service_role;
grant  execute on function public.purger_signalements()  to service_role;

revoke execute on function public.foyers_proches(float8, float8, float8) from public, anon;
grant  execute on function public.foyers_proches(float8, float8, float8) to authenticated;
revoke execute on function public.distance_km(float8, float8, float8, float8) from public, anon;
grant  execute on function public.distance_km(float8, float8, float8, float8) to authenticated;

commit;
