#!/usr/bin/env bash
set -euo pipefail

echo "== Xiaomi S400 BLE host check =="

if [[ "$(uname -s)" != "Linux" ]]; then
  echo "ERROR: direct BLE Docker mode is intended for a Linux host." >&2
  exit 1
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "ERROR: Docker is not installed." >&2
  exit 1
fi

if ! command -v bluetoothctl >/dev/null 2>&1; then
  echo "ERROR: BlueZ tools are not installed. Debian/Ubuntu: sudo apt install bluez bluetooth rfkill" >&2
  exit 1
fi

if command -v systemctl >/dev/null 2>&1; then
  if ! systemctl is-active --quiet bluetooth; then
    echo "WARNING: bluetooth.service is not active. Try: sudo systemctl enable --now bluetooth"
  else
    echo "OK: bluetooth.service is active"
  fi
fi

if command -v rfkill >/dev/null 2>&1 && rfkill list bluetooth 2>/dev/null | grep -q "Soft blocked: yes"; then
  echo "WARNING: Bluetooth is rfkill-blocked. Run: sudo rfkill unblock bluetooth"
fi

if bluetoothctl list | grep -q "Controller"; then
  echo "OK: Bluetooth controller detected"
  bluetoothctl list
else
  echo "ERROR: no Bluetooth controller detected. Add/enable a USB Bluetooth adapter." >&2
  exit 1
fi

if [[ -S /run/dbus/system_bus_socket ]]; then
  echo "OK: BlueZ D-Bus socket exists"
else
  echo "ERROR: /run/dbus/system_bus_socket is missing." >&2
  exit 1
fi

echo "Host looks ready. Keep the server physically within BLE range of the scale."
