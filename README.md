# Xiaomi Body Composition Scale S400 -> Garmin Connect (Bluetooth / Docker)

BLE bridge for a **Xiaomi Body Composition Scale S400 (MJTZC01YM / `yunmai.scales.ms104`)** to Garmin Connect.

This project does **not use Xiaomi Cloud for daily synchronisation**. It supports two deployment modes:

- Linux: BlueZ and the container scan the S400 directly.
- Windows + Docker Desktop: a native Windows Bleak scanner reads the USB Bluetooth adapter and writes completed measurements to the shared `data/history/miscale_backup.csv`; the container calculates and uploads them.

The Windows mode is the supported path for this repository's Docker Desktop setup. See [`docs/DOCKER-BLUETOOTH.md`](docs/DOCKER-BLUETOOTH.md) for the detailed runbook.

> Important: for the S400, Xiaomi Home is still required **once during initial provisioning** to register the scale and obtain its encrypted BLE key. After that, Xiaomi Home does not need to be open for daily weigh-ins. The upstream S400 documentation also says a full initial measurement including heart rate is required, and the BLE key can change if a new Xiaomi Home profile is connected to the scale.

## Architecture

```text
┌──────────────────────────────┐
│ Xiaomi S400                  │
│ weight + impedance + HR      │
└──────────────┬───────────────┘
               │ Bluetooth Low Energy
               │ encrypted Xiaomi advertisements
               ▼
┌──────────────────────────────┐
│ Linux host                   │
│  BlueZ + Docker              │
│  └─ export2garmin            │
│     ├─ BLE scan               │
│     ├─ decrypt with BLE key  │
│     ├─ calculate metrics     │
│     └─ Garmin upload         │
└──────────────┬───────────────┘
               │ HTTPS outbound only
               ▼
┌──────────────────────────────┐
│ Garmin Connect               │
│ weight / BMI / fat / muscle  │
│ bone / water / visceral fat  │
└──────────────┬───────────────┘
               ▼
        Garmin ecosystem
```

On Windows + Docker Desktop, the first box after the scale is the native Windows BLE companion. It writes the raw six-field S400 record to the shared history file; the Linux container consumes that record and performs the Garmin upload.

### How often does it sync?

There is **no 15-minute timer** in BLE mode. The S400 only advertises a completed measurement for a short time, so the service keeps the Bluetooth scanner running continuously. When it captures a full measurement, it processes and uploads it to Garmin immediately (normally seconds after the scale finishes, subject to BLE reception and Garmin connectivity).

The upstream project stores a local CSV history; this project persists it under `./data/history/`.

---

# 1. What you need

- Xiaomi Body Composition Scale **S400**.
- Linux host physically within Bluetooth range of the scale, or Windows 10/11 with Docker Desktop and a USB Bluetooth dongle.
- Docker Engine + Docker Compose plugin on Linux, or Docker Desktop on Windows.
- Python 3.11 on Windows when using the native scanner.
- Garmin Connect account.
- iPhone/Android with Xiaomi Home **for the one-time initial S400 setup only**.

A remote VPS/datacenter cannot hear a scale in your home over Bluetooth. The Docker host must be physically near the scale, or you need a small gateway such as a Raspberry Pi near it.

---

# 2. One-time Xiaomi S400 setup

This is the only part that still needs Xiaomi Home, because S400 BLE advertisements are encrypted.

1. Install **Xiaomi Home** on your phone.
2. Sign in/create a Xiaomi account.
3. Add **Xiaomi Body Composition Scale S400**.
4. Keep **heart-rate measurement enabled** in Xiaomi Home.
5. Do one **complete measurement** barefoot and wait until the scale also completes the heart-rate phase.
6. Close Xiaomi Home after setup. During direct BLE use, the phone app should not be actively connected to the scale.

## Obtain `S400_MAC` and `S400_BLE_KEY`

Use the open-source **Xiaomi Cloud Tokens Extractor** from PiotrMachowski. The S400 instructions in `export2garmin` use it specifically to obtain the scale MAC address and BLE KEY.

Project:
`https://github.com/PiotrMachowski/Xiaomi-cloud-tokens-extractor`

On Windows, the upstream S400 guide points to its current `token_extractor.exe`. On Linux, run the extractor Python tool. Sign in to the same Xiaomi account, select the server where your S400 exists (often `de` for Europe), and find an entry similar to:

```text
NAME:     Xiaomi Body Composition Scale S400
BLE KEY:  0123456789abcdef0123456789abcdef
MAC:      AA:BB:CC:DD:EE:FF
MODEL:    yunmai.scales.ms104
```

