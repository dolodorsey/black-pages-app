import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

type Candidate = {
  id: string; business_name: string; city: string; state: string | null;
  category: string | null; subcategory?: string | null; website_url: string | null;
  instagram_handle: string | null; public_email: string | null; public_phone: string | null;
  priority_score: number | string;
};

type FetchEvidence = {
  reachable: boolean; checked_url: string | null; final_url: string | null;
  fetch_status: number | null; content_type: string | null; page_title: string | null;
  explicit_ownership_evidence: boolean; ownership_evidence: string[]; error?: string; duration_ms: number;
};

const workerName = "black-pages-research-worker";
const maxBodyBytes = 400_000;
const concurrency = 10;
const ownershipPatterns = [
  /\b(?:proudly\s+)?black[\s-]+owned\b/gi,
  /\bblack[\s-]+woman[\s-]+owned\b/gi,
  /\bblack[\s-]+women[\s-]+owned\b/gi,
  /\bblack[\s-]+family[\s-]+owned\b/gi,
  /\bblack[\s-]+veteran[\s-]+owned\b/gi,
  /\bblack[\s-]+(?:founded|led|operated)\b/gi,
  /\bafrican[\s-]+american[\s-]+(?:owned|founded|led|operated)\b/gi,
];

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json", "Cache-Control": "no-store" } });
}

function isPrivateIpv4(hostname: string) {
  const p = hostname.split(".").map(Number);
  if (p.length !== 4 || p.some(v => !Number.isInteger(v) || v < 0 || v > 255)) return false;
  return p[0] === 10 || p[0] === 127 || p[0] === 0 ||
    (p[0] === 169 && p[1] === 254) || (p[0] === 172 && p[1] >= 16 && p[1] <= 31) ||
    (p[0] === 192 && p[1] === 168);
}

function validatePublicUrl(raw: string) {
  const url = new URL(raw);
  if (!["http:", "https:"].includes(url.protocol)) throw new Error("unsupported_protocol");
  const host = url.hostname.toLowerCase().replace(/\.$/, "");
  if (!host || host === "localhost" || host.endsWith(".localhost") || host.endsWith(".local") || host.endsWith(".internal")) throw new Error("blocked_hostname");
  if (host.includes(":") || isPrivateIpv4(host)) throw new Error("blocked_address");
  url.username = ""; url.password = "";
  return url;
}

async function readLimited(response: Response) {
  if (!response.body) return "";
  const reader = response.body.getReader(); const decoder = new TextDecoder();
  let total = 0; let output = "";
  try {
    while (total < maxBodyBytes) {
      const { value, done } = await reader.read(); if (done) break; if (!value) continue;
      const remaining = maxBodyBytes - total; const slice = value.byteLength > remaining ? value.slice(0, remaining) : value;
      output += decoder.decode(slice, { stream: true }); total += slice.byteLength;
      if (slice.byteLength < value.byteLength) break;
    }
    output += decoder.decode();
  } finally { await reader.cancel().catch(() => undefined); }
  return output;
}

