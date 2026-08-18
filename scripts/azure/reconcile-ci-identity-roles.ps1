#Requires -Version 5.1
<#
.SYNOPSIS
  Detects (and optionally fixes) standing-privilege drift on the CI OIDC
  service principal: any role assignment beyond the two documented in
  README "One-time bootstrap: CI OIDC identity" (Contributor + the custom
  "ztr-entra-lz CI Authorization Writer" role, both at subscription scope).

.DESCRIPTION
  This is the automated counterpart to the
  'CI identity holds only the documented standing role assignments' Pester
  test in tests/PostDeploy.Tests.ps1. That test only detects drift and fails
  the pipeline; this script removes it.

  Common causes of drift on this sandbox subscription:
    - A human assigning themselves/the SP an extra role (e.g. Owner or
      Reader) via the Portal while debugging a permissions error, then
      forgetting to revoke it.
    - Re-running scripts/azure/setup-federated-identity.ps1 by hand with a
      wider `--role` value than the two it hard-codes.
    - Any script or manual `az role assignment create` against this
      principal that isn't setup-federated-identity.ps1.

  Uses Azure CLI (az), matching the other scripts/azure/*.ps1 scripts.

.PARAMETER AppDisplayName
  Display name of the CI app registration / service principal. Default:
  ztr-entra-lz-ci (matches setup-federated-identity.ps1's default).

.PARAMETER Fix
  Without this switch, the script only reports drift and exits non-zero if
  any is found (safe to run read-only, e.g. from CI). With -Fix, it also
  removes every role assignment on the CI SP that isn't in the documented
  allow-list - i.e. it re-asserts least privilege rather than just
  alerting on the loss of it.

  -Fix requires Microsoft.Authorization/roleAssignments/delete at
  subscription scope (e.g. Owner or User Access Administrator) - the same
  privilege level setup-federated-identity.ps1 needs. Run it under your own
  admin credentials (`az login`), not the CI identity's: the CI SP's own
  grant deliberately excludes Microsoft.Authorization/roleAssignments/*
  (see README "One-time bootstrap: CI OIDC identity") specifically so it
  can never modify anyone's access, including its own. That's also why
  deploy.yml only ever runs this script without -Fix - it's a diagnostic
  there, not a remediation. Fixing drift is a deliberate, human-run action.

.EXAMPLE
  # Report-only - what deploy.yml and the weekly drift-detection job run
  .\reconcile-ci-identity-roles.ps1

.EXAMPLE
  # Auto-fix - run by hand, under an admin identity, once drift is confirmed
  az login
  .\reconcile-ci-identity-roles.ps1 -Fix
#>
param(
    [string]$AppDisplayName = "ztr-entra-lz-ci",
    [switch]$Fix
)

$ErrorActionPreference = "Stop"
if (Get-Variable -Name PSNativeCommandUseErrorActionPreference -Scope Global -ErrorAction SilentlyContinue) {
    $PSNativeCommandUseErrorActionPreference = $false
}

# Keep this allow-list in sync with README "One-time bootstrap: CI OIDC
# identity", scripts/azure/setup-federated-identity.ps1, and the Pester
# assertion in tests/PostDeploy.Tests.ps1.
$AllowedRoleNames = @(
    'Contributor',
    'ztr-entra-lz CI Authorization Writer'
)

Write-Host "Checking Azure CLI login state..."
$account = az account show 2>$null | ConvertFrom-Json
if (-not $account) {
    Write-Host "Not logged in. Running az login..."
    az login | Out-Null
    $account = az account show | ConvertFrom-Json
}
Write-Host "Using subscription: $($account.name) ($($account.id))"

Write-Host ""
Write-Host "Looking up service principal '$AppDisplayName' ..."
$sp = az ad sp list --display-name $AppDisplayName --query "[0]" | ConvertFrom-Json
if (-not $sp) {
    Write-Error "No service principal found with display name '$AppDisplayName'. Run setup-federated-identity.ps1 first."
    exit 1
}
Write-Host "Found: $($sp.id)"

Write-Host ""
Write-Host "Listing role assignments held by this service principal..."
$assignments = az role assignment list --assignee $sp.appId --all | ConvertFrom-Json

if (-not $assignments -or $assignments.Count -eq 0) {
    Write-Warning "No role assignments found at all - expected at least Contributor + the Authorization Writer role. Has setup-federated-identity.ps1 been run?"
    exit 1
}

$unexpected = $assignments | Where-Object { $AllowedRoleNames -notcontains $_.roleDefinitionName }
$missing = $AllowedRoleNames | Where-Object { $roleName = $_; -not ($assignments | Where-Object { $_.roleDefinitionName -eq $roleName }) }

Write-Host ""
Write-Host "Documented allow-list: $($AllowedRoleNames -join ', ')"
Write-Host "Currently held        : $(($assignments.roleDefinitionName | Sort-Object -Unique) -join ', ')"

if ($missing) {
    Write-Warning "Missing documented role(s): $($missing -join ', '). Run setup-federated-identity.ps1 to (re-)grant them."
}

if (-not $unexpected) {
    Write-Host ""
    Write-Host "No drift found - the CI identity holds exactly the documented standing role assignments."
    if ($missing) { exit 1 }
    exit 0
}

Write-Host ""
Write-Warning "Standing-privilege drift detected - $($unexpected.Count) undocumented role assignment(s):"
foreach ($a in $unexpected) {
    Write-Host "  - $($a.roleDefinitionName) @ $($a.scope) (assignment id: $($a.id))"
}

if (-not $Fix) {
    Write-Host ""
    Write-Host "Re-run with -Fix to remove the assignment(s) above, or do it by hand:"
    foreach ($a in $unexpected) {
        Write-Host "  az role assignment delete --ids $($a.id)"
    }
    exit 1
}

Write-Host ""
Write-Host "Removing undocumented role assignment(s) (-Fix was specified)..."
$failedRemovals = @()
foreach ($a in $unexpected) {
    Write-Host "  Removing $($a.roleDefinitionName) @ $($a.scope) ..."
    az role assignment delete --ids $a.id
    if ($LASTEXITCODE -ne 0) {
        $failedRemovals += $a
    }
}

if ($failedRemovals) {
    Write-Error "Failed to remove $($failedRemovals.Count) role assignment(s) - see errors above. Remove manually and re-run to confirm."
    exit 1
}

Write-Host ""
Write-Host "Done. The CI identity now holds exactly the documented standing role assignments."
