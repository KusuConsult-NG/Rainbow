-- No policy in schema public may reach anon or PUBLIC, at any point.
--
-- The two that did were `alerts_select_geo_lga_scoped` and
-- `telemetry_select_geo_lga_scoped`, created twelve lines apart in
-- 20260725000000_v6_geo_lga_scoping_staging.sql — one with a TO clause, one
-- without. PostgreSQL records a policy with no TO clause as TO PUBLIC, and
-- PUBLIC includes anon.
--
-- This asserts the state, not the text: pg_policies.roles is what the database
-- actually recorded, which is the only thing that decides who gets a row.
\set ON_ERROR_STOP on

DO $$
DECLARE
  open_policies TEXT;
  n INTEGER;
  r NAME[];
BEGIN
  -- 1. The whole schema, which is the claim that matters.
  SELECT count(*), string_agg(tablename || '.' || policyname || ' ' || roles::text, ', ')
    INTO n, open_policies
    FROM pg_policies
   WHERE schemaname = 'public'
     AND ('anon' = ANY(roles) OR 'public' = ANY(roles));
  IF n = 0 THEN
    RAISE NOTICE 'PASS  no policy in schema public reaches anon or public';
  ELSE
    RAISE EXCEPTION 'FAIL  % policy/policies reach anon or public: %', n, open_policies;
  END IF;

  -- 2. The two by name, where they exist. A policy that has been dropped is
  --    fine; a policy that exists and names PUBLIC is not.
  FOR r IN
    SELECT roles FROM pg_policies
     WHERE schemaname = 'public' AND policyname = 'alerts_select_geo_lga_scoped'
  LOOP
    IF 'public' = ANY(r) OR 'anon' = ANY(r) THEN
      RAISE EXCEPTION
        'FAIL  alerts_select_geo_lga_scoped is TO % — the incident table, '
        'reachable by the anonymous key', r;
    END IF;
    RAISE NOTICE 'PASS  alerts_select_geo_lga_scoped is TO %', r;
  END LOOP;

  FOR r IN
    SELECT roles FROM pg_policies
     WHERE schemaname = 'public' AND policyname = 'telemetry_select_geo_lga_scoped'
  LOOP
    IF 'public' = ANY(r) OR 'anon' = ANY(r) THEN
      RAISE EXCEPTION
        'FAIL  telemetry_select_geo_lga_scoped is TO % — position history, '
        'reachable by the anonymous key', r;
    END IF;
    RAISE NOTICE 'PASS  telemetry_select_geo_lga_scoped is TO %', r;
  END LOOP;

  -- 3. The assertion must be able to fail. A sweep nobody has watched reject
  --    something is not a sweep: the earlier version of this claim passed every
  --    run for weeks while a TO PUBLIC policy sat on telemetry.
  CREATE POLICY zz_roles_probe ON public.app_config FOR SELECT USING (true);
  SELECT count(*) INTO n
    FROM pg_policies
   WHERE schemaname = 'public' AND policyname = 'zz_roles_probe'
     AND ('anon' = ANY(roles) OR 'public' = ANY(roles));
  DROP POLICY zz_roles_probe ON public.app_config;
  IF n <> 1 THEN
    RAISE EXCEPTION
      'FAIL  a policy created with no TO clause was not recorded as reaching '
      'public — this test is checking nothing';
  END IF;
  RAISE NOTICE 'PASS  and a planted TO-PUBLIC policy is detected, so it checks something';

  SELECT count(*) INTO n
    FROM pg_policies
   WHERE schemaname = 'public' AND policyname = 'zz_roles_probe';
  IF n <> 0 THEN
    RAISE EXCEPTION 'FAIL  the probe policy outlived the test';
  END IF;
  RAISE NOTICE 'PASS  and the probe is gone';
END $$;
