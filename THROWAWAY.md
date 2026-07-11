# Throwaway Sandbox Setup (POC / Portfolio Evidence)

> **Status update**: since ict-cloud.solutions is a sole-admin tenant with
> no other real users, the POC is deploying directly against it (dedicated
> subscription + break-glass account for isolation) rather than standing
> up a separate throwaway tenant. This file is kept for reference — the
> risk-mitigation practices below (break-glass, report-only bake period,
> budget alerts) still apply and were followed in the actual POC. Skip
> Steps 1–2 (separate tenant/subscription signup) unless you later want a
> fully isolated environment for Phase 2 testing.

This repo is designed to deploy against a **dedicated sandbox tenant**, not
your production `ict-cloud.solutions` tenant. Conditional Access and PIM
policies are tenant-wide — testing them anywhere near a real business
tenant risks locking out real users. Follow this to stand up an isolated,
free environment.

## Why a separate tenant (not just a separate subscription)

Azure subscriptions can be moved between tenants, but Conditional Access
and PIM are Entra ID (tenant) features — they aren't subscription-scoped.
A second subscription under your existing tenant still shares the same
Conditional Access policy set, the same PIM roles, and the same users as
`ict-cloud.solutions`. This POC needs its own tenant to be safe to
experiment in.

## Step 1: Microsoft 365 Developer Program tenant

Solves the licensing problem — CA needs Entra ID P1, PIM needs Entra ID
P2, and a bare Azure trial only gives you Entra ID Free.

1. Go to https://developer.microsoft.com/microsoft-365/dev-program
2. Sign up with a personal Microsoft account (not your work account)
3. Choose the **"Instant sandbox"** option — provisions an E5 tenant with
   25 licensed users and sample data
4. Note the tenant's default domain: `<something>.onmicrosoft.com`
5. Keep the sandbox "active" at least every ~90 days (any sign-in or
   Graph/Bicep deployment counts) or it recycles

This tenant already includes Entra ID P2, so `conditionalAccess.bicep`
and `pim.bicep` have something to attach to immediately — no separate
license purchase needed.

## Step 2: Azure subscription under the new tenant

1. In the new tenant, go to https://azure.microsoft.com/free
2. Sign up for the free account (12 months of free-tier services + $200
   credit for 30 days) — this becomes your `connectivitySubscriptionId`
   and `identitySubscriptionId` for the sandbox environment
3. **Immediately set a budget alert**: Cost Management + Billing →
   Budgets → new budget at $20/50/100 thresholds. Sentinel (per-GB
   ingestion) and Defender for Cloud (per-resource-hour) keep billing
   after the $200 credit runs out.

## Step 3: Create a sandbox management group structure

Minimal version of the structure in the main README — you don't need the
full ALZ hierarchy for a POC, just enough to prove the pattern:

```
Tenant Root Management Group
└── mg-ztlz-sandbox
    ├── (connectivity subscription from Step 2)
    └── (identity subscription — can be the same sub for a POC)
```

## Step 4: Break-glass account (do this before touching CA policies)

Create 2 cloud-only accounts, exclude them from every CA policy (this is
already parameterised via `breakGlassGroupId` in `main.bicep`). Test that
you can sign in with them **before** enabling any policy in enforced mode.

## Step 5: Deploy CA policies in report-only mode first

Every policy in `conditionalAccess.bicep` should be flipped to
`enabledForReportingButNotEnforced` for the first deployment in the
sandbox. Check Entra ID → Conditional Access → Insights and reporting
for a few days of simulated impact before promoting any policy to
`enabled`. This costs you nothing extra since it's your own sandbox
with only test users in it, but it's the habit you want muscle memory
for before doing this anywhere near a real client tenant.

## What this sandbox is good for (and not)

**Good for**: proving the Bicep/pipeline pattern works end-to-end,
recording a demo for portfolio/contract evidence, testing Sentinel
analytics rules fire correctly, screenshotting Secure Score improvements.

**Not good for**: load/scale testing (25 user cap), long-term hosting
(tenant recycles if inactive), anything with real client data.

## Teardown

When you're done demoing, delete the sandbox subscription's resource
groups (`az group delete`) or let the M365 Developer Program tenant
recycle naturally after 90 days of inactivity. No cleanup obligation
beyond that for a POC-only environment.
