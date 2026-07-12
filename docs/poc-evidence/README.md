# Zero Trust Landing Zone — POC Evidence & Case Study

**Tenant**: ict-cloud.solutions
**Role**: Architect / Builder / Cloud Platform & Security Engineer
**Status**: 🟡 In progress — updated as each step is completed
**Purpose**: Portfolio evidence for client and employer conversations, and
working proof that this architecture deploys and functions as designed.

> How to use this doc: as you complete each step in the POC plan, replace
> the `_Pending_` marker with a 2–4 sentence summary of what happened
> (including anything that didn't go to plan — that's evidence of judgement,
> not a weakness to hide) and drop the screenshot into
> `docs/poc-evidence/screenshots/` using the filename shown, then reference
> it inline. Keep this doc narrative, not just a checklist — it's the thing
> you'll actually walk a client or interviewer through.

---

## Executive summary

_Pending — write this last, once the POC is complete. 3–4 sentences:
what was built, what it proves, what's next (Phase 2)._

---

## Architecture recap

See main `README.md` for the full diagram and persona model. This
document tracks the **evidence that it actually works**, not the design.

---

## Step-by-step evidence log

### 1. Dedicated subscription + resource group

- **What was done**: _Pending_
- **Screenshot**: `screenshots/01-subscription-overview.png`
- **Notes**:

### 2. Custom domain verification (ict-cloud.solutions)

- **What was done**: _Pending_
- **Screenshot**: `screenshots/02-verified-domain.png`
- **Notes**:

### 3. Break-glass accounts

- **What was done**: _Pending_
- **Screenshot**: `screenshots/03-breakglass-ca-exclusion.png`
- **Notes**: Confirm sign-in test performed and successful *before* any CA
  policy was set to enforced.

### 4. Repo + OIDC federated credential

- **What was done**: _Pending_
- **Screenshot**: `screenshots/04-github-actions-login-success.png`
- **Notes**: Record the federated credential subject claim used, and
  confirm no client secret exists anywhere in the app registration.

### 5. Central Log Analytics + Sentinel + Defender for Cloud

- **What was done**: _Pending_
- **Screenshots**:
  - `screenshots/05a-log-analytics-workspace.png`
  - `screenshots/05b-sentinel-workspace-overview.png`
  - `screenshots/05c-defender-secure-score.png`
- **Notes**: Note starting vs. post-deploy Secure Score.

### 6. Custom RBAC roles + PIM eligible assignments

- **What was done**: _Pending_
- **Screenshot**: `screenshots/06-pim-eligible-assignments.png`
- **Notes**: Confirm zero standing (active/permanent) privileged
  assignments exist — this is the core Zero Trust claim, so it needs to
  be provably true here.

### 7. Conditional Access — report-only bake period

- **Bake period**: _Pending_ (start date) → _Pending_ (end date, min 3–5 days)
- **What was done**: _Pending_
- **Screenshot**: `screenshots/07-ca-insights-reporting.png`
- **Notes**: Record anything the simulation flagged that would have
  blocked legitimate access — and what you changed as a result. This is
  the single most convincing piece of evidence of engineering judgement
  in the whole POC.

### 8. Conditional Access — enforced + persona testing

- **What was done**: _Pending_
- **Screenshots**:
  - `screenshots/08a-employee-signin-mfa-enforced.png`
  - `screenshots/08b-guest-access-package-request.png`
  - `screenshots/08c-guest-signin-tou-session-controls.png`
- **Notes**: Document the guest onboarding end-to-end — Access Package
  request → approval → sign-in with ToU/session restrictions applied.

### 9. Sentinel analytics rules — triggered and validated

