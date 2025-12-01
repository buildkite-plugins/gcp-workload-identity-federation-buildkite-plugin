#!/bin/bash

set -euo pipefail

DIR="$(cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd)"

# shellcheck source=lib/shared.bash
. "$DIR/shared.bash"

args=()

if [[ -z "${BUILDKITE_PLUGIN_GCP_WORKLOAD_IDENTITY_FEDERATION_AUDIENCE:-}" ]]; then
  echo "📡 Retrieving audience from GCP_WORKLOAD_IDENTITY_BUILDKITE_AUDIENCE secret"
  if BUILDKITE_PLUGIN_GCP_WORKLOAD_IDENTITY_FEDERATION_AUDIENCE=$(buildkite-agent secret get GCP_WORKLOAD_IDENTITY_BUILDKITE_AUDIENCE 2>/dev/null); then
    echo "✅ Successfully retrieved audience from secret"
  else
    echo "🚨 Missing 'audience' plugin configuration and failed to retrieve GCP_WORKLOAD_IDENTITY_BUILDKITE_AUDIENCE secret"
    exit 1
  fi
fi

# Determine service account - construct from parameters
if [[ -n "${BUILDKITE_PLUGIN_GCP_WORKLOAD_IDENTITY_FEDERATION_SERVICE_ACCOUNT:-}" ]]; then
  # Use explicitly provided service account (backwards compatibility)
  SERVICE_ACCOUNT="${BUILDKITE_PLUGIN_GCP_WORKLOAD_IDENTITY_FEDERATION_SERVICE_ACCOUNT}"
else
  # Construct service account from parameters
  if [[ -z "${BUILDKITE_PLUGIN_GCP_WORKLOAD_IDENTITY_FEDERATION_GCP_PROJECT_ID:-}" ]]; then
    echo "🚨 Missing 'gcp-project-id' plugin configuration"
    exit 1
  fi

  if [[ -z "${BUILDKITE_PIPELINE_SLUG:-}" ]]; then
    echo "🚨 BUILDKITE_PIPELINE_SLUG environment variable is not set"
    exit 1
  fi

  # Default mode to 'rw' if not provided
  MODE="${BUILDKITE_PLUGIN_GCP_WORKLOAD_IDENTITY_FEDERATION_MODE:-rw}"

  # Construct service account: <hashed_buildkite_slug>-<ro|rw>@<gcp_project_id>.iam.gserviceaccount.com
  # create a shortened, valid identifier from the Buildkite pipeline slug for use in Google Cloud service account names
  HASHED_BUILDKITE_PIPELINE_SLUG=$(echo -n "$BUILDKITE_PIPELINE_SLUG" | sha256sum | cut -c1-18)
  MODIFIED_HASHED_BUILDKITE_PIPELINE_SLUG="a${HASHED_BUILDKITE_PIPELINE_SLUG}a"

  SERVICE_ACCOUNT="${MODIFIED_HASHED_BUILDKITE_PIPELINE_SLUG}-${MODE}@${BUILDKITE_PLUGIN_GCP_WORKLOAD_IDENTITY_FEDERATION_GCP_PROJECT_ID}.iam.gserviceaccount.com"
  echo "📧 Constructed service account: ${SERVICE_ACCOUNT}"
fi

if [[ -n "${BUILDKITE_PLUGIN_GCP_WORKLOAD_IDENTITY_FEDERATION_RENDER_COMMAND:-}" ]]; then
  # Test that the given command exists, otherwise fail
  command -v "${BUILDKITE_PLUGIN_GCP_WORKLOAD_IDENTITY_FEDERATION_RENDER_COMMAND}" || {
    echo "🚨 Render command file '${BUILDKITE_PLUGIN_GCP_WORKLOAD_IDENTITY_FEDERATION_RENDER_COMMAND}' not found"
    exit 1
  }
  BUILDKITE_PLUGIN_GCP_WORKLOAD_IDENTITY_FEDERATION_AUDIENCE="$(echo "${BUILDKITE_PLUGIN_GCP_WORKLOAD_IDENTITY_FEDERATION_AUDIENCE}" | ${BUILDKITE_PLUGIN_GCP_WORKLOAD_IDENTITY_FEDERATION_RENDER_COMMAND})"
  SERVICE_ACCOUNT="$(echo "${SERVICE_ACCOUNT}" | ${BUILDKITE_PLUGIN_GCP_WORKLOAD_IDENTITY_FEDERATION_RENDER_COMMAND})"
fi

# add required arguments
args+=("--audience" "${BUILDKITE_PLUGIN_GCP_WORKLOAD_IDENTITY_FEDERATION_AUDIENCE}")
args+=("--lifetime" "${BUILDKITE_PLUGIN_GCP_WORKLOAD_IDENTITY_FEDERATION_LIFETIME:-0}")

# Parse the list of optional claims to pass to the token request command
while read -r line ; do
  [[ -n "$line" ]] && args+=("--claim" "$line")
done <<< "$(plugin_read_list CLAIMS)"

# Create a temporary directory with both BSD and GNU mktemp
TMPDIR=$(mktemp -d 2>/dev/null || mktemp -d -t 'buildkiteXXXX')

echo "~~~ :buildkite: Requesting OIDC token from Buildkite"

buildkite-agent oidc request-token "${args[@]}" > "$TMPDIR"/token.json

echo "~~~ :gcloud: Configuring Google Cloud credentials"
cat << JSON > "$TMPDIR"/credentials.json
{
  "type": "external_account",
  "audience": "$BUILDKITE_PLUGIN_GCP_WORKLOAD_IDENTITY_FEDERATION_AUDIENCE",
  "subject_token_type": "urn:ietf:params:oauth:token-type:jwt",
  "token_url": "https://sts.googleapis.com/v1/token",
  "service_account_impersonation_url": "https://iamcredentials.googleapis.com/v1/projects/-/serviceAccounts/$SERVICE_ACCOUNT:generateAccessToken",
  "credential_source": {
    "file": "$TMPDIR/token.json"
  }
}
JSON

export BUILDKITE_OIDC_TMPDIR=$TMPDIR
export GOOGLE_APPLICATION_CREDENTIALS=$TMPDIR/credentials.json
export CLOUDSDK_AUTH_CREDENTIAL_FILE_OVERRIDE=$GOOGLE_APPLICATION_CREDENTIALS
