#!/usr/bin/env bash
# Build LimitHUD and assemble a runnable .app bundle (no Xcode required).
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="LimitHUD"
CONFIG="release"
APP="${APP_NAME}.app"

echo "==> swift build -c ${CONFIG}"
swift build -c "${CONFIG}"

BIN=".build/${CONFIG}/${APP_NAME}"
if [[ ! -f "${BIN}" ]]; then
  echo "build failed: ${BIN} not found" >&2
  exit 1
fi

echo "==> assembling ${APP}"
rm -rf "${APP}"
mkdir -p "${APP}/Contents/MacOS" "${APP}/Contents/Resources"
cp "${BIN}" "${APP}/Contents/MacOS/${APP_NAME}"
cp "Info.plist" "${APP}/Contents/Info.plist"
printf 'APPL????' > "${APP}/Contents/PkgInfo"
[[ -f "AppIcon.icns" ]] && cp "AppIcon.icns" "${APP}/Contents/Resources/AppIcon.icns"

SIGN_ID="LimitHUD Self-Signed"
if security find-identity -p codesigning | grep -q "${SIGN_ID}"; then
  echo "==> codesign (${SIGN_ID})"
  codesign --force --deep --sign "${SIGN_ID}" "${APP}"
else
  echo "==> ad-hoc codesign (run ./setup-signing.sh for a stable identity)"
  codesign --force --deep --sign - "${APP}" >/dev/null 2>&1 || true
fi

echo "==> done: ${APP}"
echo "Run with:  open ${APP}    (or ./build.sh run)"

if [[ "${1:-}" == "run" ]]; then
  # kill any previous instance, then launch fresh
  pkill -x "${APP_NAME}" >/dev/null 2>&1 || true
  open "${APP}"
fi

if [[ "${1:-}" == "install" ]]; then
  pkill -x "${APP_NAME}" >/dev/null 2>&1 || true
  if cp -R "${APP}" "/Applications/${APP}.tmp" 2>/dev/null; then
    rm -rf "/Applications/${APP}"
    mv "/Applications/${APP}.tmp" "/Applications/${APP}"
    echo "✓ installed to /Applications/${APP}"
    open "/Applications/${APP}"
  else
    mkdir -p "$HOME/Applications"
    rm -rf "$HOME/Applications/${APP}"
    cp -R "${APP}" "$HOME/Applications/${APP}"
    echo "⚠ /Applications not writable — installed to ~/Applications/${APP}"
    open "$HOME/Applications/${APP}"
  fi
fi
