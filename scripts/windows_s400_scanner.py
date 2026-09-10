#!/usr/bin/env python3
"""Native Windows BLE scanner for the Xiaomi S400.

Docker Desktop's Linux VM cannot expose the Windows Bluetooth stack as hci0.
This process uses Bleak's Windows backend and appends complete, decrypted S400
measurements to data/history/miscale_backup.csv, which is mounted by compose.
"""

from __future__ import annotations

import asyncio
import os
import sys
import time
from datetime import datetime
from pathlib import Path

from bleak import BleakScanner
from bluetooth_sensor_state_data import BluetoothServiceInfo
from xiaomi_ble.parser import XiaomiBluetoothDeviceData


ROOT = Path(__file__).resolve().parents[1]
ENV_FILE = ROOT / ".env"
HISTORY_FILE = ROOT / "data" / "history" / "miscale_backup.csv"
HEADER = (
    "Data Status;Unix Time;Date [dd.mm.yyyy];Time [hh:mm];Weight [kg];"
    "Change [kg];BMI;Body Fat [%];Skeletal Muscle Mass [kg];Bone Mass [kg];"
    "Body Water [%];Physique Rating;Visceral Fat;Metabolic Age [years];"
    "BMR [kCal];LBM [kg];Ideal Wieght [kg];Fat Mass To Ideal [type:mass kg];"
    "Protein [%];Impedance;Email User;Upload Date [dd.mm.yyyy];"
    "Upload Time [hh:mm];Difference Time [s];Impedance Low;Heart Rate [bpm]"
)


def load_env() -> dict[str, str]:
    values: dict[str, str] = {}
    for raw in ENV_FILE.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        values[key.strip()] = value.strip().strip('"').strip("'")
    return values


def log(message: str) -> None:
    print(f"{datetime.now():%Y-%m-%d %H:%M:%S} {message}", flush=True)


def ensure_history() -> None:
    HISTORY_FILE.parent.mkdir(parents=True, exist_ok=True)
    if not HISTORY_FILE.exists() or HISTORY_FILE.stat().st_size == 0:
        HISTORY_FILE.write_text(HEADER + "\n", encoding="utf-8")


def append_measurement(values: dict[str, float]) -> None:
    now = int(time.time())
    # import_data.sh expects the raw S400 record in these six columns. It
    # expands the row with calculated Garmin fields after the upload.
    row = (
        f"to_import;{now};{values['Mass']:.1f};"
        f"{values['Impedance Low']:.0f};{values['Impedance High']:.0f};"
        f"{values['Heart Rate']:.0f}"
    )
    with HISTORY_FILE.open("a", encoding="utf-8", newline="") as handle:
        handle.write(row + "\n")
    log(
        "S400 complete: "
        f"weight={values['Mass']:.1f}kg, low_impedance={values['Impedance Low']:.0f}, "
        f"high_impedance={values['Impedance High']:.0f}, heart_rate={values['Heart Rate']:.0f}"
    )


async def scan_once(mac: str, key: str) -> None:
    parser = XiaomiBluetoothDeviceData(bindkey=bytes.fromhex(key))
    complete = asyncio.Event()
    last_written: tuple[float, float, float, float] | None = None

    def callback(device, advertisement_data) -> None:
        nonlocal last_written
        if device.address.upper() != mac.upper() or complete.is_set():
            return
        try:
            service_info = BluetoothServiceInfo(
                name=device.name,
                address=device.address,
                rssi=advertisement_data.rssi,
                manufacturer_data=advertisement_data.manufacturer_data,
                service_data=advertisement_data.service_data,
                service_uuids=advertisement_data.service_uuids,
                source=device.address,
            )
            if not parser.supported(service_info):
                return
            update = parser.update(service_info)
            if not update or not update.entity_values:
                return
            wanted = {"Mass", "Impedance Low", "Impedance High", "Heart Rate"}
            values = {
                item.name: item.native_value
                for item in update.entity_values.values()
                if item.name in wanted and item.native_value is not None
            }
            if wanted <= values.keys():
                fingerprint = tuple(float(values[name]) for name in sorted(wanted))
                if fingerprint == last_written:
                    return
                last_written = fingerprint
                append_measurement({name: float(values[name]) for name in wanted})
                complete.set()
        except Exception as exc:  # BLE callbacks must never kill the scanner.
            log(f"scanner callback warning: {exc}")

    scanner = BleakScanner(detection_callback=callback)
    await scanner.start()
    log(f"Windows BLE scanner active; waiting for S400 {mac.upper()}")
    try:
        await complete.wait()
    finally:
        await scanner.stop()


async def main() -> None:
    env = load_env()
    mac = env.get("S400_MAC", "")
    key = env.get("S400_BLE_KEY", "")
    if not mac or not key:
        raise SystemExit("S400_MAC and S400_BLE_KEY are required in .env")
    if sys.platform != "win32":
        raise SystemExit("windows_s400_scanner.py must run with native Windows Python")
    ensure_history()
    log("Windows Xiaomi S400 scanner starting")
    while True:
        try:
            await scan_once(mac, key)
        except asyncio.CancelledError:
            raise
        except Exception as exc:
            log(f"BLE scan failed: {exc}; retrying in 5 seconds")
            await asyncio.sleep(5)
        else:
            await asyncio.sleep(3)


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        log("Windows S400 scanner stopped")
