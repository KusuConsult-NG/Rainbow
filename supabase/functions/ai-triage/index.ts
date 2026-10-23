import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.16.0";

const GEMINI_API_KEY = Deno.env.get("GEMINI_API_KEY") || "";
const SUPABASE_URL = Deno.env.get("SUPABASE_URL") || "";
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "";

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", {
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
      },
    });
  }

  try {
    const { text, latitude, longitude, reported_by } = await req.json();

    if (!text || text.trim().length === 0) {
      return new Response(JSON.stringify({ error: "Missing incident text" }), {
        status: 400,
        headers: { "Content-Type": "application/json" },
      });
    }

    // Call Gemini API for incident triage
    const prompt = `Analyze this voice incident report in Plateau State, Nigeria and classify it.
Report Text: "${text}"
Output ONLY valid JSON with keys:
"type": "SECURITY" | "HEALTH" | "FIRE" | "DISASTER" | "SUSPICIOUS_ACTIVITY",
"severity": "LOW" | "MEDIUM" | "HIGH" | "CRITICAL",
"summary": short 1-sentence summary`;

    const geminiRes = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash-latest:generateContent?key=${GEMINI_API_KEY}`,
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          contents: [{ parts: [{ text: prompt }] }],
        }),
      }
    );

    const geminiData = await geminiRes.json();
    const resultText = geminiData.candidates?.[0]?.content?.parts?.[0]?.text || "";

    let triageResult = {
      type: "SECURITY",
      severity: "HIGH",
      summary: text,
    };

    try {
      const jsonMatch = resultText.match(/\{[\s\S]*\}/);
      if (jsonMatch) {
        triageResult = JSON.parse(jsonMatch[0]);
      }
    } catch (_) {}

    // Save alert to Supabase
    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
    const { data: alert, error } = await supabase
      .from("alerts")
      .insert({
        type: triageResult.type,
        description: text,
        ai_summary: triageResult.summary,
        severity: triageResult.severity,
        // DO NOT INVENT A POSITION — and this one was WRITTEN, not drawn.
        //
        // This was `latitude || 9.9167, longitude || 8.8917`: the centre of
        // Jos, inserted into `alerts` as the position of a report that had no
        // fix. Not a display fallback that a later read could second-guess —
        // a row in the incident table, permanently, that every consumer
        // downstream reads as a measured position. The HQ map drew a confident
        // pin and a responder could be sent to it.
        //
        // `??` rather than `||` so a legitimate 0 survives. The app's
        // AlertService and the console both already do exactly this and say so;
        // this function was in the one tree the coordinate gate did not read.
        // See E2E_AUDIT_REPORT.md C-5, T-74 and T-84.
        latitude: latitude ?? null,
        longitude: longitude ?? null,
        reported_by: reported_by || null,
        status: "PENDING",
      })
      .select()
      .single();

    if (error) throw error;

    return new Response(JSON.stringify({ success: true, alert }), {
      headers: { "Content-Type": "application/json" },
    });
  } catch (err) {
    return new Response(JSON.stringify({ error: err.message }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }
});
