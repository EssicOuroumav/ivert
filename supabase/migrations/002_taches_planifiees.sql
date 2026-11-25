-- =============================================================================
-- IVERT · Migration 002 : tâches planifiées (pg_cron)
-- À coller dans Supabase → SQL Editor → Run, APRÈS la migration 001, sur « ivert test ».
--
--   - toutes les 15 minutes : recalcul des foyers (3 comptes, 3 km, 15 jours)
--   - chaque nuit à 03:00 (heure d'Abidjan = UTC) : suppression des signalements de plus de 12 mois
-- Relancer ce fichier ne crée pas de doublon : une tâche du même nom est remplacée.
-- =============================================================================

create extension if not exists pg_cron;

select cron.schedule(
  'ivert-recalculer-foyers',
  '*/15 * * * *',
  $$select public.recalculer_foyers()$$
);

select cron.schedule(
  'ivert-purger-signalements',
  '0 3 * * *',
  $$select public.purger_signalements()$$
);

-- Vérification : doit afficher les 2 tâches, actives
select jobname, schedule, active from cron.job where jobname like 'ivert-%' order by jobname;
