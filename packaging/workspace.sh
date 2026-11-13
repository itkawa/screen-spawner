#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
# Sourced after project is set. The optional path stays local to each checkout.
workspace=${SCREEN_SPAWNER_BUILDS_DIR:-}
if [ -z "$workspace" ] && command -v git >/dev/null 2>&1; then
    workspace=$(git -c safe.directory="$project" -C "$project" config --local screenSpawner.buildsDirectory 2>/dev/null || true)
fi
workspace=${workspace:-$(dirname "$project")}