- **What was done**: _Pending_
- **Screenshot**: `screenshots/09-sentinel-incident-triggered.png`
- **Notes**: State exactly what action you took to deliberately trigger
  each rule (e.g. "activated Application Administrator role at 22:00 UTC
  to trigger CA030") — this proves the detection actually fires, not just
  that the KQL compiles.

### 10. Full CI/CD pipeline run

- **What was done**: First successful end-to-end run: PR #14 merged to
  `main` at 2026-07-12 05:34 UTC, triggering `lint-and-scan` → `what-if` →
  manual environment approval → `deploy`, which completed at 05:42 UTC
  (7m 11s total). All three post-deploy validation steps passed (Bicep
  deployment, Defender Secure Score check, Sentinel analytics rules
  enabled check). See the run itself:
  [actions/runs/29181378793](https://github.com/sufideen/ztr-entra-lz/actions/runs/29181378793).
  This followed a chain of 7 PRs (#8–#14) fixing issues that only
  surfaced once real deployments ran — see "What didn't go to plan" below.
- **Screenshots**:
  - `screenshots/10a-pr-lint-scan-results.png`
  - `screenshots/10b-whatif-output.png`
  - `screenshots/10c-environment-approval-gate.png`
  - `screenshots/10d-deploy-success.png`
- **Notes**: Link the actual GitHub Actions run if the repo is public.

### 11. Compliance evidence

- **What was done**: _Pending_
- **Screenshot**: `screenshots/11-policy-compliance-dashboard.png`
- **Notes**: Cross-reference against `docs/compliance-mapping.md` —
  confirm every control row has a real evidence source, not just a
  planned one.

---

## What didn't go to plan

- **Static validation didn't catch most of the real deploy-time bugs.**
  `az bicep build`, PSRule, and Checkov all passed cleanly on templates
  that then failed against live Azure — a bogus custom log table
  reference, an invalid Key Vault RBAC action, a deprecated Defender
  auto-provisioning API, missing required Sentinel alert-rule properties
  (only a linter *warning*, not a build error), invalid MITRE
  tactic/technique IDs, an invalid KQL `join`, and a missing required
  field on a Defender automation resource. Each only surfaced once
  `what-if`/`deploy` actually ran, one at a time, across 6 separate PRs.
  Static Bicep tooling checks syntax and type shape, not whether the
  target ARM API will actually accept the payload.
- **The subscription-scope retarget (dropping the management-group
  hierarchy for this single-subscription POC) needed more RBAC than
  expected.** The CI identity needed subscription-scope Contributor just
  to run `az deployment sub`, *and* a separate grant to write
  `Microsoft.Authorization` role/policy resources, since Contributor
  deliberately excludes those actions. Rather than grant the built-in
  User Access Administrator role (which can also grant/revoke access to
  anyone, including itself), we added a narrow custom role scoped to
  only the three specific write actions needed — a real trade-off between
  pipeline automation and least privilege, resolved in favour of a
  custom role over a broader built-in one.
- **`Microsoft.Security/pricings` needed serial deployment.** Deploying
  Defender for Cloud's 8 pricing plans as a Bicep `for` loop (parallel by
  default) intermittently failed with `Conflict: Another update operation
  is in progress` — an internal Azure lock on pricing tier changes that
  isn't visible from the ARM resource model. Fixed with `@batchSize(1)`
  to force sequential deployment.

---

## Metrics

| Metric | Before | After |
|---|---|---|
| Defender for Cloud Secure Score | _Pending_ | _Pending_ — needs a Portal/CLI check against the sandbox subscription; not obtainable from GitHub Actions data alone |
| Standing privileged **human** role assignments | 0 | 0 — PIM (`pim.bicep`) is still disabled pending the Graph Bicep extension (see Phase 2 readiness), so no human RBAC/Entra role assignments have been created by this pipeline yet |
| Standing role assignments on the **CI identity** | 0 | 2 — subscription-scope Contributor + the narrow custom "ztr-entra-lz CI Authorization Writer" role (see README "One-time bootstrap"). Deliberately excludes `Microsoft.Authorization/roleAssignments/*`, but is still a standing (non-PIM-eligible) grant on an unattended identity, worth flagging against the "0 standing assignments" Zero Trust claim rather than glossing over |
| CA policies in enforced state | 0 | 0 — `conditionalAccess.bicep` remains disabled (Graph Bicep extension unavailable on this CI runner, `BCP407`); the PowerShell fallback in `scripts/graph/` exists but its trigger condition (`vars.GRAPH_BICEP_EXTENSION_AVAILABLE == 'false'`) isn't wired up as a repo variable yet, so it doesn't currently run either |
| Mean time from PR merge to deploy | — | 7m 11s (first successful end-to-end run, PR #14 → [run 29181378793](https://github.com/sufideen/ztr-entra-lz/actions/runs/29181378793); n=1, includes manual approval wait time) |

---

## Phase 2 readiness

_Pending — once Phase 1 evidence is complete, note here which Phase 2
gaps (from the roadmap) are the priority to close next, informed by what
actually surfaced during this POC rather than the original guess list._
