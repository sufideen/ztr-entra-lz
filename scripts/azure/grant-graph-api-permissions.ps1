#Requires -Version 5.1
<#
.SYNOPSIS
  Grants the Microsoft Graph Application (app role) permissions the CI
  identity needs to run the automated Graph PowerShell fallback path
  (deploy.yml's "Apply Conditional Access / PIM fallback" step), which is
  currently unwired because the CI app registration has no Graph API
  permissions at all - see docs/graph-resources.md and
  docs/phase2-roadmap.md item 3.

.DESCRIPTION
  Adds permissions to the app registration's requested-permissions list
  only. Does NOT grant admin consent - Application permissions are inert
  until a Global Administrator (or Privileged Role Administrator) runs
  the `az ad app permission admin-consent` command this script prints at
  the end. This mirrors the rest of this repo's pattern for tenant-
  modifying actions that need a deliberate, informed decision rather than
  a script running them silently - see docs/break-glass-procedure.md and
  the "author, don't execute" note on scripts/graph/create-test-personas.ps1.

  Deliberately scoped to only the two permissions
  deploy-conditional-access.ps1 and deploy-pim-policies.ps1 declare via
  their own Connect-MgGraph -Scopes calls - those are the only two
  scripts deploy.yml's fallback step actually runs unattended. This
  script does NOT grant User.ReadWrite.All / EntitlementManagement.ReadWrite.All
  (needed by create-test-personas.ps1 / create-access-package.ps1 /
  teardown-test-personas.ps1): those scripts are designed to run under a
  human operator's own delegated Graph session (interactive
  Connect-MgGraph, not the CI identity), so granting the CI service
  principal standing Application permissions over every user and
  entitlement in the tenant would be an unnecessary privilege increase
  for scripts that are explicitly manual-only by design.

  Looks up each permission's app role ID dynamically from the Microsoft
  Graph service principal rather than hardcoding GUIDs, since
  transcribing a permission GUID wrong would silently request the wrong
  permission with no error until someone checks.

.PARAMETER AppDisplayName
  Must match the app registration created by setup-federated-identity.ps1.

.PARAMETER IncludeGroupsPermission
  Also request Group.ReadWrite.All. Off by default: bicep/modules/groups.bicep
  is authored but has no PowerShell fallback deploy script yet (unlike
  conditionalAccess.bicep/pim.bicep), so there's nothing in deploy.yml
  that would use this permission today. Pass this switch once a
  deploy-groups.ps1 fallback script exists and is wired into deploy.yml.

.EXAMPLE
  .\grant-graph-api-permissions.ps1
#>
param(
    [string]$AppDisplayName = "ztr-entra-lz-ci",
    [switch]$IncludeGroupsPermission
)

$ErrorActionPreference = "Stop"
if (Get-Variable -Name PSNativeCommandUseErrorActionPreference -Scope Global -ErrorAction SilentlyContinue) {
    $PSNativeCommandUseErrorActionPreference = $false
}

$graphAppId = "00000003-0000-0000-c000-000000000000"

$permissions = @(
    'Policy.ReadWrite.ConditionalAccess'        # deploy-conditional-access.ps1
    'RoleManagementPolicy.ReadWrite.Directory'  # deploy-pim-policies.ps1
)
if ($IncludeGroupsPermission) {
    $permissions += 'Group.ReadWrite.All'
}

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
Write-Host "Resolving Microsoft Graph service principal ($graphAppId)..."
$graphSp = az ad sp show --id $graphAppId | ConvertFrom-Json

Write-Host ""
Write-Host "Requesting Application permissions: $($permissions -join ', ')"
foreach ($permName in $permissions) {
    $role = $graphSp.appRoles | Where-Object { $_.value -eq $permName -and $_.allowedMemberTypes -contains 'Application' }
    if (-not $role) {
        Write-Warning "Could not resolve app role '$permName' on the Microsoft Graph service principal - skipping."
        continue
    }
    Write-Host "  $permName -> role id $($role.id)"
    az ad app permission add --id $appId --api $graphAppId --api-permissions "$($role.id)=Role" | Out-Null
}

Write-Host ""
Write-Host "Done. Permissions were added to the app registration's requested-permissions"
Write-Host "list but are NOT active yet - Application permissions require tenant admin"
Write-Host "consent before they take effect."
Write-Host ""
Write-Host "A Global Administrator (or Privileged Role Administrator) must run:"
Write-Host ""
Write-Host "  az ad app permission admin-consent --id $appId"
Write-Host ""
Write-Host "This script deliberately does not run that command itself. Consenting is a"
Write-Host "real, tenant-wide privilege escalation for the CI identity -"
Write-Host "RoleManagementPolicy.ReadWrite.Directory and Policy.ReadWrite.ConditionalAccess"
Write-Host "let it rewrite PIM and Conditional Access enforcement tenant-wide - and should"
Write-Host "be a deliberate, reviewed action, not something a script does silently."
Write-Host ""
Write-Host "After consenting, set the GRAPH_BICEP_EXTENSION_AVAILABLE repo variable to"
Write-Host "'false' so deploy.yml's PowerShell fallback step actually runs:"
Write-Host ""
Write-Host "  gh variable set GRAPH_BICEP_EXTENSION_AVAILABLE --body false"
Write-Host ""
Write-Host "(or Settings > Secrets and variables > Actions > Variables in the GitHub UI)"
