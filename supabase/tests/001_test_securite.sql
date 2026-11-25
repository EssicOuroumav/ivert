-- =============================================================================
-- IVERT · Test de la migration 001 (à coller dans le SQL Editor, APRÈS la migration)
-- Tout se passe dans une transaction annulée à la fin : AUCUNE donnée ne reste.
-- Résultat attendu : la dernière ligne affiche « TOUS LES TESTS SONT PASSÉS ».
-- En cas d'échec, une erreur « ÉCHEC … » indique le test en cause.
-- =============================================================================

begin;

-- Comptes fictifs (supprimés par le rollback final)
insert into auth.users (id, aud, role, phone) values
  ('00000000-0000-4000-a000-00000000000a', 'authenticated', 'authenticated', '22500000000a'),
  ('00000000-0000-4000-a000-00000000000b', 'authenticated', 'authenticated', '22500000000b'),
  ('00000000-0000-4000-a000-00000000000c', 'authenticated', 'authenticated', '22500000000c'),
  ('00000000-0000-4000-a000-00000000000d', 'authenticated', 'authenticated', '22500000000d');

-- Agir comme un compte connecté donné
create function pg_temp.en_tant_que(u uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', u, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
end $$;
create function pg_temp.en_admin() returns void language plpgsql as $$
begin
  perform set_config('role', 'postgres', true);
end $$;

do $$
declare
  a uuid := '00000000-0000-4000-a000-00000000000a';
  b uuid := '00000000-0000-4000-a000-00000000000b';
  c uuid := '00000000-0000-4000-a000-00000000000c';
  d uuid := '00000000-0000-4000-a000-00000000000d';
  n integer;
  ok boolean;
begin
  -- Préconditions : les comptes fictifs existent bien (sinon les refus ne prouveraient rien)
  select count(*) into n from auth.users where id in (a, b, c, d);
  if n <> 4 then raise exception 'ÉCHEC précondition : comptes de test absents (%)', n; end if;

  -- T1 : sans consentement, l'envoi est refusé
  perform pg_temp.en_tant_que(a);
  insert into public.profils (id) values (a);
  begin
    insert into public.signalements (culture, maladie, niveau, lat, lon)
    values ('cacao', 'swollen_shoot', 'certain', 5.79, -6.61);
    raise exception 'ÉCHEC T1 : signalement accepté sans consentement';
  exception when insufficient_privilege then null; end;

  -- T2 : avec consentement, l'envoi passe et la position est arrondie à 0,01°
  update public.profils set consentement_le = now() where id = a;
  insert into public.signalements (culture, maladie, niveau, lat, lon)
  values ('cacao', 'swollen_shoot', 'certain', 5.78912, -6.61234);
  select count(*) into n from public.signalements where lat = 5.79 and lon = -6.61;
  if n <> 1 then raise exception 'ÉCHEC T2 : position non arrondie (%)', n; end if;

  -- T3 : une maladie qui n'existe pas pour la culture est refusée
  begin
    insert into public.signalements (culture, maladie, niveau, lat, lon)
    values ('anacarde', 'swollen_shoot', 'certain', 9.46, -5.63);
    raise exception 'ÉCHEC T3 : maladie incohérente acceptée';
  exception when check_violation then null; end;

  -- T4 : une position hors de Côte d'Ivoire est refusée
  begin
    insert into public.signalements (culture, maladie, niveau, lat, lon)
    values ('cacao', 'swollen_shoot', 'certain', 48.85, 2.35);
    raise exception 'ÉCHEC T4 : position hors Côte d''Ivoire acceptée';
  exception when check_violation then null; end;

  -- T5 : impossible d'envoyer au nom d'un autre compte
  begin
    insert into public.signalements (user_id, culture, maladie, niveau, lat, lon)
    values (b, 'cacao', 'swollen_shoot', 'certain', 5.79, -6.61);
    raise exception 'ÉCHEC T5 : signalement au nom d''un autre accepté';
  exception when insufficient_privilege then null; end;

  -- T6 : un compte ne voit pas les signalements d'un autre (IDOR)
  perform pg_temp.en_tant_que(b);
  insert into public.profils (id, consentement_le) values (b, now());
  insert into public.signalements (culture, maladie, niveau, lat, lon)
  values ('cacao', 'swollen_shoot', 'probable', 5.80, -6.62);
  select count(*) into n from public.signalements;
  if n <> 1 then raise exception 'ÉCHEC T6 : B voit % signalement(s) au lieu de 1', n; end if;
  select count(*) into n from public.profils;
  if n <> 1 then raise exception 'ÉCHEC T6 : B voit % profil(s) au lieu de 1', n; end if;

  -- T7 : un compte ne peut pas écrire dans les foyers ni lancer le calcul
  begin
    insert into public.foyers (culture, maladie, lat, lon, nb_comptes, premier_le, dernier_le)
    values ('cacao', 'swollen_shoot', 5.79, -6.61, 9, current_date, current_date);
    raise exception 'ÉCHEC T7 : écriture de foyer acceptée';
  exception when insufficient_privilege then null; end;
  begin
    perform public.recalculer_foyers();
    raise exception 'ÉCHEC T7 : calcul des foyers lancé par un compte';
  exception when insufficient_privilege then null; end;

  -- T8 : 2 comptes ne suffisent pas pour un foyer
  perform pg_temp.en_admin();
  perform public.recalculer_foyers();
  select count(*) into n from public.foyers;
  if n <> 0 then raise exception 'ÉCHEC T8 : foyer créé avec 2 comptes'; end if;

  -- T9 : 3 signalements du MÊME compte ne créent pas de foyer
  perform pg_temp.en_tant_que(c);
  insert into public.profils (id, consentement_le) values (c, now());
  insert into public.signalements (culture, maladie, niveau, lat, lon, observe_le) values
    ('anacarde', 'gommose', 'certain', 9.46, -5.63, current_date),
    ('anacarde', 'gommose', 'certain', 9.46, -5.63, current_date - 1),
    ('anacarde', 'gommose', 'certain', 9.47, -5.63, current_date - 2);
  perform pg_temp.en_admin();
  perform public.recalculer_foyers();
  select count(*) into n from public.foyers where culture = 'anacarde';
  if n <> 0 then raise exception 'ÉCHEC T9 : foyer créé par un seul compte'; end if;

  -- T10 : 3 comptes différents à moins de 3 km créent UN seul foyer « non confirmé »
  perform pg_temp.en_tant_que(c);
  insert into public.signalements (culture, maladie, niveau, lat, lon)
  values ('cacao', 'swollen_shoot', 'certain', 5.81, -6.61);
  perform pg_temp.en_admin();
  perform public.recalculer_foyers();
  select count(*) into n from public.foyers where culture = 'cacao' and maladie = 'swollen_shoot';
  if n <> 1 then raise exception 'ÉCHEC T10 : % foyer(s) au lieu de 1', n; end if;
  select count(*) into n from public.foyers where nb_comptes = 3 and statut = 'non_confirme';
  if n <> 1 then raise exception 'ÉCHEC T10 : foyer mal renseigné'; end if;

  -- T11 : un compte au loin (Korhogo) ne s'ajoute pas au foyer de Soubré
  perform pg_temp.en_tant_que(d);
  insert into public.profils (id, consentement_le) values (d, now());
  insert into public.signalements (culture, maladie, niveau, lat, lon)
  values ('cacao', 'swollen_shoot', 'certain', 9.46, -5.63);
  perform pg_temp.en_admin();
  perform public.recalculer_foyers();
  select nb_comptes into n from public.foyers where culture = 'cacao';
  if n <> 3 then raise exception 'ÉCHEC T11 : foyer à % comptes au lieu de 3', n; end if;

  -- T12 : un compte connecté voit le foyer, et la recherche par rayon fonctionne
  perform pg_temp.en_tant_que(d);
  select count(*) into n from public.foyers_proches(5.79, -6.61, 10);
  if n <> 1 then raise exception 'ÉCHEC T12 : foyer proche non trouvé (%)', n; end if;
  select count(*) into n from public.foyers_proches(9.46, -5.63, 10);
  if n <> 0 then raise exception 'ÉCHEC T12 : foyer de Soubré vu à Korhogo'; end if;

  -- T13 : un foyer validé garde son statut au recalcul
  perform pg_temp.en_admin();
  update public.foyers set statut = 'confirme', valide_le = now();
  perform public.recalculer_foyers();
  select count(*) into n from public.foyers where statut = 'confirme';
  if n <> 1 then raise exception 'ÉCHEC T13 : statut confirmé perdu'; end if;

  -- T14 : limite de 20 signalements par 24 heures
  perform pg_temp.en_tant_que(d);
  begin
    for i in 0..14 loop
      insert into public.signalements (culture, maladie, niveau, lat, lon, observe_le)
      values ('cacao', 'anthracnose', 'probable', 6.00 + i * 0.01, -6.00, current_date);
    end loop;
    for i in 0..9 loop
      insert into public.signalements (culture, maladie, niveau, lat, lon, observe_le)
      values ('cacao', 'pourriture_brune', 'probable', 6.00 + i * 0.01, -6.00, current_date);
    end loop;
    raise exception 'ÉCHEC T14 : plus de 20 signalements acceptés en 24 h';
  exception when raise_exception then
    if sqlerrm not like 'Limite atteinte%' then raise; end if;
  end;

  -- T15 : un visiteur anonyme ne lit rien
  perform set_config('role', 'anon', true);
  begin
    select count(*) into n from public.foyers;
    raise exception 'ÉCHEC T15 : un visiteur anonyme lit les foyers';
  exception when insufficient_privilege then null; end;

  -- T16 : supprimer un compte supprime ses signalements
  perform pg_temp.en_admin();
  delete from auth.users where id = a;
  select count(*) into n from public.signalements where user_id = a;
  if n <> 0 then raise exception 'ÉCHEC T16 : signalements du compte supprimé conservés'; end if;
end $$;

select 'TOUS LES TESTS SONT PASSÉS' as resultat;

rollback;
