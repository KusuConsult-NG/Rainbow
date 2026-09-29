import { NextResponse } from 'next/server';
import { getSupabaseAdmin, requireRole, COMMAND_ROLES } from '@/lib/supabase-server';
import { serverEnv } from '@/lib/env';

/**
 * Server-side Gemini access for the dashboard's two AI features.
 *
 * ## Why this route exists
 *
 * `dashboard/page.tsx` is a `'use client'` component, and it read
 * `process.env.NEXT_PUBLIC_GEMINI_API_KEY` and called Google directly from the
 * browser. `NEXT_PUBLIC_*` is inlined into the client bundle at build time, so
 * in any deployment where that variable was actually set, the Gemini key was
 * served to every visitor of the dashboard. The key also travelled in the URL
 * query string (`?key=...`), which additionally puts it in browser history,
 * `Referer` headers, and any intermediate proxy or CDN log.
 *
 * This is the same defect class as C-1 (a server credential reaching the
 * browser). It differs only in that nobody hardcoded a literal, so nothing
 * leaked from the repository itself — the leak happens at deploy time.
 *
 * ## Why this is not an authenticated proxy to Gemini
 *
 * Moving the key server-side is worthless if the endpoint will run any prompt
 * a caller supplies — that is just a billable open relay behind a login. The
 * client therefore sends **no prompt text at all**: it sends an alert id and
 * which of the two analyses it wants. This route fetches the alert itself and
 * composes the prompt from the row. There is no path by which caller-authored
 * text reaches Gemini except the incident description already stored in the
 * database, which is the data being analysed.
 *
 * Callers must hold a command role — the same bar as the other dashboard APIs.
 */

const MODEL = 'gemini-1.5-flash-latest';

type Kind = 'summary' | 'triage';

interface AlertRow {
  id: string;
  type: string | null;
  description: string | null;
  severity: string | null;
  priority: string | null;
  geo_lga: string | null;
  geo_ward: string | null;
}

function summaryPrompt(a: AlertRow): string {
  return `You are the Operation Rainbow Forensic AI Assistant. Your task is to analyze the following resolved incident report and compile a premium, structured Post-Action Operational Summary.

INCIDENT METADATA:
- ID: ${a.id}
- Type: ${a.type || 'N/A'}
- Description: ${a.description || 'No description provided'}
- Severity: ${a.severity || a.priority || 'MEDIUM'}
- LGA: ${a.geo_lga || 'STATE HQ'}
- Ward: ${a.geo_ward || 'N/A'}

Provide your analysis formatted in Markdown. Your summary MUST contain the following four specific sections:
1. ### EXECUTIVE OPERATIONAL SUMMARY: A concise 2-sentence tactical summary of the incident and its resolution.
2. ### TIMELINE SLA AUDIT: Audit response times and evaluate if response milestones were met.
3. ### KEY RESOURCE PERFORMANCE: Evaluate the actions taken by responding officers and field units.
4. ### STRATEGIC RECOMMENDATIONS: Provide 2-3 actionable, high-impact tactical recommendations for geofenced patrols in this LGA/Ward.`;
}

function triagePrompt(a: AlertRow): string {
  const description = a.description ?? '';
  return `You are the Operation Rainbow Emergency Triage AI. Analyze: "${description}".
Respond ONLY with a JSON object with this exact shape:
{
  "recommended_type": "CRIME",
  "recommended_priority": "HIGH",
  "justification": "Threat analysis details",
  "weapons_detected": false,
  "crowd_size": "1-5",
  "detected_language": "English",
  "translated_description": "${description}"
}`;
}

export async function POST(request: Request) {
  try {
    const auth = await requireRole(COMMAND_ROLES);
    if (!auth.ok) {
      return NextResponse.json({ error: auth.error }, { status: auth.status });
    }

    let body: { alertId?: unknown; kind?: unknown };
    try {
      body = await request.json();
    } catch {
      return NextResponse.json({ error: 'Malformed JSON body' }, { status: 400 });
    }

    const alertId = typeof body.alertId === 'string' ? body.alertId : '';
    const kind = body.kind as Kind;
    if (!alertId || (kind !== 'summary' && kind !== 'triage')) {
      return NextResponse.json(
        { error: "alertId and kind ('summary' | 'triage') are required" },
        { status: 400 }
      );
    }

    const { geminiApiKey } = serverEnv();
    if (!geminiApiKey) {
      // An explicit, distinguishable state. The triage caller has a rule-based
      // fallback and needs to know the difference between "AI is off" and
      // "AI broke"; the old client code could not tell those apart.
      return NextResponse.json({ status: 'UNCONFIGURED' }, { status: 200 });
    }

    const admin = getSupabaseAdmin();
    const { data: alert, error } = await admin
      .from('alerts')
      // `priority` was named here too. It is not a column in any migration —
      // both apps write `severity` — and PostgREST rejects a select naming an
      // unknown column IN FULL, so on a database without it this route
      // returned 400 for every incident rather than a triage. The prompt below
      // already falls back to `a.priority` if a row happens to carry one.
      .select('id, type, description, severity, geo_lga, geo_ward')
      .eq('id', alertId)
      .maybeSingle();

    if (error || !alert) {
      return NextResponse.json({ error: 'Alert not found' }, { status: 404 });
    }

    const prompt =
      kind === 'summary'
        ? summaryPrompt(alert as AlertRow)
        : triagePrompt(alert as AlertRow);

    // The key goes in a header, not the query string, so it cannot end up in
    // proxy logs or a Referer the way `?key=...` could.
    const res = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models/${MODEL}:generateContent`,
      {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'x-goog-api-key': geminiApiKey,
        },
        body: JSON.stringify({ contents: [{ parts: [{ text: prompt }] }] }),
      }
    );

    if (!res.ok) {
      // Logged server-side; not echoed, which would leak quota and account
      // detail to any authenticated dashboard user.
      console.error('[AI_ANALYZE] Gemini rejected the request:', res.status, await res.text());
      return NextResponse.json({ status: 'FAILED' }, { status: 200 });
    }

    const data = await res.json();
    const text = data?.candidates?.[0]?.content?.parts?.[0]?.text ?? '';

    // KEEP IT. This used to return the text and nothing more: the console put it
    // in React state, rendered it, and lost it when the dossier closed. So there
    // was nowhere for an administrator to see a report that had been generated,
    // every reopen billed the same analysis again, and — the one that matters —
    // there was no record of what the model said at the moment an officer acted
    // on it. A forensic assessment that lives until a browser tab closes cannot
    // be part of an audit trail.
    //
    // Written HERE, by the server that actually called Gemini, and INSERT on that
    // table is service-role only. If the browser wrote it, an operator could put
    // words in the model's mouth in the audit record and nothing downstream could
    // tell that from a real completion. See migration 20261014000000.
    if (text) {
      const { error: keepErr } = await admin.from('incident_ai_reports').insert({
        alert_id: alertId,
        kind,
        body: text,
        model: MODEL,
        requested_by: auth.userId,
      });
      if (keepErr) {
        // The analysis still goes back to the operator who asked for it. Losing
        // the record is bad; withholding a forensic debrief from the person
        // looking at the incident because a write failed is worse.
        console.error('[AI_ANALYZE] could not keep the report', keepErr);
      }
    }

    return NextResponse.json({ status: 'OK', text }, { status: 200 });
  } catch (err) {
    console.error('[AI_ANALYZE_ERR]', err);
    return NextResponse.json({ error: 'Internal server error' }, { status: 500 });
  }
}
