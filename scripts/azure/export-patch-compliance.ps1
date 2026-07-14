#Requires -Version 5.1
<#
.SYNOPSIS
  Exports per-VM Azure Update Manager patch-assessment state to CSV - the
  actual evidence artifact behind the "Patch/update management" row in
  docs/compliance-mapping.md, which today only says "Update Manager
  compliance report" with no scripted export.

.DESCRIPTION
  Queries Azure Resource Graph's patchassessmentresources table (the
  supported way to pull Update Manager assessment data across every VM in
  a subscription in one call, rather than per-VM API calls). Requires the
  `resource-graph` az CLI extension, which this script installs on demand.
  Read-only.

  NOTE: Resource Graph's patch-assessment schema has changed across API
  versions in the past. Field names below match Microsoft's documented
  sample queries as of when this script was written - if a column comes
  back empty in your tenant, run:
    az graph query -q "patchassessmentresources | take 1"
  and adjust the -Query below to match the properties.* fields you
  actually see.

  Also note this only returns data for VMs that have Update Manager
  periodic assessment (or a completed on-demand assessment) enabled - a
  VM with no assessment configured simply won't appear in the results.

.PARAMETER OutputPath
  Where to write the CSV. Default: AzurePatchComplianceAudit.csv in the current directory.

.EXAMPLE
  .\export-patch-compliance.ps1
#>
param(
    [string]$OutputPath = "AzurePatchComplianceAudit.csv"
)

$ErrorActionPreference = "Stop"
if (Get-Variable -Name PSNativeCommandUseErrorActionPreference -Scope Global -ErrorAction SilentlyContinue) {
    $PSNativeCommandUseErrorActionPreference = $false
}

Write-Host "Checking Azure CLI login state..."
$account = az account show 2>$null | ConvertFrom-Json
if (-not $account) {
    Write-Host "Not logged in. Running az login..."
    az login | Out-Null
    $account = az account show | ConvertFrom-Json
}
Write-Host "Using subscription: $($account.name) ($($account.id))"

Write-Host ""
Write-Host "Ensuring the resource-graph az CLI extension is installed..."
az extension add --name resource-graph --only-show-errors 2>$null | Out-Null

$query = @"
patchassessmentresources
| where type == 'microsoft.compute/virtualmachines/patchassessmentresults'
| extend vmId = tostring(split(id, '/patchAssessmentResults')[0])
| join kind=leftouter (
    Resources
    | where type == 'microsoft.compute/virtualmachines'
    | project vmId = tostring(id), VmName = name, ResourceGroup = resourceGroup
  ) on vmId
| project
    VmName,
    ResourceGroup,
    OsType = tostring(properties.osType),
    AssessmentStatus = tostring(properties.status),
    RebootPending = tostring(properties.rebootPending),
    CriticalAndSecurityPatchCount = toint(properties.criticalAndSecurityPatchCount),
    OtherPatchCount = toint(properties.otherPatchCount),
    LastAssessedTime = tostring(properties.lastModifiedDateTime)
"@

Write-Host ""
Write-Host "Querying patch assessment results via Azure Resource Graph..."
$results = az graph query -q $query --query "data" -o json | ConvertFrom-Json

if (-not $results) {
    Write-Warning "No patch assessment results returned. This means either no VMs have Update Manager assessment enabled, or the schema has drifted - see the NOTE in this script's header for how to check."
}

$results | Export-Csv -Path $OutputPath -NoTypeInformation

Write-Host ""
Write-Host "Wrote $($results.Count) row(s) to $OutputPath"
