#!/usr/bin/env bats

setup() {
  load "$BATS_PLUGIN_PATH/load.bash"
}

@test "Exports credentials" {
    export BUILDKITE_PLUGIN_GCP_WORKLOAD_IDENTITY_FEDERATION_AUDIENCE="//iam.googleapis.com/projects/123456789/locations/global/workloadIdentityPools/buildkite-example-pipeline/providers/buildkite"
    export BUILDKITE_PLUGIN_GCP_WORKLOAD_IDENTITY_FEDERATION_SERVICE_ACCOUNT="buildkite-example-pipeline@oidc-project.iam.gserviceaccount.com"

    stub buildkite-agent "oidc request-token --audience //iam.googleapis.com/projects/123456789/locations/global/workloadIdentityPools/buildkite-example-pipeline/providers/buildkite : echo dummy-jwt"

    run "$PWD/hooks/pre-command"

    assert_success

    assert_output --partial "Requesting OIDC token from Buildkite"
    assert_output --partial "Configuring Google Cloud credentials"

    diff /plugin/credentials.json /plugin/fixtures/credentials.json
    diff /plugin/token.json /plugin/fixtures/token.json

    unstub buildkite-agent
}
