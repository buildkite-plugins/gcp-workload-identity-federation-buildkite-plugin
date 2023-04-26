#!/usr/bin/env bats

# Uncomment to enable stub debug output:
# export DOCKER_STUB_DEBUG=/dev/tty

setup() {
  load "$BATS_PLUGIN_PATH/load.bash"
}

@test "fails when mktemp fails" {
    export BUILDKITE_PLUGIN_GCP_WORKLOAD_IDENTITY_FEDERATION_AUDIENCE="//iam.googleapis.com/projects/123456789/locations/global/workloadIdentityPools/buildkite-example-pipeline/providers/buildkite"
    export BUILDKITE_PLUGIN_GCP_WORKLOAD_IDENTITY_FEDERATION_SERVICE_ACCOUNT="buildkite-example-pipeline@oidc-project.iam.gserviceaccount.com"

    stub mktemp "exit 1"
    stub mktemp "exit 1"

    run "$PWD/hooks/pre-command"

    assert_failure
}

@test "fails when audience is missing" {
    export BUILDKITE_PLUGIN_GCP_WORKLOAD_IDENTITY_FEDERATION_SERVICE_ACCOUNT="buildkite-example-pipeline@oidc-project.iam.gserviceaccount.com"

    run "$PWD/hooks/pre-command"

    assert_failure
}

@test "fails when service account is missing" {
    export BUILDKITE_PLUGIN_GCP_WORKLOAD_IDENTITY_FEDERATION_AUDIENCE="//iam.googleapis.com/projects/123456789/locations/global/workloadIdentityPools/buildkite-example-pipeline/providers/buildkite"

    run "$PWD/hooks/pre-command"

    assert_failure
}

@test "exports credentials" {
    export BUILDKITE_PLUGIN_GCP_WORKLOAD_IDENTITY_FEDERATION_AUDIENCE="//iam.googleapis.com/projects/123456789/locations/global/workloadIdentityPools/buildkite-example-pipeline/providers/buildkite"
    export BUILDKITE_PLUGIN_GCP_WORKLOAD_IDENTITY_FEDERATION_SERVICE_ACCOUNT="buildkite-example-pipeline@oidc-project.iam.gserviceaccount.com"

    TMPDIR="/tmp"

    stub mktemp "echo $TMPDIR"
    stub buildkite-agent "oidc request-token --audience //iam.googleapis.com/projects/123456789/locations/global/workloadIdentityPools/buildkite-example-pipeline/providers/buildkite : echo dummy-jwt"

    run "$PWD/hooks/pre-command"

    assert_success

    assert_output --partial "Requesting OIDC token from Buildkite"
    assert_output --partial "Configuring Google Cloud credentials"

    diff $TMPDIR/token.json <(echo dummy-jwt)
    diff $TMPDIR/credentials.json <(cat << JSON
{
  "type": "external_account",
  "audience": "//iam.googleapis.com/projects/123456789/locations/global/workloadIdentityPools/buildkite-example-pipeline/providers/buildkite",
  "subject_token_type": "urn:ietf:params:oauth:token-type:jwt",
  "token_url": "https://sts.googleapis.com/v1/token",
  "service_account_impersonation_url": "https://iamcredentials.googleapis.com/v1/projects/-/serviceAccounts/buildkite-example-pipeline@oidc-project.iam.gserviceaccount.com:generateAccessToken",
  "credential_source": {
    "file": "$TMPDIR/token.json"
  }
}
JSON)

    unstub mktemp
    unstub buildkite-agent
}
