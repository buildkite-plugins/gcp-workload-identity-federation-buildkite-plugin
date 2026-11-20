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

    run "$PWD/hooks/environment"

    assert_failure
}

@test "fails when audience is missing" {
    export BUILDKITE_PLUGIN_GCP_WORKLOAD_IDENTITY_FEDERATION_SERVICE_ACCOUNT="buildkite-example-pipeline@oidc-project.iam.gserviceaccount.com"

    run "$PWD/hooks/environment"

    assert_failure
}

@test "fails when service account is missing" {
    export BUILDKITE_PLUGIN_GCP_WORKLOAD_IDENTITY_FEDERATION_AUDIENCE="//iam.googleapis.com/projects/123456789/locations/global/workloadIdentityPools/buildkite-example-pipeline/providers/buildkite"

    run "$PWD/hooks/environment"

    assert_failure
}

@test "fails when render command has non-existent binary" {
    export BUILDKITE_PLUGIN_GCP_WORKLOAD_IDENTITY_FEDERATION_AUDIENCE="//iam.googleapis.com/projects/123456789/locations/global/workloadIdentityPools/buildkite-example-pipeline/providers/buildkite"
    export BUILDKITE_PLUGIN_GCP_WORKLOAD_IDENTITY_FEDERATION_SERVICE_ACCOUNT="buildkite-example-pipeline@oidc-project.iam.gserviceaccount.com"
    export BUILDKITE_PLUGIN_GCP_WORKLOAD_IDENTITY_FEDERATION_RENDER_COMMAND="this-file-purposely-does-not-exist"

    run "$PWD/hooks/environment"

    assert_failure
}

@test "succeeds when mktemp fails once" {
    export BUILDKITE_PLUGIN_GCP_WORKLOAD_IDENTITY_FEDERATION_AUDIENCE="//iam.googleapis.com/projects/123456789/locations/global/workloadIdentityPools/buildkite-example-pipeline/providers/buildkite"
    export BUILDKITE_PLUGIN_GCP_WORKLOAD_IDENTITY_FEDERATION_SERVICE_ACCOUNT="buildkite-example-pipeline@oidc-project.iam.gserviceaccount.com"

    stub mktemp "-d : exit 1"
    stub mktemp "-d -t 'buildkiteXXXX' : echo $BATS_TEST_TMPDIR"
    stub buildkite-agent "echo dummy-jwt"

    run "$PWD/hooks/environment"

    assert_success

    unstub mktemp
    unstub buildkite-agent
}

