#Requires -Version 5.1
<#
.SYNOPSIS
  Exports every Azure RBAC role assignment on the current subscription to a
  CSV, for the "Azure Policy compliance state ... exported to CSV" style of
  audit evidence described in docs/compliance-mapping.md.

.DESCRIPTION
  Uses Azure CLI (az), not PowerShell's Az module, so it works from the same
  azcli-venv session used throughout this project without an extra
  Install-Module step. Read-only - lists role assignments, writes nothing to
  the subscription.

.PARAMETER OutputPath
  Where to write the CSV. Default: AzureRBACAudit.csv in the current directory.

.PARAMETER IncludeInherited
  Include role assignments inherited from management group / subscription
  scope in addition to ones defined directly at or below the current scope.
  Passed straight through to `az role assignment list --include-inherited`.

.EXAMPLE
  .\export-rbac-audit.ps1
.EXAMPLE
  .\export-rbac-audit.ps1 -OutputPath C:\audit\AzureRBACAudit.csv -IncludeInherited
#>
param(
    [string]$OutputPath = "AzureRBACAudit.csv",
    [switch]$IncludeInherited
)

$ErrorActionPreference = "Stop"
if (Get-Variable -Name PSNativeCommandUseErrorActionPreference -Scope Global -ErrorAction SilentlyContinue) {
    $PSNativeCommandUseErrorActionPreference = $false
}

Write-Host "Checking Azure CLI login state..."
$account = az account show --output json 2>$null | ConvertFrom-Json
if (-not $account) {
    Write-Host "Not logged in. Running az login..."
    az login | Out-Null
    $account = az account show --output json | ConvertFrom-Json
}
Write-Host "Using subscription: $($account.name) ($($account.id))"

Write-Host ""
Write-Host "Listing role assignments..."
$listArgs = @('role', 'assignment', 'list', '--all', '--output', 'json')
if ($IncludeInherited) {
    $listArgs += '--include-inherited'
}
$assignments = az @listArgs | ConvertFrom-Json

if (-not $assignments) {
    Write-Warning "No role assignments returned - check your az login context and permissions."
}

$rows = $assignments | ForEach-Object {
    [pscustomobject]@{
        PrincipalName = $_.principalName
        PrincipalType = $_.principalType
        RoleName      = $_.roleDefinitionName
        Scope         = $_.scope
    }
}

$rows | Export-Csv -Path $OutputPath -NoTypeInformation

Write-Host ""
Write-Host "Wrote $($rows.Count) role assignment(s) to $OutputPath"
