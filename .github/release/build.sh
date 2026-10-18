#!/usr/bin/env bash
set -euo pipefail

version="$1"
stage="dist/stage"

rm -rf "${stage}"
mkdir -p "${stage}"
git archive HEAD scripts config LICENSE README.md | tar -x -C "${stage}"
sed -i "s/^\(\s*ModuleVersion\s*=\s*\)'[^']*'/\1'${version}'/" "${stage}/scripts/DocFlowEngine.psd1"
(cd "${stage}" && zip -q -r "../DocFlowEngine-v${version}.zip" .)
rm -rf "${stage}"
