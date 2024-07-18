#!/usr/bin/env bats

# Uncomment to enable stub debug output:
# export BUILDKITE_AGENT_STUB_DEBUG=/dev/tty
# export MKTEMP_STUB_DEBUG=/dev/tty

setup() {
  load "$BATS_PLUGIN_PATH/load.bash"
}

@test "fails when mktemp fails" {
    export BUILDKITE_PLUGIN_GCP_WORKLOAD_IDENTITY_FEDERATION_AUDIENCE="//iam.googleapis.com/projects/123456789/locations/global/workloadIdentityPools/buildkite-example-pipeline/providers/buildkite"
    export BUILDKITE_PLUGIN_GCP_WORKLOAD_IDENTITY_FEDERATION_SERVICE_ACCOUNT="buildkite-example-pipeline@oidc-project.iam.gserviceaccount.com"

    stub mktemp "-d : exit 1"
    stub mktemp "-d -t 'buildkiteXXXX' : exit 1"

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

@test "fails when render command has non-existent binary" {
    export BUILDKITE_PLUGIN_GCP_WORKLOAD_IDENTITY_FEDERATION_AUDIENCE="//iam.googleapis.com/projects/123456789/locations/global/workloadIdentityPools/buildkite-example-pipeline/providers/buildkite"
    export BUILDKITE_PLUGIN_GCP_WORKLOAD_IDENTITY_FEDERATION_SERVICE_ACCOUNT="buildkite-example-pipeline@oidc-project.iam.gserviceaccount.com"
    export BUILDKITE_PLUGIN_GCP_WORKLOAD_IDENTITY_FEDERATION_RENDER_COMMAND="this-file-purposely-does-not-exist"

    run "$PWD/hooks/pre-command"

    assert_failure
}

@test "succeeds when mktemp fails once" {
    export BUILDKITE_PLUGIN_GCP_WORKLOAD_IDENTITY_FEDERATION_AUDIENCE="//iam.googleapis.com/projects/123456789/locations/global/workloadIdentityPools/buildkite-example-pipeline/providers/buildkite"
    export BUILDKITE_PLUGIN_GCP_WORKLOAD_IDENTITY_FEDERATION_SERVICE_ACCOUNT="buildkite-example-pipeline@oidc-project.iam.gserviceaccount.com"

    stub mktemp "-d : exit 1"
    stub mktemp "-d -t 'buildkiteXXXX' : echo $BATS_TEST_TMPDIR"
    stub buildkite-agent "echo dummy-jwt"

    run "$PWD/hooks/pre-command"

    assert_success

    unstub mktemp
    unstub buildkite-agent
}

@test "exports credentials" {
    export BUILDKITE_PLUGIN_GCP_WORKLOAD_IDENTITY_FEDERATION_AUDIENCE="//iam.googleapis.com/projects/123456789/locations/global/workloadIdentityPools/buildkite-example-pipeline/providers/buildkite"
    export BUILDKITE_PLUGIN_GCP_WORKLOAD_IDENTITY_FEDERATION_SERVICE_ACCOUNT="buildkite-example-pipeline@oidc-project.iam.gserviceaccount.com"

    stub mktemp "-d : echo $BATS_TEST_TMPDIR"
    stub buildkite-agent "oidc request-token --audience //iam.googleapis.com/projects/123456789/locations/global/workloadIdentityPools/buildkite-example-pipeline/providers/buildkite --lifetime 0 : echo dummy-jwt"

    run "$PWD/hooks/pre-command"

    assert_success

    assert_output --partial "Requesting OIDC token from Buildkite"
    assert_output --partial "Configuring Google Cloud credentials"

    diff $BATS_TEST_TMPDIR/token.json <(echo dummy-jwt)
    diff $BATS_TEST_TMPDIR/credentials.json <(cat << JSON
{
  "type": "external_account",
  "audience": "//iam.googleapis.com/projects/123456789/locations/global/workloadIdentityPools/buildkite-example-pipeline/providers/buildkite",
  "subject_token_type": "urn:ietf:params:oauth:token-type:jwt",
  "token_url": "https://sts.googleapis.com/v1/token",
  "service_account_impersonation_url": "https://iamcredentials.googleapis.com/v1/projects/-/serviceAccounts/buildkite-example-pipeline@oidc-project.iam.gserviceaccount.com:generateAccessToken",
  "credential_source": {
    "file": "$BATS_TEST_TMPDIR/token.json"
  }
}
JSON)

    unstub mktemp
    unstub buildkite-agent
}

@test "exports credentials with render command using envsubst" {
    export GCP_PROJECT_ID=oidc-project
    export GCP_PROJECT_NUMBER=123456789
    export BUILDKITE_PLUGIN_GCP_WORKLOAD_IDENTITY_FEDERATION_AUDIENCE="//iam.googleapis.com/projects/\${GCP_PROJECT_NUMBER}/locations/global/workloadIdentityPools/buildkite-example-pipeline/providers/buildkite"
    export BUILDKITE_PLUGIN_GCP_WORKLOAD_IDENTITY_FEDERATION_SERVICE_ACCOUNT="buildkite-example-pipeline@\${GCP_PROJECT_ID}.iam.gserviceaccount.com"
    export BUILDKITE_PLUGIN_GCP_WORKLOAD_IDENTITY_FEDERATION_RENDER_COMMAND="envsubst"

    stub mktemp "-d : echo $BATS_TEST_TMPDIR"
    stub buildkite-agent "oidc request-token --audience //iam.googleapis.com/projects/123456789/locations/global/workloadIdentityPools/buildkite-example-pipeline/providers/buildkite --lifetime 0 : echo dummy-jwt"

    run "$PWD/hooks/pre-command"

    assert_success

    assert_output --partial "Requesting OIDC token from Buildkite"
    assert_output --partial "Configuring Google Cloud credentials"

    diff $BATS_TEST_TMPDIR/token.json <(echo dummy-jwt)
    diff $BATS_TEST_TMPDIR/credentials.json <(cat << JSON
{
  "type": "external_account",
  "audience": "//iam.googleapis.com/projects/123456789/locations/global/workloadIdentityPools/buildkite-example-pipeline/providers/buildkite",
  "subject_token_type": "urn:ietf:params:oauth:token-type:jwt",
  "token_url": "https://sts.googleapis.com/v1/token",
  "service_account_impersonation_url": "https://iamcredentials.googleapis.com/v1/projects/-/serviceAccounts/buildkite-example-pipeline@oidc-project.iam.gserviceaccount.com:generateAccessToken",
  "credential_source": {
    "file": "$BATS_TEST_TMPDIR/token.json"
  }
}
JSON)

    unstub mktemp
    unstub buildkite-agent
}
