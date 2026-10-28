#!/bin/bash
# Build Redactor.app, sign it, and optionally install to ~/Applications and launch.
#   ./build.sh               build into ./build/Redactor.app
#   ./build.sh --install     also copy to ~/Applications and open it
#   ./build.sh --reset-tcc   reset Screen Recording / Desktop permissions first
# Signing: uses $SIGN_ID, else "Redactor Local Signing" if present, else ad-hoc.
set -euo pipefail
cd "$(dirname "$0")"

BUNDLE_ID="com.noelabu.redactor"
APP="build/Redactor.app"
INSTALL=0

for arg in "$@"; do
    case "$arg" in
        --install) INSTALL=1 ;;
        --reset-tcc)
            tccutil reset ScreenCapture "$BUNDLE_ID" || true
            tccutil reset SystemPolicyDesktopFolder "$BUNDLE_ID" || true
            ;;
        *) echo "unknown option: $arg" >&2; exit 1 ;;
    esac
done

if [[ -z "${SIGN_ID:-}" ]]; then
    if security find-identity -p codesigning | grep -q "Redactor Local Signing"; then
        SIGN_ID="Redactor Local Signing"
    else
        SIGN_ID="-"
        echo "warning: ad-hoc signing; permissions reset on every rebuild" >&2
    fi
fi

swift build -c release
BIN="$(swift build -c release --show-bin-path)/Redactor"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/Redactor"
cp Support/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign "$SIGN_ID" --identifier "$BUNDLE_ID" "$APP"
echo "built $APP (signed: $SIGN_ID)"

if [[ $INSTALL -eq 1 ]]; then
    # Wait for the old instance to exit; opening while it's still terminating fails with -600.
    pkill -x Redactor || true
    for _ in $(seq 50); do pgrep -x Redactor >/dev/null || break; sleep 0.1; done
    rm -rf "$HOME/Applications/Redactor.app"
    mkdir -p "$HOME/Applications"
    ditto "$APP" "$HOME/Applications/Redactor.app"
    open "$HOME/Applications/Redactor.app" || { sleep 1; open "$HOME/Applications/Redactor.app"; }
    echo "installed and launched ~/Applications/Redactor.app"
fi