Copy **BLE KEY** and **MAC**. You do not need to store the Xiaomi username/password in this repository.

Security: treat the BLE key as a password. Never commit it to Git.

After changing batteries, the upstream documentation recommends synchronising the scale with Xiaomi Home again. If you connect a **new Xiaomi Home profile** to the scale, the BLE key can be replaced; in that case extract the new key and update `.env`.

---

# 3. Prepare Bluetooth on the Docker host

Choose the section matching the deployment mode.

## Linux + Docker Engine

On Debian/Ubuntu/Raspberry Pi OS:

```bash
sudo apt update
sudo apt install -y bluez bluetooth rfkill
sudo systemctl enable --now bluetooth
sudo rfkill unblock bluetooth
```

Check the controller:

```bash
bluetoothctl list
```

You should see a controller. Then from this project run:

```bash
chmod +x scripts/*.sh
./scripts/check-host.sh
```

If the host has several Bluetooth adapters, identify the desired one with:

```bash
hciconfig -a
```

`hci0` means `HCI_INDEX=0`, `hci1` means `HCI_INDEX=1`, etc.

> BlueZ experimental mode: the upstream S400 instructions recommend starting `bluetoothd` with `--experimental`. Many recent BlueZ installations work without changing this. Try the project first. If BLE scanning fails despite the controller being visible, see **Troubleshooting** below.

## Windows + Docker Desktop

Docker Desktop runs Linux containers inside a Linux VM. The Windows Bluetooth stack is not exposed as `hci0` inside that VM, so this mode keeps BLE access in a native Windows process and uses the bind-mounted history file as the hand-off point.

