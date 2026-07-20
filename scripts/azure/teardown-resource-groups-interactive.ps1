#Requires -Version 5.1
<#
.SYNOPSIS
  Enumerates resource groups in the current subscription, then walks them
  one at a time - opening each to show its resources tagged billable /
  non-billable - and asks Delete or Keep, while guaranteeing a minimum
  number of resource groups survive.

.DESCRIPTION
  teardown-all-resource-groups.ps1 is all-or-nothing (-Force deletes every
  resource group). This script is for the case where you want to keep some
  resource groups around and decide group-by-group:

    1. Enumerate every resource group in the subscription (name + resource
       count only - a quick list, not a full dump).
    2. Open each resource group in turn and list the resources inside it,
       each tagged [Billable] / [Non-billable] / [Unknown] using a
       best-effort lookup table by resource type (see Get-BillabilityLabel
       below - always confirm actual spend in Cost Management, this is a
       heuristic, not billing data).
    3. Ask Delete or Keep for that group. Answering keeps moves straight to
       the next resource group - no need to reselect anything.

  For a group you delete, resources inside it are deleted first, then the
  (now empty) group itself - so you see exactly what's being removed at
  each step rather than a single opaque `az group delete`.

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
  Enumerates every resource group, then opens each one in turn and prompts.

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

# Best-effort classification by resource type. Azure's actual bill depends
# on SKU/tier/usage (e.g. a Basic Load Balancer is free, Standard isn't),
# so treat this as a guide for what to look at first, not ground truth -
# cross-check anything that matters in Cost Management + Billing.
$BillableTypePatterns = @(
    'microsoft.compute/virtualmachines',
    'microsoft.compute/disks',
    'microsoft.compute/virtualmachinescalesets',
    'microsoft.storage/storageaccounts',
    'microsoft.operationalinsights/workspaces',
    'microsoft.insights/components',
    'microsoft.sql/servers/databases',
    'microsoft.sql/managedinstances',
    'microsoft.web/serverfarms',
    'microsoft.web/sites',
    'microsoft.containerservice/managedclusters',
    'microsoft.network/publicipaddresses',
    'microsoft.network/applicationgateways',
    'microsoft.network/loadbalancers',
    'microsoft.network/azurefirewalls',
    'microsoft.network/bastionhosts',
    'microsoft.network/natgateways',
    'microsoft.network/virtualnetworkgateways',
    'microsoft.network/expressroutecircuits',
    'microsoft.network/privateendpoints',
    'microsoft.keyvault/vaults',
    'microsoft.cognitiveservices/accounts',
    'microsoft.documentdb/databaseaccounts',
    'microsoft.cache/redis',
    'microsoft.eventhub/namespaces',
    'microsoft.servicebus/namespaces',
    'microsoft.cdn/profiles',
    'microsoft.containerregistry/registries'
)
$NonBillableTypePatterns = @(
    'microsoft.network/virtualnetworks',
    'microsoft.network/networksecuritygroups',
    'microsoft.network/routetables',
    'microsoft.network/networkinterfaces',
    'microsoft.network/privatednszones',
    'microsoft.managedidentity/userassignedidentities',
    'microsoft.authorization/roleassignments',
    'microsoft.authorization/policyassignments',
    'microsoft.insights/diagnosticsettings',
    'microsoft.insights/workbooks',
    'microsoft.operationsmanagement/solutions',
    'microsoft.securityinsights',
    'microsoft.resources/deployments'
)

function Get-BillabilityLabel {
    param([string]$ResourceType)
    $t = $ResourceType.ToLowerInvariant()
    foreach ($pattern in $BillableTypePatterns) {
        if ($t -like "$pattern*") { return '[Billable]' }
    }
    foreach ($pattern in $NonBillableTypePatterns) {
        if ($t -like "$pattern*") { return '[Non-billable]' }
    }
    return '[Unknown - check Cost Management]'
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
Write-Host "Enumerating resource groups..."
$groupNames = @(az group list --query "[].name" | ConvertFrom-Json)

if (-not $groupNames) {
    Write-Host "No resource groups in this subscription. Nothing to do."
    exit 0
}

Write-Host ""
Write-Host "=== $($groupNames.Count) resource group(s) ==="
for ($i = 0; $i -lt $groupNames.Count; $i++) {
    Write-Host "  $($i + 1). $($groupNames[$i])"
}

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

    Write-Host ""
    Write-Host "=== Opening '$rg' ===" -ForegroundColor Yellow
    $resources = @(az resource list --resource-group $rg --query "[].{Id:id,Name:name,Type:type,Location:location}" | ConvertFrom-Json)
    if ($resources.Count -eq 0) {
        Write-Host "  (empty - no resources)"
    }
    else {
        foreach ($res in $resources) {
            $label = Get-BillabilityLabel -ResourceType $res.Type
            Write-Host "  - $($res.Name)  [$($res.Type)]  $label"
        }
    }

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
            Write-Host "Keeping '$rg'. Moving to the next resource group."
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
