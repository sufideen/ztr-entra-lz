#Requires -Version 5.1
<#
.SYNOPSIS
  Interactively tears down resource groups in the current subscription one
  at a time, reporting billable resources before each deletion, while
  guaranteeing a minimum number of resource groups survive.

.DESCRIPTION
  teardown-all-resource-groups.ps1 is all-or-nothing (-Force deletes every
  resource group). This script is for the case where you want to keep some
  resource groups around and decide group-by-group: it first prints an
  inventory of every resource group and the resources inside it, then walks
  each resource group in turn and asks Delete / Keep / Quit. For a group
  you choose to delete, it deletes the resources inside that group first,
  then deletes the (now empty) group itself - resources before resource
  groups, so you see exactly what's being removed at each step rather than
  a single opaque `az group delete`.

  A minimum-keep floor (-MinimumKeep, default 3) is enforced: once enough
  groups have been deleted that only MinimumKeep remain, the rest are kept
  automatically without prompting - you can't accidentally delete past the
  floor.

  Uses Azure CLI (az), matching the rest of scripts/azure/.

.PARAMETER MinimumKeep
  Minimum number of resource groups to leave in place. Default: 3.

.PARAMETER ExcludeResourceGroups
  Names of resource groups to keep automatically, without prompting.
  Matched case-insensitively. These still count toward MinimumKeep.

.EXAMPLE
  .\teardown-resource-groups-interactive.ps1
  Lists every resource group and its resources, then prompts for each one.

.EXAMPLE
  .\teardown-resource-groups-interactive.ps1 -MinimumKeep 5 -ExcludeResourceGroups rg-security-sandbox
  Keeps rg-security-sandbox automatically and stops prompting once only
  5 resource groups remain.
#>
param(
    [int]$MinimumKeep = 3,
    [string[]]$ExcludeResourceGroups = @()
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
Write-Host "Discovering resource groups and their resources..."
$groupNames = @(az group list --query "[].name" | ConvertFrom-Json)

if (-not $groupNames) {
    Write-Host "No resource groups in this subscription. Nothing to do."
    exit 0
}

# Inventory pass: pull resources for every group up front so the full
# picture (and total resource/billable footprint) is visible before any
# prompting starts.
$inventory = [ordered]@{}
foreach ($rg in $groupNames) {
    $resources = @(az resource list --resource-group $rg --query "[].{Id:id,Name:name,Type:type,Location:location}" | ConvertFrom-Json)
    $inventory[$rg] = $resources
}

Write-Host ""
Write-Host "=== Inventory: $($groupNames.Count) resource group(s) ==="
$totalResources = 0
foreach ($rg in $groupNames) {
    $resources = $inventory[$rg]
    $totalResources += $resources.Count
    Write-Host ""
    Write-Host "$rg ($($resources.Count) resource(s))" -ForegroundColor Cyan
    if ($resources.Count -eq 0) {
        Write-Host "  (empty)"
    }
    else {
        foreach ($res in $resources) {
            Write-Host "  - $($res.Name)  [$($res.Type)]  $($res.Location)"
        }
    }
}
Write-Host ""
Write-Host "Total: $($groupNames.Count) resource group(s), $totalResources resource(s) across all of them."

$excludeSet = [System.Collections.Generic.HashSet[string]]::new(
    [string[]]$ExcludeResourceGroups,
    [System.StringComparer]::OrdinalIgnoreCase
)

if ($groupNames.Count -le $MinimumKeep) {
    Write-Host ""
    Write-Host "Only $($groupNames.Count) resource group(s) exist, at or below MinimumKeep ($MinimumKeep)."
    Write-Host "Nothing will be deleted."
    exit 0
}

$maxDeletable = $groupNames.Count - $MinimumKeep
Write-Host ""
Write-Host "Minimum $MinimumKeep resource group(s) will be kept - up to $maxDeletable can be deleted this run."

$deleted = @()
$kept = @()

foreach ($rg in $groupNames) {
    if ($deleted.Count -ge $maxDeletable) {
        Write-Host ""
        Write-Host "Reached the floor of $MinimumKeep remaining group(s) - keeping '$rg' and everything after it without prompting."
        $kept += $rg
        continue
    }

    if ($excludeSet.Contains($rg)) {
        Write-Host ""
        Write-Host "Keeping '$rg' (in -ExcludeResourceGroups)."
        $kept += $rg
        continue
    }

    $resources = $inventory[$rg]
    Write-Host ""
    Write-Host "--- $rg ($($resources.Count) resource(s)) ---" -ForegroundColor Yellow
    foreach ($res in $resources) {
        Write-Host "  - $($res.Name)  [$($res.Type)]"
    }
    $remainingAfterThis = $groupNames.Count - $deleted.Count - 1
    $answer = Read-Host "Delete '$rg' and its $($resources.Count) resource(s)? [y/N/q=quit]"

    switch ($answer.ToLowerInvariant()) {
        'q' {
            Write-Host "Quitting - no further groups will be prompted."
            $kept += $groupNames | Where-Object { $_ -notin $deleted -and $_ -notin $kept }
        }
        'y' {
            if ($resources.Count -gt 0) {
                Write-Host "Deleting $($resources.Count) resource(s) in '$rg' first..."
                $ids = $resources | ForEach-Object { $_.Id }
                try {
                    az resource delete --ids @ids
                }
                catch {
                    Write-Warning "One or more resources failed to delete individually: $_. Continuing to delete the resource group, which will remove anything left."
                }
            }
            Write-Host "Deleting resource group '$rg' (--no-wait, runs asynchronously in Azure)..."
            az group delete --name $rg --yes --no-wait
            $deleted += $rg
        }
        default {
            Write-Host "Keeping '$rg'."
            $kept += $rg
        }
    }

    if ($answer.ToLowerInvariant() -eq 'q') {
        break
    }
}

Write-Host ""
Write-Host "=== Summary ==="
Write-Host "Deleted ($($deleted.Count)): $(if ($deleted) { $deleted -join ', ' } else { '(none)' })"
Write-Host "Kept ($($kept.Count)): $(if ($kept) { $kept -join ', ' } else { '(none)' })"
Write-Host ""
Write-Host "Resource group deletions run asynchronously - check"
Write-Host "  az group list --query '[].name'"
Write-Host "in a few minutes to confirm they're gone."
Write-Host ""
Write-Host "After running, confirm via Cost Management + Billing that the expected"
Write-Host "resources are gone and billing has stopped."
