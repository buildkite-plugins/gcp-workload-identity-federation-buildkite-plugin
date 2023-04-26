#!/usr/bin/env bats

# Uncomment to enable stub debug output:
# export DOCKER_STUB_DEBUG=/dev/tty

setup() {
  load "$BATS_PLUGIN_PATH/load.bash"
}

@test "removes tmp directory" {
    export BUILDKITE_OIDC_TMPDIR=$BATS_TEST_TMPDIR

    run "$PWD/hooks/pre-exit"

    assert_success

    assert_output --partial "Removed credentials from $BATS_TEST_TMPDIR"
}

@test "does nothing if the directory is not set" {
    run "$PWD/hooks/pre-exit"

    assert_success

    assert_output ""
}
