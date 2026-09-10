#!/usr/bin/env python3
import os
import sys
from pathlib import Path
from garminconnect import Garmin

email = os.environ["GARMIN_USERNAME"].strip()
password = os.environ["GARMIN_PASSWORD"]
is_cn = os.environ.get("GARMIN_IS_CN", "false").lower() in {"1", "true", "yes", "on"}
token_dir = Path("/persist/garmin") / email

token_dir.parent.mkdir(parents=True, exist_ok=True)

if token_dir.exists() and any(token_dir.iterdir()):
    print(f"Garmin OAuth tokens already exist for {email}; reusing them.")
    sys.exit(0)

print(f"Creating Garmin OAuth tokens for {email} ...")
garmin = Garmin(email, password, is_cn=is_cn)
garmin.login(str(token_dir))
print("Garmin OAuth tokens created successfully.")
