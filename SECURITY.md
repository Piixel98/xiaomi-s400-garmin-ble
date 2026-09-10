# Security notes

This project does not expose an HTTP service or publish any TCP/UDP ports.

Linux mode gives the container Bluetooth access through the host network namespace and host BlueZ D-Bus socket, and grants `NET_ADMIN` + `NET_RAW`. Windows mode keeps Bluetooth in the native Windows scanner and gives the container only the shared history file. These permissions and data paths deserve care, so:

- Run it only on a trusted Linux host.
- Prefer a small Raspberry Pi / mini-PC near the scale instead of a public-facing production server.
- Do not set `privileged: true`; this compose file intentionally avoids it.
- Keep `.env` out of Git and use `chmod 600 .env`.
- The Xiaomi BLE key is a secret. Do not publish it.
- Garmin credentials are used to bootstrap OAuth tokens. The tokens persist under `./data/garmin/`.
- Restrict `./data`: `chmod -R go-rwx data`.
- Keep Docker, BlueZ and the host OS patched.
- Do not expose Docker's daemon socket to this container.
- In Windows mode, keep the USB dongle attached to Windows while `windows_s400_scanner.py` is running. Do not share the same dongle with WSL at the same time.

If you rotate/re-pair the S400 with a new Xiaomi Home profile, Xiaomi may replace the BLE key. Extract the new key and update `.env`.
