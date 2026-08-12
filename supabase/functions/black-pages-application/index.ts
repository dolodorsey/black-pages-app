import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const exactOrigins = new Set([
  "https://the-black-pages.vercel.app",
  "https://the-black-pages-dr-dorseys-projects.vercel.app",
  "https://black-pages.vercel.app",
  "http://localhost:5173",
  "http://127.0.0.1:5173",
  "capacitor://localhost",
]);

function originAllowed(origin: string | null) {
  if (!origin) return true;
  if (exactOrigins.has(origin)) return true;
  try {
    const url = new URL(origin);
    return url.protocol === "https:" && /^the-black-pages-[a-z0-9-]+-dr-dorseys-projects\.vercel\.app$/i.test(url.hostname);
  } catch {
    return false;
  }
}

function cors(origin: string | null) {
  return {
    "Access-Control-Allow-Origin": originAllowed(origin) && origin ? origin : "",
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Vary": "Origin",
  };
}

function json(body: unknown, status: number, origin: string | null) {
  return new Response(JSON.stringify(body), { status, headers: { ...cors(origin), "Content-Type": "application/json" } });
}

function cleanText(payload: Record<string, unknown>, key: string, max: number) {
  return typeof payload[key] === "string" ? String(payload[key]).trim().slice(0, max) : "";
}

function cleanUrl(value: string) {
  if (!value) return "";
  try {
    const url = new URL(value);
    return url.protocol === "http:" || url.protocol === "https:" ? url.toString() : "";
  } catch {
    return "";
  }
}

function cleanList(value: unknown, maxItems: number, maxLength: number) {
  if (!Array.isArray(value)) return [] as string[];
  return value.filter((item): item is string => typeof item === "string").map((item) => item.trim().slice(0, maxLength)).filter(Boolean).slice(0, maxItems);
}

function cleanUrlList(value: unknown, maxItems: number) {
  return cleanList(value, maxItems, 600).map(cleanUrl).filter(Boolean);
}

