#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

SCHEME="${SCHEME:-VibeScribeUITests}"
DESTINATION="${DESTINATION:-platform=macOS}"
XCODEBUILD_BIN="${XCODEBUILD_BIN:-xcodebuild}"

usage() {
    cat <<'EOF'
Usage:
  ./scripts/run_test_sets.sh <set> [value]

Sets:
  ui-all                Run all UI tests in VibeScribeUITests scheme.
  ui-core               Run core UI flows (populated/empty/settings/delete/state).
  ui-mock               Run all mock pipeline flows.
  ui-mock-core          Run mock flows except provider matrix check (faster).
  ui-smoke              Run high-coverage smoke with minimal app relaunches.
  ui-smoke-lite         Run an expanded smoke subset with the same 3-launch budget.
  ui-class <ClassName>  Run one UI test class (e.g. MockPipelineFlowTests).
  ui-test <Class/test>  Run one UI test method (e.g. MockPipelineFlowTests/testMockFlow_NoSpeakers_EndToEndFromFirstLaunchToManualSummaryEdit).
  help                  Show this help.

Environment overrides:
  SCHEME=VibeScribeUITests
  DESTINATION='platform=macOS'
  XCODEBUILD_BIN=xcodebuild
EOF
}

run_xcodebuild_tests() {
    local -a args=("$@")
    echo "Running: $XCODEBUILD_BIN -scheme \"$SCHEME\" -destination \"$DESTINATION\" ${args[*]} test"
    "$XCODEBUILD_BIN" -scheme "$SCHEME" -destination "$DESTINATION" "${args[@]}" test
}

set_name="${1:-help}"

case "$set_name" in
    ui-all)
        run_xcodebuild_tests
        ;;

    ui-core)
        run_xcodebuild_tests \
            -only-testing:VibeScribeUITests/PopulatedStateTests \
            -only-testing:VibeScribeUITests/EmptyStateTests \
            -only-testing:VibeScribeUITests/LanguageRestartTests \
            -only-testing:VibeScribeUITests/DeleteFlowTests \
            -only-testing:VibeScribeUITests/StateTransitionTests
        ;;

    ui-mock)
        run_xcodebuild_tests \
            -only-testing:VibeScribeUITests/MockPipelineFlowTests
        ;;

    ui-mock-core)
        run_xcodebuild_tests \
            -only-testing:VibeScribeUITests/MockPipelineFlowTests \
            -skip-testing:VibeScribeUITests/MockPipelineFlowTests/testMockFlow_ProviderMatrix_TranscriptionReflectsSelectedProvider
        ;;

    ui-smoke)
        run_xcodebuild_tests \
            -only-testing:VibeScribeUITests/PopulatedStateTests \
            -only-testing:VibeScribeUITests/EmptyStateTests \
            -only-testing:VibeScribeUITests/MockPipelineFlowTests/testMockFlow_NoSpeakers_EndToEndFromFirstLaunchToManualSummaryEdit
        ;;

    ui-smoke-lite)
        run_xcodebuild_tests \
            -only-testing:VibeScribeUITests/PopulatedStateTests/testWorkspaceFlow_ShowsSidebarSeededRecordsAndActiveDetail \
            -only-testing:VibeScribeUITests/PopulatedStateTests/testContentModeFlow_SwitchTabsAndValidateActionAvailability \
            -only-testing:VibeScribeUITests/PopulatedStateTests/testModelPickerIsolation_NonMockSessionDoesNotExposeMockModels \
            -only-testing:VibeScribeUITests/EmptyStateTests/testEmptyOnboardingFlow_ShowsWelcomeAndNoRecords \
            -only-testing:VibeScribeUITests/EmptyStateTests/testEmptyOnboardingSettingsFlow_OpenSwitchTabsAndReturnToWelcome \
            -only-testing:VibeScribeUITests/MockPipelineFlowTests/testMockFlow_NoSpeakers_EndToEndFromFirstLaunchToManualSummaryEdit
        ;;

    ui-class)
        class_name="${2:-}"
        if [[ -z "$class_name" ]]; then
            echo "Error: ui-class requires a class name." >&2
            usage
            exit 1
        fi
        run_xcodebuild_tests "-only-testing:VibeScribeUITests/$class_name"
        ;;

    ui-test)
        test_name="${2:-}"
        if [[ -z "$test_name" ]]; then
            echo "Error: ui-test requires ClassName/testMethod." >&2
            usage
            exit 1
        fi
        run_xcodebuild_tests "-only-testing:VibeScribeUITests/$test_name"
        ;;

    help|-h|--help)
        usage
        ;;

    *)
        echo "Unknown set: $set_name" >&2
        usage
        exit 1
        ;;
esac
