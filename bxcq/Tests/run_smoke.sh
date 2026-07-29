#!/usr/bin/env bash
set -euo pipefail

BXCQ_GODOT_BIN="${BXCQ_GODOT_BIN:-/Applications/Godot 4.7 .NET.app/Contents/MacOS/Godot}"

dotnet build BXCQ.csproj --no-restore

tests=(
  smoke_path_network_controls.gd
  smoke_examine_investigate.gd
  smoke_interaction_roles.gd
  smoke_acceptance_loop.gd
  smoke_narrrail_bridge.gd
  smoke_presentation_events.gd
  smoke_story_state.gd
  smoke_cross_scene_story.gd
  smoke_scene_parity.gd
  smoke_dialogue_presenter.gd
)

for test_name in "${tests[@]}"; do
  echo "==> ${test_name}"
  "${BXCQ_GODOT_BIN}" --headless --path . --script "res://Tests/Smoke/${test_name}"
done

echo "All BXCQ smoke tests passed."
