-- The forensic report the AI produced, kept.
--
-- ## What was wrong
--
-- `generateAISummary()` in the console called Gemini, put the text in React
-- state, and rendered it. Nothing wrote it anywhere. Close the dossier and the
-- forensic debrief was gone; reopen the incident and the console billed another
-- Gemini call to produce it again.
--
-- Three separate costs, and the third is the one that matters:
--
--   * There was nowhere for an administrator to see a report that had been
--     generated. That was the operator's own question — "where can admin see the
--     forensic report that was generated?" — and the answer was nowhere.
--   * Every reopen paid for the same analysis.
--   * **There was no record of what the AI said at the moment a decision was
--     made.** If an officer escalated an incident or cleared it partly on the
--     strength of an AI debrief, the text they read is part of why. A forensic
--     assessment that exists only until a browser tab closes cannot be part of an
--     audit trail, which is the entire purpose of the word forensic.
--
-- ## Why a table and not the existing ai_summary column
--
-- `alerts.ai_summary` is free text that already accumulates operator-facing
-- notes — the classification lines `[AI CLASSIFICATION APPLIED] severity ...`
-- are appended to it. Mixing a multi-paragraph forensic document into the same
-- column means neither can be read back reliably, and it makes "which report was
-- generated when, by whom, by which model" unanswerable.
--
-- A report is also not singular. One may be generated while an incident is
-- running and another after the debrief, and the earlier one does not stop being
-- evidence of what was known at the time. So: rows, with provenance, kept.
--
-- ## Why only the server may write one
--
-- This is the important rule. `/api/ai/analyze` holds the Gemini key, composes
-- the prompt from the alert row, and receives the answer. It is the only thing
-- that knows what the model actually said.
--
-- If the browser wrote the text, an operator could put words in the model's mouth
-- in the audit record — "the AI concluded the responders acted correctly" — and
-- nothing downstream could tell that from a genuine completion. So INSERT is
-- service-role only. Nobody signed in from a browser or a phone can create one,
-- and the console reads them back rather than supplying them.

CREATE TABLE IF NOT EXISTS public.incident_ai_reports (
  id           BIGSERIAL PRIMARY KEY,
  alert_id     UUID NOT NULL REFERENCES public.alerts(id) ON DELETE CASCADE,
  -- 'summary' is the forensic debrief; 'triage' is the classification
  -- recommendation. Kept apart because they are read in different places and a
  -- triage recommendation is not a report.
  kind         TEXT NOT NULL CHECK (kind IN ('summary', 'triage')),
  body         TEXT NOT NULL,
  -- Which model produced it. A debrief written by a model that has since been
  -- retired still has to be readable as such: "the AI said" is not a fact
  -- without knowing which AI.
  model        TEXT,
  -- Who asked for it. Not who wrote it — the model wrote it — but an AI
  -- assessment appearing on an incident with nobody's name against the request
  -- is an unattributed document in an audit trail.
  requested_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE public.incident_ai_reports IS
  'Forensic debriefs and triage recommendations as the model actually returned '
  'them. INSERT is service-role only: if a browser could write these, an operator '
  'could put words in the model''s mouth in the audit record.';

-- The console reads the newest report for one incident, constantly.
CREATE INDEX IF NOT EXISTS incident_ai_reports_alert_idx
  ON public.incident_ai_reports (alert_id, kind, created_at DESC);

ALTER TABLE public.incident_ai_reports ENABLE ROW LEVEL SECURITY;

-- ── Who may read one ───────────────────────────────────────────────────────

DROP POLICY IF EXISTS "ai_reports_select_with_alert" ON public.incident_ai_reports;
CREATE POLICY "ai_reports_select_with_alert" ON public.incident_ai_reports
  FOR SELECT TO authenticated
  USING (
    -- Operation Rainbow STAFF, within their command, and no one else.
    --
    -- Two exclusions, both for the same reason. A machine assessment is
    -- Rainbow's own working note: it may speculate about what happened and who
    -- was involved, and it may be wrong.
    --
    --   * A LIAISON sees the incidents escalated to their agency, deliberately.
    --     Handing another organisation our internal assessment of those
    --     incidents is not a decision a policy should make on a commander's
    --     behalf. If it should be shared, a person can share it.
    --
    --   * The REPORTER is excluded for the same reason, and this was a
    --     correction. The first version of this policy required only
    --     alert_is_ours(), which admits the person who reported the incident —
    --     so a citizen would have read a forensic debrief of their own
    --     kidnapping, including whatever the model speculated about suspects or
    --     about how the response went. The behaviour test caught it and recorded
    --     it as a NOTE rather than a failure; leaving it as a note would have
    --     been leaving the inconsistency in, since the liaison exclusion rests
    --     on exactly the same argument.
    --
    -- This is reversible: if Plateau decides a reporter should see the analysis
    -- of their own incident, removing is_staff() here is the whole change.
    public.is_staff()
    AND NOT public.is_liaison()
    AND EXISTS (
      SELECT 1 FROM public.alerts a
       WHERE a.id = incident_ai_reports.alert_id
         AND public.alert_is_ours(a)
    )
  );

-- No INSERT, UPDATE or DELETE policy at all, for anybody signed in. The absence
-- is the control: with RLS enabled and no permissive policy, `authenticated`
-- cannot write a row whatever it tries. Stated explicitly so a later migration
-- does not read the gap as an oversight and "fix" it.
--
-- There are in fact TWO independent blocks here, which is worth knowing before
-- anybody relaxes either one. Verifying the behaviour test by deliberately
-- adding a permissive INSERT policy AND the table grant did not break it — the
-- insert still failed, on `permission denied for sequence
-- incident_ai_reports_id_seq`, because the BIGSERIAL default needs USAGE on the
-- sequence and only service_role has it. The test only failed once all three
-- were granted.
--
-- So a future migration that adds an INSERT policy will appear to have no
-- effect, and the reason will be forty lines away in a GRANT. That is a good
-- accident to have, and a terrible one to debug blind.
REVOKE INSERT, UPDATE, DELETE ON public.incident_ai_reports FROM anon, authenticated;
GRANT SELECT ON public.incident_ai_reports TO authenticated;
GRANT ALL ON public.incident_ai_reports TO service_role;
GRANT USAGE, SELECT ON SEQUENCE public.incident_ai_reports_id_seq TO service_role;

-- ── Reading the latest one back ────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.latest_ai_report(p_alert_id UUID, p_kind TEXT)
RETURNS TABLE (body TEXT, model TEXT, requested_by UUID, created_at TIMESTAMPTZ)
LANGUAGE sql
SECURITY INVOKER
STABLE
SET search_path = public, pg_temp
AS $$
  -- SECURITY INVOKER, so the SELECT policy above decides. A definer function
  -- here would hand every authenticated account the analysis of every incident
  -- in Plateau, straight through the scoping this policy relies on.
  SELECT r.body, r.model, r.requested_by, r.created_at
    FROM public.incident_ai_reports r
   WHERE r.alert_id = p_alert_id
     AND r.kind = p_kind
   ORDER BY r.created_at DESC, r.id DESC
   LIMIT 1;
$$;

COMMENT ON FUNCTION public.latest_ai_report(UUID, TEXT) IS
  'The most recent AI report of one kind for one incident. SECURITY INVOKER so '
  'the table''s own policy decides who may read it.';

REVOKE ALL ON FUNCTION public.latest_ai_report(UUID, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.latest_ai_report(UUID, TEXT) TO authenticated, service_role;
