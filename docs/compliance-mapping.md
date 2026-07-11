# Compliance Control Mapping

This maps each technical control in this repo to Cyber Essentials themes and
ISO 27001:2022 Annex A controls, with the evidence location for an audit.

| Control area | Cyber Essentials theme | ISO 27001 Annex A | Implementation | Evidence location |
|---|---|---|---|---|
| MFA everywhere | User access control | A.5.17, A.8.5 | `conditionalAccess.bicep` CA001 | Entra sign-in logs, CA report-only insights |
| Block legacy auth | Secure configuration | A.8.5 | `conditionalAccess.bicep` CA002 | CA policy report |
| Least-privilege / no standing admin | User access control | A.8.2, A.5.18 | PIM eligible-only (`pim.bicep`) | PIM audit history, Access Reviews |
| Approval + justification on privilege elevation | User access control | A.5.16, A.8.2 | `pim.bicep` approval rules | PIM activation audit log |
| Device compliance for admin access | Malware protection / secure config | A.8.1, A.8.9 | `conditionalAccess.bicep` CA010 | Intune compliance + CA sign-in logs |
| Patch/update management | Security update management | A.8.8 | Azure Update Manager (managed subscription) | Update Manager compliance report |
| Boundary firewall / network segmentation | Firewalls | A.8.20, A.8.22 | ALZ hub-spoke + NSGs (see `ict-labs-platform`) | NSG flow logs in central LAW |
| Central logging, 365-day retention | - | A.8.15, A.12.4 | `logAnalyticsWorkspace.bicep` | Workspace retention config, exported via policy |
| Continuous monitoring / detection | - | A.5.7, A.8.16 | Sentinel analytics rules (`analyticsRules.bicep`) | Sentinel incidents, workbooks |
| Vulnerability/posture management | Malware protection | A.8.8, A.8.9 | Defender for Cloud CSPM plan | Secure Score export to LAW |
| Supplier/vendor access control | - | A.5.19, A.5.20, A.5.21 | Access Packages scoped per vendor, time-boxed | Entitlement Management request history |
| Time-boxed contractor access | User access control | A.6.1, A.8.2 | Access Package expiry + access reviews | Access review completion records |
| Change control on identity config | - | A.8.32 | GitHub PR review + What-If gate | PR history, CI run logs |
| No stored credentials in pipelines | Secure configuration | A.8.24 | OIDC Workload Identity Federation | GitHub Actions OIDC token exchange logs |
| Segregation of duties (deploy vs approve) | - | A.5.3 | GitHub environment protection rules (manual approval on prod) | GitHub environment deployment history |
| Incident detection & response readiness | - | A.5.24, A.5.26 | Sentinel incidents + playbooks (extend as needed) | Sentinel incident queue |

## Audit evidence collection

For an ISO27001 surveillance audit or Cyber Essentials Plus technical
verification, evidence is pulled from:

1. **Azure Policy compliance state** - `az policy state list` at management
   group scope, exported to CSV
2. **PIM audit history** - Entra ID > PIM > Audit history, or
   `Get-MgRoleManagementDirectoryRoleAssignmentScheduleInstance`
3. **Sentinel workbook** - a dedicated "Compliance Evidence" workbook
   (recommended next addition) pulling the queries above into a single
   exportable report
4. **GitHub audit log** - PR approvals, environment deployment approvals,
   branch protection settings (proves change control / segregation of duties)

## Gaps to close before a formal audit

- [ ] Build the Sentinel "Compliance Evidence" workbook referenced above
- [ ] Formalise the Access Review cadence (quarterly minimum for CE Plus)
- [ ] Document the break-glass account procedure and test it (dry run)
- [ ] Confirm Defender for Cloud regulatory compliance dashboard is mapped
      to ISO 27001 standard (built-in initiative available in Azure Policy)
- [ ] Raise `required_approving_review_count` on the `main` branch protection
      rule from 0 back to 1+ once a second collaborator is added to the repo.
      GitHub does not allow a PR author to satisfy their own required-review
      count, so as a sole operator this was set to 0 - PRs are still
      mandatory (forcing the CI/What-If gate to run), but no second-person
      sign-off is currently enforced. See `scripts/github/configure-repo-protections.py`.

## PSRule / Checkov findings - Phase 2 remediation backlog

On the first real CI run against a working Bicep build, PSRule for Azure
flagged 32 policy-as-code findings across the `sandbox`, `dev`, and `prod`
parameter sets. Rather than block pipeline progress on cosmetic-but-real
governance polish while the OIDC/deployment chain was still being proven
end-to-end, `PSRule for Azure` and `Checkov IaC security scan` were set to
`continue-on-error: true` in `deploy.yml` - findings are still generated
and uploaded to the GitHub Security tab as SARIF, just not blocking. This
is a deliberate, documented trade-off, not an oversight - the intent is to
re-enable both as hard gates once the backlog below is cleared, ideally
before treating this as anything beyond a POC.

Findings by category:

- **Missing descriptions** (AZR-000142, AZR-000143, AZR-000144, AZR-000235):
  the custom diagnostic-settings policy definition/assignment and 19
  resources across the template lack description metadata. Low effort,
  high value fix - add `description` properties throughout.
- **Missing tags on Sentinel alert rules** (AZR-000166): the 4 analytics
  rules in `sentinel/analyticsRules.bicep` don't inherit the `commonTags`
  object the rest of the template uses. Fix: add a `tags` property to each
  `Microsoft.SecurityInsights/alertRules` resource.
- **Log Analytics workspace replication** (AZR-000425): recommends
  workspace replication across regions for availability. Cost/complexity
  trade-off worth a deliberate decision rather than a default - flagged
  for Phase 2 discussion, not a quick fix.
- **Defender for Servers/Storage sub-plan** (AZR-000293, AZR-000296):
  recommends explicit `subPlan` (e.g. P2) rather than the bare `Standard`
  tier used in `defenderForCloud.bicep`. Also a cost decision - defer to
  Phase 2 alongside a real budget conversation.
- **Resource location expression** (AZR-000222): flags that some locations
  are hardcoded (`'uksouth'`) rather than parameterized/expression-based.
  Minor, low-effort cleanup.
