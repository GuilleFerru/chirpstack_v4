import-lorawan-devices:
	docker compose run --rm --entrypoint sh --user root chirpstack -c '\
		apk add --no-cache git && \
		git clone https://github.com/brocaar/lorawan-devices /tmp/lorawan-devices && \
		chirpstack -c /etc/chirpstack import-legacy-lorawan-devices-repository -d /tmp/lorawan-devices'

setup:
	chmod +x scripts/setup.sh && sudo scripts/setup.sh

generate-certs:
	chmod +x scripts/02_generate-certs.sh && scripts/02_generate-certs.sh

generate-mqtt-certs:
	chmod +x scripts/04_generate-mqtt-server-certs.sh && scripts/04_generate-mqtt-server-certs.sh

renew-certs:
	chmod +x scripts/03_renew-certs.sh && scripts/03_renew-certs.sh

start:
	docker compose up -d

stop:
	docker compose down

logs:
	docker compose logs -f

restart:
	docker compose restart
