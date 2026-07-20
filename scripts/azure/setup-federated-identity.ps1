#Requires -Version 5.1
<#
.SYNOPSIS
  Creates the Entra ID app registration, service principal, OIDC federated
  credential, and initial RBAC role assignment needed for GitHub Actions
  to deploy this repo's Bicep against Azure - no client secret involved
  anywhere in this chain.

.DESCRIPTION
  Uses Azure CLI (az), not PowerShell's Az module, so it works from the
  same azcli-venv session used throughout this project. Idempotent where
  practical: re-running it will not create duplicate app registrations if
  one with the same display name already exists.

.PARAMETER GitHubOrg
  GitHub username/org that owns the repo. Default: sufideen

.PARAMETER GitHubRepo
  Repo name. Default: ztr-entra-lz

.PARAMETER GitHubEnvironment
  The GitHub Environment name this federated credential trusts. Must
  exactly match the environment value used in deploy.yml jobs and the
  GitHub Environment already configured with required reviewers.

.PARAMETER ResourceGroupName
  Resource group created up front so it exists before the first deployment
  (Bicep also (re)creates it idempotently at deploy time). The RBAC grant
  itself is scoped to the subscription, not this resource group - see the
  "Assigning Contributor" step below for why a resource-group-scoped grant
  is not sufficient for this repo's deployment model.

.PARAMETER Location
  Azure region for the resource group if it needs creating.

.EXAMPLE
  .\setup-federated-identity.ps1 -GitHubEnvironment sandbox -ResourceGroupName rg-security-sandbox
#>
param(
    [string]$GitHubOrg = "sufideen",
    [string]$GitHubRepo = "ztr-entra-lz",
    [Parameter(Mandatory)]
    [string]$GitHubEnvironment,
    [Parameter(Mandatory)]
    [string]$ResourceGroupName,
    [string]$Location = "uksouth",
    [string]$AppDisplayName = "ztr-entra-lz-ci"
)

$ErrorActionPreference = "Stop"

# PowerShell 7.3+ auto-converts a native command's non-zero exit code into a
# terminating error when $ErrorActionPreference = 'Stop', which bypasses this
# script's own $LASTEXITCODE checks below (e.g. the federated-credential
# create call a few steps down, which is expected to "fail" harmlessly when
# the credential already exists on a re-run). Restore the classic exit-code
# behavior so those checks actually get a chance to run. The variable does
# not exist on Windows PowerShell 5.1, hence the guarded check.
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
$subscriptionId = $account.id
$tenantId = $account.tenantId
Write-Host "Using subscription: $($account.name) ($subscriptionId)"

Write-Host ""
Write-Host "Checking for existing app registration $AppDisplayName ..."
$existingApp = az ad app list --display-name $AppDisplayName --query "[0]" --output json | ConvertFrom-Json

if ($existingApp) {
    Write-Host "Found existing app: $($existingApp.appId)"
    $appId = $existingApp.appId
    $appObjectId = $existingApp.id
}
else {
    Write-Host "Creating new app registration..."
    $app = az ad app create --display-name $AppDisplayName --output json | ConvertFrom-Json
    $appId = $app.appId
    $appObjectId = $app.id
    Write-Host "Created app: $appId"
}

Write-Host ""
Write-Host "Checking for service principal..."
$sp = az ad sp list --filter "appId eq '$appId'" --query "[0]" --output json | ConvertFrom-Json
if (-not $sp) {
    Write-Host "Creating service principal..."
    $sp = az ad sp create --id $appId --output json | ConvertFrom-Json
}
else {
    Write-Host "Service principal already exists: $($sp.id)"
}

$credName = "${GitHubRepo}-${GitHubEnvironment}-deploy"
$subject = "repo:${GitHubOrg}/${GitHubRepo}:environment:${GitHubEnvironment}"

Write-Host ""
Write-Host "Creating federated credential $credName ..."
Write-Host "  Subject claim: $subject"

$fedCredBody = @{
    name        = $credName
    issuer      = "https://token.actions.githubusercontent.com"
    subject     = $subject
    description = "GitHub Actions OIDC trust for $GitHubOrg/$GitHubRepo environment $GitHubEnvironment"
    audiences   = @("api://AzureADTokenExchange")
}
$fedCredJson = $fedCredBody | ConvertTo-Json -Compress

$tempFile = New-TemporaryFile
Set-Content -Path $tempFile -Value $fedCredJson

