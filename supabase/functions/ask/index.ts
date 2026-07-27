// Supabase Edge Function: "ask"  (DEPLOYED version)
// Secure proxy to OpenAI. OPENAI_API_KEY is a Supabase secret — never in the browser or repo.
// Requires a signed-in user (validates the caller's JWT via /auth/v1/user) so the public
// publishable key alone cannot invoke it. Also set an OpenAI budget/usage limit as cost protection.
//
// Deploy: Dashboard -> Edge Functions -> function "ask" -> Code -> paste -> Deploy.
// Secret: Dashboard -> Edge Functions -> Secrets -> OPENAI_API_KEY = <your new key>.

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body, status) {
  return new Response(JSON.stringify(body), {
    status: status || 200,
    headers: Object.assign({ "Content-Type": "application/json" }, cors),
  });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "POST only" }, 405);

  // Require a real signed-in user (blocks anonymous publishable-key calls).
  const authz = req.headers.get("Authorization") || "";
  const apikeyH = req.headers.get("apikey") || "";
  if (authz.indexOf("Bearer ") !== 0) return json({ error: "Sign in required." }, 401);
  const SUPABASE_URL = Deno.env.get("SUPABASE_URL") || "https://xopvxkrorsndcvbtxnlw.supabase.co";
  try {
    const uRes = await fetch(SUPABASE_URL + "/auth/v1/user", { headers: { "apikey": apikeyH, "Authorization": authz } });
    if (!uRes.ok) return json({ error: "Sign in required." }, 401);
  } catch (_e) { return json({ error: "Auth check failed." }, 401); }

  const key = Deno.env.get("OPENAI_API_KEY");
  if (!key) return json({ error: "OPENAI_API_KEY secret is not set in Supabase." }, 500);

  let payload;
  try { payload = await req.json(); } catch (_e) { return json({ error: "Invalid JSON body." }, 400); }

  const question = String((payload && payload.question) || "").slice(0, 4000);
  const history = Array.isArray(payload && payload.history) ? payload.history.slice(-8) : [];
  const data = (payload && payload.tasks) || {};
  if (!question) return json({ error: "Empty question." }, 400);

  const today = new Date().toISOString().slice(0, 10);
  const system = "You are the assistant inside a maintenance and project task tracker. Answer the user question and analyse their data (workload per person, overdue or at-risk tasks, priorities, timelines, summaries, suggestions). Be concise and use short bullet points. Reply in the user language (English or Malay), matching their message. Base answers only on the DATA provided; if something is not in the data, say so plainly. Today date is " + today + ".";

  const messages = [
    { role: "system", content: system },
    { role: "system", content: "DATA (JSON): " + JSON.stringify(data).slice(0, 120000) },
  ];
  for (const m of history) {
    messages.push({ role: (m && m.role === "user") ? "user" : "assistant", content: String((m && m.content) || "").slice(0, 4000) });
  }
  messages.push({ role: "user", content: question });

  try {
    const r = await fetch("https://api.openai.com/v1/chat/completions", {
      method: "POST",
      headers: { "Authorization": "Bearer " + key, "Content-Type": "application/json" },
      body: JSON.stringify({ model: "gpt-4o-mini", messages: messages, temperature: 0.2, max_tokens: 800 }),
    });
    const out = await r.json();
    if (!r.ok) return json({ error: (out && out.error && out.error.message) || ("OpenAI error " + r.status) }, 502);
    const answer = (out && out.choices && out.choices[0] && out.choices[0].message && out.choices[0].message.content) ? out.choices[0].message.content.trim() : "(no answer)";
    return json({ answer: answer });
  } catch (e) {
    return json({ error: "Upstream call failed: " + String(e) }, 502);
  }
});
