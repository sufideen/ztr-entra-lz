#Requires -Version 5.1
<#
.SYNOPSIS
  Deletes every resource group in the current Azure subscription and resets
  Defender for Cloud plans to Free tier, to zero out billing on the
  all-in-one ict-cloud.solutions subscription between POC/demo sessions.

.DESCRIPTION
  teardown-sandbox.ps1 only removes what bicep/main.bicep deploys
  (rg-security-<environment> plus the policy/role objects that live outside
  any resource group). Because this subscription is also used ad hoc for
  POC/demo/testing (see THROWAWAY.md), other resource groups can accumulate
  outside that scope and keep billing unnoticed. This script is the blunt
  instrument: it lists every resource group in the subscription and deletes
  it, then resets the eight Defender for Cloud plans to Free.

  Uses Azure CLI (az), matching the rest of scripts/azure/. Defaults to a
  dry run - it only lists what it would delete. Pass -Force to actually
  delete. Resource group deletion is issued with --no-wait, so it runs
  asynchronously in Azure; this script does not block until deletion
  finishes.

  Does NOT touch anything that isn't a resource group: the CI OIDC app
  registration / federated credential / RBAC role assignments
  (setup-federated-identity.ps1), custom RBAC role *definitions* or policy
  *assignments* (those are handled by teardown-sandbox.ps1, Steps 3-5), or
  Entra ID objects such as test personas or the break-glass accounts
  (scripts/graph/teardown-test-personas.ps1). Run teardown-sandbox.ps1
  first (or after) if you also want those cleared.

.PARAMETER Force
  Actually delete the resource groups and reset Defender plans. Without
  this switch, the script only lists what it would do.

.PARAMETER ExcludeResourceGroups
  Names of resource groups to skip, e.g. ones you want to keep around
  between sessions. Matched case-insensitively.

.EXAMPLE
  .\teardown-all-resource-groups.ps1
  Lists every resource group in the current subscription without deleting
  anything.

.EXAMPLE
  .\teardown-all-resource-groups.ps1 -Force
  Deletes every resource group in the current subscription and resets
  Defender for Cloud plans to Free.

.EXAMPLE
  .\teardown-all-resource-groups.ps1 -Force -ExcludeResourceGroups rg-keep-me
  Deletes every resource group except rg-keep-me.
#>
param(
    [switch]$Force,
    [string[]]$ExcludeResourceGroups = @()
)

$ErrorActionPreference = "Stop"
if (Get-Variable -Name PSNativeCommandUseErrorActionPreference -Scope Global -ErrorAction SilentlyContinue) {
    $PSNativeCommandUseErrorActionPreference = $false
}

Write-Host "Checking Azure CLI login state..."
$subscriptionName = az account show --query name --output tsv 2>$null
if (-not $subscriptionName) {
    Write-Host "Not logged in. Running az login..."
    az login | Out-Null
    $subscriptionName = az account show --query name --output tsv
}
$subscriptionId = az account show --query id --output tsv
Write-Host "Using subscription: $subscriptionName ($subscriptionId)"

if (-not $Force) {
    Write-Host ""
    Write-Host "DRY RUN - no changes will be made. Pass -Force to actually delete." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Listing resource groups in this subscription..."
# --output tsv, not json: az group list --query "[].name" | ConvertFrom-Json
# has been observed to collapse the whole array into a single space-joined
# string on some Windows PowerShell 5.1 setups (a ConvertFrom-Json
# pipeline-aggregation quirk with JSON arrays of bare scalars). tsv
# sidesteps it - PowerShell splits external command stdout into a real
# array of lines on its own, no JSON parsing involved.
$resourceGroups = @(az group list --query "[].name" --output tsv | Where-Object { $_ })

$excludeSet = [System.Collections.Generic.HashSet[string]]::new(
    [string[]]$ExcludeResourceGroups,
    [System.StringComparer]::OrdinalIgnoreCase
)
$toDelete = @($resourceGroups | Where-Object { -not $excludeSet.Contains($_) })
$skipped = @($resourceGroups | Where-Object { $excludeSet.Contains($_) })

if (-not $toDelete) {
    Write-Host "No resource groups to delete."
}
else {
    Write-Host ""
    Write-Host "Resource group(s) to delete ($($toDelete.Count)):"
    foreach ($rg in $toDelete) {
        Write-Host "  - $rg"
    }
}

if ($skipped) {
    Write-Host ""
    Write-Host "Resource group(s) excluded ($($skipped.Count)):"
    foreach ($rg in $skipped) {
        Write-Host "  - $rg"
    }
}

if ($Force -and $toDelete) {
    Write-Host ""
    Write-Host "Deleting resource groups (--no-wait, runs asynchronously in Azure)..."
    foreach ($rg in $toDelete) {
        Write-Host "  Deleting $rg ..."
        az group delete --name $rg --yes --no-wait
    }
}

$defenderPlans = @(
    'VirtualMachines', 'AppServices', 'SqlServers', 'KeyVaults',
    'StorageAccounts', 'Containers', 'Arm', 'CloudPosture'
)

Write-Host ""
if ($Force) {
    Write-Host "Resetting Defender for Cloud plans to Free tier..."
    foreach ($plan in $defenderPlans) {
        Write-Host "  $plan -> Free"
        az security pricing create --name $plan --tier Free 2>$null | Out-Null
    }
}
else {
    Write-Host "Would reset these Defender for Cloud plans to Free tier: $($defenderPlans -join ', ')"
}

Write-Host ""
if ($Force) {
    Write-Host "Teardown complete."
    Write-Host ""
    Write-Host "Resource group deletions run asynchronously - check"
    Write-Host "  az group list --query '[].name'"
    Write-Host "in a few minutes to confirm they're gone."
}
else {
    Write-Host "Dry run complete. Re-run with -Force to actually delete."
}
Write-Host ""
Write-Host "Not removed by this script (see teardown-sandbox.ps1 and"
Write-Host "scripts/graph/teardown-test-personas.ps1 for those):"
Write-Host "  - Custom RBAC role definitions / policy assignments (outside any resource group)"
Write-Host "  - CI OIDC app registration / federated credential / role assignments"
Write-Host "  - Entra ID test persona accounts and break-glass accounts"
Write-Host ""
Write-Host "After running with -Force, confirm via Cost Management + Billing that"
Write-Host "the expected resources are gone and billing has stopped."