Deno.serve(async (req) => {
  const origin = req.headers.get("origin");
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: cors(origin) });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405, origin);
  if (!originAllowed(origin)) return json({ error: "Origin not allowed" }, 403, origin);

  let payload: Record<string, unknown>;
  try { payload = await req.json(); } catch { return json({ error: "Invalid JSON" }, 400, origin); }

  const businessName = cleanText(payload, "businessName", 140);
  const ownerName = cleanText(payload, "ownerName", 120);
  const contactEmail = cleanText(payload, "contactEmail", 254).toLowerCase();
  const contactPhone = cleanText(payload, "contactPhone", 30);
  const businessEmail = cleanText(payload, "businessEmail", 254).toLowerCase();
  const businessPhone = cleanText(payload, "businessPhone", 30);
  const category = cleanText(payload, "category", 100);
  const subcategory = cleanText(payload, "subcategory", 100);
  const addressLine1 = cleanText(payload, "addressLine1", 180);
  const addressLine2 = cleanText(payload, "addressLine2", 120);
  const neighborhood = cleanText(payload, "neighborhood", 120);
  const city = cleanText(payload, "city", 100);
  const state = cleanText(payload, "state", 2).toUpperCase();
  const postalCode = cleanText(payload, "postalCode", 10);
  const serviceArea = cleanText(payload, "serviceArea", 240);
  const websiteUrlRaw = cleanText(payload, "websiteUrl", 600);
  const websiteUrl = cleanUrl(websiteUrlRaw);
  const instagramHandle = cleanText(payload, "instagramHandle", 100).replace(/^@/, "");
  const facebookUrl = cleanUrl(cleanText(payload, "facebookUrl", 600));
  const linkedinUrl = cleanUrl(cleanText(payload, "linkedinUrl", 600));
  const tiktokUrl = cleanUrl(cleanText(payload, "tiktokUrl", 600));
  const description = cleanText(payload, "description", 1600);
  const hoursSummary = cleanText(payload, "hoursSummary", 1000);
  const specialties = cleanList(payload.specialties, 12, 80);
  const photoUrls = cleanUrlList(payload.photoUrls, 8);
  const ownershipProofUrls = cleanUrlList(payload.ownershipProofUrls, 5);
  const ownershipCertification = payload.ownershipCertification === true;
  const servesCustomersAtLocation = payload.servesCustomersAtLocation !== false;
  const serviceRadiusCandidate = Number(payload.serviceRadiusMiles ?? 0);
  const serviceRadiusMiles = Number.isFinite(serviceRadiusCandidate) && serviceRadiusCandidate >= 0 && serviceRadiusCandidate <= 500 ? Math.round(serviceRadiusCandidate) : null;

  if (!businessName || !ownerName || !category || !subcategory || !city || !state || !postalCode || !description || !ownershipCertification) return json({ error: "Complete all required business, category, location, and ownership fields." }, 400, origin);
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(contactEmail)) return json({ error: "Enter a valid contact email address." }, 400, origin);
  if (businessEmail && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(businessEmail)) return json({ error: "Enter a valid public business email address." }, 400, origin);
  if (!/^[A-Z]{2}$/.test(state)) return json({ error: "Enter a valid two-letter state." }, 400, origin);
  if (!/^\d{5}(-\d{4})?$/.test(postalCode)) return json({ error: "Enter a valid ZIP code." }, 400, origin);
  if (websiteUrlRaw && !websiteUrl) return json({ error: "Website must be a valid http:// or https:// URL." }, 400, origin);
  if (servesCustomersAtLocation && !addressLine1) return json({ error: "Enter the business street address or turn off customer visits at this location." }, 400, origin);
  if (!servesCustomersAtLocation && !serviceArea) return json({ error: "Enter the service area for a mobile or service-area business." }, 400, origin);
  if (ownershipProofUrls.length < 1) return json({ error: "Add at least one ownership proof link for directory verification." }, 400, origin);

  const supabase = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  const [{ data: categoryRow }, { data: subcategoryRow }] = await Promise.all([
    supabase.from("black_pages_categories").select("slug").eq("slug", category).eq("active", true).maybeSingle(),
    supabase.from("black_pages_subcategories").select("slug").eq("category_slug", category).eq("slug", subcategory).eq("active", true).maybeSingle(),
  ]);
  if (!categoryRow || !subcategoryRow) return json({ error: "Choose a valid active category and subcategory." }, 400, origin);

  const since = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();
  const { count } = await supabase.from("black_pages_applications").select("id", { count: "exact", head: true }).eq("contact_email", contactEmail).gte("created_at", since);
  if ((count ?? 0) >= 3) return json({ error: "Application limit reached. Try again tomorrow." }, 429, origin);

  const forwarded = req.headers.get("x-forwarded-for")?.split(",")[0]?.trim() ?? "";
  const digest = forwarded ? Array.from(new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(forwarded)))).map((b) => b.toString(16).padStart(2, "0")).join("") : null;

  const { error } = await supabase.from("black_pages_applications").insert({
    business_name: businessName, owner_name: ownerName, contact_email: contactEmail, contact_phone: contactPhone || null,
    category, subcategory, address_line1: addressLine1 || null, address_line2: addressLine2 || null, neighborhood: neighborhood || null,
    city, state, postal_code: postalCode, service_area: serviceArea || null, business_phone: businessPhone || null, business_email: businessEmail || null,
    website_url: websiteUrl || null, instagram_handle: instagramHandle || null, facebook_url: facebookUrl || null, linkedin_url: linkedinUrl || null, tiktok_url: tiktokUrl || null,
    description, hours: hoursSummary ? { summary: hoursSummary } : null, specialties, photo_urls: photoUrls, ownership_proof_urls: ownershipProofUrls,
    ownership_certification: true, serves_customers_at_location: servesCustomersAtLocation, service_radius_miles: serviceRadiusMiles, source_ip_hash: digest,
  });

  if (error) return json({ error: "Business could not be submitted." }, 500, origin);
  return json({ ok: true }, 201, origin);
});
