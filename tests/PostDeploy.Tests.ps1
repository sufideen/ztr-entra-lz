#Requires -Modules Pester, Az.Accounts, Az.SecurityInsights, Az.Security, Az.Resources, Az.OperationalInsights

<#
.SYNOPSIS
  Post-deploy validation: assert the live sandbox subscription matches
  what main.bicep is supposed to have deployed.

.DESCRIPTION
  NOT YET WIRED INTO CI. Unlike ConditionalAccess.RegressionGuard.Tests.ps1
  (a static test over Bicep source), this runs against live Azure and needs
  real credentials + the Az PowerShell modules - test it locally first:

    Connect-AzAccount
    Select-AzSubscription -SubscriptionId <sandbox-subscription-id>
    Invoke-Pester -Path ./tests/PostDeploy.Tests.ps1 -Container (New-PesterContainer -Path ./tests/PostDeploy.Tests.ps1 -Data @{ Environment = 'sandbox' })

  Once confirmed working, wire into deploy.yml's `deploy` job as a step
  after "Deploy landing zone (Bicep)", using the same OIDC login already
  established there - see docs/phase2-roadmap.md, item 1.

.PARAMETER Environment
  sandbox | dev | prod - used to build resource/resource-group names,
  matching the naming convention in bicep/modules/logAnalytics.bicep and
  bicep/modules/defenderForCloud.bicep.
#>
param(
    [ValidateSet('sandbox', 'dev', 'prod')]
    [string]$Environment = 'sandbox'
)

BeforeDiscovery {
    $script:ExpectedDefenderPlans = @(
        'VirtualMachines', 'AppServices', 'SqlServers', 'KeyVaults',
        'StorageAccounts', 'Containers', 'Arm', 'CloudPosture'
    )
    $script:ExpectedCustomRoles = @(
        'Contractor Scoped Reader', 'Vendor Scoped App Deployer', 'Pipeline Scoped Contributor'
    )
}

BeforeAll {
    $script:ResourceGroupName = "rg-security-$Environment"
    $script:WorkspaceName = "law-central-sec-$Environment"
}

Describe 'Central Log Analytics workspace' {
    It 'exists in the expected resource group' {
        { Get-AzOperationalInsightsWorkspace -ResourceGroupName $script:ResourceGroupName -Name $script:WorkspaceName -ErrorAction Stop } |
            Should -Not -Throw
    }

    It 'retains logs for 365 days (ISO27001 A.12.4)' {
        $workspace = Get-AzOperationalInsightsWorkspace -ResourceGroupName $script:ResourceGroupName -Name $script:WorkspaceName
        $workspace.RetentionInDays | Should -Be 365
    }
}

Describe 'Defender for Cloud pricing plans' {
    It '<_> is set to Standard tier' -ForEach $script:ExpectedDefenderPlans {
        $pricing = Get-AzSecurityPricing -Name $_
        $pricing.PricingTier | Should -Be 'Standard'
    }
}

Describe 'Sentinel analytics rules' {
    It 'at least one rule is onboarded and every onboarded rule is enabled' {
        $rules = Get-AzSentinelAlertRule -ResourceGroupName $script:ResourceGroupName -WorkspaceName $script:WorkspaceName
        $rules.Count | Should -BeGreaterThan 0 -Because 'analyticsRules.bicep should have deployed at least one rule'
        $disabledRules = $rules | Where-Object { -not $_.Enabled }
        $disabledRules | Should -BeNullOrEmpty -Because "these rules are disabled: $($disabledRules.DisplayName -join ', ')"
    }
}

Describe 'Custom RBAC role definitions' {
    It '<_> exists at subscription scope' -ForEach $script:ExpectedCustomRoles {
        $role = Get-AzRoleDefinition -Name $_
        $role | Should -Not -BeNullOrEmpty
    }
}

Describe 'CI identity holds only the documented standing role assignments' {
    It 'the CI service principal holds exactly Contributor + the custom Authorization Writer role' {
        # See README "One-time bootstrap: CI OIDC identity" for the expected
        # grant, both at subscription scope. Anything beyond these two is a
        # standing-privilege regression worth investigating - this is the
        # metric tracked as a known gap in docs/poc-evidence/README.md.
        $sp = Get-AzADServicePrincipal -DisplayName 'ztr-entra-lz-ci'
        $sp | Should -Not -BeNullOrEmpty

        $assignments = Get-AzRoleAssignment -ObjectId $sp.Id
        $roleNames = $assignments.RoleDefinitionName | Sort-Object -Unique
        $roleNames | Should -Contain 'Contributor'
        $roleNames | Should -Contain 'ztr-entra-lz CI Authorization Writer'
        $roleNames.Count | Should -Be 2 -Because "unexpected roles found: $($roleNames -join ', ')"
    }
}
