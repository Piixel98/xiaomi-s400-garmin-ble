FROM debian:trixie-slim

ARG EXPORT2GARMIN_COMMIT=3761f07b3efb328ac02f7d576c83985cecb93001
ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

RUN apt-get update && apt-get install -y --no-install-recommends \
      bash ca-certificates git make gcc build-essential python3 python3-pip python3-venv \
      bluez bluetooth rfkill libglib2.0-dev libssl-dev libjpeg-dev \
      procmail bc sudo kmod procps tzdata \
    && rm -rf /var/lib/apt/lists/*

RUN git clone https://github.com/RobertWojtowicz/export2garmin.git /opt/export2garmin \
    && cd /opt/export2garmin \
    && git checkout "$EXPORT2GARMIN_COMMIT"

RUN python3 -m pip install --break-system-packages --no-cache-dir \
      bluepy garminconnect bleak xiaomi-ble requests pycryptodome \
      charset-normalizer pillow colorama

COPY scripts/entrypoint.sh /usr/local/bin/entrypoint.sh
COPY scripts/bootstrap_garmin.py /usr/local/bin/bootstrap_garmin.py
RUN chmod 0755 /usr/local/bin/entrypoint.sh /usr/local/bin/bootstrap_garmin.py \
    && chmod 0755 /opt/export2garmin/import_data.sh

WORKDIR /opt/export2garmin
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
