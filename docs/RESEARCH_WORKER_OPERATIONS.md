# BLACK PAGES research worker operations

BLACK PAGES uses only the canonical `black_pages_*` tables in the gateway
project. It does not use the legacy `bp_*` command-center tables in the GOOD
TIMES auth project.

The external `black-pages-research-worker` Edge Function claims due candidates,
checks public business websites, records evidence, and routes explicit ownership
language to the private human verification ledger. It never publishes a
candidate or marks an owner verified automatically.

Operational checks:

```sql
select count(*) from black_pages_candidate_queue;
select count(*) from black_pages_evidence_reviews;
select status, count(*) from black_pages_research_runs group by status;
select pipeline_stage, ownership_evidence_status, count(*)
from black_pages_candidate_queue group by 1, 2 order by 1, 2;
```

The internal tables intentionally have RLS enabled with no client policies and
all grants revoked from `anon` and `authenticated`. Advisor notices for those
tables are expected informational findings, not missing client access.

Rollback: unschedule `black-pages-research-worker` before removing the Edge
Function or its RPCs. Preserve candidate activity and evidence-review rows for
auditability; do not delete them during a worker rollback.
