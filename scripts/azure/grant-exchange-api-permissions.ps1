#Requires -Version 5.1
<#
.SYNOPSIS
  Grants the CI identity the Application permission needed to eventually
  run scripts/purview/deploy-dlp-policies.ps1 unattended, and prints the
  additional Security & Compliance role-group step that plane requires.

.DESCRIPTION
  Mirrors scripts/azure/grant-graph-api-permissions.ps1's pattern exactly:
  resolves the app role ID dynamically off the target service principal's
  appRoles (never hardcodes a GUID), adds the permission to the app
  registration's requested-permissions list, and prints - but never runs -
  the admin-consent command. See that script's header comment for the full
  rationale; this one only calls out what differs.

  Targets the Office 365 Exchange Online first-party service principal
  (00000002-0000-0ff1-ce00-000000000000), not the Microsoft Graph service
  principal - Security & Compliance PowerShell (Connect-IPPSSession) is a
  separate control plane from Microsoft Graph, see docs/graph-resources.md.

  Unlike Graph Application permissions, an Exchange.ManageAsApp grant +
  admin consent is NOT sufficient on its own for Connect-IPPSSession to
  succeed - the app must also be a member of an Exchange Online RBAC role
  group scoped to DLP management. This script does not create that role
  group (least-privilege, human-reviewed action, same as admin-consent
  below) - it prints the commands for a Global Administrator / Compliance
  Administrator to run, following a dedicated custom role group rather
  than the broad built-in "Compliance Administrator" role, matching this
  repo's least-privilege pattern in bicep/modules/rbac/customRoles.bicep.

.PARAMETER AppDisplayName
  Must match the app registration created by setup-federated-identity.ps1.

.EXAMPLE
  .\grant-exchange-api-permissions.ps1
#>
param(
    [string]$AppDisplayName = "ztr-entra-lz-ci"
)

$ErrorActionPreference = "Stop"
if (Get-Variable -Name PSNativeCommandUseErrorActionPreference -Scope Global -ErrorAction SilentlyContinue) {
    $PSNativeCommandUseErrorActionPreference = $false
}

$exoAppId = "00000002-0000-0ff1-ce00-000000000000"  # Office 365 Exchange Online
$permission = 'Exchange.ManageAsApp'

Write-Host "Checking Azure CLI login state..."
$account = az account show 2>$null | ConvertFrom-Json
if (-not $account) {
    Write-Host "Not logged in. Running az login..."
    az login | Out-Null
}
Write-Host "Using subscription: $($account.name)"

Write-Host ""
Write-Host "Looking up app registration '$AppDisplayName'..."
$app = az ad app list --display-name $AppDisplayName --query "[0]" | ConvertFrom-Json
if (-not $app) {
    throw "App registration '$AppDisplayName' not found - run scripts/azure/setup-federated-identity.ps1 first."
}
$appId = $app.appId
Write-Host "Found app: $appId"

Write-Host ""
Write-Host "Resolving Office 365 Exchange Online service principal ($exoAppId)..."
$exoSp = az ad sp show --id $exoAppId | ConvertFrom-Json

Write-Host ""
Write-Host "Requesting Application permission: $permission"
$role = $exoSp.appRoles | Where-Object { $_.value -eq $permission -and $_.allowedMemberTypes -contains 'Application' }
if (-not $role) {
    throw "Could not resolve app role '$permission' on the Exchange Online service principal."
}
Write-Host "  $permission -> role id $($role.id)"
az ad app permission add --id $appId --api $exoAppId --api-permissions "$($role.id)=Role" | Out-Null

Write-Host ""
Write-Host "Done. Permission was added to the app registration's requested-permissions"
Write-Host "list but is NOT active yet - Application permissions require tenant admin"
Write-Host "consent before they take effect."
Write-Host ""
Write-Host "A Global Administrator must run:"
Write-Host ""
Write-Host "  az ad app permission admin-consent --id $appId"
Write-Host ""
Write-Host "This script deliberately does not run that command itself - see"
Write-Host "grant-graph-api-permissions.ps1 for the same 'author, don't execute' rationale."
Write-Host ""
Write-Host "Exchange.ManageAsApp consent alone is NOT sufficient for Connect-IPPSSession"
Write-Host "to succeed - the app must also be added to an Exchange Online RBAC role group"
Write-Host "scoped to DLP management. A Global Administrator / Compliance Administrator"
Write-Host "must also run (in a Connect-IPPSSession as themselves, after creating a"
Write-Host "purpose-scoped role group rather than granting the broad built-in"
Write-Host "'Compliance Administrator' role):"
Write-Host ""
Write-Host "  New-RoleGroup -Name 'ztr-entra-lz DLP Policy Manager' -Roles 'DLP Compliance Management'"
Write-Host "  Add-RoleGroupMember -Identity 'ztr-entra-lz DLP Policy Manager' -Member $appId"
Write-Host ""
Write-Host "See docs/graph-resources.md for the open decision on whether"
Write-Host "Connect-IPPSSession can authenticate via this repo's existing OIDC"
Write-Host "federated credential or requires a new certificate-based app-only auth"
Write-Host "artifact - resolve that before wiring this into deploy.yml unattended."
