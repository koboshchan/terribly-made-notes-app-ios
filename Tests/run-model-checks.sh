#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
swiftc "$ROOT/Notes/Models/Note.swift" "$ROOT/Tests/StudyModelChecks.swift" -o "$WORK/study-model-checks"
"$WORK/study-model-checks"
