#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_home="$(mktemp -d /tmp/formationflow-roster-test-XXXXXX)"
trap 'rm -rf "$test_home"' EXIT
compiler="$(xcode-select -p)/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc"
sdk="$(xcrun --sdk macosx --show-sdk-path)"
"$compiler" -sdk "$sdk" -target "$(uname -m)-apple-macosx14.0" -parse-as-library \
    FormationFlow/Models.swift FormationFlow/RosterImport.swift \
    Tests/bulk_roster_regression.swift -o "$test_home/regression"
CFFIXED_USER_HOME="$test_home" "$test_home/regression"
