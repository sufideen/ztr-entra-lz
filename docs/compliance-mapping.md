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
| Central logging, 365-day retention | — | A.8.15, A.12.4 | `logAnalyticsWorkspace.bicep` | Workspace retention config, exported via policy |
| Continuous monitoring / detection | — | A.5.7, A.8.16 | Sentinel analytics rules (`analyticsRules.bicep`) | Sentinel incidents, workbooks |
| Vulnerability/posture management | Malware protection | A.8.8, A.8.9 | Defender for Cloud CSPM plan | Secure Score export to LAW |
| Supplier/vendor access control | — | A.5.19, A.5.20, A.5.21 | Access Packages scoped per vendor, time-boxed | Entitlement Management request history |
| Time-boxed contractor access | User access control | A.6.1, A.8.2 | Access Package expiry + access reviews | Access review completion records |
| Change control on identity config | — | A.8.32 | GitHub PR review + What-If gate | PR history, CI run logs |
| No stored credentials in pipelines | Secure configuration | A.8.24 | OIDC Workload Identity Federation | GitHub Actions OIDC token exchange logs |
| Segregation of duties (deploy vs approve) | — | A.5.3 | GitHub environment protection rules (manual approval on prod) | GitHub environment deployment history |
| Incident detection & response readiness | — | A.5.24, A.5.26 | Sentinel incidents + playbooks (extend as needed) | Sentinel incident queue |

## Audit evidence collection

For an ISO27001 surveillance audit or Cyber Essentials Plus technical
verification, evidence is pulled from:

1. **Azure Policy compliance state** — `az policy state list` at management
   group scope, exported to CSV
2. **Azure RBAC role assignments** — `scripts/azure/export-rbac-audit.ps1`,
   exported to CSV
3. **PIM audit history** — Entra ID > PIM > Audit history, or
   `Get-MgRoleManagementDirectoryRoleAssignmentScheduleInstance`
4. **Sentinel workbook** — the "Zero Trust Landing Zone - Compliance
   Evidence" workbook (`bicep/modules/sentinel/complianceWorkbook.bicep`)
   pulling the queries above into a single exportable report
5. **GitHub audit log** — PR approvals, environment deployment approvals,
   branch protection settings (proves change control / segregation of duties)

## Gaps to close before a formal audit

- [x] Build the Sentinel "Compliance Evidence" workbook referenced above
- [x] Formalise the Access Review cadence (quarterly minimum for CE Plus)
      - see `docs/access-review-policy.md` for scope, cadence, and current
        manual-process status pending the Graph extension gap (Workstream E)
- [x] Document the break-glass account procedure and test it (dry run)
      - see `docs/break-glass-procedure.md`; the dry-run itself is still a
        manual step to perform and log in `docs/poc-evidence/README.md`
- [x] Assign the built-in ISO 27001:2013 regulatory-compliance initiative
      (`bicep/modules/compliance/iso27001PolicyAssignment.bicep`) so the
      Defender for Cloud regulatory compliance dashboard maps to it
