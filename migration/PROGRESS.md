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
| 2 GitOps repo | done; helm lint/template pass for all variants |
| 3 Content repo | done; Antora build clean; image public; GitHub Pages preview live |
| 4 Code repo | done; tooling image public |
| 5 Provisioning | done: four bootstraps (about 10 min each); final cleanup.sh removed a full installation with participant content in one pass with verified end state; bootstrap #4 left running |
| 6 Smoke tests | done: platform-check 112/112 and isolation-check 44/44 on bootstrap #4; user-journey user1 76/76 on bootstraps #2 and #3; reset 11/11 |
| 7 Docs and handoff | done: FINAL-REPORT final; independent review round 3 passed all DoD items, its documentation notes fixed |

## Environment notes

- The Keycloak realm had per-user passwords; user1..user5 were reset to `WORKSHOP_USER_PASSWORD`
  (owner approved, 2026-09-24).
- quay.io repositories `inner-outer-loop-lab` and `workshop-tools` were made public by the owner.
- The owner added the `workflow` scope to the GitHub token; GitHub Pages was enabled for the
  content repository.
- A subagent accidentally created (and ~20 s later deleted) a Pipeline in namespace `default`;
  verified gone.
- The cluster is left with the workshop installed for 3 users (bootstrap #4).

## After the migration

- 2026-09-24: lab guide part selection for two-day events (`guidePart`, `--guide-part`,
  `set-guide-part.sh`, DECISIONS D19), tested on the cluster (FINAL-REPORT section 5).
- Next topic to discuss with the owner: unique passwords per user (credentials file proposal).

## Next

- Nothing open for the migration. Remaining manual work: screenshot recapture (SCREENSHOTS-TODO.md)
  and an event-specific password (KNOWN-ISSUES K12, K17).

## Blockers

- none
