#Requires -Modules Microsoft.Graph.Identity.SignIns
<#
.SYNOPSIS
  Idempotent fallback deployment of Conditional Access policies via
  Microsoft Graph PowerShell, used when the Bicep Microsoft Graph
  extension is unavailable in the pipeline runner's Bicep CLI version.

.DESCRIPTION
  Reads policy definitions from ../../bicep/modules/conditionalAccess.bicep
  is NOT what this does — that file is the source of truth for structure.
  This script is a temporary bridge: policies are defined here in parallel
  and kept in sync manually until the Graph Bicep extension is GA in this
  pipeline. Tracked as tech debt in docs/graph-resources.md.

.PARAMETER Environment
  sandbox | dev | prod — used only for logging/tagging, CA policies are tenant-wide.
#>
param(
  [Parameter(Mandatory)]
  [ValidateSet('sandbox', 'dev', 'prod')]
  [string]$Environment
)

# Auth uses the same federated OIDC workload identity as the Azure login step —
# Connect-MgGraph -Identity works when running in a GitHub-hosted runner with
# an OIDC-federated app registration granted Policy.ReadWrite.ConditionalAccess.
Connect-MgGraph -Scopes "Policy.ReadWrite.ConditionalAccess" -NoWelcome

$breakGlassGroupId = $env:BREAK_GLASS_GROUP_ID
if (-not $breakGlassGroupId) {
  throw "BREAK_GLASS_GROUP_ID is not set. Refusing to deploy Conditional Access policies without a break-glass exclusion - see docs/break-glass-procedure.md to create the group first, then set it as a secret/env var before re-running."
}

function Set-CaPolicy {
  param([string]$DisplayName, [hashtable]$Body)

  $existing = Get-MgIdentityConditionalAccessPolicy -Filter "displayName eq '$DisplayName'"
  if ($existing) {
    Write-Host "Updating existing policy: $DisplayName"
    Update-MgIdentityConditionalAccessPolicy -ConditionalAccessPolicyId $existing.Id -BodyParameter $Body
  } else {
    Write-Host "Creating new policy: $DisplayName"
    New-MgIdentityConditionalAccessPolicy -BodyParameter $Body
  }
}

# All policies below deploy report-only per THROWAWAY.md Step 5 - promote
# each to "enabled" individually only after a bake period (min 3-5 days)
# confirms Entra ID > Conditional Access > Insights and reporting shows no
# legitimate access would be blocked.
Set-CaPolicy -DisplayName "CA001 - Baseline - Require MFA for all users" -Body @{
  displayName = "CA001 - Baseline - Require MFA for all users"
  state       = "enabledForReportingButNotEnforced"
  conditions  = @{
    users        = @{ includeUsers = @("All"); excludeGroups = @($breakGlassGroupId) }
    applications = @{ includeApplications = @("All") }
    clientAppTypes = @("all")
  }
  grantControls = @{ operator = "OR"; builtInControls = @("mfa") }
}

Set-CaPolicy -DisplayName "CA002 - Baseline - Block legacy authentication" -Body @{
  displayName = "CA002 - Baseline - Block legacy authentication"
  state       = "enabledForReportingButNotEnforced"
  conditions  = @{
    users        = @{ includeUsers = @("All"); excludeGroups = @($breakGlassGroupId) }
    applications = @{ includeApplications = @("All") }
    clientAppTypes = @("exchangeActiveSync", "other")
  }
  grantControls = @{ operator = "OR"; builtInControls = @("block") }
}

# NOTE: replace this placeholder app ID with your tenant's actual Azure
# management app registration ID before running in enforced mode.
$azureManagementAppId = if ($env:AZURE_MGMT_APP_ID) { $env:AZURE_MGMT_APP_ID } else { "00000002-0000-0ff1-ce00-000000000000" }

Set-CaPolicy -DisplayName "CA010 - Employees - Require compliant device for admin portals" -Body @{
  displayName = "CA010 - Employees - Require compliant device for admin portals"
  state       = "enabledForReportingButNotEnforced"
  conditions  = @{
    users        = @{ includeUsers = @("All"); excludeGroups = @($breakGlassGroupId) }
    applications = @{ includeApplications = @($azureManagementAppId) }
    clientAppTypes = @("all")
  }
  grantControls = @{ operator = "AND"; builtInControls = @("mfa", "compliantDevice") }
}

Set-CaPolicy -DisplayName "CA020 - Guests - MFA, ToU, browser-only, no persistent session" -Body @{
  displayName = "CA020 - Guests - MFA, ToU, browser-only, no persistent session"
  state       = "enabledForReportingButNotEnforced"
  conditions  = @{
    users = @{
      includeGuestsOrExternalUsers = @{
        guestOrExternalUserTypes = "b2bCollaborationGuest,b2bCollaborationMember"
        externalTenants           = @{ membershipKind = "all" }
      }
    }
    applications    = @{ includeApplications = @("All") }
    clientAppTypes  = @("browser")
  }
  grantControls = @{
    operator         = "AND"
    builtInControls  = @("mfa")
    termsOfUse       = @("vendor-contractor-tou")
  }
  sessionControls = @{
    persistentBrowser = @{ isEnabled = $true; mode = "never" }
    signInFrequency   = @{ isEnabled = $true; type = "hours"; value = 4 }
  }
}

Set-CaPolicy -DisplayName "CA030 - Risk-based - Block on medium/high sign-in risk" -Body @{
  displayName = "CA030 - Risk-based - Block on medium/high sign-in risk"
  state       = "enabledForReportingButNotEnforced"
  conditions  = @{
    users            = @{ includeUsers = @("All"); excludeGroups = @($breakGlassGroupId) }
    applications     = @{ includeApplications = @("All") }
    clientAppTypes   = @("all")
    signInRiskLevels = @("high", "medium")
  }
  grantControls = @{ operator = "OR"; builtInControls = @("block") }
}

# Deployed report-only first, same as the Bicep source — promote to
# "enabled" only after a bake period once you've confirmed the CI/CD
# runner egress ranges are correctly captured as trusted locations.
Set-CaPolicy -DisplayName "CA040 - Workload identity - restrict to CI/CD egress ranges" -Body @{
  displayName = "CA040 - Workload identity - restrict to CI/CD egress ranges"
  state       = "enabledForReportingButNotEnforced"
  conditions  = @{
    clientApplications = @{ includeServicePrincipals = @("ServicePrincipalsInMyTenant") }
    applications        = @{ includeApplications = @("All") }
    locations = @{
      includeLocations = @("All")
      excludeLocations = @("AllTrusted")
    }
  }
  grantControls = @{ operator = "OR"; builtInControls = @("block") }
}

Write-Host "Conditional Access fallback deployment complete for environment: $Environment"
Disconnect-MgGraph | Out-Null
