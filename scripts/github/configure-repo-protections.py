"""
Configure branch protection and environment protection rules via the
GitHub REST API — "repo config as code," consistent with the rest of
this project's philosophy that security controls should be scripted
and repeatable, not manually clicked once and forgotten.

Requires a token with Administration: Read and write on this repo
(fine-grained, scoped to ztr-entra-lz only). This is broader than the
Contents: Read and write token used for day-to-day git push/pull —
use it only for this one-off setup, then revoke or let it expire.

Usage:
    $env:GH_TOKEN = "your-admin-scoped-token"
    python configure-repo-protections.py

What this does:
    1. Requires PRs into main (still triggers lint/scan/What-If checks),
       with 0 required approvals — see note below — and blocks admin bypass
    2. Creates (or updates) a "sandbox" GitHub Environment
    3. Adds the repo owner as a required reviewer on that environment
    4. Restricts deployments against that environment to the main branch

NOTE on required_approving_review_count = 0:
    GitHub does not allow a PR author to approve their own PR toward a
    required-review count, even with write access — by design, so
    self-approval can't rubber-stamp a review requirement. As a
    solo operator this made every PR permanently unmergeable, so the
    approval count is set to 0 for now: PRs are still required (forcing
    the CI/What-If gate to run before anything reaches main), but no
    second-person sign-off is enforced. Once collaborators are added to
    this repo, raise this back to 1+ — that's the actual intended state
    for a multi-person team and is noted as a Phase 2 follow-up in
    docs/compliance-mapping.md.
"""

import os
import sys

import requests

OWNER = "sufideen"
REPO = "ztr-entra-lz"
BRANCH = "main"
ENVIRONMENT_NAME = "sandbox"

token = os.environ.get("GH_TOKEN")
if not token:
    print("Set $env:GH_TOKEN before running this script.")
    sys.exit(1)

headers = {
    "Authorization": f"Bearer {token}",
    "Accept": "application/vnd.github+json",
    "X-GitHub-Api-Version": "2022-11-28",
}

BASE = f"https://api.github.com/repos/{OWNER}/{REPO}"


def check(response, label):
    if response.status_code not in (200, 201, 204):
        print(f"FAILED: {label} -> {response.status_code}")
        print(response.json())
        sys.exit(1)
    print(f"OK: {label} ({response.status_code})")


# --- 1. Branch protection on main ---
branch_protection_body = {
    "required_status_checks": None,  # add job names here after the workflow has run once,
    # e.g. {"strict": True, "checks": [{"context": "lint-and-scan"}, {"context": "what-if"}]}
    "enforce_admins": True,  # blocks bypass, including by you as owner
    "required_pull_request_reviews": {
        "required_approving_review_count": 0,  # see NOTE in module docstring
        "dismiss_stale_reviews": True,
    },
    "restrictions": None,  # no push restriction beyond PR requirement — sole collaborator for now
}

resp = requests.put(
    f"{BASE}/branches/{BRANCH}/protection",
    headers=headers,
    json=branch_protection_body,
)
check(resp, f"Branch protection on '{BRANCH}'")

# --- 2. Create/update the sandbox environment ---
resp = requests.put(
    f"{BASE}/environments/{ENVIRONMENT_NAME}",
    headers=headers,
    json={
        "deployment_branch_policy": {
            "protected_branches": False,
            "custom_branch_policies": True,
        }
    },
)
check(resp, f"Environment '{ENVIRONMENT_NAME}' created/updated")

# Restrict deployments to main only (requires custom_branch_policies=True above)
resp = requests.post(
    f"{BASE}/environments/{ENVIRONMENT_NAME}/deployment-branch-policies",
    headers=headers,
    json={"name": BRANCH},
)
# 422 here usually means the policy already exists — treat as non-fatal
if resp.status_code not in (200, 201, 422):
    check(resp, "Restrict deployment branch to main")
else:
    print(f"OK: deployment branch policy for '{BRANCH}' (or already existed)")

# --- 3. Add repo owner as required reviewer ---
# Look up the numeric user ID required by the API (username alone isn't enough)
user_resp = requests.get(f"https://api.github.com/users/{OWNER}", headers=headers)
check(user_resp, f"Look up user ID for {OWNER}")
user_id = user_resp.json()["id"]

resp = requests.put(
    f"{BASE}/environments/{ENVIRONMENT_NAME}",
    headers=headers,
    json={
        "reviewers": [{"type": "User", "id": user_id}],
        "deployment_branch_policy": {
            "protected_branches": False,
            "custom_branch_policies": True,
        },
    },
)
check(resp, f"Required reviewer added to '{ENVIRONMENT_NAME}'")

print("\nDone. Verify at:")
print(f"  https://github.com/{OWNER}/{REPO}/settings/branches")
print(f"  https://github.com/{OWNER}/{REPO}/settings/environments")
print("\nReminder: revoke the admin-scoped token now that setup is complete.")
