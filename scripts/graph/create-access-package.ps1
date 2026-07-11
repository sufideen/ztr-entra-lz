#Requires -Modules Microsoft.Graph.Identity.Governance
<#
.SYNOPSIS
  Creates a time-boxed Entra Entitlement Management Access Package for
  contractor or vendor onboarding — the only supported path to create a
  B2B guest account in this tenant (enforced/detected by the Sentinel rule
  "Guest account created outside Access Package workflow").

.PARAMETER Persona
  contractor | vendor

.PARAMETER DisplayName
  Name shown to the requester/approver, e.g. "Acme Corp - Q3 Contractor Access"

.PARAMETER DurationDays
  Access expiry — default 90 for contractors, 30 for vendors (renewable via re-request)

.PARAMETER SponsorGroupId
  Object ID of the internal sponsor/approver group
#>
param(
  [Parameter(Mandatory)][ValidateSet('contractor', 'vendor')]
  [string]$Persona,

  [Parameter(Mandatory)][string]$DisplayName,

  [int]$DurationDays = $(if ($Persona -eq 'contractor') { 90 } else { 30 }),

  [Parameter(Mandatory)][string]$SponsorGroupId
)

Connect-MgGraph -Scopes "EntitlementManagement.ReadWrite.All" -NoWelcome

$catalogId = $env:ZTLZ_ACCESS_PACKAGE_CATALOG_ID

$body = @{
  displayName = $DisplayName
  description = "Auto-created via ZTLZ pipeline for persona: $Persona"
  catalogId   = $catalogId
}

$pkg = New-MgEntitlementManagementAccessPackage -BodyParameter $body

$policy = @{
  displayName = "$DisplayName - Access Policy"
  accessPackageId = $pkg.Id
  requestApprovalSettings = @{
    isApprovalRequired = $true
    isApprovalRequiredForExtension = $true
    approvalStages = @(
      @{
        approvalStageTimeOutInDays = 3
        isApproverJustificationRequired = $true
        primaryApprovers = @(
          @{ "@odata.type" = "#microsoft.graph.groupMembers"; groupId = $SponsorGroupId }
        )
      }
    )
  }
  accessReviewSettings = @{
    isEnabled = $true
    recurrenceType = "onetime"
  }
  expiration = @{
    type = "afterDuration"
    duration = "P${DurationDays}D"
  }
}

New-MgEntitlementManagementAccessPackageAssignmentPolicy -BodyParameter $policy

Write-Host "Access Package '$DisplayName' created — persona=$Persona, expiry=${DurationDays}d, approver group=$SponsorGroupId"
Disconnect-MgGraph | Out-Null
