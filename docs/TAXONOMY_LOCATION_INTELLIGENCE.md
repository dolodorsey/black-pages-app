# THE BLACK PAGES — Taxonomy & Location Intelligence

THE BLACK PAGES is a Black-owned business directory, not an events feed.

## Canonical taxonomy

The live directory taxonomy is stored in `black_pages_categories` and `black_pages_subcategories`. The current production taxonomy contains 32 active master categories and 441 active business types. The UI reads this taxonomy directly, so new categories and types do not require hard-coded screen changes.

## Business submissions

`black-pages-application` accepts complete directory profiles: category, subcategory, public phone/email, address or service area, city, state, ZIP, business hours, specialties, photo URLs, website/social profiles, service radius, and Black-ownership evidence. Public submissions are validated server-side and remain unpublished until review.

## Location intelligence

The public directory reads `black_pages_directory_v2` and supports:

- WHAT search across business name, category, business type, services, description, and tags
- WHERE search across city, state, neighborhood, street address, ZIP, and service area
- city/state grouping with neighborhood and ZIP drill-down
- browser geolocation with a default 50-mile near-me radius
- distance sorting when coordinates exist
- shareable query-string searches using `q`, `where`, `category`, `subcategory`, and `sort`

## Coverage contract

Location infrastructure is national-ready, but UI copy must not imply nationwide listing population until source coverage actually supports that claim. Current counts shown in the app come from published directory data rather than marketing estimates.
