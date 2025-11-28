#!/bin/bash

set -euo pipefail

DIR="$(cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd)"

# shellcheck source=lib/shared.bash
. "$DIR/shared.bash"

args=()

if [[ -z "${BUILDKITE_PLUGIN_GCP_WORKLOAD_IDENTITY_FEDERATION_AUDIENCE:-}" ]]; then
  echo "🚨 Missing 'audience' plugin configuration"
  exit 1
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
  else
    case "${BUILDKITE_PLUGIN_GCP_WORKLOAD_IDENTITY_FEDERATION_GCP_PROJECT_ID}" in
      *dev*) BUILDKITE_PLUGIN_GCP_WORKLOAD_IDENTITY_FEDERATION_ENVIRONMENT="dev" ;;
      *sit*) BUILDKITE_PLUGIN_GCP_WORKLOAD_IDENTITY_FEDERATION_ENVIRONMENT="sit" ;;
      *prod*) BUILDKITE_PLUGIN_GCP_WORKLOAD_IDENTITY_FEDERATION_ENVIRONMENT="prod" ;;
      *)
        echo "🚨 Could not infer environment from 'gcp-project-id' plugin configuration. Please ensure it contains one of 'dev', 'sit', or 'prod'."
        exit 1
        ;;
    esac
  fi

  if [[ -z "${BUILDKITE_PLUGIN_GCP_WORKLOAD_IDENTITY_FEDERATION_MODE:-}" ]]; then
    echo "🚨 Missing 'mode' plugin configuration (must be 'ro' or 'rw')"
    exit 1
  fi

  if [[ -z "${BUILDKITE_PIPELINE_SLUG:-}" ]]; then
    echo "🚨 BUILDKITE_PIPELINE_SLUG environment variable is not set"
    exit 1
  fi

  # Construct service account: <buildkite_slug>-<env>-<ro|rw>@<gcp_project_id>.iam.gserviceaccount.com
  SERVICE_ACCOUNT="${BUILDKITE_PIPELINE_SLUG}-${BUILDKITE_PLUGIN_GCP_WORKLOAD_IDENTITY_FEDERATION_ENVIRONMENT}-${BUILDKITE_PLUGIN_GCP_WORKLOAD_IDENTITY_FEDERATION_MODE}@${BUILDKITE_PLUGIN_GCP_WORKLOAD_IDENTITY_FEDERATION_GCP_PROJECT_ID}.iam.gserviceaccount.com"
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
