#!/bin/bash
# Builds BiscuitFlow.app into ./build. Usage: scripts/build.sh [Debug|Release]
set -uo pipefail
cd "$(dirname "$0")/.."
CONFIG="${1:-Release}"
# Prefer the release Xcode; the beta toolchain's stdlib breaks swift-collections 1.7.
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
LOG=.build/build.log

# Signing: ad-hoc by default (no certificate needed). Optional:
#   TEAM_ID=ABCDE12345 scripts/build.sh          → "Apple Development" (or $SIGN_IDENTITY) for that team
#   SIGN_IDENTITY="BiscuitFlow Local" scripts/build.sh → any keychain identity, e.g. a self-signed one
SIGNING=()
if [ -n "${TEAM_ID:-}" ]; then
  SIGNING=(DEVELOPMENT_TEAM="$TEAM_ID" CODE_SIGN_IDENTITY="${SIGN_IDENTITY:-Apple Development}")
elif [ -n "${SIGN_IDENTITY:-}" ]; then
  SIGNING=(CODE_SIGN_IDENTITY="$SIGN_IDENTITY")
fi
if [ ${#SIGNING[@]} -eq 0 ]; then echo "Signing: ad-hoc"; else echo "Signing: ${SIGNING[*]}"; fi
mkdir -p .build
scripts/fetch_model.sh
command -v xcodegen >/dev/null && xcodegen generate --quiet
xcodebuild -project BiscuitFlow.xcodeproj -scheme BiscuitFlow -configuration "$CONFIG" \
  -destination 'platform=macOS,arch=arm64' \
  -clonedSourcePackagesDirPath .build/spm \
  -derivedDataPath .build/DerivedData \
  -skipPackagePluginValidation -skipMacroValidation \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES ${SIGNING[@]+"${SIGNING[@]}"} build > "$LOG" 2>&1
STATUS=$?
grep -E "error:|warning: .*BiscuitFlow/" "$LOG" | grep -v "/.build/spm/" | sort -u | head -60
if [ $STATUS -ne 0 ]; then echo "** BUILD FAILED ** (see $LOG)"; tail -5 "$LOG"; exit $STATUS; fi
APP=".build/DerivedData/Build/Products/$CONFIG/BiscuitFlow.app"
rm -rf build && mkdir -p build && cp -R "$APP" build/
echo "Built $(pwd)/build/BiscuitFlow.app"
