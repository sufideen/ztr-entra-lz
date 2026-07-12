#Requires -Modules Pester

<#
.SYNOPSIS
  Regression guard: every Conditional Access policy in conditionalAccess.bicep
  must deploy report-only (enabledForReportingButNotEnforced), never
  'enabled', until an explicit, deliberate promotion after a bake period.

.DESCRIPTION
  Static test over the Bicep *source text* - no Azure/Graph credentials
  needed, safe to run in CI on every PR. Catches the exact regression found
  during the 2026-07-12 project review, where 5 of 6 CA policies were
  accidentally hardcoded to 'enabled' with no bake period.

  This is deliberately a strict allow-list test, not a "some policies can
  be enabled" test: promoting a policy out of report-only is a real,
  deliberate security decision (see THROWAWAY.md Step 5) that should be a
  one-line diff a reviewer can see and question, not something this test
  should quietly accommodate.

.NOTES
  Run locally: Invoke-Pester -Path ./tests/ConditionalAccess.RegressionGuard.Tests.ps1
#>

BeforeAll {
    $script:BicepPath = Join-Path $PSScriptRoot '..' 'bicep' 'modules' 'conditionalAccess.bicep'
    $script:BicepContent = Get-Content -Path $script:BicepPath -Raw

    # Split into individual resource blocks so a failure names the specific
    # policy, not just "something in the file".
    $script:ResourceBlocks = [regex]::Matches(
        $script:BicepContent,
        "resource\s+(?<name>\w+)\s+'Microsoft\.Graph/conditionalAccessPolicies@[^']+'\s*=\s*\{(?<body>.*?)\n\}",
        [System.Text.RegularExpressions.RegexOptions]::Singleline
    )
}

Describe 'Conditional Access policies deploy report-only' {

    It 'finds conditionalAccess.bicep' {
        Test-Path $script:BicepPath | Should -BeTrue
    }

    It 'finds at least one Conditional Access policy resource' {
        $script:ResourceBlocks.Count | Should -BeGreaterThan 0
    }

    It '<name> is enabledForReportingButNotEnforced, not enabled' -ForEach @(
        $script:ResourceBlocks | ForEach-Object {
            @{ Name = $_.Groups['name'].Value; Body = $_.Groups['body'].Value }
        }
    ) {
        $stateMatch = [regex]::Match($Body, "state:\s*'(?<state>[^']+)'")
        $stateMatch.Success | Should -BeTrue -Because "resource '$Name' must have an explicit state property"
        $stateMatch.Groups['state'].Value | Should -Be 'enabledForReportingButNotEnforced' -Because "CA policy '$Name' must deploy report-only per THROWAWAY.md Step 5 - promote to 'enabled' only as a deliberate, reviewed change"
    }
}
