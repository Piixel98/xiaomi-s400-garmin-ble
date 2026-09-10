#!/usr/bin/env bash
set -euo pipefail

APP=/opt/export2garmin
PERSIST=/persist

required=(GARMIN_USERNAME GARMIN_PASSWORD S400_MAC S400_BLE_KEY USER_SEX USER_HEIGHT_CM USER_BIRTHDATE USER_WEIGHT_MIN_KG USER_WEIGHT_MAX_KG)
if [[ "${BLE_SOURCE:-linux}" == "linux" ]]; then
  required+=(HCI_INDEX)
fi
for var in "${required[@]}"; do
  if [[ -z "${!var:-}" ]]; then
    echo "ERROR: missing required environment variable: $var" >&2
    exit 2
  fi
done

if [[ ! "$S400_MAC" =~ ^([[:xdigit:]]{2}:){5}[[:xdigit:]]{2}$ ]]; then
  echo "ERROR: S400_MAC must look like AA:BB:CC:DD:EE:FF" >&2
  exit 2
fi
if [[ ! "$S400_BLE_KEY" =~ ^[[:xdigit:]]{32}$ ]]; then
  echo "ERROR: S400_BLE_KEY must be exactly 32 hexadecimal characters" >&2
  exit 2
fi
if [[ ! "$USER_SEX" =~ ^(male|female)$ ]]; then
  echo "ERROR: USER_SEX must be male or female (upstream export2garmin format)." >&2
  exit 2
fi

mkdir -p "$PERSIST/garmin" "$PERSIST/history"
chmod 700 "$PERSIST/garmin" || true

# Verify the Bluetooth controller only when the scanner runs in Linux. In
# Windows mode the native host scanner writes completed S400 records to the
# shared persistent history file and this container only uploads them.
if [[ "${BLE_SOURCE:-linux}" == "linux" ]]; then
  if ! hcitool dev | grep -q "hci${HCI_INDEX}"; then
    echo "ERROR: hci${HCI_INDEX} is not visible inside Docker." >&2
    echo "Run ./scripts/check-host.sh on the host and verify BlueZ is running." >&2
    exit 3
  fi
fi

# Generate upstream configuration from .env.
pulse=off
[[ "${UPLOAD_HEART_RATE:-false}" =~ ^(1|true|yes|on)$ ]] && pulse=on
cn=False
[[ "${GARMIN_IS_CN:-false}" =~ ^(1|true|yes|on)$ ]] && cn=True

cat > "$APP/user/export2garmin.cfg" <<CFG
switch_wifi_watchdog=off
switch_temp_path=/dev/shm
switch_bt=on
ble_arg_hci=${HCI_INDEX}
ble_arg_hci2mac=off
ble_arg_mac=00:00:00:00:00:00
ble_adapter_time=10
ble_adapter_check=off
ble_adapter_repeat=7
tokens_is_cn=${cn}

ble_miscale_mac=${S400_MAC^^}
miscale_export_user1=("${USER_SEX}", ${USER_HEIGHT_CM}, "${USER_BIRTHDATE}", "${GARMIN_USERNAME}", ${USER_WEIGHT_MAX_KG}, ${USER_WEIGHT_MIN_KG})

switch_miscale=off
miscale_time_offset=0
miscale_time_unsync=1200
miscale_time_check=30
switch_mqtt=off
miscale_mqtt_passwd=unused
miscale_mqtt_user=unused

switch_s400=on
ble_miscale_key=${S400_BLE_KEY}
switch_s400_hci=off
s400_arg_hci=${HCI_INDEX}
s400_arg_hci2mac=off
s400_arg_mac=00:00:00:00:00:00
s400_pulse=${pulse}

switch_omron=off
omron_omblepy_model=hem-7155t
omron_omblepy_mac=00:00:00:00:00:00
omron_omblepy_time=10
omron_omblepy_debug=off
omron_omblepy_all=off
omron_export_user1=unused@example.com
omron_export_user2=unused@example.com
omron_export_category=eu
CFG

if [[ "${BLE_SOURCE:-linux}" == "windows" ]]; then
  # import_data.sh still owns the Garmin upload loop, but must not attempt a
  # Linux BLE scan from Docker Desktop. The Windows companion scanner feeds
  # the same persistent miscale_backup.csv file.
  sed -i 's/^switch_bt=.*/switch_bt=off/' "$APP/user/export2garmin.cfg"
fi

