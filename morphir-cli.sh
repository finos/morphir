#!/usr/bin/env bash
# Run one of the samples.
# The first argument must be the name of the sample task (e.g. echo).
# Any remaining arguments are forwarded to the sample's argv.


./gradlew --quiet ":morphir-cli:installJvmDist" && "./morphir-cli/build/install/morphir-cli-jvm/bin/morphir-cli" "$@"