#Requires -Version 5.1
<#
.SYNOPSIS
  Exports an inventory of every VM in the current subscription to CSV -
  name, size, OS, power state, and tags - for asset-register style audit
  evidence alongside export-rbac-audit.ps1.

.DESCRIPTION
  Uses Azure CLI (az), matching the rest of scripts/azure/. Read-only -
  lists VMs, writes nothing to the subscription. `az vm list -d` (the
  "-d"/--show-details flag) is what actually populates PowerState; without
  it that field comes back empty.

.PARAMETER OutputPath
  Where to write the CSV. Default: AzureVMInventory.csv in the current directory.

.EXAMPLE
  .\export-vm-inventory.ps1
.EXAMPLE
  .\export-vm-inventory.ps1 -OutputPath C:\audit\AzureVMInventory.csv
#>
param(
    [string]$OutputPath = "AzureVMInventory.csv"
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
Write-Host "Listing VMs..."
$vms = az vm list -d | ConvertFrom-Json

if (-not $vms) {
    Write-Warning "No VMs returned - check your az login context and permissions."
}

$rows = $vms | ForEach-Object {
    [pscustomobject]@{
        Name         = $_.name
        ResourceGroup = $_.resourceGroup
        Location     = $_.location
        VmSize       = $_.hardwareProfile.vmSize
        OsType       = $_.storageProfile.osDisk.osType
        PowerState   = $_.powerState
        Tags         = if ($_.tags) { ($_.tags.PSObject.Properties | ForEach-Object { "$($_.Name)=$($_.Value)" }) -join ';' } else { "" }
    }
}

$rows | Export-Csv -Path $OutputPath -NoTypeInformation

Write-Host ""
Write-Host "Wrote $($rows.Count) VM(s) to $OutputPath"