# The current garminconnect client rejects symlinked token stores. Keep a
# regular application directory and synchronize its token file to persistent
# storage instead.
token_persist="$PERSIST/garmin/${GARMIN_USERNAME}"
token_app="$APP/user/${GARMIN_USERNAME}"
rm -rf "$token_app"
mkdir -p "$token_app"

# Persist measurement history across container rebuilds/restarts. Keep the
# application file linked to the persistent file so the native Windows BLE
# scanner and the container share it without a polling/copy race.
history_file="$PERSIST/history/miscale_backup.csv"
if [[ ! -f "$history_file" ]]; then
  printf '%s\n' 'Data Status;Unix Time;Date [dd.mm.yyyy];Time [hh:mm];Weight [kg];Change [kg];BMI;Body Fat [%];Skeletal Muscle Mass [kg];Bone Mass [kg];Body Water [%];Physique Rating;Visceral Fat;Metabolic Age [years];BMR [kCal];LBM [kg];Ideal Wieght [kg];Fat Mass To Ideal [type:mass kg];Protein [%];Impedance;Email User;Upload Date [dd.mm.yyyy];Upload Time [hh:mm];Difference Time [s];Impedance Low;Heart Rate [bpm]' > "$history_file"
fi
rm -f "$APP/user/miscale_backup.csv"
ln -s "$history_file" "$APP/user/miscale_backup.csv"

/usr/local/bin/bootstrap_garmin.py

if [[ -f "$token_persist/garmin_tokens.json" ]]; then
  cp "$token_persist/garmin_tokens.json" "$token_app/garmin_tokens.json"
fi

sync_garmin_tokens() {
  if [[ -f "$token_app/garmin_tokens.json" ]]; then
    cp "$token_app/garmin_tokens.json" "$token_persist/garmin_tokens.json.tmp"
    mv "$token_persist/garmin_tokens.json.tmp" "$token_persist/garmin_tokens.json"
  fi
}

# Keep OAuth tokens synchronized while the upstream loop runs. The history file
# is already a symlink to persistent storage, so copying it every few seconds
# would needlessly replace the file and look like a new measurement.
mirror_history() {
  while true; do
    sleep 15
    sync_garmin_tokens
  done
}
mirror_history &

cleanup() {
  if [[ -f "$APP/user/miscale_backup.csv" ]]; then
    cp "$APP/user/miscale_backup.csv" "$PERSIST/history/miscale_backup.csv" || true
  fi
  sync_garmin_tokens || true
}
trap cleanup EXIT TERM INT

echo ""
echo "Xiaomi S400 BLE -> Garmin service started"
if [[ "${BLE_SOURCE:-linux}" == "windows" ]]; then
  echo "BLE source: Windows native scanner; waiting for new measurements"
else
  echo "BLE source: Linux BlueZ hci${HCI_INDEX}; connected and scanning"
fi
echo ""

if [[ "${BLE_SOURCE:-linux}" == "windows" ]]; then
  # With native Windows BLE, import_data.sh must not run its Linux scanner.
  # Wait silently for the Windows companion to append a new raw measurement,
  # then expose only the useful synchronization result in container logs.
  history_signature() {
    stat -c '%s:%Y' "$PERSIST/history/miscale_backup.csv" 2>/dev/null || true
  }

  report_import() {
    local import_log=/dev/shm/import_data.log
    local output

    if grep -Eq 'Calculating data from import|Upload to Garmin Connect' "$import_log"; then
      output=$(grep -E 'Calculating data from import|Upload to Garmin Connect' "$import_log" || true)
      printf '%s\n' "$output"
    elif grep -Eq 'ERROR|Error|failed|Failed|Exception|Traceback|authentication|Authentication' "$import_log"; then
      echo "ERROR: Garmin synchronization failed; diagnostic follows:"
      grep -E 'ERROR|Error|failed|Failed|Exception|Traceback|authentication|Authentication' "$import_log" | tail -n 20
    fi
  }

  last_history_signature=$(history_signature)
  if grep -q '^to_import;' "$PERSIST/history/miscale_backup.csv" 2>/dev/null; then
    # Retry a pending measurement left by a previous interrupted run.
    last_history_signature=''
  fi

  while true; do
    current_history_signature=$(history_signature)
    if [[ -n "$current_history_signature" && "$current_history_signature" != "$last_history_signature" ]]; then
      last_history_signature="$current_history_signature"
      "$APP/import_data.sh" > /dev/shm/import_data.log 2>&1 || true
      report_import
      sync_garmin_tokens
    fi
    sleep 1
  done
else
  exec "$APP/import_data.sh" -l
fi
