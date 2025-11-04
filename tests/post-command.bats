#!/usr/bin/env bats

setup() {
  load "$BATS_PLUGIN_PATH/load.bash"
}

@test "post-command hook does nothing when configured to use the environment hook" {
  export BUILDKITE_PLUGIN_GCP_WORKLOAD_IDENTITY_FEDERATION_HOOK="environment"
  export BUILDKITE_PLUGIN_GCP_WORKLOAD_IDENTITY_FEDERATION_AUDIENCE="//iam.googleapis.com/projects/123456789/locations/global/workloadIdentityPools/buildkite-example-pipeline/providers/buildkite"
    export BUILDKITE_PLUGIN_GCP_WORKLOAD_IDENTITY_FEDERATION_SERVICE_ACCOUNT="buildkite-example-pipeline@oidc-project.iam.gserviceaccount.com"

  run "$PWD/hooks/post-command"

  assert_success
  assert_output --partial "Skipping post-command hook"
}

@test "post-command hook runs when configured to use the pre-command hook" {
  export BUILDKITE_PLUGIN_GCP_WORKLOAD_IDENTITY_FEDERATION_HOOK="pre-command"
  export BUILDKITE_PLUGIN_GCP_WORKLOAD_IDENTITY_FEDERATION_AUDIENCE="//iam.googleapis.com/projects/123456789/locations/global/workloadIdentityPools/buildkite-example-pipeline/providers/buildkite"
    export BUILDKITE_PLUGIN_GCP_WORKLOAD_IDENTITY_FEDERATION_SERVICE_ACCOUNT="buildkite-example-pipeline@oidc-project.iam.gserviceaccount.com"

  run "$PWD/hooks/post-command"

  assert_success
  assert_output --partial "Running in the post-command hook"
}

@test "unsets the gcloud environment variables" {
  export BUILDKITE_PLUGIN_GCP_WORKLOAD_IDENTITY_FEDERATION_HOOK="pre-command"

  export GOOGLE_APPLICATION_CREDENTIALS=/some/tmp/path/credentials.json
  export CLOUDSDK_AUTH_CREDENTIAL_FILE_OVERRIDE=$GOOGLE_APPLICATION_CREDENTIALS

  source "$PWD/hooks/post-command"

  # allow unbound variables so we can check if they are unset
  set +u

  [ -z "$GOOGLE_APPLICATION_CREDENTIALS" ]
  [ -z "$CLOUDSDK_AUTH_CREDENTIAL_FILE_OVERRIDE" ]
}
