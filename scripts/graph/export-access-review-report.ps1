#Requires -Modules Microsoft.Graph.Identity.Governance
<#
.SYNOPSIS
  Exports Entra ID Access Review definitions, their instances, and each
  instance's reviewer decisions to CSV - the scripted alternative to
  manually confirming each scheduled review completed, per
  docs/access-review-policy.md's "Current status" section.

.DESCRIPTION
  Read-only - requests AccessReview.Read.All, not the ReadWrite.Membership
  scope create-access-review automation would need. This script does NOT
  create or apply reviews (that's the still-open "Action item" in
  docs/access-review-policy.md, tracked under Workstream E / the Graph
  Bicep extension gap in docs/graph-resources.md); it only reports on
  reviews that already exist, however they were created (portal or code),
  so you have an exportable artifact for docs/poc-evidence/README.md
  instead of a screenshot.

.PARAMETER TenantId
  For manual local runs, to avoid Windows' Web Account Manager silently
  defaulting to a different cached work/personal account.

.PARAMETER OutputPath
  Where to write the CSV. Default: EntraAccessReviewAudit.csv in the current directory.

.EXAMPLE
  .\export-access-review-report.ps1
#>
param(
    [string]$TenantId,
    [string]$OutputPath = "EntraAccessReviewAudit.csv"
)

$connectParams = @{ Scopes = "AccessReview.Read.All"; NoWelcome = $true }
if ($TenantId) { $connectParams.TenantId = $TenantId }
Connect-MgGraph @connectParams

Write-Host "Listing access review definitions..."
$definitions = Get-MgIdentityGovernanceAccessReviewDefinition -All

if (-not $definitions) {
    Write-Warning "No access review definitions found. Per docs/access-review-policy.md, reviews are currently created manually in the portal - confirm at least one exists under Entra ID > Identity Governance > Access reviews."
}

$rows = foreach ($definition in $definitions) {
    $instances = Get-MgIdentityGovernanceAccessReviewDefinitionInstance -AccessReviewScheduleDefinitionId $definition.Id -All

    foreach ($instance in $instances) {
        $decisions = Get-MgIdentityGovernanceAccessReviewDefinitionInstanceDecision `
            -AccessReviewScheduleDefinitionId $definition.Id `
            -AccessReviewInstanceId $instance.Id `
            -All

        if (-not $decisions) {
            [pscustomobject]@{
                ReviewName        = $definition.DisplayName
                InstanceId        = $instance.Id
                InstanceStatus    = $instance.Status
                StartDateTime     = $instance.StartDateTime
                EndDateTime       = $instance.EndDateTime
                PrincipalReviewed = ""
                ResourceReviewed  = ""
                Decision          = ""
                Justification     = ""
                ReviewedBy        = ""
                ReviewedDateTime  = ""
            }
            continue
        }

        foreach ($decision in $decisions) {
            [pscustomobject]@{
                ReviewName        = $definition.DisplayName
                InstanceId        = $instance.Id
                InstanceStatus    = $instance.Status
                StartDateTime     = $instance.StartDateTime
                EndDateTime       = $instance.EndDateTime
                PrincipalReviewed = $decision.Principal.AdditionalProperties.userPrincipalName
                ResourceReviewed  = $decision.Resource.AdditionalProperties.displayName
                Decision          = $decision.Decision
                Justification     = $decision.Justification
                ReviewedBy        = $decision.ReviewedBy.AdditionalProperties.userPrincipalName
                ReviewedDateTime  = $decision.ReviewedDateTime
            }
        }
    }
}

$rows | Export-Csv -Path $OutputPath -NoTypeInformation

Write-Host ""
Write-Host "Wrote $(($rows | Measure-Object).Count) row(s) to $OutputPath"
Disconnect-MgGraph | Out-Null
