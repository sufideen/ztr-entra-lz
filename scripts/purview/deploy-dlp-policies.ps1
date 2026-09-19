#Requires -Modules ExchangeOnlineManagement
<#
.SYNOPSIS
  Idempotent deployment of Microsoft Purview DLP (Data Loss Prevention)
  compliance policies via Security & Compliance PowerShell.

.DESCRIPTION
  Unlike scripts/graph/deploy-conditional-access.ps1 and deploy-pim-policies.ps1,
  this is NOT a fallback for a Bicep source of truth - DLP compliance
  policies (New-DlpCompliancePolicy / New-DlpComplianceRule) are Security &
  Compliance Center resources, not Microsoft Graph or ARM resources, and
  have no confirmed Bicep-deployable resource type. This script is the real
  and only source of truth for the policies it defines. See
  docs/graph-resources.md's "DLP/Purview is a separate control plane, not
  Microsoft Graph" entry for why this lives in scripts/purview/ instead of
  scripts/graph/, and uses ExchangeOnlineManagement (Connect-IPPSSession)
  instead of the Microsoft.Graph SDK used everywhere else in this repo.

  All policies below deploy in a non-enforcing bake-period mode
  (TestWithNotifications), mirroring the Conditional Access discipline in
  THROWAWAY.md Step 5: promote a policy to "Enable" only as an individual,
  deliberate, reviewed change after a bake period (repo convention: 3-5
  days) reviewing Purview > Data loss prevention > Activity explorer for
  false positives. tests/DlpPolicies.RegressionGuard.Tests.ps1 enforces
  this the same way ConditionalAccess.RegressionGuard.Tests.ps1 enforces
  'enabledForReportingButNotEnforced' for Conditional Access.

.PARAMETER Environment
  sandbox | dev | prod - used only for logging, DLP policies are tenant-wide.

.PARAMETER TenantId
  For manual local runs, to avoid an ambiguous cached-account prompt.

.NOTES
  Auth: this script connects interactively (Connect-IPPSSession) by
  default, matching the human-operator-run pattern of
  scripts/graph/create-test-personas.ps1 - unlike deploy-conditional-access.ps1,
  there is currently no unattended/CI-safe auth path wired up for this
  script. Whether Connect-IPPSSession/Connect-ExchangeOnline supports an
  OIDC-federated access token (avoiding a new certificate secret, keeping
  this repo's "no stored secrets anywhere" posture from README.md) is
  UNVERIFIED - confirm against the current ExchangeOnlineManagement module
  docs before wiring this into deploy.yml. See docs/graph-resources.md for
  the open decision.
#>
param(
  [Parameter(Mandatory)]
  [ValidateSet('sandbox', 'dev', 'prod')]
  [string]$Environment,

  [string]$TenantId
)

$connectParams = @{}
if ($TenantId) { $connectParams.Organization = $TenantId }
Connect-IPPSSession @connectParams

function Set-DlpPolicy {
  param(
    [string]$DisplayName,
    [hashtable]$PolicyParams,
    [string]$RuleName,
    [hashtable]$RuleParams
  )

  $existingPolicy = Get-DlpCompliancePolicy -Identity $DisplayName -ErrorAction SilentlyContinue
  if ($existingPolicy) {
    Write-Host "Updating existing DLP policy: $DisplayName"
    Set-DlpCompliancePolicy -Identity $DisplayName @PolicyParams
  } else {
    Write-Host "Creating new DLP policy: $DisplayName"
    New-DlpCompliancePolicy -Name $DisplayName @PolicyParams
  }

  $existingRule = Get-DlpComplianceRule -Identity $RuleName -ErrorAction SilentlyContinue
  if ($existingRule) {
    Write-Host "Updating existing DLP rule: $RuleName"
    Set-DlpComplianceRule -Identity $RuleName @RuleParams
  } else {
    Write-Host "Creating new DLP rule: $RuleName"
    New-DlpComplianceRule -Name $RuleName -Policy $DisplayName @RuleParams
  }
}

# DLP001 - deploys in TestWithNotifications (report-only) per the bake-period
# discipline above - promote to 'Enable' only as a deliberate, reviewed
# follow-up change once Activity explorer confirms no false positives.
Set-DlpPolicy -DisplayName "DLP001 - Financial data - Restrict credit card sharing in SharePoint/OneDrive" `
  -PolicyParams @{
    Mode              = "TestWithNotifications"
    SharePointLocation = "All"
    OneDriveLocation   = "All"
  } `
  -RuleName "DLP001 - Credit card content rule" `
  -RuleParams @{
    ContentContainsSensitiveInformation = @(@{ Name = "Credit Card Number"; minCount = "1" })
    BlockAccess           = $true
    BlockAccessScope       = "PerUser"
    NotifyUser             = @("SiteAdmin", "LastModifier")
    NotifyPolicyTipCustomText = "This file appears to contain credit card numbers. Sharing may violate policy - see docs/compliance-mapping.md."
    GenerateIncidentReport = @("SiteAdmin")
  }

# DLP002 - audit/notify only, no block, deploys in TestWithNotifications.
Set-DlpPolicy -DisplayName "DLP002 - PII - Audit national ID data leaving via Exchange email" `
  -PolicyParams @{
    Mode             = "TestWithNotifications"
    ExchangeLocation = "All"
  } `
  -RuleName "DLP002 - National ID content rule" `
  -RuleParams @{
    ContentContainsSensitiveInformation = @(@{ Name = "EU National Identification Number"; minCount = "1" })
    ExceptIfRecipientDomainIs = @()
    GenerateIncidentReport    = @("Owner")
    NotifyUser                = @("Owner")
    NotifyPolicyTipCustomText  = "This email appears to contain a national ID number sent externally - flagged for audit, not blocked."
  }

Write-Host "DLP policy deployment complete for environment: $Environment"
Disconnect-ExchangeOnline -Confirm:$false
