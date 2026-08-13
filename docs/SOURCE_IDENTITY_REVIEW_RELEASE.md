# BLACK PAGES source + identity + review scale release

## Production data proof before merge
- 8,735 private candidate records
- 8,112 resolved business identities
- 253 multi-candidate identities
- 60 multi-source identities
- 623 duplicate discovery rows grouped into master identities
- 1,861 Ready business identities
- 935 Research business identities
- 5,316 Hold business identities
- 40 clean Atlanta Eats curated Black-owned restaurant candidates
- 0 identity-review actions created public directory records

## Source QA state
- Atlanta Eats current Black-owned restaurant guide: active, server-rendered, QA-passed; curated evidence routes to Research.
- ByBlack Certified: registered as high-trust certified source, but automated page extraction did not pass worker QA; inactive/reference only.
- SavorBLK: registered as verified Black food/hospitality source, but automated city-page extraction did not pass worker QA; inactive/reference only.
- Discover Atlanta Black-owned restaurant guide: source returned HTTP 403 to the worker; inactive/reference only.
- City of Atlanta, Georgia, Georgia Tech and Emory supplier/minority-diversity sources: cross-evidence references only; they never independently establish Black ownership.

## Review safety
Business identity review supports 25 / 50 / 100-business batches. A human reason is mandatory. Approval advances private verification only and returns `new_directory_records_published: 0`; publication remains separate.
