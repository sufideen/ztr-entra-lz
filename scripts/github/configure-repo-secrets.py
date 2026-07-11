"""
Set GitHub Actions repository secrets and variables via the GitHub API —
scripted equivalent of Settings > Secrets and variables > Actions.

GitHub encrypts secret values client-side before they're sent, using the
repo's public key (libsodium/NaCl sealed box) — this script handles that
encryption step, which is the part most manual walkthroughs skip and the
reason this can't just be a plain requests.post() like the earlier
branch-protection script.

Requires:
    pip install requests pynacl --break-system-packages

Requires a token with:
    - "Secrets: Read and write" (fine-grained, repo-scoped)
    - "Variables: Read and write" (fine-grained, repo-scoped)

Usage:
    $env:GH_TOKEN = "your-secrets-scoped-token"
    python configure-repo-secrets.py `
        --client-id <appId> `
        --tenant-id <tenantId> `
        --subscription-id <subscriptionId> `
        --mg-platform-id <managementGroupOrRgId>
"""

import argparse
import base64
import os
import sys

import requests
from nacl import encoding, public

OWNER = "sufideen"
REPO = "ztr-entra-lz"
BASE = f"https://api.github.com/repos/{OWNER}/{REPO}"


def encrypt_secret(public_key_b64: str, secret_value: str) -> str:
    """Encrypt a secret value using the repo's public key, per GitHub's
    documented libsodium sealed-box scheme."""
    public_key = public.PublicKey(public_key_b64.encode("utf-8"), encoding.Base64Encoder())
    sealed_box = public.SealedBox(public_key)
    encrypted = sealed_box.encrypt(secret_value.encode("utf-8"))
    return base64.b64encode(encrypted).decode("utf-8")


def set_secret(headers: dict, name: str, value: str) -> None:
    key_resp = requests.get(f"{BASE}/actions/secrets/public-key", headers=headers)
    key_resp.raise_for_status()
    key_data = key_resp.json()

    encrypted_value = encrypt_secret(key_data["key"], value)

    resp = requests.put(
        f"{BASE}/actions/secrets/{name}",
        headers=headers,
        json={
            "encrypted_value": encrypted_value,
            "key_id": key_data["key_id"],
        },
    )
    if resp.status_code not in (201, 204):
        print(f"FAILED: secret {name} -> {resp.status_code}")
        print(resp.json())
        sys.exit(1)
    print(f"OK: secret {name} set ({resp.status_code})")


def set_variable(headers: dict, name: str, value: str) -> None:
    # Try create first; if it already exists, fall back to update
    resp = requests.post(
        f"{BASE}/actions/variables",
        headers=headers,
        json={"name": name, "value": value},
    )
    if resp.status_code == 201:
        print(f"OK: variable {name} created")
        return

    resp = requests.patch(
        f"{BASE}/actions/variables/{name}",
        headers=headers,
        json={"name": name, "value": value},
    )
    if resp.status_code not in (200, 204):
        print(f"FAILED: variable {name} -> {resp.status_code}")
        print(resp.json())
        sys.exit(1)
    print(f"OK: variable {name} updated")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--client-id", required=True)
    parser.add_argument("--tenant-id", required=True)
    parser.add_argument("--subscription-id", required=True)
    parser.add_argument("--mg-platform-id", required=True)
    args = parser.parse_args()

    token = os.environ.get("GH_TOKEN")
    if not token:
        print("Set $env:GH_TOKEN before running this script.")
        sys.exit(1)

    headers = {
        "Authorization": f"Bearer {token}",
        "Accept": "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28",
    }

    set_secret(headers, "AZURE_CLIENT_ID", args.client_id)
    set_secret(headers, "AZURE_TENANT_ID", args.tenant_id)
    set_secret(headers, "AZURE_SUBSCRIPTION_ID", args.subscription_id)
    set_variable(headers, "MG_PLATFORM_ID", args.mg_platform_id)

    print("\nDone. Verify at:")
    print(f"  https://github.com/{OWNER}/{REPO}/settings/secrets/actions")
    print(f"  https://github.com/{OWNER}/{REPO}/settings/variables/actions")
    print("\nReminder: revoke this token once setup is complete.")


if __name__ == "__main__":
    main()
