# THE BLACK PAGES — Bulk Discovery Engine

The bulk discovery engine keeps high-volume candidate acquisition separate from public publication.

## Throughput

- Bulk provider intake accepts up to 1,000 discovery records per call.
- Research claims support up to 100 candidates per worker run.
- Four staggered research dispatch lanes run every five minutes.
- Each research worker processes candidates in concurrent chunks of 10.

## Research lanes

- `black-pages-research-worker`: public website research.
- `black-pages-social-research-worker`: Instagram/social-only leads awaiting a legitimate social-profile research source.
- `black-pages-endpoint-enrichment`: candidates without a usable public research endpoint.

## Safety / quality contract

Bulk discovery records are private candidates only. They are not assumed to be Black-owned and cannot become public directory listings without the existing ownership-evidence review and publication gates.

## Sources currently seeded

The enterprise `contacts_master` reservoir is bulk-seeded into the private candidate queue with dedupe by business name and city plus a stable source key. The system can also accept future Places/search provider batches through `black_pages_bulk_ingest_discovery` without changing the public directory contract.
