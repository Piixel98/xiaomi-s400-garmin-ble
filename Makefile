.PHONY: up down restart logs status build doctor test-ble relogin-garmin update windows-up windows-down windows-autostart

up:
	docker compose up -d --build

down:
	docker compose down

restart:
	docker compose restart scale

logs:
	docker compose logs -f --tail=200 scale

status:
	docker compose ps

build:
	docker compose build --pull

doctor:
	./scripts/check-host.sh

test-ble:
	./scripts/test-ble.sh

relogin-garmin:
	./scripts/relogin-garmin.sh

update:
	docker compose build --pull --no-cache && docker compose up -d

windows-up:
	powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\start-windows.ps1

windows-down:
	powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\stop-windows.ps1

windows-autostart:
	powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\install-windows-autostart.ps1
