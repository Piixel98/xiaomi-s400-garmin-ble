#!/usr/bin/env bash
set -euo pipefail
source .env
safe_email=${GARMIN_USERNAME:?GARMIN_USERNAME missing}
echo "Removing stored OAuth tokens for $safe_email. They will be recreated on next start."
rm -rf "./data/garmin/$safe_email"
docker compose restart scale
