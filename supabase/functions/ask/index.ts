// Supabase Edge Function: "ask"
// Secure proxy to OpenAI. The OPENAI_API_KEY is stored as a Supabase secret and
// never reaches the browser or the public repo. Only signed-in users can call it
// (the platform verifies the JWT the app sends).
//
// Deploy: Supabase Dashboard → Edge Functions → create "ask" → paste this → Deploy.
// Secret: Dashboard → Edge Functions → Secrets → add OPENAI_API_KEY = <your new key>.

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "POST only" }, 405);

  const key = Deno.env.get("OPENAI_API_KEY");
  if (!key) return json({ error: "OPENAI_API_KEY secret is not set in Supabase." }, 500);

  let payload: any;
  try { payload = await req.json(); } catch { return json({ error: "Invalid JSON body." }, 400); }

  const question = String(payload?.question || "").slice(0, 4000);
  const history = Array.isArray(payload?.history) ? payload.history.slice(-8) : [];
  const data = payload?.tasks ?? {};
  if (!question) return json({ error: "Empty question." }, 400);

  const today = new Date().toISOString().slice(0, 10);
  const system =
    "You are the assistant inside a maintenance/project task tracker. " +
    "Answer the user's question and analyse their data (workload per person, overdue/at-risk tasks, " +
    "priorities, timelines, summaries, suggestions). Be concise and use short bullet points. " +
    "Reply in the user's language (English or Malay), matching their message. " +
    "Base answers ONLY on the DATA provided; if something isn't in the data, say so plainly. " +
    "Today's date is " + today + ".\n\nDATA (JSON):\n" +
    JSON.stringify(data).slice(0, 120000);

  const messages = [
    { role: "system", content: system },
    ...history.map((m: any) => ({
      role: m?.role === "user" ? "user" : "assistant",
      content: String(m?.content || "").slice(0, 4000),
    })),
    { role: "user", content: question },
  ];

  try {
    const r = await fetch("https://api.openai.com/v1/chat/completions", {
      method: "POST",
      headers: { "Authorization": `Bearer ${key}`, "Content-Type": "application/json" },
      body: JSON.stringify({ model: "gpt-4o-mini", messages, temperature: 0.2, max_tokens: 800 }),
    });
    const out = await r.json();
    if (!r.ok) return json({ error: out?.error?.message || ("OpenAI error " + r.status) }, 502);
    const answer = out?.choices?.[0]?.message?.content?.trim() || "(no answer)";
    return json({ answer });
  } catch (e) {
    return json({ error: "Upstream call failed: " + String(e) }, 502);
  }
});
