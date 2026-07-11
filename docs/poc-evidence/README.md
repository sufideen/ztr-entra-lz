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

- **What was done**: _Pending_
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

_Pending — this section matters. Real engineering has friction points:
a Graph API quirk, a CA policy interaction you didn't expect, a PIM
onboarding step that had to be done manually. Document 2–3 of these
honestly. This is what separates a credible case study from a marketing
page._

---

## Metrics

| Metric | Before | After |
|---|---|---|
| Defender for Cloud Secure Score | _Pending_ | _Pending_ |
| Standing privileged role assignments | _Pending_ | 0 (target) |
| CA policies in enforced state | 0 | _Pending_ |
| Mean time from PR merge to deploy | — | _Pending_ |

---

## Phase 2 readiness

_Pending — once Phase 1 evidence is complete, note here which Phase 2
gaps (from the roadmap) are the priority to close next, informed by what
actually surfaced during this POC rather than the original guess list._
