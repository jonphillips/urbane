#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

qr="${JON_PLATFORM:-$HOME/code/jon-platform}/scripts/quiet-run"
[[ -x "$qr" ]] || qr=""

xcodegen generate --use-cache --quiet
$qr swiftlint lint --strict
$qr swift test --package-path UrbaneLibrary
$qr xcodebuild -resolvePackageDependencies -project Urbane.xcodeproj -scheme Urbane \
  -clonedSourcePackagesDirPath ./.build/SourcePackages
$qr xcodebuild -project Urbane.xcodeproj -scheme Urbane \
  -destination 'generic/platform=iOS Simulator' \
  -skipMacroValidation \
  -onlyUsePackageVersionsFromResolvedFile \
  -derivedDataPath ./.build/DerivedData \
  -clonedSourcePackagesDirPath ./.build/SourcePackages \
  build-for-testing

handoff="${JON_PLATFORM:-$HOME/code/jon-platform}/scripts/check-handoff"
if [[ -x "$handoff" ]]; then
  "$handoff"
else
  echo "check-drift: check-handoff unavailable; skip the documentation-shape check."
fi
