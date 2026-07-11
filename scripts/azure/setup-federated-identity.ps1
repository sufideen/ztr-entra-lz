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
  Resource group the app is granted Contributor on for this first
  deployment. Created if it does not exist. Deliberately scoped to a
  single resource group, not the subscription, to cap blast radius.

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

Write-Host "Checking Azure CLI login state..."
$account = az account show 2>$null | ConvertFrom-Json
if (-not $account) {
    Write-Host "Not logged in. Running az login..."
    az login | Out-Null
    $account = az account show | ConvertFrom-Json
}
$subscriptionId = $account.id
$tenantId = $account.tenantId
Write-Host "Using subscription: $($account.name) ($subscriptionId)"

Write-Host ""
Write-Host "Checking for existing app registration $AppDisplayName ..."
$existingApp = az ad app list --display-name $AppDisplayName --query "[0]" | ConvertFrom-Json

if ($existingApp) {
    Write-Host "Found existing app: $($existingApp.appId)"
    $appId = $existingApp.appId
    $appObjectId = $existingApp.id
}
else {
    Write-Host "Creating new app registration..."
    $app = az ad app create --display-name $AppDisplayName | ConvertFrom-Json
    $appId = $app.appId
    $appObjectId = $app.id
    Write-Host "Created app: $appId"
}

Write-Host ""
Write-Host "Checking for service principal..."
$sp = az ad sp list --filter "appId eq '$appId'" --query "[0]" | ConvertFrom-Json
if (-not $sp) {
    Write-Host "Creating service principal..."
    $sp = az ad sp create --id $appId | ConvertFrom-Json
}
else {
    Write-Host "Service principal already exists: $($sp.id)"
}

$credName = "$GitHubRepo-$GitHubEnvironment-deploy"
$subject = "repo:$GitHubOrg/$GitHubRepo:environment:$GitHubEnvironment"

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

$fedCredResult = az ad app federated-credential create --id $appObjectId --parameters "@$tempFile" 2>&1
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
$rgExists = az group exists --name $ResourceGroupName | ConvertFrom-Json
if (-not $rgExists) {
    Write-Host "Creating resource group in $Location..."
    az group create --name $ResourceGroupName --location $Location | Out-Null
}
else {
    Write-Host "Resource group already exists."
}

Write-Host ""
Write-Host "Assigning Contributor role scoped to resource group $ResourceGroupName ..."
$scope = "/subscriptions/$subscriptionId/resourceGroups/$ResourceGroupName"

az role assignment create --assignee $appId --role "Contributor" --scope $scope | Out-Null

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
