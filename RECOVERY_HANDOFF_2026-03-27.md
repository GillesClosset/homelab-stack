# Recovery Handoff — 2026-03-27

## Outcome

- Restic-based recovery of the infra stack is considered successful.
- `Finance_dashboard/` was restored and is maintained as a separate Git repository.
- Runtime-critical `supabase/docker/` files were restored sufficiently for the current stack.
- Parent infra repository is now tracked at `GillesClosset/homelab-stack`.

## Decisions

- `graphiti-mcp` is disabled by default in `docker-compose.yml` and only enabled via the `graphiti` profile.
- `Finance_dashboard` remains a separate application repository; infra stays in this repo.
- The new Neo4j knowledge-graph schema is the active production path.
- The previous KG schema is deprecated and should not receive new work except explicit rollback/archive needs.

## Current repo posture

- This repo is the infra/platform repository for the homelab stack.
- It should contain deployment/runtime source, not secrets, certificates, live data, or disposable artifacts.
- `Finance_dashboard` app changes should be committed in its own repo.

## Recommended next-session starting point

- Assume recovery is complete unless a specific missing path is reported.
- Treat KG adoption as closed; only cleanup, docs, or follow-up hardening should reopen that area.
- Make future infra changes in this repo and future Finance app changes in `Finance_dashboard`.
