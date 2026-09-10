#!/usr/bin/env bash
set -euo pipefail

docker compose run --rm --entrypoint bash scale -lc '
  echo "Controllers visible in container:";
  hcitool dev;
  echo;
  echo "Testing S400 scan. Step on the scale now and wait for a COMPLETE measurement including heart rate.";
  python3 -B /opt/export2garmin/miscale/s400_ble.py -a "${HCI_INDEX}";
'