Use a USB Bluetooth dongle. The Windows Bluetooth adapter must remain attached to Windows; do not attach the dongle to WSL with `usbipd` while the native scanner is running. Microsoft documents USB/IP for WSL, but this project does not need it in Windows mode: [`Connect USB devices`](https://learn.microsoft.com/en-us/windows/wsl/connect-usb).

Install the native scanner dependencies once:

```powershell
py -3.11 -m pip install --upgrade -r requirements-windows.txt
```

The project scripts start Docker Desktop if needed, wait for the Docker engine, start the Windows BLE scanner and then run Compose:

```powershell
.\scripts\start-windows.ps1
```

To start this automatically when the Windows user logs in:

```powershell
.\scripts\install-windows-autostart.ps1
```

Stop both processes with:

```powershell
.\scripts\stop-windows.ps1
```

Docker Desktop's USB/IP documentation applies to USB devices passed into the Docker Desktop VM and requires a separate USB/IP setup; it does not make the Windows Bluetooth API available as Linux BlueZ. See [`Using USB/IP with Docker Desktop`](https://docs.docker.com/desktop/features/usbip/).

---

# 4. Configure `.env`

```bash
cp .env.example .env
nano .env
chmod 600 .env
```

Fill in:

```dotenv
GARMIN_USERNAME=your@email.com
GARMIN_PASSWORD=your_garmin_password
GARMIN_IS_CN=false

S400_MAC=AA:BB:CC:DD:EE:FF
S400_BLE_KEY=0123456789abcdef0123456789abcdef

USER_SEX=male
USER_HEIGHT_CM=181
USER_BIRTHDATE=01-01-1990
USER_WEIGHT_MIN_KG=55
USER_WEIGHT_MAX_KG=110

HCI_INDEX=0
UPLOAD_HEART_RATE=false
TZ=Europe/Madrid
```

`USER_WEIGHT_MIN_KG` and `USER_WEIGHT_MAX_KG` are used by upstream `export2garmin` to decide which Garmin account owns a measurement. With one user, choose a sensible range around your actual weight.

The first container start logs into Garmin using your credentials and creates persistent OAuth tokens under `./data/garmin/`. Subsequent starts reuse those tokens instead of logging in every time.

---

# 5. Deploy

## Linux

```bash
make doctor
make up
make logs
```

Equivalent Docker command:

```bash
docker compose up -d --build
docker compose logs -f --tail=200 scale
```

The first build downloads the pinned `export2garmin` upstream revision and Python dependencies.

Expected startup includes messages indicating that the BLE adapter was detected and that the S400 module is enabled.

## Windows + Docker Desktop

```powershell
.\scripts\start-windows.ps1
```

Optional automatic start at Windows logon:

```powershell
.\scripts\install-windows-autostart.ps1
```

The scanner log is `data/windows-scanner.log`; Docker logs are available with `docker compose logs -f --tail=200 scale`.

---

# 6. First real test

1. Leave Xiaomi Home **closed**.
2. Keep the phone away from actively connecting to the scale.
3. Follow logs:

```bash
make logs
```

4. Step on the S400 barefoot.
5. Stay still until the complete measurement finishes, including heart rate.
6. The service should detect your S400 MAC, decrypt the advertisement and upload the body-composition record to Garmin Connect.

The upstream S400 scanner expects the complete set: mass, low impedance, high impedance and heart rate. If you step off too early, no complete record is uploaded.

You can also run a one-off BLE diagnostic while the main service is stopped:

```bash
make down
make test-ble
make up
```

---

# 7. Day-to-day use

Nothing to press and no scheduled cloud job:

```text
step on S400
   -> complete measurement
   -> BLE scanner captures the S400 advertisement
   -> decrypts data with the BLE key
   -> shared history receives a raw record
   -> Docker calculates metrics
   -> uploads to Garmin Connect
```

The scanner is continuous precisely because S400 broadcasts its measurement only briefly.

Useful commands:

```bash
make status
make logs
make restart
make down
make up
```

To recreate Garmin OAuth tokens:

```bash
make relogin-garmin
```

---

# 8. What reaches Garmin

Upstream `export2garmin` supports the S400 and uploads the following body-composition values to Garmin Connect when available/calculated:

- measurement date/time
- weight
- BMI
- body fat
- skeletal muscle mass
- bone mass
- body water
- physique rating
- visceral fat
- metabolic age
- basal metabolism

The S400 heart rate can optionally be sent to Garmin's blood-pressure area, but this project leaves that **disabled by default** because it is a workaround rather than a native Garmin scale heart-rate field. Enable only if you specifically want it:

```dotenv
UPLOAD_HEART_RATE=true
```

---

# 9. Troubleshooting

## `hci0 is not visible inside Docker`

This is expected in Windows mode. Check that `.env` contains `BLE_SOURCE=windows`, start the native scanner with `.\scripts\start-windows.ps1`, and inspect `data/windows-scanner.log`. Docker Desktop's Linux VM does not provide the Windows Bluetooth adapter as a Linux BlueZ controller.

For Linux mode, continue with the checks below.

Check on the host:

```bash
bluetoothctl list
hciconfig -a
sudo rfkill unblock bluetooth
sudo systemctl restart bluetooth
```

Then:

```bash
make doctor
make restart
```

## Scale appears but `Decryption failed`

The BLE key is wrong or was rotated. Re-run Xiaomi Cloud Tokens Extractor and replace `S400_BLE_KEY` in `.env`.

## It doesn't capture my weighing

- Xiaomi Home must not be actively connected to the scale.
- Keep the Linux host or Windows Bluetooth dongle near the S400.
- Do a **full measurement**, including heart rate.
- Do not disable heart-rate measurement in Xiaomi Home.
- Verify `S400_MAC`.
- On Linux, run `make down && make test-ble` and step on the scale during the test.
- On Windows, confirm that `data/windows-scanner.log` contains `Windows BLE scanner active` and no scan errors.

## Enable BlueZ experimental mode

Only do this if standard scanning fails. On a systemd Linux host, inspect your BlueZ unit and add `--experimental` to the `bluetoothd` command via a systemd override rather than editing vendor unit files directly. For example:

```bash
systemctl cat bluetooth.service
sudo systemctl edit bluetooth.service
```

Create an override matching your distro's `bluetoothd` path, then:

```bash
sudo systemctl daemon-reload
sudo systemctl restart bluetooth
```

Because the executable path varies by distribution, do not blindly copy a path from another system.

## Garmin authentication fails

Check credentials in `.env`, then:

```bash
make relogin-garmin
make logs
```

Garmin Connect is an unofficial API dependency in this integration and can change. OAuth tokens are persisted to reduce repeated logins and rate-limit risk.

---

# 10. Security

Read [`SECURITY.md`](SECURITY.md).

The important points are: no ports are published, `.env` is ignored by Git, Garmin tokens and measurement history are local under `./data`, the Windows scanner keeps the BLE key on the local machine, and the Linux compose mode uses only the Bluetooth-related capabilities required instead of `privileged: true`.

---

# Upstream projects

This deployment wraps:

- `RobertWojtowicz/export2garmin`
- `Bluetooth-Devices/xiaomi-ble`
- `cyberjunky/python-garminconnect`
- `PiotrMachowski/Xiaomi-cloud-tokens-extractor` for the one-time BLE-key extraction

`export2garmin` is pinned by default to commit:

```text
3761f07b3efb328ac02f7d576c83985cecb93001
```

You can override the build arg `EXPORT2GARMIN_COMMIT`, but test before changing it because upstream configuration/code can change.
