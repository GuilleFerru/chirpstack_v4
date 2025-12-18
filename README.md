# ChirpStack Docker example

This repository contains a skeleton to setup the [ChirpStack](https://www.chirpstack.io)
open-source LoRaWAN Network Server (v4) using [Docker Compose](https://docs.docker.com/compose/).

**Note:** Please use this `docker-compose.yml` file as a starting point for testing
but keep in mind that for production usage it might need modifications. 

## Quick Start (Instalación Automática)

### Opción 1: Instalación completa automática (recomendado para VMs nuevas)
```bash
git clone https://github.com/GuilleFerru/chirpstack_v4.git
cd chirpstack_v4
sudo chmod +x scripts/setup.sh
sudo ./scripts/setup.sh
```

Este script automáticamente:
- ✅ Instala Docker y Docker Compose
- ✅ Instala herramientas necesarias (make, cfssl, etc.)
- ✅ Genera certificados CA (válidos por **5 años**)
- ✅ Inicia todos los servicios de ChirpStack
- ✅ Importa todos los dispositivos LoRaWAN

### Opción 2: Instalación manual (si ya tienes Docker)
```bash
git clone https://github.com/GuilleFerru/chirpstack_v4.git
cd chirpstack_v4

# Generar certificados (válidos por 5 años)
chmod +x scripts/02_generate-certs.sh
./scripts/02_generate-certs.sh

# Iniciar servicios
docker compose up -d

# Importar dispositivos LoRaWAN (opcional)
make import-lorawan-devices
```

### Acceder a ChirpStack
- **URL:** http://localhost:8080
- **Usuario:** `admin`
- **Contraseña:** `admin`

## Gestión de Certificados

### Información sobre los certificados

Los certificados CA generados tienen una **validez de 5 años** desde su fecha de creación.

- **Ubicación:** `configuration/chirpstack/certs/`
- **Archivos:**
  - `ca.pem` - Certificado de autoridad certificadora (público)
  - `ca-key.pem` - Clave privada de la CA (privado)
  - `mqtt-server.pem` - Certificado del servidor Mosquitto (público)
  - `mqtt-server-key.pem` - Clave privada del servidor Mosquitto (privado)

### Generar certificados iniciales

Si es la primera vez o no tienes certificados:

```bash
# 1. Generar certificados CA
make generate-certs

# 2. Generar certificados del servidor MQTT
make generate-mqtt-certs
```

O directamente:

```bash
chmod +x scripts/02_generate-certs.sh
./scripts/02_generate-certs.sh
```

### Renovar certificados existentes

Cuando los certificados estén próximos a expirar o necesites regenerarlos:

```bash
make renew-certs
```

O directamente:

```bash
chmod +x scripts/03_renew-certs.sh
./scripts/03_renew-certs.sh
```

Este script:
1. ✅ Hace backup automático de certificados existentes
2. ✅ Genera nuevos certificados (válidos 5 años)
3. ✅ Los coloca en el directorio correcto
4. ✅ Configura permisos adecuados

**⚠️ IMPORTANTE:** Después de renovar los certificados CA:

1. Reinicia ChirpStack:
   ```bash
   docker compose restart chirpstack
   ```

2. Regenera los certificados de tus aplicaciones:
   - Ve a: **Applications → [Tu App] → Integrations**
   - Haz clic en **"Generate certificate"**
   - Descarga los nuevos certificados
   - Actualiza tu cliente MQTT con los nuevos certificados

### Verificar validez de certificados

Para ver cuándo expiran tus certificados actuales:

```bash
openssl x509 -in configuration/chirpstack/certs/ca.pem -noout -dates
```

Esto mostrará:
```
notBefore=Dec 17 18:19:34 2025 GMT
notAfter=Dec 17 18:19:34 2030 GMT
```

## Comandos útiles

```bash
make start                    # Iniciar servicios
make stop                     # Detener servicios
make restart                  # Reiniciar servicios
make logs                     # Ver logs en tiempo real
make import-lorawan-devices   # Importar dispositivos LoRaWAN
make generate-certs           # Generar certificados CA iniciales
make generate-mqtt-certs      # Generar certificados del servidor MQTT
make renew-certs              # Renovar certificados existentes
```

## Conexiones MQTT

### Puerto 1883 (Sin cifrado)
- Uso interno entre contenedores Docker
- ChirpStack ↔ Mosquitto
- Gateway Bridges ↔ Mosquitto

### Puerto 1884 (TLS/SSL)
- Conexiones externas seguras
- Requiere certificados de cliente
- Uso desde Node-RED, aplicaciones externas, dispositivos IoT

Para conectarte desde un cliente externo:
1. Genera certificado de cliente desde ChirpStack UI: **Applications → [App] → Integrations → MQTT → Generate TLS Certificate**
2. Descarga los 3 archivos (CA, Certificate, Key)
3. Configura tu cliente MQTT con:
   - Server: `IP_DEL_SERVIDOR:1884`
   - CA Certificate: `ca.pem`
   - Client Certificate: (descargado de ChirpStack)
   - Client Key: (descargado de ChirpStack)

## Directory layout

* `docker-compose.yml`: the docker-compose file containing the services
* `configuration/chirpstack`: directory containing the ChirpStack configuration files
* `configuration/chirpstack/certs`: certificados CA (no incluidos en git)
* `configuration/chirpstack-gateway-bridge`: directory containing the ChirpStack Gateway Bridge configuration
* `configuration/mosquitto`: directory containing the Mosquitto (MQTT broker) configuration
* `configuration/postgresql/initdb/`: directory containing PostgreSQL initialization scripts
* `scripts/`: scripts de instalación y configuración
  * `setup.sh` - Instalación completa automática
  * `01_install_docker.sh` - Solo instalar Docker
  * `02_generate-certs.sh` - Generar certificados CA iniciales
  * `03_renew-certs.sh` - Renovar certificados existentes
  * `04_generate-mqtt-server-certs.sh` - Generar certificados del servidor MQTT

## Configuration

This setup is pre-configured for all regions. You can either connect a ChirpStack Gateway Bridge
instance (v3.14.0+) to the MQTT broker (port 1883) or connect a Semtech UDP Packet Forwarder.
Please note that:

* You must prefix the MQTT topic with the region.
  Please see the region configuration files in the `configuration/chirpstack` for a list
  of topic prefixes (e.g. eu868, us915_0, au915_0, as923_2, ...).
* The protobuf marshaler is configured.

This setup also comes with two instances of the ChirpStack Gateway Bridge. One
is configured to handle the Semtech UDP Packet Forwarder data (port 1700), the
other is configured to handle the Basics Station protocol (port 3001). Both
instances are by default configured for EU868 (using the `eu868` MQTT topic
prefix).

### Reconfigure regions

ChirpStack has at least one configuration of each region enabled. You will find
the list of `enabled_regions` in `configuration/chirpstack/chirpstack.toml`.
Each entry in `enabled_regions` refers to the `id` that can be found in the
`region_XXX.toml` file. This `region_XXX.toml` also contains a `topic_prefix`
configuration which you need to configure the ChirpStack Gateway Bridge
UDP instance (see below).

#### ChirpStack Gateway Bridge (UDP)

Within the `docker-compose.yml` file, you must replace the `eu868` prefix in the
`INTEGRATION__..._TOPIC_TEMPLATE` configuration with the MQTT `topic_prefix` of
the region you would like to use (e.g. `us915_0`, `au915_0`, `in865`, ...).

#### ChirpStack Gateway Bridge (Basics Station)

Within the `docker-compose.yml` file, you must update the configuration file
that the ChirpStack Gateway Bridge instance must used. The default is
`chirpstack-gateway-bridge-basicstation-eu868.toml`. For available
configuration files, please see the `configuration/chirpstack-gateway-bridge`
directory.

# Data persistence

PostgreSQL and Redis data is persisted in Docker volumes, see the `docker-compose.yml`
`volumes` definition.

## Requirements

Before using this `docker-compose.yml` file, make sure you have [Docker](https://www.docker.com/community-edition)
installed.

## Importing device repository

To import the [lorawan-devices](https://github.com/TheThingsNetwork/lorawan-devices)
repository (optional step), run the following command:

```bash
make import-lorawan-devices
```

This will clone the `lorawan-devices` repository and execute the import command of ChirpStack.
Please note that for this step you need to have the `make` command installed.

**Note:** an older snapshot of the `lorawan-devices` repository is cloned as the
latest revision no longer contains a `LICENSE` file.

## Usage

To start the ChirpStack simply run:

```bash
$ docker-compose up
```

After all the components have been initialized and started, you should be able
to open http://localhost:8080/ in your browser.

##

The example includes the [ChirpStack REST API](https://github.com/chirpstack/chirpstack-rest-api).
You should be able to access the UI by opening http://localhost:8090 in your browser.

**Note:** It is recommended to use the [gRPC](https://www.chirpstack.io/docs/chirpstack/api/grpc.html)
interface over the [REST](https://www.chirpstack.io/docs/chirpstack/api/rest.html) interface.
