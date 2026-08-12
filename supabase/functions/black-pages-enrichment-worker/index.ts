import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

type Candidate = {
  id: string;
  source_id: string;
  business_name: string;
  city: string;
  state: string | null;
  website_url: string | null;
  instagram_handle: string | null;
  google_place_id: string | null;
  attempt_count: number;
};

type LocationResult = {
  address: string | null;
  postal_code: string | null;
  latitude: number | null;
  longitude: number | null;
  confidence: 'high' | 'low' | 'none';
  source: string;
  source_url: string | null;
  reason?: string;
};

const workerName = 'black-pages-enrichment-worker';
const maxBytes = 700_000;
const detailLinkPattern = /(contact|location|visit|find[-_ ]?us|directions|about)/i;

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' } });
}

function isPrivateIpv4(hostname: string) {
  const p = hostname.split('.').map(Number);
  if (p.length !== 4 || p.some(x => !Number.isInteger(x) || x < 0 || x > 255)) return false;
  return p[0] === 10 || p[0] === 127 || p[0] === 0 || (p[0] === 169 && p[1] === 254) || (p[0] === 172 && p[1] >= 16 && p[1] <= 31) || (p[0] === 192 && p[1] === 168);
}

function publicUrl(raw: string) {
  const url = new URL(raw);
  if (!['http:', 'https:'].includes(url.protocol)) throw new Error('unsupported_protocol');
  const host = url.hostname.toLowerCase().replace(/\.$/, '');
  if (!host || host === 'localhost' || host.endsWith('.local') || host.endsWith('.internal') || host.includes(':') || isPrivateIpv4(host)) throw new Error('blocked_host');
  url.username = ''; url.password = '';
  return url;
}

async function fetchText(raw: string) {
  let current = publicUrl(raw);
  let response: Response | null = null;
  for (let i = 0; i < 4; i += 1) {
    response = await fetch(current, {
      redirect: 'manual', signal: AbortSignal.timeout(9000),
      headers: { 'User-Agent': 'TheBlackPagesEnrichmentBot/1.1 (+public business data enrichment)', 'Accept': 'text/html,application/xhtml+xml,text/plain;q=0.8,*/*;q=0.2' },
    });
    if ([301,302,303,307,308].includes(response.status)) {
      const location = response.headers.get('location');
      if (!location) break;
      current = publicUrl(new URL(location, current).toString());
      continue;
    }
    break;
  }
  if (!response) throw new Error('no_response');
  const type = response.headers.get('content-type') || '';
  if (!/text|html|xhtml|json/i.test(type)) return { text: '', url: current.toString(), status: response.status };
  const reader = response.body?.getReader();
  if (!reader) return { text: '', url: current.toString(), status: response.status };
  const decoder = new TextDecoder(); let out = ''; let total = 0;
  try {
    while (total < maxBytes) {
      const { value, done } = await reader.read(); if (done) break; if (!value) continue;
      const remaining = maxBytes - total; const slice = value.byteLength > remaining ? value.slice(0, remaining) : value;
      out += decoder.decode(slice, { stream: true }); total += slice.byteLength;
      if (slice.byteLength < value.byteLength) break;
    }
    out += decoder.decode();
  } finally { await reader.cancel().catch(() => undefined); }
  return { text: out, url: current.toString(), status: response.status };
}