function htmlToText(html: string) {
  return html.replace(/<!--[\s\S]*?-->/g, " ").replace(/<script\b[^>]*>[\s\S]*?<\/script>/gi, " ")
    .replace(/<style\b[^>]*>[\s\S]*?<\/style>/gi, " ").replace(/<noscript\b[^>]*>[\s\S]*?<\/noscript>/gi, " ")
    .replace(/<[^>]+>/g, " ").replace(/&nbsp;/gi, " ").replace(/&amp;/gi, "&").replace(/&quot;/gi, '"')
    .replace(/&#39;/gi, "'").replace(/\s+/g, " ").trim();
}

function titleFromHtml(html: string) {
  const match = html.match(/<title\b[^>]*>([\s\S]*?)<\/title>/i);
  return match ? htmlToText(match[1]).slice(0, 240) : null;
}

function extractOwnershipEvidence(text: string) {
  const snippets = new Set<string>();
  for (const pattern of ownershipPatterns) {
    pattern.lastIndex = 0; let match: RegExpExecArray | null;
    while ((match = pattern.exec(text)) && snippets.size < 5) {
      snippets.add(text.slice(Math.max(0, match.index - 90), Math.min(text.length, match.index + match[0].length + 120)).trim().slice(0, 320));
    }
  }
  return [...snippets];
}

function evidenceLinks(html: string, base: URL) {
  const links = new Set<string>(); const pattern = /href\s*=\s*["']([^"'#]+)["']/gi; let match: RegExpExecArray | null;
  while ((match = pattern.exec(html)) && links.size < 4) {
    if (!/(about|our[-_ ]?story|founder|ownership|mission|who[-_ ]?we[-_ ]?are)/i.test(match[1])) continue;
    try { const target = validatePublicUrl(new URL(match[1], base).toString()); if (target.hostname === base.hostname) links.add(target.toString()); } catch { /* ignore */ }
  }
  return [...links];
}

async function fetchText(target: URL, timeout = 7000) {
  let current = target; let response: Response | null = null;
  for (let redirect = 0; redirect <= 4; redirect += 1) {
    response = await fetch(current, { method: "GET", redirect: "manual", signal: AbortSignal.timeout(timeout), headers: {
      "User-Agent": "TheBlackPagesResearchBot/2.0 (+public business verification)",
      "Accept": "text/html,application/xhtml+xml;q=0.9,text/plain;q=0.8,*/*;q=0.2",
    }});
    if ([301,302,303,307,308].includes(response.status)) {
      const location = response.headers.get("location"); if (!location) break;
      current = validatePublicUrl(new URL(location, current).toString()); continue;
    }
    break;
  }
  if (!response) throw new Error("no_response");
  const contentType = response.headers.get("content-type");
  const html = !contentType || /text|html|xhtml|json/i.test(contentType) ? await readLimited(response) : "";
  return { response, html, current, contentType };
}

async function fetchPublicEvidence(candidate: Candidate): Promise<FetchEvidence> {
  const started = Date.now();
  if (!candidate.website_url) return { reachable:false,checked_url:null,final_url:null,fetch_status:null,content_type:null,page_title:null,explicit_ownership_evidence:false,ownership_evidence:[],error:"no_public_endpoint",duration_ms:Date.now()-started };
  let startUrl: URL;
  try { startUrl = validatePublicUrl(candidate.website_url); }
  catch (error) { return { reachable:false,checked_url:candidate.website_url,final_url:null,fetch_status:null,content_type:null,page_title:null,explicit_ownership_evidence:false,ownership_evidence:[],error:error instanceof Error ? error.message : "invalid_url",duration_ms:Date.now()-started }; }
  try {
    const first = await fetchText(startUrl, 7000); let evidence = extractOwnershipEvidence(htmlToText(first.html)); let evidenceUrl = first.current.toString();
    if (!evidence.length && first.response.ok && /html|xhtml/i.test(first.contentType || "text/html") && first.current.hostname !== "www.instagram.com") {
      for (const link of evidenceLinks(first.html, first.current).slice(0,2)) {
        try { const detail = await fetchText(validatePublicUrl(link), 5000); const found = extractOwnershipEvidence(htmlToText(detail.html)); if (found.length) { evidence = found; evidenceUrl = detail.current.toString(); break; } } catch { /* continue */ }
      }
    }
    return { reachable:first.response.status >= 200 && first.response.status < 500,checked_url:candidate.website_url,final_url:evidenceUrl,fetch_status:first.response.status,content_type:first.contentType,page_title:titleFromHtml(first.html),explicit_ownership_evidence:evidence.length>0,ownership_evidence:evidence,duration_ms:Date.now()-started };
  } catch (error) {
    return { reachable:false,checked_url:candidate.website_url,final_url:startUrl.toString(),fetch_status:null,content_type:null,page_title:null,explicit_ownership_evidence:false,ownership_evidence:[],error:error instanceof Error ? error.message.slice(0,300) : "fetch_failed",duration_ms:Date.now()-started };
  }
}

Deno.serve(async request => {
  if (request.method !== "POST") return json({ error: "Method not allowed" }, 405);
  const supabaseUrl = Deno.env.get("SUPABASE_URL"); const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceRoleKey) return json({ error: "Worker environment is incomplete" }, 500);
  const supabase = createClient(supabaseUrl, serviceRoleKey, { auth: { persistSession:false, autoRefreshToken:false } });
  const workerToken = request.headers.get("x-worker-token") || "";
  const { data: authorized, error: authError } = await supabase.rpc("black_pages_authorize_worker_token", { p_token: workerToken });
  if (authError || authorized !== true) return json({ error: "Unauthorized" }, 401);

  let payload: { limit?: number } = {}; try { payload = await request.json(); } catch { payload = {}; }
  const limit = Math.min(100, Math.max(1, Number(payload.limit) || 50));
  const { data: claim, error: claimError } = await supabase.rpc("black_pages_claim_research_batch", { p_limit: limit, p_worker: workerName });
  if (claimError) return json({ error: claimError.message }, 500);
  const runId = String(claim?.run_id || ""); const candidates = Array.isArray(claim?.candidates) ? claim.candidates as Candidate[] : [];
  if (!runId) return json({ error: "Worker did not receive a run ID" }, 500);
  if (!candidates.length) return json({ ok:true,run_id:runId,claimed:0,processed:0,concurrency });

  const outcomes: unknown[] = []; let fatalError = "";
  try {
    for (let offset = 0; offset < candidates.length; offset += concurrency) {
      const chunk = candidates.slice(offset, offset + concurrency);
      const settled = await Promise.allSettled(chunk.map(async candidate => {
        const evidence = await fetchPublicEvidence(candidate);
        const { data: result, error } = await supabase.rpc("black_pages_complete_research_candidate", { p_run_id:runId,p_candidate_id:candidate.id,p_result:evidence,p_worker:workerName });
        return error ? { candidate_id:candidate.id,error:error.message } : result;
      }));
      for (const item of settled) outcomes.push(item.status === "fulfilled" ? item.value : { error: item.reason instanceof Error ? item.reason.message : "candidate_failed" });
    }
  } catch (error) { fatalError = error instanceof Error ? error.message : "worker_failed"; }

  const { data: finalRun, error: finalizeError } = await supabase.rpc("black_pages_finalize_research_run", { p_run_id:runId,p_error:fatalError || null });
  if (finalizeError) return json({ error:finalizeError.message,run_id:runId,outcomes },500);
  return json({ ok:!fatalError,run_id:runId,claimed:candidates.length,processed:outcomes.length,concurrency,run:finalRun,outcomes },fatalError ? 500 : 200);
});
