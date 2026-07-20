#!/usr/bin/env bats

setup() {
  load "$BATS_PLUGIN_PATH/load.bash"
}

@test "environment hook does nothing when configured to use the pre-command hook" {
  export BUILDKITE_PLUGIN_GCP_WORKLOAD_IDENTITY_FEDERATION_HOOK="pre-command"
  export BUILDKITE_PLUGIN_GCP_WORKLOAD_IDENTITY_FEDERATION_AUDIENCE="//iam.googleapis.com/projects/123456789/locations/global/workloadIdentityPools/buildkite-example-pipeline/providers/buildkite"
    export BUILDKITE_PLUGIN_GCP_WORKLOAD_IDENTITY_FEDERATION_SERVICE_ACCOUNT="buildkite-example-pipeline@oidc-project.iam.gserviceaccount.com"

  run "$PWD/hooks/environment"

  assert_success
  assert_output --partial "Skipping environment hook"
}

@test "environment hook is skipped by default when hook is not configured" {
  export BUILDKITE_PLUGIN_GCP_WORKLOAD_IDENTITY_FEDERATION_AUDIENCE="//iam.googleapis.com/projects/123456789/locations/global/workloadIdentityPools/buildkite-example-pipeline/providers/buildkite"
  export BUILDKITE_PLUGIN_GCP_WORKLOAD_IDENTITY_FEDERATION_SERVICE_ACCOUNT="buildkite-example-pipeline@oidc-project.iam.gserviceaccount.com"

  run "$PWD/hooks/environment"

  assert_success
  assert_output --partial "Skipping environment hook"
}

@test "pre-command hook does nothing when configured to use the environment hook" {
  export BUILDKITE_PLUGIN_GCP_WORKLOAD_IDENTITY_FEDERATION_HOOK="environment"
  export BUILDKITE_PLUGIN_GCP_WORKLOAD_IDENTITY_FEDERATION_AUDIENCE="//iam.googleapis.com/projects/123456789/locations/global/workloadIdentityPools/buildkite-example-pipeline/providers/buildkite"
    export BUILDKITE_PLUGIN_GCP_WORKLOAD_IDENTITY_FEDERATION_SERVICE_ACCOUNT="buildkite-example-pipeline@oidc-project.iam.gserviceaccount.com"

  run "$PWD/hooks/pre-command"

  assert_success
  assert_output --partial "Skipping pre-command hook"
}

@test "pre-command hook runs by default when hook is not configured" {
  export BUILDKITE_PLUGIN_GCP_WORKLOAD_IDENTITY_FEDERATION_AUDIENCE="//iam.googleapis.com/projects/123456789/locations/global/workloadIdentityPools/buildkite-example-pipeline/providers/buildkite"
  export BUILDKITE_PLUGIN_GCP_WORKLOAD_IDENTITY_FEDERATION_SERVICE_ACCOUNT="buildkite-example-pipeline@oidc-project.iam.gserviceaccount.com"

  stub mktemp "-d : echo $BATS_TEST_TMPDIR"
  stub buildkite-agent "oidc request-token --audience //iam.googleapis.com/projects/123456789/locations/global/workloadIdentityPools/buildkite-example-pipeline/providers/buildkite --lifetime 0 : echo dummy-jwt"

  run "$PWD/hooks/pre-command"

  assert_success
  assert_output --partial "Running in the pre-command hook"

  unstub mktemp
  unstub buildkite-agent
}

@test "post-command hook unsets WIF variables by default when hook is not configured" {
  export BUILDKITE_PLUGIN_GCP_WORKLOAD_IDENTITY_FEDERATION_AUDIENCE="//iam.googleapis.com/projects/123456789/locations/global/workloadIdentityPools/buildkite-example-pipeline/providers/buildkite"
  export BUILDKITE_PLUGIN_GCP_WORKLOAD_IDENTITY_FEDERATION_SERVICE_ACCOUNT="buildkite-example-pipeline@oidc-project.iam.gserviceaccount.com"
  export GOOGLE_APPLICATION_CREDENTIALS="/tmp/some-creds-file"
  export CLOUDSDK_AUTH_CREDENTIAL_FILE_OVERRIDE="/tmp/some-creds-file"

  run "$PWD/hooks/post-command"

  assert_success
  assert_output --partial "Running in the post-command hook"
}
