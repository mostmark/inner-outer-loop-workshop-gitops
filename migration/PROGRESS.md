# Migration progress

## Environment

| Item | Value |
|---|---|
| Cluster API | `https://api.cluster-khd65.dyn.redhatworkshops.io:6443` |
| Cluster version | OpenShift 4.22.14 (Kubernetes v1.35.6), single node, 32 vCPU / 128 GiB, x86_64 |
| Identity provider | `rhbk` (OpenID, Red Hat build of Keycloak); workshop users `user1..userN` |
| Pre-installed | cert-manager, RHBK (keycloak), ODF external storage (default SC `ocs-external-storagecluster-ceph-rbd`) |
| Operator (admin) | `admin` |

## Status

| Phase | State |
|---|---|
| 0 Orientation | done (CLAUDE.md in the workspace root) |
| 1 Inventory | done (`COMPONENT-INVENTORY.md`) |
| 2 GitOps repo | done: charts, bootstrap, cleanup, print-user-urls, README; helm lint/template pass for all variants |
| 3 Content repo | done: 15 pages, Antora build clean, image `quay.io/mostmark/inner-outer-loop-lab:latest` public, Pages workflow enabled |
| 4 Code repo | done: devfile, .tasks, pipelines, labs, tooling image `quay.io/mostmark/workshop-tools:latest` public |
| 5 Provisioning | first bootstrap (3 users) green; cleanup + second bootstrap pending |
| 6 Smoke tests | platform-check 109/112 then fixed check URLs; isolation-check 37/37; user-journey user1 running |
| 7 Docs and handoff | README, MIGRATION, DECISIONS, KNOWN-ISSUES, SCREENSHOTS-TODO written; FINAL-REPORT pending; independent review pending |

## Environment notes

- The Keycloak realm had per-user passwords; user1..user5 were reset to `WORKSHOP_USER_PASSWORD`
  (owner approved, 2026-09-24).
- quay.io repositories `inner-outer-loop-lab` and `workshop-tools` were made public by the owner.
- A subagent accidentally created (and ~20 s later deleted) a Pipeline in namespace `default`;
  verified gone.

## Next

1. Finish `user-journey.sh user1` (fix: inventory endpoint is `/api/inventory/329299`), fix findings.
2. `user-journey.sh user1 --reset`, then `cleanup.sh --yes`, confirm the cluster is near-empty,
   `bootstrap.sh --users 3` from scratch, rerun all smoke tests.
3. Measure the per-user footprint, write FINAL-REPORT.md, fill the README sizing table.
4. Independent review subagent; fix gaps; repeat.

## Blockers

- none
