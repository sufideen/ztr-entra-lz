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

  The resource-block data used by the -ForEach below is built in
  BeforeDiscovery, not BeforeAll: Pester v5 evaluates -ForEach at Discovery
  time, which runs *before* BeforeAll - putting this in BeforeAll leaves
  the -ForEach data null. (First version of this file got this wrong and
  failed CI with "Cannot index into a null array" - see PR #19.)

  BeforeDiscovery's script-scope variables are visible to -ForEach (its
  data is bound during Discovery), but are NOT reliably visible to plain,
  non-ForEach It blocks - those execute later during the Run phase, which
  Pester gives an isolated scope that does not inherit BeforeDiscovery's
  assignments (this is deliberate, so Discovery re-runs don't leak state
  into Run). The first fix in PR #19 missed this and still failed CI on a
  real run: "finds conditionalAccess.bicep" / "finds at least one ...
  resource" saw $script:BicepPath / $script:ResourceBlocks as null/empty
  even though the -ForEach-driven per-policy tests passed (their data is
  bound at Discovery time, so they're unaffected). Fixed by duplicating
  the same few lines into BeforeAll, which plain It blocks in the Run
  phase can see. Deliberately duplicated rather than factored into a
  shared variable/function: a value assigned to a script-scope variable
  during Discovery has the exact same visibility problem as $script:BicepPath
  did, so a "shared helper" defined at Discovery time would not be callable
  from BeforeAll either.
#>

BeforeDiscovery {
    $script:BicepPath = Join-Path $PSScriptRoot '..' 'bicep' 'modules' 'conditionalAccess.bicep'
    $script:BicepContent = Get-Content -Path $script:BicepPath -Raw

    # Split into individual resource blocks so a failure names the specific
    # policy, not just "something in the file".
    $script:ResourceBlocks = [regex]::Matches(
        $script:BicepContent,
        "resource\s+(?<name>\w+)\s+'Microsoft\.Graph/conditionalAccessPolicies@[^']+'\s*=\s*\{(?<body>.*?)\n\}",
        [System.Text.RegularExpressions.RegexOptions]::Singleline
    )

    $script:ResourceBlockData = @($script:ResourceBlocks | ForEach-Object {
        @{ Name = $_.Groups['name'].Value; Body = $_.Groups['body'].Value }
    })
}

BeforeAll {
    # Recompute (don't just reference the BeforeDiscovery values) - see the
    # .NOTES above for why the Discovery-phase values aren't visible here.
    $script:BicepPath = Join-Path $PSScriptRoot '..' 'bicep' 'modules' 'conditionalAccess.bicep'
    $script:BicepContent = Get-Content -Path $script:BicepPath -Raw
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

    It '<name> is enabledForReportingButNotEnforced, not enabled' -ForEach $script:ResourceBlockData {
        $stateMatch = [regex]::Match($Body, "state:\s*'(?<state>[^']+)'")
        $stateMatch.Success | Should -BeTrue -Because "resource '$Name' must have an explicit state property"
        $stateMatch.Groups['state'].Value | Should -Be 'enabledForReportingButNotEnforced' -Because "CA policy '$Name' must deploy report-only per THROWAWAY.md Step 5 - promote to 'enabled' only as a deliberate, reviewed change"
    }
}
