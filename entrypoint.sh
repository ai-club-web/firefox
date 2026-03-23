#!/usr/bin/env bash
set -Eeuo pipefail

export DISPLAY="${DISPLAY:-:99}"

SCREEN_WIDTH="${SCREEN_WIDTH:-1366}"
SCREEN_HEIGHT="${SCREEN_HEIGHT:-768}"
SCREEN_DEPTH="${SCREEN_DEPTH:-16}"
ENABLE_TOR="${ENABLE_TOR:-true}"
TOR_SOCKS_PORT="${TOR_SOCKS_PORT:-9050}"
TOR_MAX_CIRCUIT_DIRTINESS="${TOR_MAX_CIRCUIT_DIRTINESS:-60}"
TOR_NEW_CIRCUIT_PERIOD="${TOR_NEW_CIRCUIT_PERIOD:-30}"
TOR_BOOTSTRAP_TIMEOUT="${TOR_BOOTSTRAP_TIMEOUT:-90}"
NOVNC_BIND="${NOVNC_BIND:-0.0.0.0}"
NOVNC_PORT="${NOVNC_PORT:-8080}"
APP_STATE_DIR="${APP_STATE_DIR:-/tmp/kioskuser}"

if ! mkdir -p "$APP_STATE_DIR" 2>/dev/null; then
  APP_STATE_DIR="/dev/shm/kioskuser"
  mkdir -p "$APP_STATE_DIR"
fi
if [ ! -w "${HOME:-/home/kioskuser}" ]; then
  export HOME="$APP_STATE_DIR/home"
  mkdir -p "$HOME"
fi

VNC_DIR="${VNC_DIR:-$APP_STATE_DIR/.vnc}"
FIREFOX_BASE="${FIREFOX_BASE:-$APP_STATE_DIR/.mozilla/firefox}"
FIREFOX_PROFILE_DIR="$FIREFOX_BASE/lowmem.default"
TOR_DATA_DIR="${TOR_DATA_DIR:-$APP_STATE_DIR/tor_data}"
TOR_LOG_FILE="${TOR_LOG_FILE:-$APP_STATE_DIR/tor.log}"
TORRC_FILE="${TORRC_FILE:-$APP_STATE_DIR/torrc}"

XVFB_PID=""
OPENBOX_PID=""
X11VNC_PID=""
WEBSOCKIFY_PID=""
TOR_PID=""
TOR_WATCH_PID=""

cleanup() {
  set +e
  for pid in "$TOR_WATCH_PID" "$TOR_PID" "$WEBSOCKIFY_PID" "$X11VNC_PID" "$OPENBOX_PID" "$XVFB_PID"; do
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
      kill "$pid" 2>/dev/null
      wait "$pid" 2>/dev/null || true
    fi
  done
}
trap cleanup EXIT INT TERM

mkdir -p "$VNC_DIR"
x11vnc -storepasswd "${VNC_PASSWORD:-securepass}" "$VNC_DIR/passwd" >/dev/null

mkdir -p "$FIREFOX_PROFILE_DIR"
cat > "$FIREFOX_BASE/profiles.ini" <<PROFILES
[Profile0]
Name=default
IsRelative=1
Path=lowmem.default
Default=1

[General]
StartWithLastProfile=1
Version=2
PROFILES

cat > "$FIREFOX_PROFILE_DIR/user.js" <<FIREFOX_PREFS
user_pref("browser.cache.disk.enable", false);
user_pref("browser.sessionstore.interval", 600000);
user_pref("browser.startup.page", 0);
user_pref("browser.tabs.unloadOnLowMemory", true);
user_pref("dom.ipc.processCount", 1);
user_pref("dom.ipc.processCount.webIsolated", 1);
user_pref("fission.autostart", false);
user_pref("gfx.webrender.all", false);
user_pref("network.proxy.type", 0);
user_pref("network.proxy.socks", "");
user_pref("network.proxy.socks_port", 0);
user_pref("network.proxy.socks_remote_dns", false);
user_pref("toolkit.cosmeticAnimations.enabled", false);
FIREFOX_PREFS

Xvfb "$DISPLAY" -screen 0 "${SCREEN_WIDTH}x${SCREEN_HEIGHT}x${SCREEN_DEPTH}" -nolisten tcp &
XVFB_PID=$!
sleep 1

openbox-session &
OPENBOX_PID=$!

x11vnc -display "$DISPLAY" -rfbauth "$VNC_DIR/passwd" -forever -shared -localhost -xkb -noxrecord -noxfixes -noxdamage &
X11VNC_PID=$!
sleep 1

websockify --web /usr/share/novnc "${NOVNC_BIND}:${NOVNC_PORT}" localhost:5900 &
WEBSOCKIFY_PID=$!

if [ "$ENABLE_TOR" = "true" ]; then
  echo "Configuring Tor service on SOCKS port ${TOR_SOCKS_PORT}..."
  mkdir -p "$TOR_DATA_DIR"
  chmod 700 "$TOR_DATA_DIR"

  : > "$TOR_LOG_FILE"

  cat > "$TORRC_FILE" <<TORRC
DataDirectory $TOR_DATA_DIR
SocksPort 127.0.0.1:${TOR_SOCKS_PORT}
MaxCircuitDirtiness ${TOR_MAX_CIRCUIT_DIRTINESS}
NewCircuitPeriod ${TOR_NEW_CIRCUIT_PERIOD}
AvoidDiskWrites 1
Log notice file ${TOR_LOG_FILE}
TORRC

  tor -f "$TORRC_FILE" &
  TOR_PID=$!

  echo "Tor bootstrap check started in background (web UI is available immediately)."
  (
    BOOTSTRAP_DONE="false"
    for _ in $(seq 1 "$TOR_BOOTSTRAP_TIMEOUT"); do
      if ! kill -0 "$TOR_PID" 2>/dev/null; then
        echo "Tor process exited unexpectedly. Check ${TOR_LOG_FILE} for details."
        break
      fi
      if grep -q "Bootstrapped 100%" "$TOR_LOG_FILE" 2>/dev/null; then
        BOOTSTRAP_DONE="true"
        echo "Tor bootstrap complete."
        break
      fi
      sleep 1
    done
    if [ "$BOOTSTRAP_DONE" != "true" ]; then
      echo "Tor did not reach 100% bootstrap within ${TOR_BOOTSTRAP_TIMEOUT}s; SOCKS proxy use may timeout until Tor finishes."
    fi
  ) &
  TOR_WATCH_PID=$!
else
  echo "Tor is disabled (ENABLE_TOR=${ENABLE_TOR})."
fi

echo "Starting Firefox..."
while true; do
  unset http_proxy https_proxy ftp_proxy all_proxy HTTP_PROXY HTTPS_PROXY FTP_PROXY ALL_PROXY no_proxy NO_PROXY
  firefox-esr --new-instance --profile "$FIREFOX_PROFILE_DIR" || true
  sleep 1
done
