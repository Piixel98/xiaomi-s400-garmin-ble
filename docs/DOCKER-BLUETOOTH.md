# Docker and Bluetooth operations

This project has two Bluetooth paths. Select one with `BLE_SOURCE` in `.env`.

## Linux mode

Linux mode runs BlueZ on the host and scans from the container. The host must be physically close to the S400 and must expose a working controller such as `hci0`.

```bash
sudo apt update
sudo apt install -y bluez bluetooth rfkill
sudo systemctl enable --now bluetooth
sudo rfkill unblock bluetooth
bluetoothctl list
./scripts/check-host.sh
docker compose up -d --build
```

Set:

```dotenv
BLE_SOURCE=linux
HCI_INDEX=0
```

The compose file mounts `/run/dbus/system_bus_socket`, uses host networking and grants only `NET_ADMIN` and `NET_RAW`. Do not add `privileged: true` unless the deployment is being redesigned and reviewed.

## Windows + Docker Desktop mode

Docker Desktop's Linux VM does not expose the Windows Bluetooth API as a Linux BlueZ controller. Windows mode therefore runs [`scripts/windows_s400_scanner.py`](../scripts/windows_s400_scanner.py) with Bleak on the Windows host. When it receives a complete encrypted S400 measurement, it appends the raw record to `data/history/miscale_backup.csv`. The container has that directory mounted at `/persist/history` and runs the Garmin import loop.

Install the Windows dependencies:

```powershell
py -3.11 -m pip install --upgrade -r requirements-windows.txt
```

Set:

```dotenv
BLE_SOURCE=windows
```

Start the complete stack:

```powershell
.\scripts\start-windows.ps1
```

That script starts Docker Desktop when needed, waits for its engine, starts the native scanner, and runs `docker compose up -d --build`. It keeps the scanner PID in `data/windows-scanner.pid`; that file is ignored by Git.

Install logon startup once:

```powershell
.\scripts\install-windows-autostart.ps1
```

Stop the scanner and container together:

```powershell
.\scripts\stop-windows.ps1
```

Check both sides:

```powershell
Get-Content .\data\windows-scanner.log -Tail 50
docker compose ps
docker compose logs --tail=100 scale
```

The Windows container waits silently for a new row in the shared history. Its
log shows the BLE source at startup and only prints a Garmin synchronization
result or an actionable error; the upstream idle polling banners are filtered.

The USB dongle must remain owned by Windows in this mode. `usbipd-win` can attach USB devices to WSL2, but attaching this dongle to WSL removes it from Windows and does not provide the `hci0` controller required by the Linux scanner on this host. Docker's USB/IP procedure is a separate Hyper-V-oriented path and is not required for the native Windows scanner.

## Data flow and privacy

The scanner reads `S400_MAC` and `S400_BLE_KEY` from `.env` and writes only completed measurements to the local history file. Garmin tokens remain in `data/garmin/`. Keep `.env`, `data/garmin/` and runtime logs out of Git.

For the S400, Xiaomi Home is needed once to provision the scale and obtain its encrypted BLE key. Close Xiaomi Home before taking measurements so it does not claim the scale connection.