# Merging a native command's stderr via 2>&1 turns each stderr line into a
# PowerShell ErrorRecord - with $ErrorActionPreference = 'Stop' (set above),
# that throws immediately and skips the $LASTEXITCODE check below entirely,
# regardless of PowerShell version. This call is expected to "fail" harmlessly
# when the credential already exists on a re-run, so temporarily relax to
# 'Continue' just for this one native invocation.
$previousErrorActionPreference = $ErrorActionPreference
$ErrorActionPreference = "Continue"
$fedCredResult = az ad app federated-credential create --id $appObjectId --parameters "@$tempFile" 2>&1
$ErrorActionPreference = $previousErrorActionPreference
if ($LASTEXITCODE -eq 0) {
    Write-Host "Federated credential created."
}
else {
    Write-Warning "Federated credential creation may have failed or already exists. Details:"
    Write-Warning $fedCredResult
}
Remove-Item $tempFile -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "Checking resource group $ResourceGroupName ..."
$rgExists = az group exists --name $ResourceGroupName --output json | ConvertFrom-Json
if (-not $rgExists) {
    Write-Host "Creating resource group in $Location..."
    az group create --name $ResourceGroupName --location $Location | Out-Null
}
else {
    Write-Host "Resource group already exists."
}

Write-Host ""
Write-Host "Assigning Contributor role scoped to subscription $subscriptionId ..."
# main.bicep deploys at subscription scope (targetScope = 'subscription') - it
# creates its own resource groups and deploys subscription-level resources
# (Defender pricing plans, custom RBAC role definitions, policy definitions).
# `az deployment sub what-if|create` requires Microsoft.Resources/deployments/*
# permissions at the subscription itself, not just at a child resource group,
# so a resource-group-scoped grant is not sufficient here even though the
# resources it provisions mostly land inside rg-security-<environment>.
# This widens the CI identity's blast radius from a single resource group to
# the whole subscription - acceptable for the throwaway sandbox this targets
# by default (see THROWAWAY.md), but re-evaluate before pointing this at a
# real subscription.
$scope = "/subscriptions/$subscriptionId"

az role assignment create --assignee $appId --role "Contributor" --scope $scope | Out-Null

$authWriterRoleName = "ztr-entra-lz CI Authorization Writer"

Write-Host ""
Write-Host "Checking for existing custom role $authWriterRoleName ..."
$existingAuthWriterRole = az role definition list --name $authWriterRoleName --query "[0]" --output json | ConvertFrom-Json

if ($existingAuthWriterRole) {
    Write-Host "Custom role already exists: $($existingAuthWriterRole.id)"
}
else {
    Write-Host "Creating custom role $authWriterRoleName ..."
    # Contributor deliberately excludes all Microsoft.Authorization/*/write
    # actions (Azure's guardrail against Contributor self-escalating access),
    # which blocks main.bicep's customRoles.bicep (custom RBAC role
    # definitions) and diagnosticSettings.bicep (policy definition +
    # assignment) modules. Rather than granting the CI identity the built-in
    # User Access Administrator role - which also grants
    # Microsoft.Authorization/roleAssignments/write|delete, letting it grant
    # or revoke access to anyone including itself - this narrow custom role
    # grants only the three specific write actions those modules need, and
    # nothing else. The CI identity can define roles and policies but can
    # never assign them.
    $authWriterRoleBody = @{
        Name             = $authWriterRoleName
        IsCustom         = $true
        Description      = "Least-privilege alternative to User Access Administrator for CI/CD: allows writing RBAC role definitions and policy definitions/assignments only. Deliberately excludes Microsoft.Authorization/roleAssignments/* to prevent the CI identity from granting or revoking access to anyone, including itself."
        Actions          = @(
            "Microsoft.Authorization/roleDefinitions/write"
            "Microsoft.Authorization/policyDefinitions/write"
            "Microsoft.Authorization/policyAssignments/write"
        )
        NotActions       = @()
        AssignableScopes = @($scope)
    }
    $authWriterRoleJson = $authWriterRoleBody | ConvertTo-Json -Compress

    $authWriterRoleFile = New-TemporaryFile
    Set-Content -Path $authWriterRoleFile -Value $authWriterRoleJson

    az role definition create --role-definition "@$authWriterRoleFile" | Out-Null
    Remove-Item $authWriterRoleFile -ErrorAction SilentlyContinue
    Write-Host "Custom role created."
}

Write-Host ""
Write-Host "Assigning $authWriterRoleName role scoped to subscription $subscriptionId ..."
az role assignment create --assignee $appId --role $authWriterRoleName --scope $scope | Out-Null

Write-Host ""
Write-Host "Done. Summary:"
Write-Host "  App client ID     : $appId"
Write-Host "  Tenant ID         : $tenantId"
Write-Host "  Subscription ID   : $subscriptionId"
Write-Host "  Resource group    : $ResourceGroupName"
Write-Host "  Federated subject : $subject"
Write-Host ""
Write-Host "Add these as GitHub repo secrets (or run configure-repo-secrets.py):"
Write-Host "  AZURE_CLIENT_ID       = $appId"
Write-Host "  AZURE_TENANT_ID       = $tenantId"
Write-Host "  AZURE_SUBSCRIPTION_ID = $subscriptionId"
