# Access Review policy

## Purpose

Standing access - even PIM-eligible (never permanently active) access -
drifts from "who should have it" over time as roles change, contracts
end, and projects wind down. Entra ID Access Reviews are the control that
catches that drift on a schedule instead of relying on someone remembering
to revoke it. This doc defines the cadence and scope for this repo; the
reviews themselves are **not yet automated** - see "Current status" below.

## Scope

| Reviewed population | Source | Reviewer |
|---|---|---|
| Privileged Entra ID roles (Global Administrator, User Administrator, Application Administrator, Helpdesk Administrator) | `bicep/modules/pim.bicep`'s `privilegedEntraRoles` | Role owner group per `primaryApprovers` in the role's PIM policy |
| Privileged Azure RBAC roles (custom roles from `bicep/modules/rbac/customRoles.bicep`, plus the built-in Contributor grant documented in README's "One-time bootstrap") | `bicep/modules/pim.bicep`'s `azureRbacEligibleAssignments` | Subscription owner |
| Contractor / vendor test persona groups (Workstream C, once `bicep/modules/groups.bicep` and `scripts/graph/create-test-personas.ps1` are executed against the tenant) | Entra ID groups created by `groups.bicep` | Sponsor named at Access Package creation time (`scripts/graph/create-access-package.ps1`) |
| B2B guest accounts generally | Entra ID guest user list | Sponsor / Access Package owner |

Break-glass accounts (`docs/break-glass-procedure.md`) are **excluded**
from Access Review - they're reviewed via the dry-run/rotation procedure
in that doc instead, not a standing-access review, since their assignment
is permanent by design.

## Cadence

- **Privileged roles (Entra + Azure RBAC)**: quarterly, minimum bar for
  Cyber Essentials Plus technical verification and referenced in
  `docs/compliance-mapping.md`'s control mapping (A.5.18 - Access rights).
- **Contractor/vendor test personas and B2B guests**: aligned to the
  Access Package's own expiry (default 90 days per the README's Personas
  table) - the Access Review runs at expiry, not on a separate clock, so a
  guest whose access has already lapsed doesn't also need a manual review
  to confirm what expiry already enforced.

## What a review actually checks

For each reviewed assignment: is the person still at the organization /
still engaged as a contractor or vendor, do they still need this specific
role for their current work, and does the assignment still have a
business justification on file (PIM's `Approval_EndUser_Assignment` rule
already requires justification at activation time - the review confirms
that justification still holds, not just that it existed once).

## Current status: policy defined, automation not yet built

Entra ID Access Reviews (the native feature -
`Microsoft.Graph/accessReviewScheduleDefinitions`) is a Microsoft Graph
resource, same category and same blocker as `conditionalAccess.bicep` and
`pim.bicep` - see `docs/graph-resources.md` for the decision record on why
Graph-based resources in this repo are currently deployed via the
PowerShell fallback path rather than the Bicep extension.

Until that's revisited (Workstream E in the Phase 2 execution plan -
closing the Graph extension gap, which needs
`RoleManagementPolicy.ReadWrite.Directory` /
`AccessReview.ReadWrite.Membership` admin-consented Graph permissions for
the CI identity), running this policy means manually creating the
recurring Access Review in Entra ID → Identity Governance → Access
reviews, using the scope/cadence table above, and manually confirming each
scheduled review actually completed. Track manual review completions in
`docs/poc-evidence/README.md` alongside the break-glass dry-run log, so
both pieces of ongoing operational evidence live in one place.

**Action item**: once Workstream E is resolved, add a
`bicep/modules/accessReviews.bicep` (or equivalent `scripts/graph/`
script) authoring the reviews in this table as code, matching the pattern
`groups.bicep` and `conditionalAccess.bicep` already use.
