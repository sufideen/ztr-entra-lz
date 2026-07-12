# Break-glass emergency access procedure

## Purpose

Every Conditional Access policy in `bicep/modules/conditionalAccess.bicep`
excludes `breakGlassGroupId` (see `caBaselineMfa`, `caBlockLegacyAuth`,
`caEmployeeDeviceCompliance`, `caSignInRisk`). This is the "how do we get
back in" answer if a CA policy misconfiguration, an MFA outage, or a
Conditional Access Insights false-positive locks out every normal admin
account at once. Two dedicated accounts exist for exactly this scenario -
this doc is the runbook for setting them up, testing them, and using them
without turning them into a standing backdoor.

## Setup (one-time, do this before enabling any CA policy)

1. Create **2 cloud-only** accounts (not synced from on-prem AD, not tied
   to any individual's normal identity) - e.g.
   `breakglass1@ict-cloud.solutions` and `breakglass2@ict-cloud.solutions`.
   Two, not one, so a single account compromise or lockout doesn't remove
   the escape hatch entirely.
2. Assign both accounts **Global Administrator**, permanently (not
   PIM-eligible) - the entire point of break-glass is that it works even
   if PIM/Entra ID role activation itself is the thing that's broken.
3. Set passwords to long, random, unique values (not reused anywhere). Do
   not enroll either account in MFA - see "Why no MFA" below.
4. Store the credentials in a **physical or offline** secret store (e.g. a
   sealed envelope in a safe, or an offline password manager entry) - not
   in a CA-gated cloud secret store, since that would be exactly the kind
   of dependency break-glass exists to avoid.
5. Add both accounts' object IDs to the Entra ID group referenced by
   `breakGlassGroupId`, and pass that group's object ID as the
   `breakGlassGroupId` parameter to `bicep/main.bicep` /
   `scripts/graph/deploy-conditional-access.ps1`.
6. Confirm the exclusion took effect: Entra ID → Conditional Access →
   policy → Assignments → Users → Exclude, and confirm the break-glass
   group is listed on every policy in `conditionalAccess.bicep`.

### Why no MFA on break-glass accounts

This looks like it weakens security, but it's the standard, Microsoft-
recommended pattern (see Microsoft Learn's "Manage emergency access
accounts" guidance): if the break-glass account required MFA and the MFA
provider itself is down (which is a realistic reason you'd need
break-glass in the first place), the account would be unusable exactly
when it's needed. The compensating controls are: the account is excluded
from all *conditional* enforcement but its use is tightly monitored (see
"Monitoring" below), the credential is offline and physically secured, and
the account exists in exactly the two-account pattern described above so
one going missing doesn't lock the tenant out permanently.

## Dry-run test (do this before enabling any CA policy in enforced mode)

Per `THROWAWAY.md` Step 4/5: test **before** any policy leaves report-only
mode, and periodically afterward (recommend every 90 days, tracked as a
recurring item alongside the Access Review cadence in
`docs/access-review-policy.md`).

1. Sign in to `portal.azure.com` (or `myaccount.microsoft.com`) using one
   break-glass account, from a network/browser session that would
   otherwise be blocked by at least one enforced CA policy (e.g. a
   non-compliant device, or a location outside any trusted range).
2. Confirm sign-in succeeds without MFA prompt and without being blocked.
3. Sign out. Do not leave an active session or leave the account signed in
   anywhere.
4. Record the test date, which policies were "live" (enforced, not
   report-only) at the time, and the result in
   `docs/poc-evidence/README.md`.

## Monitoring

`bicep/modules/sentinel/analyticsRules.bicep`'s `ruleCaPolicyChange` rule
alerts on CA policy changes outside the pipeline - relevant if someone
manually edits the break-glass exclusion itself. Break-glass account
**sign-in** is not currently covered by a dedicated Sentinel rule; add one
matching `SigninLogs | where UserPrincipalName in (<breakglass UPNs>)` as
a Phase 2 item if break-glass usage monitoring needs to be more than "check
`docs/poc-evidence/README.md`'s dry-run log and the native Entra ID sign-in
log."

## Incident use (real emergency, not a dry run)

1. Sign in with a break-glass account per the dry-run steps above.
2. Diagnose and fix the underlying issue (revert the bad CA policy change
   via a PR + pipeline redeploy, wait out the MFA provider outage, etc.) -
   don't use the break-glass session to make unrelated changes.
3. Sign out as soon as the fix is deployed and verified.
4. Rotate both break-glass account passwords immediately after use, even
   if only one account was used.
5. Record the incident (what broke, which account was used, when) in
   `docs/poc-evidence/README.md` for the audit trail.

## What this is not

Break-glass accounts are not a convenience shortcut for admins who don't
want to deal with MFA day-to-day, and not a shared "admin" login. Using
them outside a genuine incident or a scheduled dry-run defeats the control
this procedure exists to provide.
