#Requires -Modules Microsoft.Graph.Identity.SignIns, Microsoft.Graph.Users, Microsoft.Graph.Identity.Governance
<#
.SYNOPSIS
  Creates test persona identities (Contractor and Vendor B2B guests via the
  real Access Package flow; optionally an Employee-persona member account)
  for exercising this repo's RBAC/CA/PIM controls end-to-end against the
  real ict-cloud.solutions tenant.

.DESCRIPTION
  Every object created here is tagged `ztlz-test-<persona>-<RunId>` (in
  DisplayName and JobTitle - Entra ID users don't support arbitrary
  key/value tags the way Azure resources do) so
  scripts/graph/teardown-test-personas.ps1 can remove exactly, and only,
  what a given run created.

  Contractor/vendor personas go through the same Access Package request
  flow a real contractor/vendor would use (see create-access-package.ps1),
  not a shortcut straight to New-MgInvitation with no assignment - the
  Sentinel rule "Guest account created outside Access Package workflow"
  (bicep/modules/sentinel/analyticsRules.bicep, ruleGuestOutsideAccessPackage)
  specifically detects and flags guest creation that skips this flow, so
  a shortcut here would trip our own detection.

  NOT executed against the real tenant as part of authoring this script -
  per the Phase 2 execution plan's Workstream C sequencing note, run this
  manually, with explicit go-ahead, after review. Creating B2B guest
  invitations and a cloud-only member account are both tenant-visible
  actions.

.PARAMETER Personas
  Which personas to create test identities for. Default: contractor, vendor.
  'employee' additionally creates a cloud-only member account (not a guest -
  employees are Entra-native per the README's Personas table).

.PARAMETER ContractorSponsorGroupId
  Object ID of the contractor test sponsor/approver group - see
  bicep/modules/groups.bicep's contractorTestGroup output (once that
  module has been deployed via the Graph fallback path), or supply an
  existing group's Object ID.

.PARAMETER VendorSponsorGroupId
  Object ID of the vendor test sponsor/approver group - see
  bicep/modules/groups.bicep's vendorTestGroup output.

.PARAMETER TestEmailDomain
  Real, reachable email domain to send B2B invitations to (e.g. a personal
  inbox or a distribution list you control) - Entra requires a deliverable
  invite email even for test identities.

.PARAMETER RunId
  Uniquely tags every object created by this run. Default: yyyyMMddHHmm
  timestamp. Pass a fixed value to make a run's objects predictable.

.EXAMPLE
  .\create-test-personas.ps1 -ContractorSponsorGroupId <guid> -VendorSponsorGroupId <guid> -TestEmailDomain example.com
#>
param(
    [ValidateSet('contractor', 'vendor', 'employee')]
    [string[]]$Personas = @('contractor', 'vendor'),

    [string]$ContractorSponsorGroupId,
    [string]$VendorSponsorGroupId,

    [Parameter(Mandatory)]
    [string]$TestEmailDomain,

    [string]$RunId = (Get-Date -Format 'yyyyMMddHHmm')
)

$ErrorActionPreference = "Stop"

Connect-MgGraph -Scopes "User.ReadWrite.All", "EntitlementManagement.ReadWrite.All" -NoWelcome

function New-TestGuestPersona {
    param(
        [string]$Persona,        # contractor | vendor
        [string]$SponsorGroupId
    )

    $tag = "ztlz-test-$Persona-$RunId"
    $email = "$tag@$TestEmailDomain"

    Write-Host ""
    Write-Host "Inviting guest for persona '$Persona': $email"
    $invitation = New-MgInvitation -InvitedUserEmailAddress $email `
        -InvitedUserDisplayName $tag `
        -InviteRedirectUrl "https://myaccount.microsoft.com" `
        -SendInvitationMessage:$true

    $guestUserId = $invitation.InvitedUser.Id
    Write-Host "  Guest object created: $guestUserId"

    # Naming convention (JobTitle = $tag) IS the teardown tag - Entra ID
    # users don't support arbitrary resource tags.
    Update-MgUser -UserId $guestUserId -JobTitle $tag

    if (-not $SponsorGroupId) {
        Write-Warning "No sponsor group supplied for persona '$Persona' - skipping Access Package request. The guest is invited but has no assigned access; this leaves a standing guest without an Access Package, which the Sentinel rule ruleGuestOutsideAccessPackage will flag. Either pass -${Persona}SponsorGroupId or request access manually."
        return $guestUserId
    }

    Write-Host "  Creating Access Package for persona '$Persona' via create-access-package.ps1..."
    & (Join-Path $PSScriptRoot 'create-access-package.ps1') `
        -Persona $Persona `
        -DisplayName $tag `
        -SponsorGroupId $SponsorGroupId

    # create-access-package.ps1 disconnects Graph on exit - reconnect for
    # the rest of this script.
    Connect-MgGraph -Scopes "User.ReadWrite.All", "EntitlementManagement.ReadWrite.All" -NoWelcome

    $package = Get-MgEntitlementManagementAccessPackage -Filter "displayName eq '$tag'" | Select-Object -First 1
    if (-not $package) {
        Write-Warning "Could not find the Access Package just created for '$tag' - skipping assignment request. Request access manually."
        return $guestUserId
    }

    Write-Host "  Requesting assignment of '$tag' access package for the new guest..."
    $requestBody = @{
        requestType             = "AdminAdd"
        accessPackageAssignment = @{
            targetId           = $guestUserId
            assignmentPolicyId = $package.Id
        }
    }
    New-MgEntitlementManagementAccessPackageAssignmentRequest -BodyParameter $requestBody | Out-Null

    Write-Host "  Persona '$Persona' ($tag) provisioned: guest=$guestUserId"
    return $guestUserId
}

$createdObjects = [System.Collections.Generic.List[string]]::new()

if ('contractor' -in $Personas) {
    $id = New-TestGuestPersona -Persona 'contractor' -SponsorGroupId $ContractorSponsorGroupId
    $createdObjects.Add("user:$id")
}

if ('vendor' -in $Personas) {
    $id = New-TestGuestPersona -Persona 'vendor' -SponsorGroupId $VendorSponsorGroupId
    $createdObjects.Add("user:$id")
}

if ('employee' -in $Personas) {
    $tag = "ztlz-test-employee-$RunId"
    Write-Host ""
    Write-Host "Creating cloud-only member account for persona 'employee': $tag"

    $defaultDomain = (Get-MgOrganization).VerifiedDomains | Where-Object { $_.IsDefault } | Select-Object -First 1 -ExpandProperty Name
    $upn = "$tag@$defaultDomain"
    $password = -join ((48..57) + (65..90) + (97..122) + (33, 35, 37, 64) | Get-Random -Count 24 | ForEach-Object { [char]$_ })

    $employee = New-MgUser -DisplayName $tag -UserPrincipalName $upn -MailNickname $tag `
        -AccountEnabled `
        -PasswordProfile @{ Password = $password; ForceChangePasswordNextSignIn = $true } `
        -JobTitle $tag

    Write-Host "  Employee test account created: $($employee.Id) ($upn)"
    Write-Host "  Initial password (record and discard now - forced change on first sign-in): $password"
    $createdObjects.Add("user:$($employee.Id)")
}

Write-Host ""
Write-Host "Done. Objects created this run (RunId=$RunId):"
$createdObjects | ForEach-Object { Write-Host "  $_" }
Write-Host ""
Write-Host "Tear down with:"
Write-Host "  .\teardown-test-personas.ps1 -RunId $RunId"

Disconnect-MgGraph | Out-Null
