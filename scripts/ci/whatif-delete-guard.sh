#!/usr/bin/env bash
# Fails the pipeline if an `az deployment ... what-if` result contains a
# Delete against an identity-plane resource type (Conditional Access, PIM,
# Entra ID groups, or Azure RBAC role definitions/assignments). A Delete
# here either means a real intended removal - which deserves its own
# explicit, reviewed PR, not a silent side effect of an unrelated Bicep
# change - or an authoring mistake (e.g. a renamed resource symbolic name,
# which ARM treats as delete-then-create).
#
# Usage: whatif-delete-guard.sh <path-to-whatif-result.json>
# Expects the JSON produced by:
#   az deployment sub what-if ... --result-format FullResourcePayloads -o json
set -euo pipefail

WHATIF_FILE="${1:?Usage: $0 <path-to-whatif-result.json>}"

if [ ! -f "$WHATIF_FILE" ]; then
  echo "::error::What-If result file not found at $WHATIF_FILE"
  exit 1
fi

GUARDED_TYPE_PATTERN='^/subscriptions/[^/]+/providers/(Microsoft\.Graph/(conditionalAccessPolicies|roleManagementPolicies|groups)|Microsoft\.Authorization/(roleAssignments|roleDefinitions))/'

DELETIONS=$(jq -r --arg pattern "$GUARDED_TYPE_PATTERN" '
  (.changes // [])[]
  | select(.changeType == "Delete")
  | select(.resourceId | test($pattern; "i"))
  | .resourceId
' "$WHATIF_FILE")

if [ -n "$DELETIONS" ]; then
  echo "::error::What-If reports a Delete against identity-plane resource(s). Refusing to proceed."
  while IFS= read -r id; do
    echo "::error::  Delete detected: $id"
  done <<< "$DELETIONS"
  echo "If this delete is genuinely intended, it needs its own reviewed PR that updates this guard's expectations explicitly - not a silent pass-through here." >&2
  exit 1
fi

echo "No identity-plane deletes detected in What-If output. Guard passed."