function cleanString(value: unknown) { return typeof value === 'string' ? value.replace(/\s+/g, ' ').trim() : ''; }
function num(value: unknown) { const n = typeof value === 'number' ? value : Number(value); return Number.isFinite(n) ? n : null; }
function escapeRegex(value: string) { return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'); }
function cityMatches(value: string, candidate: Candidate) { return !value || value.toLowerCase().includes(candidate.city.toLowerCase()) || candidate.city.toLowerCase().includes(value.toLowerCase()); }
function stateMatches(value: string, candidate: Candidate) { return !candidate.state || !value || value.toUpperCase() === candidate.state.toUpperCase(); }

function htmlToText(html: string) {
  return html.replace(/<!--[\s\S]*?-->/g, ' ').replace(/<script\b[^>]*>[\s\S]*?<\/script>/gi, ' ').replace(/<style\b[^>]*>[\s\S]*?<\/style>/gi, ' ').replace(/<[^>]+>/g, ' ').replace(/&nbsp;/gi, ' ').replace(/&amp;/gi, '&').replace(/&#39;/gi, "'").replace(/&quot;/gi, '"').replace(/\s+/g, ' ').trim();
}

function fromAddressObject(address: Record<string, unknown>, geo: Record<string, unknown> | null, candidate: Candidate, source: string, sourceUrl: string): LocationResult | null {
  const street = cleanString(address.streetAddress);
  const locality = cleanString(address.addressLocality);
  const region = cleanString(address.addressRegion);
  const postal = cleanString(address.postalCode);
  if (!street && !locality && !postal && !geo) return null;
  if (!cityMatches(locality, candidate) || !stateMatches(region, candidate)) return null;
  const parts = [street, locality, region && postal ? `${region} ${postal}` : region || postal].filter(Boolean);
  const lat = geo ? num(geo.latitude) : null; const lng = geo ? num(geo.longitude) : null;
  const validGeo = lat != null && lng != null && Math.abs(lat) <= 90 && Math.abs(lng) <= 180;
  return { address: street ? parts.join(', ') : null, postal_code: postal || null, latitude: validGeo ? lat : null, longitude: validGeo ? lng : null, confidence: street || validGeo ? 'high' : 'low', source, source_url: sourceUrl };
}

function walkJson(value: unknown, candidate: Candidate, sourceUrl: string): LocationResult | null {
  if (Array.isArray(value)) {
    for (const item of value) { const found = walkJson(item, candidate, sourceUrl); if (found?.confidence === 'high') return found; }
    return null;
  }
  if (!value || typeof value !== 'object') return null;
  const obj = value as Record<string, unknown>;
  if (obj.address && typeof obj.address === 'object') {
    const geo = obj.geo && typeof obj.geo === 'object' ? obj.geo as Record<string, unknown> : null;
    const found = fromAddressObject(obj.address as Record<string, unknown>, geo, candidate, 'official_website_structured_data', sourceUrl);
    if (found?.confidence === 'high') return found;
  }
  for (const child of Object.values(obj)) { const found = walkJson(child, candidate, sourceUrl); if (found?.confidence === 'high') return found; }
  return null;
}

function structuredLocation(html: string, candidate: Candidate, sourceUrl: string) {
  for (const match of html.matchAll(/<script\b[^>]*type=["']application\/ld\+json["'][^>]*>([\s\S]*?)<\/script>/gi)) {
    try { const found = walkJson(JSON.parse(match[1].trim()), candidate, sourceUrl); if (found?.confidence === 'high') return found; } catch { /* Ignore malformed publisher JSON-LD. */ }
  }
  const lat = html.match(/(?:place:location:latitude|latitude)["'][^>]*content=["'](-?\d{1,3}(?:\.\d+)?)/i)?.[1] || html.match(/content=["'](-?\d{1,3}(?:\.\d+)?)["'][^>]*(?:place:location:latitude|latitude)/i)?.[1];
  const lng = html.match(/(?:place:location:longitude|longitude)["'][^>]*content=["'](-?\d{1,3}(?:\.\d+)?)/i)?.[1] || html.match(/content=["'](-?\d{1,3}(?:\.\d+)?)["'][^>]*(?:place:location:longitude|longitude)/i)?.[1];
  const latN = num(lat), lngN = num(lng);
  if (latN != null && lngN != null && Math.abs(latN) <= 90 && Math.abs(lngN) <= 180) return { address: null, postal_code: null, latitude: latN, longitude: lngN, confidence: 'high' as const, source: 'official_website_geo_meta', source_url: sourceUrl };
  return null;
}

function textAddress(html: string, candidate: Candidate, sourceUrl: string): LocationResult | null {
  const text = htmlToText(html);
  const city = escapeRegex(candidate.city);
  const state = candidate.state ? escapeRegex(candidate.state) : '[A-Z]{2}';
  const streetType = '(?:Street|St\\.?|Avenue|Ave\\.?|Road|Rd\\.?|Boulevard|Blvd\\.?|Drive|Dr\\.?|Lane|Ln\\.?|Way|Court|Ct\\.?|Parkway|Pkwy\\.?|Highway|Hwy\\.?|Place|Pl\\.?|Circle|Cir\\.?)';
  const regex = new RegExp(`\\b\\d{1,6}\\s+[A-Za-z0-9.'#&\\- ]{2,70}\\s${streetType}[, ]{1,3}[A-Za-z0-9.'#&\\- ]{0,35}${city}[, ]{1,3}${state}(?:\\s+\\d{5}(?:-\\d{4})?)?`, 'i');
  const match = text.match(regex)?.[0]?.replace(/\s+/g, ' ').trim();
  if (!match) return null;
  const postal = match.match(/\b\d{5}(?:-\d{4})?\b/)?.[0] || null;
  return { address: match, postal_code: postal, latitude: null, longitude: null, confidence: 'high', source: 'official_website_contact_text', source_url: sourceUrl };
}

function internalDetailLinks(html: string, base: string) {
  const baseUrl = new URL(base); const links = new Set<string>();
  for (const match of html.matchAll(/href\s*=\s*["']([^"'#]+)["']/gi)) {
    if (!detailLinkPattern.test(match[1])) continue;
    try { const url = publicUrl(new URL(match[1], baseUrl).toString()); if (url.hostname === baseUrl.hostname) links.add(url.toString()); } catch { /* Ignore unsafe links. */ }
    if (links.size >= 5) break;
  }
  return [...links];
}

function googleEmbeddedLocation(html: string, candidate: Candidate, sourceUrl: string): LocationResult | null {
  const decoded = html.replace(/\\u0026/g, '&').replace(/\\u003d/g, '=').replace(/\\u0027/g, "'").replace(/\\u0022/g, '"').replace(/\\\"/g, '"');
  const candidates = [
    decoded.match(/"(?:formattedAddress|address)"\s*:\s*"([^"\n]{8,220})"/i)?.[1],
    decoded.match(new RegExp(`"([^"\\n]{4,180}${escapeRegex(candidate.city)}[, ]+${escapeRegex(candidate.state || '')}\\s+\\d{5}(?:-\\d{4})?)"`, 'i'))?.[1],
  ].filter((value): value is string => Boolean(value));
  for (const raw of candidates) {
    const formatted = raw.replace(/\\n/g, ', ').replace(/\\u003d/g, '=').trim();
    if (!formatted.toLowerCase().includes(candidate.city.toLowerCase())) continue;
    if (candidate.state && !new RegExp(`\\b${escapeRegex(candidate.state)}\\b`, 'i').test(formatted)) continue;
    const postal = formatted.match(/\b\d{5}(?:-\d{4})?\b/)?.[0] || null;
    return { address: formatted, postal_code: postal, latitude: null, longitude: null, confidence: 'high', source: 'google_maps_public_page', source_url: sourceUrl };
  }
  return null;
}

async function enrich(candidate: Candidate): Promise<LocationResult> {
  if (candidate.website_url) {
    try {
      const home = await fetchText(candidate.website_url);
      if (home.status >= 200 && home.status < 500) {
        const homeFound = structuredLocation(home.text, candidate, home.url) || textAddress(home.text, candidate, home.url);
        if (homeFound?.confidence === 'high') return homeFound;
        for (const link of internalDetailLinks(home.text, home.url).slice(0, 3)) {
          try {
            const detail = await fetchText(link);
            if (detail.status < 200 || detail.status >= 500) continue;
            const detailFound = structuredLocation(detail.text, candidate, detail.url) || textAddress(detail.text, candidate, detail.url);
            if (detailFound?.confidence === 'high') return detailFound;
          } catch { /* Try the next same-site detail page. */ }
        }
      }
    } catch { /* Fall through to place-id lookup. */ }
  }

  if (candidate.google_place_id) {
    try {
      const maps = `https://www.google.com/maps/search/?api=1&query=${encodeURIComponent(candidate.business_name + ' ' + candidate.city)}&query_place_id=${encodeURIComponent(candidate.google_place_id)}`;
      const page = await fetchText(maps);
      const found = googleEmbeddedLocation(page.text, candidate, page.url);
      if (found?.confidence === 'high') return found;
    } catch { /* Queue will route unresolved rows to manual review after bounded attempts. */ }
  }

  return { address: null, postal_code: null, latitude: null, longitude: null, confidence: 'none', source: 'public_web_lookup', source_url: candidate.website_url, reason: 'No high-confidence public location found' };
}

Deno.serve(async (request) => {
  if (request.method !== 'POST') return json({ error: 'Method not allowed' }, 405);
  const url = Deno.env.get('SUPABASE_URL'); const key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!url || !key) return json({ error: 'Worker environment is incomplete' }, 500);
  const supabase = createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } });
  const token = request.headers.get('x-worker-token') || '';
  const { data: authorized, error: authError } = await supabase.rpc('black_pages_authorize_worker_token', { p_token: token });
  if (authError || authorized !== true) return json({ error: 'Unauthorized' }, 401);
  let body: { limit?: number } = {}; try { body = await request.json(); } catch { body = {}; }
  const limit = Math.min(25, Math.max(1, Number(body.limit) || 25));
  const { data: claim, error: claimError } = await supabase.rpc('black_pages_claim_source_enrichment_batch', { p_limit: limit, p_worker: workerName });
  if (claimError) return json({ error: claimError.message }, 500);
  const candidates = Array.isArray(claim?.candidates) ? claim.candidates as Candidate[] : [];
  const outcomes: unknown[] = [];
  for (const candidate of candidates) {
    const result = await enrich(candidate);
    const { data, error } = await supabase.rpc('black_pages_complete_source_enrichment', { p_queue_id: candidate.id, p_result: result, p_worker: workerName });
    outcomes.push(error ? { id: candidate.id, error: error.message } : data);
  }
  return json({ ok: true, claimed: candidates.length, processed: outcomes.length, outcomes });
});
