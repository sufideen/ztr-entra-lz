#Requires -Modules Microsoft.Graph.Users, Microsoft.Graph.Identity.Governance
<#
.SYNOPSIS
  Removes every object created by scripts/graph/create-test-personas.ps1,
  matching the ztlz-test-<persona>-<RunId> naming convention (tagged via
  JobTitle/DisplayName, since Entra ID users don't support arbitrary
  resource tags the way Azure resources do).

.DESCRIPTION
  Idempotent - finds objects by the ztlz-test-* naming convention,
  optionally scoped to a single RunId, and removes them. Safe to re-run;
  skips cleanly if nothing matches. Companion to
  scripts/azure/teardown-sandbox.ps1, which handles the Azure-resource
  side of teardown and does not touch Entra ID objects - run both to tear
  down everything a test/demo session created.

.PARAMETER RunId
  Only remove objects from this specific create-test-personas.ps1 run
  (the value it printed at the end, or that you passed it via -RunId).
  Omit to remove ALL ztlz-test-* objects regardless of run - use -WhatIf
  first to review what that would catch.

.PARAMETER WhatIf
  Preview what would be deleted without deleting anything (standard
  PowerShell ShouldProcess switch).

.EXAMPLE
  .\teardown-test-personas.ps1 -RunId 202607121530
.EXAMPLE
  .\teardown-test-personas.ps1 -WhatIf
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$RunId
)

Connect-MgGraph -Scopes "User.ReadWrite.All", "EntitlementManagement.ReadWrite.All" -NoWelcome

Write-Host "Finding test persona users tagged 'ztlz-test-*'$(if ($RunId) { " for RunId=$RunId" })..."
$users = Get-MgUser -All -Property Id, DisplayName, UserPrincipalName, JobTitle |
    Where-Object { $_.JobTitle -like 'ztlz-test-*' -and (-not $RunId -or $_.JobTitle -like "*-$RunId") }

if (-not $users) {
    Write-Host "No matching test persona users found."
}
else {
    foreach ($user in $users) {
        if ($PSCmdlet.ShouldProcess($user.UserPrincipalName, "Delete Entra ID user")) {
            Write-Host "Deleting user $($user.UserPrincipalName) ($($user.Id))..."
            Remove-MgUser -UserId $user.Id
        }
    }
}

Write-Host ""
Write-Host "Finding test Access Packages tagged 'ztlz-test-*'$(if ($RunId) { " for RunId=$RunId" })..."
$packages = Get-MgEntitlementManagementAccessPackage -All |
    Where-Object { $_.DisplayName -like 'ztlz-test-*' -and (-not $RunId -or $_.DisplayName -like "*-$RunId") }

if (-not $packages) {
    Write-Host "No matching test Access Packages found."
}
else {
    foreach ($package in $packages) {
        if ($PSCmdlet.ShouldProcess($package.DisplayName, "Delete Access Package")) {
            Write-Host "Deleting Access Package $($package.DisplayName) ($($package.Id))..."
            Remove-MgEntitlementManagementAccessPackage -AccessPackageId $package.Id
        }
    }
}

Write-Host ""
Write-Host "Teardown complete."
Write-Host "Note: this does not remove bicep/modules/groups.bicep's break-glass or"
Write-Host "sponsor-group objects (those are reusable across runs, not test-run-scoped)"
Write-Host "or any Azure resources - see scripts/azure/teardown-sandbox.ps1 for those."

Disconnect-MgGraph | Out-Null
