#Requires -Modules Microsoft.Graph.Identity.Governance
<#
.SYNOPSIS
  Idempotent fallback deployment of PIM role management policies (Entra
  eligible-role settings) via Microsoft Graph PowerShell, used when the
  Bicep Microsoft Graph extension is unavailable in the pipeline runner's
  Bicep CLI version. Mirrors bicep/modules/pim.bicep — see
  docs/graph-resources.md for why both paths exist.

.DESCRIPTION
  Applies to each privileged Entra directory role: require approval +
  justification, MFA on activation, and an 8-hour maximum activation
  window. This intentionally does NOT create or remove role
  *assignments* (who is eligible for what) — that's a request-driven
  process, not something a landing-zone deployment should own. See
  scripts/graph/pim-assign-eligible.ps1 (create as needed per access
  request) for assignment management.

.PARAMETER Environment
  sandbox | dev | prod — used only for logging, PIM policies are tenant-wide.
#>
param(
  [Parameter(Mandatory)]
  [ValidateSet('sandbox', 'dev', 'prod')]
  [string]$Environment,

  [string]$TenantId
)

# -TenantId is for manual local runs, to avoid Windows' Web Account Manager
# silently defaulting to a different cached work/personal account.
$connectParams = @{ Scopes = "RoleManagementPolicy.ReadWrite.Directory"; NoWelcome = $true }
if ($TenantId) { $connectParams.TenantId = $TenantId }
Connect-MgGraph @connectParams

# Same role set as bicep/modules/pim.bicep — keep these two lists in sync.
$privilegedEntraRoles = @(
  @{ Id = "62e90394-69f5-4237-9190-012177145e10"; Name = "Global Administrator" }
  @{ Id = "fe930be7-5e62-47db-91af-98c3a49a38b1"; Name = "User Administrator" }
  @{ Id = "9b895d92-2cd3-44c7-9d02-a6ac2d5ea5c3"; Name = "Application Administrator" }
  @{ Id = "729827e3-9c14-49f7-bb1b-9608f156bbb8"; Name = "Helpdesk Administrator" }
)

foreach ($role in $privilegedEntraRoles) {
  Write-Host "Configuring PIM policy for role: $($role.Name)"

  # Locate the role management policy assignment for this directory role
  $policyAssignment = Get-MgPolicyRoleManagementPolicyAssignment `
    -Filter "scopeId eq '/' and scopeType eq 'DirectoryRole' and roleDefinitionId eq '$($role.Id)'"

  if (-not $policyAssignment) {
    Write-Warning "No policy assignment found for $($role.Name) - skipping. This role may need PIM onboarding first via the Entra portal (PIM > Roles > Discover and add roles)."
    continue
  }

  $policyId = $policyAssignment.PolicyId

  # Rule 1: max activation duration 8 hours
  Update-MgPolicyRoleManagementPolicyRule -UnifiedRoleManagementPolicyId $policyId `
    -UnifiedRoleManagementPolicyRuleId "Expiration_EndUser_Assignment" `
    -BodyParameter @{
      "@odata.type"       = "#microsoft.graph.unifiedRoleManagementPolicyExpirationRule"
      id                  = "Expiration_EndUser_Assignment"
      isExpirationRequired = $true
      maximumDuration     = "PT8H"
    }

  # Rule 2: require approval + justification on activation
  Update-MgPolicyRoleManagementPolicyRule -UnifiedRoleManagementPolicyId $policyId `
    -UnifiedRoleManagementPolicyRuleId "Approval_EndUser_Assignment" `
    -BodyParameter @{
      "@odata.type" = "#microsoft.graph.unifiedRoleManagementPolicyApprovalRule"
      id            = "Approval_EndUser_Assignment"
      setting       = @{
        isApprovalRequired = $true
        approvalStages     = @(
          @{
            approvalStageTimeOutInMinutes   = 1440
            isApproverJustificationRequired = $true
            primaryApprovers                = @()  # populate per role owner group before enforcing
          }
        )
      }
    }

  # Rule 3: require MFA + justification on activation
  Update-MgPolicyRoleManagementPolicyRule -UnifiedRoleManagementPolicyId $policyId `
    -UnifiedRoleManagementPolicyRuleId "Enablement_EndUser_Assignment" `
    -BodyParameter @{
      "@odata.type" = "#microsoft.graph.unifiedRoleManagementPolicyEnablementRule"
      id            = "Enablement_EndUser_Assignment"
      enabledRules  = @("MultiFactorAuthentication", "Justification")
    }

  # Rule 4: notify admins on activation
  Update-MgPolicyRoleManagementPolicyRule -UnifiedRoleManagementPolicyId $policyId `
    -UnifiedRoleManagementPolicyRuleId "Notification_Admin_EndUser_Assignment" `
    -BodyParameter @{
      "@odata.type"              = "#microsoft.graph.unifiedRoleManagementPolicyNotificationRule"
      id                         = "Notification_Admin_EndUser_Assignment"
      notificationType           = "Email"
      recipientType              = "Admin"
      isDefaultRecipientsEnabled = $true
    }

  Write-Host "  -> $($role.Name): max 8h activation, approval required, MFA + justification enforced"
}

Write-Host "PIM policy fallback deployment complete for environment: $Environment"
Write-Host "NOTE: primaryApprovers on the approval rule is empty in this script by design - populate it with your role-owner group ID before promoting any role out of report-only testing."
Disconnect-MgGraph | Out-Null