@test "exports credentials" {
    export BUILDKITE_PLUGIN_GCP_WORKLOAD_IDENTITY_FEDERATION_AUDIENCE="//iam.googleapis.com/projects/123456789/locations/global/workloadIdentityPools/buildkite-example-pipeline/providers/buildkite"
    export BUILDKITE_PLUGIN_GCP_WORKLOAD_IDENTITY_FEDERATION_SERVICE_ACCOUNT="buildkite-example-pipeline@oidc-project.iam.gserviceaccount.com"

    stub mktemp "-d : echo $BATS_TEST_TMPDIR"
    stub buildkite-agent "oidc request-token --audience //iam.googleapis.com/projects/123456789/locations/global/workloadIdentityPools/buildkite-example-pipeline/providers/buildkite --lifetime 0 : echo dummy-jwt"

    run "$PWD/hooks/environment"

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

@test "exports Windows credential paths and preserves the Bash cleanup path" {
    export BUILDKITE_PLUGIN_GCP_WORKLOAD_IDENTITY_FEDERATION_AUDIENCE="//iam.googleapis.com/projects/123456789/locations/global/workloadIdentityPools/buildkite-example-pipeline/providers/buildkite"
    export BUILDKITE_PLUGIN_GCP_WORKLOAD_IDENTITY_FEDERATION_SERVICE_ACCOUNT="buildkite-example-pipeline@oidc-project.iam.gserviceaccount.com"
    local tmpdir="$BATS_TEST_TMPDIR/wif credentials"

    for ostype in msys cygwin; do
        mkdir "$tmpdir"
        stub mktemp "-d : printf '%s\n' '$tmpdir'"
        stub cygpath "-m '$tmpdir' : printf '%s\n' 'C:/tools/msys64/tmp/wif credentials'"
        stub buildkite-agent "oidc request-token --audience //iam.googleapis.com/projects/123456789/locations/global/workloadIdentityPools/buildkite-example-pipeline/providers/buildkite --lifetime 0 : echo dummy-jwt"

        run bash -c '
            OSTYPE=$1
            source "$2"
            printf "GOOGLE_APPLICATION_CREDENTIALS=%s\n" "$GOOGLE_APPLICATION_CREDENTIALS"
            printf "CLOUDSDK_AUTH_CREDENTIAL_FILE_OVERRIDE=%s\n" "$CLOUDSDK_AUTH_CREDENTIAL_FILE_OVERRIDE"
            printf "BUILDKITE_OIDC_TMPDIR=%s\n" "$BUILDKITE_OIDC_TMPDIR"
        ' -- "$ostype" "$PWD/hooks/environment"

        assert_success
        assert_output --partial "GOOGLE_APPLICATION_CREDENTIALS=C:/tools/msys64/tmp/wif credentials/credentials.json"
        assert_output --partial "CLOUDSDK_AUTH_CREDENTIAL_FILE_OVERRIDE=C:/tools/msys64/tmp/wif credentials/credentials.json"
        assert_output --partial "BUILDKITE_OIDC_TMPDIR=$tmpdir"
        grep -Fq '"file": "C:/tools/msys64/tmp/wif credentials/token.json"' "$tmpdir/credentials.json"
        diff "$tmpdir/token.json" <(printf '%s\n' dummy-jwt)

        unstub mktemp
        unstub cygpath
        unstub buildkite-agent

        export BUILDKITE_OIDC_TMPDIR="$tmpdir"
        run "$PWD/hooks/pre-exit"

        assert_success
        [ ! -d "$tmpdir" ]
    done
}

@test "fails when Windows path conversion fails" {
    export BUILDKITE_PLUGIN_GCP_WORKLOAD_IDENTITY_FEDERATION_AUDIENCE="//iam.googleapis.com/projects/123456789/locations/global/workloadIdentityPools/buildkite-example-pipeline/providers/buildkite"
    export BUILDKITE_PLUGIN_GCP_WORKLOAD_IDENTITY_FEDERATION_SERVICE_ACCOUNT="buildkite-example-pipeline@oidc-project.iam.gserviceaccount.com"

    stub mktemp "-d : echo $BATS_TEST_TMPDIR"
    stub cygpath "-m $BATS_TEST_TMPDIR : printf '%s\n' 'path conversion failed' >&2; exit 1"

    run bash -c 'OSTYPE=msys; source "$1"' -- "$PWD/hooks/environment"

    assert_failure
    assert_output --partial "path conversion failed"

    unstub mktemp
    unstub cygpath
}

@test "exports credentials with render command using envsubst" {
    export GCP_PROJECT_ID=oidc-project
    export GCP_PROJECT_NUMBER=123456789
    export BUILDKITE_PLUGIN_GCP_WORKLOAD_IDENTITY_FEDERATION_AUDIENCE="//iam.googleapis.com/projects/\${GCP_PROJECT_NUMBER}/locations/global/workloadIdentityPools/buildkite-example-pipeline/providers/buildkite"
    export BUILDKITE_PLUGIN_GCP_WORKLOAD_IDENTITY_FEDERATION_SERVICE_ACCOUNT="buildkite-example-pipeline@\${GCP_PROJECT_ID}.iam.gserviceaccount.com"
    export BUILDKITE_PLUGIN_GCP_WORKLOAD_IDENTITY_FEDERATION_RENDER_COMMAND="envsubst"

    stub mktemp "-d : echo $BATS_TEST_TMPDIR"
    stub buildkite-agent "oidc request-token --audience //iam.googleapis.com/projects/123456789/locations/global/workloadIdentityPools/buildkite-example-pipeline/providers/buildkite --lifetime 0 : echo dummy-jwt"

    run "$PWD/hooks/environment"

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

@test "exports credentials with optional claim organization id" {
    export BUILDKITE_PLUGIN_GCP_WORKLOAD_IDENTITY_FEDERATION_AUDIENCE="//iam.googleapis.com/projects/123456789/locations/global/workloadIdentityPools/buildkite-example-pipeline/providers/buildkite"
    export BUILDKITE_PLUGIN_GCP_WORKLOAD_IDENTITY_FEDERATION_SERVICE_ACCOUNT="buildkite-example-pipeline@oidc-project.iam.gserviceaccount.com"
    export BUILDKITE_PLUGIN_GCP_WORKLOAD_IDENTITY_FEDERATION_CLAIMS_0="organization_id"

    stub mktemp "-d : echo $BATS_TEST_TMPDIR"
    stub buildkite-agent "oidc request-token --audience //iam.googleapis.com/projects/123456789/locations/global/workloadIdentityPools/buildkite-example-pipeline/providers/buildkite --lifetime 0 --claim organization_id : echo dummy-jwt"

    run "$PWD/hooks/environment"

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

@test "exports credentials with optional claim pipeline id" {
    export BUILDKITE_PLUGIN_GCP_WORKLOAD_IDENTITY_FEDERATION_AUDIENCE="//iam.googleapis.com/projects/123456789/locations/global/workloadIdentityPools/buildkite-example-pipeline/providers/buildkite"
    export BUILDKITE_PLUGIN_GCP_WORKLOAD_IDENTITY_FEDERATION_SERVICE_ACCOUNT="buildkite-example-pipeline@oidc-project.iam.gserviceaccount.com"
    export BUILDKITE_PLUGIN_GCP_WORKLOAD_IDENTITY_FEDERATION_CLAIMS_0="pipeline_id"

    stub mktemp "-d : echo $BATS_TEST_TMPDIR"
    stub buildkite-agent "oidc request-token --audience //iam.googleapis.com/projects/123456789/locations/global/workloadIdentityPools/buildkite-example-pipeline/providers/buildkite --lifetime 0 --claim pipeline_id : echo dummy-jwt"

    run "$PWD/hooks/environment"

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

@test "exports credentials with optional claims organization_id and pipeline id" {
    export BUILDKITE_PLUGIN_GCP_WORKLOAD_IDENTITY_FEDERATION_AUDIENCE="//iam.googleapis.com/projects/123456789/locations/global/workloadIdentityPools/buildkite-example-pipeline/providers/buildkite"
    export BUILDKITE_PLUGIN_GCP_WORKLOAD_IDENTITY_FEDERATION_SERVICE_ACCOUNT="buildkite-example-pipeline@oidc-project.iam.gserviceaccount.com"
    export BUILDKITE_PLUGIN_GCP_WORKLOAD_IDENTITY_FEDERATION_CLAIMS_0="organization_id"
    export BUILDKITE_PLUGIN_GCP_WORKLOAD_IDENTITY_FEDERATION_CLAIMS_1="pipeline_id"

    stub mktemp "-d : echo $BATS_TEST_TMPDIR"
    stub buildkite-agent "oidc request-token --audience //iam.googleapis.com/projects/123456789/locations/global/workloadIdentityPools/buildkite-example-pipeline/providers/buildkite --lifetime 0 --claim organization_id --claim pipeline_id : echo dummy-jwt"

    run "$PWD/hooks/environment"

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
