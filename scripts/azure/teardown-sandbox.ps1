#Requires -Version 5.1
<#
.SYNOPSIS
  Inverse of bicep/main.bicep's deployment: removes every subscription-scope
  resource this repo has put into the target subscription, so cost doesn't
  run unattended between test/demo sessions against the all-in-one
  ict-cloud.solutions subscription.

.DESCRIPTION
  Uses Azure CLI (az), matching setup-federated-identity.ps1. Idempotent -
  safe to re-run; each step checks existence before deleting, so a partial
  prior teardown (or a resource that was never created) doesn't error out
  the whole script.

  Does NOT remove the CI OIDC app registration / federated credential / RBAC
  grants created by setup-federated-identity.ps1 - those are re-usable
  across teardown/redeploy cycles and cheap to leave in place (no billing).
  Re-run setup-federated-identity.ps1 if you need to recreate them from
  scratch.

  Does NOT remove Entra ID test persona objects created by
  scripts/graph/create-test-personas.ps1 - use
  scripts/graph/teardown-test-personas.ps1 for those.

.PARAMETER Environment
  sandbox | dev | prod - used to build resource/resource-group names,
  matching the naming convention in bicep/modules/logAnalytics.bicep.

.EXAMPLE
  .\teardown-sandbox.ps1 -Environment sandbox
#>
param(
    [ValidateSet('sandbox', 'dev', 'prod')]
    [string]$Environment = 'sandbox'
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

$resourceGroupName = "rg-security-$Environment"
$customRoleNames = @(
    'Contractor Scoped Reader',
    'Vendor Scoped App Deployer',
    'Pipeline Scoped Contributor',
    'ztr-entra-lz CI Authorization Writer'
)
$defenderPlans = @(
    'VirtualMachines', 'AppServices', 'SqlServers', 'KeyVaults',
    'StorageAccounts', 'Containers', 'Arm', 'CloudPosture'
)

Write-Host ""
Write-Host "Step 1: Deleting resource group $resourceGroupName (Log Analytics, Sentinel, compliance workbook)..."
$rgExists = az group exists --name $resourceGroupName | ConvertFrom-Json
if ($rgExists) {
    az group delete --name $resourceGroupName --yes --no-wait
    Write-Host "Deletion started (--no-wait) - this runs in the background in Azure."
}
else {
    Write-Host "Resource group does not exist. Skipping."
}

Write-Host ""
Write-Host "Step 2: Resetting Defender for Cloud plans to Free tier..."
foreach ($plan in $defenderPlans) {
    Write-Host "  $plan -> Free"
    az security pricing create --name $plan --tier Free 2>$null | Out-Null
}

Write-Host ""
Write-Host "Step 3: Deleting the ISO27001 policy assignment..."
$isoAssignment = az policy assignment list --query "[?name=='assign-iso27001-2013'] | [0]" | ConvertFrom-Json
if ($isoAssignment) {
    az policy assignment delete --name 'assign-iso27001-2013'
    Write-Host "Deleted."
}
else {
    Write-Host "Not found. Skipping."
}

Write-Host ""
Write-Host "Step 4: Deleting the diagnostic-settings policy assignment and definition..."
$diagAssignment = az policy assignment list --query "[?name=='assign-diag-settings'] | [0]" | ConvertFrom-Json
if ($diagAssignment) {
    az policy assignment delete --name 'assign-diag-settings'
    Write-Host "Deleted assignment."
}
else {
    Write-Host "Assignment not found. Skipping."
}
$diagDefinition = az policy definition list --query "[?name=='deploy-diag-settings-to-central-law'] | [0]" | ConvertFrom-Json
if ($diagDefinition) {
    az policy definition delete --name 'deploy-diag-settings-to-central-law'
    Write-Host "Deleted definition."
}
else {
    Write-Host "Definition not found. Skipping."
}

Write-Host ""
Write-Host "Step 5: Deleting custom RBAC role definitions..."
foreach ($roleName in $customRoleNames) {
    $role = az role definition list --name $roleName --query "[0]" | ConvertFrom-Json
    if ($role) {
        Write-Host "  Deleting $roleName ..."
        az role definition delete --name $roleName
    }
    else {
        Write-Host "  $roleName not found. Skipping."
    }
}

Write-Host ""
Write-Host "Teardown complete."
Write-Host ""
Write-Host "Note: Step 1's resource group deletion runs asynchronously - check"
Write-Host "  az group exists --name $resourceGroupName"
Write-Host "in a few minutes to confirm it's gone."
Write-Host ""
Write-Host "Not removed by this script (re-usable, no ongoing cost):"
Write-Host "  - CI OIDC app registration / federated credential / role assignments"
Write-Host "    (see setup-federated-identity.ps1)"
Write-Host "  - Entra ID test persona accounts (see scripts/graph/teardown-test-personas.ps1)"
Write-Host ""
Write-Host "After running, confirm via Cost Management + Billing that the expected"
Write-Host "resources are gone and billing has stopped."
