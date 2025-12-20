# ChirpStack v4 - Network Server LoRaWAN

Servidor de Red LoRaWAN open-source basado en ChirpStack v4, configurado con soporte multi-región, seguridad TLS/mTLS y gestión automática de certificados.

---

## 📋 Tabla de Contenidos

- [Características Principales](#características-principales)
- [Requisitos del Sistema](#requisitos-del-sistema)
- [Instalación](#instalación)
- [Arquitectura del Sistema](#arquitectura-del-sistema)
- [Configuración de Seguridad](#configuración-de-seguridad)
- [Conexión de Gateways](#conexión-de-gateways)
- [Integración con Aplicaciones](#integración-con-aplicaciones)
- [Gestión de Certificados](#gestión-de-certificados)
- [Comandos Útiles](#comandos-útiles)
- [Resolución de Problemas](#resolución-de-problemas)

---

## 🚀 Características Principales

### Región LoRaWAN Soportada
- **AU915** (Australia) - 8 sub-bandas (0-7)

### Seguridad Implementada

#### 1. Gateway → Network Server

El gateway puede conectarse de **dos formas**:

**Opción A: Tipo Semtech (UDP Packet Forwarder)**
- **Protocolo:** UDP sin cifrado
- **Puerto:** 1700/UDP
- **Ventajas:** Simple, compatible con todos los gateways LoRaWAN
- **Desventajas:** Sin cifrado, menos seguro

**Opción B: Tipo ChirpStack-v4 (MQTT con TLS)**
- **Protocolo:** MQTT sobre TLS con autenticación mutua (mTLS)
- **Puerto:** 1884/TCP
- **Certificados requeridos:** ca.crt, client.crt, client.key
- **Ventajas:** Conexión cifrada y segura
- **Desventajas:** Requiere configuración de certificados en el gateway
- **Compatible con:** Milesight UG65/UG67/UG87 y otros que soporten mTLS

#### 2. Network Server → Aplicaciones Externas
- **Protocolo:** MQTT sobre TLS con autenticación mutua (mTLS)
- **Puerto:** 1884 (externo, cifrado)
- **Certificados:** Generados desde ChirpStack UI
- **Validez:** 50 años

### Componentes del Sistema
- **ChirpStack v4** - Network Server (NS + Application Server + Join Server)
- **ChirpStack Gateway Bridge** - Traducción UDP Packet Forwarder → MQTT
- **PostgreSQL 14** - Base de datos
- **Redis 7** - Cache y gestión de estado
- **Mosquitto 2** - Broker MQTT con soporte TLS/mTLS
- **ChirpStack REST API** - API HTTP alternativa

---

## 💻 Requisitos del Sistema

### Hardware
- **CPU:** 2 cores mínimo (4 recomendado)
- **RAM:** 4 GB mínimo (8 GB recomendado)
- **Disco:** 20 GB de espacio libre
- **Red:** Conectividad a Internet para instalación

### Software
- **Sistema Operativo:** Ubuntu 20.04/22.04, Debian 10/11, o similar
- **Docker:** Versión 20.10 o superior (instalado automáticamente)
- **Docker Compose:** Versión 2.0 o superior (instalado automáticamente)

### Puertos Requeridos
| Puerto | Protocolo | Uso | Externo |
|--------|-----------|-----|---------|
| 1700/UDP | UDP | Gateway tipo Semtech | ✅ Sí |
| 1883 | MQTT | Broker interno (sin cifrado) | ❌ No |
| 1884 | MQTT/TLS | Gateway tipo ChirpStack-v4 + Apps externas | ✅ Sí |
| 8080 | HTTP | ChirpStack Web UI | ✅ Sí |
| 8090 | HTTP | ChirpStack REST API | ⚠️ Opcional |

---

## 📦 Instalación

### Opción 1: Instalación Automática Completa (Recomendada)

Para una VM nueva sin Docker instalado:

```bash
# 1. Clonar el repositorio
git clone https://github.com/GuilleFerru/chirpstack_v4.git
cd chirpstack_v4

# 2. Ejecutar instalación automática
sudo chmod +x scripts/setup.sh
sudo ./scripts/setup.sh
```

**Este script realiza automáticamente:**
1. ✅ Instalación de Docker y Docker Compose
2. ✅ Instalación de herramientas necesarias (make, git, curl, openssl, cfssl)
3. ✅ Generación de certificados CA (válidos por 50 años)
4. ✅ Configuración de permisos
5. ✅ Inicio de todos los servicios
6. ✅ Verificación del estado de los contenedores

**Duración:** 5-10 minutos (depende de la conexión a Internet)

---

### Opción 2: Instalación Manual (Con Docker Ya Instalado)

Si ya tenés Docker y Docker Compose instalados:

```bash
# 1. Clonar el repositorio
git clone https://github.com/GuilleFerru/chirpstack_v4.git
cd chirpstack_v4

# 2. Generar certificados CA (válidos por 50 años)
chmod +x scripts/02_generate-certs.sh
./scripts/02_generate-certs.sh

# 3. Generar certificados del servidor MQTT
chmod +x scripts/04_generate-mqtt-server-certs.sh
./scripts/04_generate-mqtt-server-certs.sh

# 4. Iniciar servicios
docker compose up -d

# 5. Verificar estado
docker compose ps

# 6. (Opcional) Importar repositorio de dispositivos LoRaWAN
make import-lorawan-devices
```

---

### Acceso a la Interfaz Web

Una vez completada la instalación:

- **URL:** `http://<IP_DEL_SERVIDOR>:8080`
- **Usuario por defecto:** `admin`
- **Contraseña por defecto:** `admin`

⚠️ **IMPORTANTE:** Cambiá la contraseña después del primer login:
1. Ir a: **User → Change Password**
2. Establecer una contraseña segura

---

## 🏗️ Arquitectura del Sistema

```
┌────────────────────────────────────────────────────────────────────────┐
│                        ChirpStack v4 Network Server                     │
│                                                                         │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐            │
│  │  ChirpStack  │◄───│ PostgreSQL   │    │    Redis     │            │
│  │  (NS/AS/JS)  │    │   Database   │    │    Cache     │            │
│  └───────┬──────┘    └──────────────┘    └──────────────┘            │
│          │                                                             │
│          │ MQTT interno (puerto 1883)                                  │
│          ▼                                                             │
│  ┌─────────────────────────────────────────────────────┐             │
│  │          Mosquitto MQTT Broker                       │             │
│  │                                                      │             │
│  │  ┌──────────────────┐      ┌──────────────────┐   │             │
│  │  │  Puerto 1883     │      │  Puerto 1884     │   │             │
│  │  │  (Sin cifrado)   │      │  (TLS/mTLS)      │   │             │
│  │  │  Interno Docker  │      │  Externo         │   │             │
│  │  └────────┬─────────┘      └────────┬─────────┘   │             │
│  └───────────┼────────────────────────┼──────────────┘             │
│              │                         │                              │
└──────────────┼─────────────────────────┼──────────────────────────────┘
               │                         │
               ▼                         ▼
     ┌──────────────────┐     ┌──────────────────────┐
     │ Gateway Bridge   │     │ Aplicaciones Externas│
     │ (UDP → MQTT)     │     │                      │
     └────────┬─────────┘     │ • Node-RED           │
              │               │ • ThingsBoard        │
              ▼               │ • Grafana            │
     ┌──────────────────┐     │ • Custom Apps        │
     │ Gateways         │     └──────────────────────┘
     │ (Milesight, etc) │
     │                  │     Requiere certificados:
     │ UDP Port 1700    │     • ca.crt
     └──────────────────┘     • client.crt
                              • client.key
```

---

## 🔒 Configuración de Seguridad

### Sistema de Certificados

Este sistema utiliza una **Infraestructura de Clave Pública (PKI)** propia basada en:

1. **CA (Autoridad Certificadora)** - Certificado raíz que firma todos los demás
2. **Certificados de Servidor** - Para servicios (Mosquitto MQTT)
3. **Certificados de Cliente** - Para aplicaciones y dispositivos

#### Ubicación de Certificados

```
configuration/chirpstack/certs/
├── ca.pem                          # Certificado CA (público)
├── ca-key.pem                      # Clave privada CA (privado)
├── mqtt-server.pem                 # Certificado servidor Mosquitto
├── mqtt-server-key.pem             # Clave privada servidor Mosquitto
└── (otros certificados generados desde UI)
```

⚠️ **SEGURIDAD:** Los archivos `*-key.pem` son privados y **nunca deben compartirse**.

---

### Generación Inicial de Certificados

#### Paso 1: Generar CA (Autoridad Certificadora)

```bash
# Usando el script automático
./scripts/02_generate-certs.sh
```

Este certificado:
- **Validez:** 50 años
- **Uso:** Firmar todos los certificados de cliente y servidor
- **Ubicación:** `configuration/chirpstack/certs/ca.pem`

#### Paso 2: Generar Certificado del Servidor MQTT

```bash
./scripts/04_generate-mqtt-server-certs.sh
```

El script te preguntará:
1. **¿Deseas ingresar la IP pública manualmente?** → Responder `y` e ingresar tu IP pública
2. Genera certificado con SANs (Subject Alternative Names) incluyendo:
   - IP interna (192.168.x.x)
   - IP pública (la que ingresaste)
   - localhost
   - Nombre del hostname

**Importante:** La IP pública debe estar en los SANs para que las conexiones externas funcionen.

#### Verificar Certificados Generados

```bash
# Ver detalles del CA
openssl x509 -in configuration/chirpstack/certs/ca.pem -noout -text

# Ver fechas de validez
openssl x509 -in configuration/chirpstack/certs/ca.pem -noout -dates

# Ver SANs del certificado MQTT
openssl x509 -in configuration/chirpstack/certs/mqtt-server.pem -noout -text | grep -A1 "Subject Alternative Name"
```

#### Reiniciar Servicios

Después de generar los certificados:

```bash
docker compose down
docker compose up -d
```

---

## 📡 Conexión de Gateways

### Tipos de Conexión Soportados

ChirpStack v4 soporta **dos tipos de conexión** para gateways:

#### Tipo 1: Semtech (UDP Packet Forwarder) - Recomendado para comenzar
- **Puerto:** 1700/UDP
- **Seguridad:** Sin cifrado
- **Ventajas:** Configuración simple, universalmente compatible
- **Usar cuando:** Querés una configuración rápida y simple

#### Tipo 2: ChirpStack-v4 (MQTT con TLS) - Mayor seguridad
- **Puerto:** 1884/TCP  
- **Seguridad:** TLS/mTLS con certificados
- **Ventajas:** Conexión cifrada y autenticada
- **Usar cuando:** Necesitás máxima seguridad o el gateway está en Internet público

---

### Configuración en ChirpStack UI

#### 1. Registrar el Gateway

1. Ir a: **Gateways → Add Gateway**
2. Completar:
   - **Gateway EUI:** El EUI del gateway (formato: `0123456789ABCDEF`)
   - **Gateway name:** Nombre descriptivo
   - **Gateway description:** (opcional)
3. Clic en **Submit**

---

### Configuración en Gateway Milesight (Ejemplo: UG67)

#### Opción A: Tipo Semtech (UDP - Más Simple)

1. Acceder a la interfaz web del gateway
2. Ir a: **Packet Forwarder → General**
3. Configurar:

| Parámetro | Valor |
|-----------|-------|
| **Enable** | ☑ Activar |
| **Type** | Semtech |
| **Server Address** | IP o dominio del servidor ChirpStack |
| **Port Up** | 1700 |
| **Port Down** | 1700 |

4. Guardar y el gateway se conectará automáticamente

---

#### Opción B: Tipo ChirpStack-v4 (MQTT con TLS - Más Seguro)

**Prerequisito:** Generar certificados desde ChirpStack UI (ver sección siguiente)

1. Acceder a la interfaz web del gateway
2. Ir a: **Packet Forwarder → General**
3. Configurar:

| Parámetro | Valor |
|-----------|-------|
| **Enable** | ☑ Activar |
| **Type** | ChirpStack-v4 |
| **Server Address** | IP o dominio del servidor ChirpStack |
| **MQTT Port** | 1884 |
| **Region ID** | au915_1 (o la región que uses) |
| **User Credentials** | ☐ Desactivar |
| **TLS Authentication** | ☑ Activar |
| **Mode** | Self signed certificates |
| **CA File** | (Subir ca.crt) |
| **Client Certificate File** | (Subir client.crt) |
| **Client Key File** | (Subir client.key) |

4. Guardar y el gateway se conectará por MQTT cifrado

---

#### Generar Certificados para ChirpStack-v4 Type

Si elegiste la **Opción B (ChirpStack-v4)**, necesitás generar certificados:

1. En ChirpStack UI, ir a: **Gateways → [Tu Gateway] → Certificates**
2. Clic en: **Generate Gateway Certificate**
3. Descargar los 3 archivos:
   - `ca.crt` - Certificado CA
   - `client.crt` - Certificado del gateway
   - `client.key` - Clave privada del gateway
4. En la interfaz del gateway Milesight:
   - **CA File:** Subir `ca.crt`
   - **Client Certificate File:** Subir `client.crt`  
   - **Client Key File:** Subir `client.key`
5. Guardar configuración

#### 2. Configuración de Región

Ir a: **LoRa Network → Channel Plan**

- **Region:** AU915
- **Sub-band:** Según tu operador (generalmente Sub-band 1 o 2)

#### 3. Verificar Conexión

1. En ChirpStack UI: **Gateways → [Tu Gateway]**
2. Verificar:
   - **Last seen at:** Debe mostrar timestamp reciente
   - **State:** Active
   - En la pestaña **LoRaWAN frames:** Deberías ver tráfico

---

### Configuración de Otros Gateways

#### RAK Gateways

1. Acceder via SSH o Web UI
2. Editar: `/etc/chirpstack-gateway-bridge/chirpstack-gateway-bridge.toml`
3. Configurar:
```toml
[integration.mqtt]
  servers=["tcp://IP_SERVIDOR:1883"]
```

#### The Things Indoor Gateway (TTIG)

El TTIG requiere configuración especial. No es directamente compatible con ChirpStack v4 en modo UDP.

---

## 🔗 Integración con Aplicaciones

### MQTT sobre TLS (Puerto 1884)

Las aplicaciones externas (Node-RED, ThingsBoard, Grafana, etc.) se conectan al broker MQTT usando **autenticación mutua (mTLS)**.

---

### Paso 1: Generar Certificados de Cliente desde ChirpStack UI

1. Ir a: **Applications → [Tu Aplicación] → Integrations**
2. Clic en **Add integration → MQTT**
3. Configurar:
   - **Server:** `tcp://mosquitto:1883` (interno) o `tcp://IP_SERVIDOR:1883` (externo sin TLS)
   - **Event topic template:** `application/{{application_id}}/device/{{dev_eui}}/event/{{event}}`
4. Clic en **Submit**
5. En la integración creada, clic en **Generate TLS Certificate**
6. Descargar los 3 archivos:
   - `ca.crt` - Certificado CA
   - `[id].crt` - Certificado del cliente
   - `[id].key` - Clave privada del cliente

---

### Paso 2: Configuración en Node-RED

#### Instalación de Node-RED (si no lo tenés)

```bash
# Instalación global
npm install -g --unsafe-perm node-red

# Iniciar Node-RED
node-red
```

Acceder a: `http://localhost:1880`

#### Configuración del Nodo MQTT

1. Arrastrar un nodo **mqtt in** o **mqtt out** al flow
2. Doble clic para configurar
3. Clic en el lápiz para agregar un nuevo broker
4. Configurar:

**Pestaña Connection:**
- **Server:** `IP_SERVIDOR` (tu IP pública o dominio)
- **Port:** `1884`
- **Protocol:** `MQTT V3.1.1`

**Pestaña Security:**
- (Dejar usuario y contraseña vacíos)

**Pestaña TLS:**
- ☑ **Enable secure (SSL/TLS) connection**
- Clic en el lápiz para agregar configuración TLS
- **CA Certificate:** Upload → Seleccionar `ca.crt`
- **Client Certificate:** Upload → Seleccionar `[id].crt`
- **Private Key:** Upload → Seleccionar `[id].key`
- ☑ **Verify server certificate** (activar)

5. Clic en **Add** y luego **Done**

#### Tópicos MQTT

**Para recibir datos (uplinks):**
```
application/[APPLICATION_ID]/device/[DEV_EUI]/event/up
```

**Para enviar comandos (downlinks):**
```
application/[APPLICATION_ID]/device/[DEV_EUI]/command/down
```

Payload ejemplo para downlink:
```json
{
  "devEui": "0004a30b001a2b3c",
  "confirmed": true,
  "fPort": 10,
  "data": "AQIDBAUGBwg="
}
```

El campo `data` debe estar en **Base64**.

---

### Paso 3: Configuración en otras aplicaciones

#### ThingsBoard

1. Ir a: **Integrations → Add Integration → MQTT**
2. Configurar:
   - **Host:** `IP_SERVIDOR`
   - **Port:** `1884`
   - **SSL:** Enabled
   - **Credentials type:** PEM
   - **CA certificate:** (pegar contenido de `ca.crt`)
   - **Client certificate:** (pegar contenido de `[id].crt`)
   - **Private key:** (pegar contenido de `[id].key`)

#### Python (paho-mqtt)

```python
import paho.mqtt.client as mqtt
import ssl

# Callback cuando se conecta
def on_connect(client, userdata, flags, rc):
    print(f"Conectado con código: {rc}")
    client.subscribe("application/+/device/+/event/up")

# Callback cuando llega un mensaje
def on_message(client, userdata, msg):
    print(f"Tópico: {msg.topic}")
    print(f"Payload: {msg.payload.decode()}")

# Crear cliente
client = mqtt.Client()
client.on_connect = on_connect
client.on_message = on_message

# Configurar TLS
client.tls_set(
    ca_certs="ca.crt",
    certfile="client.crt",
    keyfile="client.key",
    tls_version=ssl.PROTOCOL_TLSv1_2
)

# Conectar
client.connect("IP_SERVIDOR", 1884, 60)

# Loop
client.loop_forever()
```

---

## 🔄 Gestión de Certificados

### Verificar Validez de Certificados

```bash
# Ver fechas de expiración del CA
openssl x509 -in configuration/chirpstack/certs/ca.pem -noout -dates

# Ver fingerprint (huella digital)
openssl x509 -in configuration/chirpstack/certs/ca.pem -noout -fingerprint -sha256

# Verificar que un certificado de cliente está firmado por el CA
openssl verify -CAfile configuration/chirpstack/certs/ca.pem client.crt
```

### Renovar Certificados CA (Antes de Expirar)

⚠️ **IMPORTANTE:** Este proceso invalida TODOS los certificados existentes (servidor MQTT, gateways y aplicaciones).

#### Calendario de Renovación

| Certificado | Validez | Script de Renovación |
|-------------|---------|----------------------|
| CA (ca.pem) | 50 años | `03_renew-certs.sh` |
| Servidor MQTT (mqtt-server.pem) | 50 años | `04_generate-mqtt-server-certs.sh` |
| Clientes (gateways/apps) | 50 años | Regenerar desde ChirpStack UI |

#### Procedimiento Paso a Paso

**Paso 1: Renovar el CA (Certificado Raíz)**
```bash
cd /ruta/a/chirpstack_v4
./scripts/03_renew-certs.sh
```

Este script:
- Hace backup de certificados antiguos en `certs/backup_TIMESTAMP/`
- Genera nuevo CA válido por 50 años
- Configura permisos correctos

**Paso 2: Renovar Certificado del Servidor MQTT**
```bash
./scripts/04_generate-mqtt-server-certs.sh
```

Este script:
- Genera nuevo certificado firmado por el nuevo CA
- Incluye todas las IPs (interna, pública, localhost)
- Validez: 50 años

**Paso 3: Reiniciar Todos los Servicios**
```bash
docker compose down
docker compose up -d
```

**Paso 4: Regenerar Certificados de Gateways (si usan tipo ChirpStack-v4)**

1. Ir a: **Gateways → [Tu Gateway] → Certificates**
2. Clic en: **Generate Gateway Certificate**
3. Descargar nuevos archivos: `ca.crt`, `client.crt`, `client.key`
4. Subir nuevos certificados al gateway Milesight
5. Guardar y reiniciar el gateway

**Paso 5: Regenerar Certificados de Aplicaciones (Node-RED, etc.)**

1. Ir a: **Applications → [Tu App] → Integrations → MQTT**
2. Clic en: **Generate TLS Certificate**
3. Descargar nuevos archivos: `ca.crt`, `[id].crt`, `[id].key`
4. Actualizar certificados en Node-RED/ThingsBoard/etc.
5. Reiniciar la aplicación

#### Verificar Renovación Exitosa

```bash
# Ver nueva fecha de expiración del CA
openssl x509 -in configuration/chirpstack/certs/ca.pem -noout -dates

# Ver nueva fecha de expiración del servidor MQTT
openssl x509 -in configuration/chirpstack/certs/mqtt-server.pem -noout -dates

# Verificar que el servidor MQTT está firmado por el CA
openssl verify -CAfile configuration/chirpstack/certs/ca.pem \
  configuration/chirpstack/certs/mqtt-server.pem
```

Debe mostrar: `mqtt-server.pem: OK`

---

### Regenerar Solo Certificado del Servidor MQTT

Si solo necesitás actualizar el certificado del servidor (por ejemplo, cambió la IP pública):

```bash
./scripts/04_generate-mqtt-server-certs.sh
```

Luego reiniciar Mosquitto:
```bash
docker compose restart mosquitto
```

⚠️ **Nota:** Esto NO afecta los certificados de cliente existentes.

---

## 🛠️ Comandos Útiles

### Gestión de Servicios

```bash
# Iniciar todos los servicios
docker compose up -d

# Detener todos los servicios
docker compose down

# Reiniciar todos los servicios
docker compose restart

# Reiniciar un servicio específico
docker compose restart chirpstack
docker compose restart mosquitto

# Ver estado de los servicios
docker compose ps

# Ver logs en tiempo real
docker compose logs -f

# Ver logs de un servicio específico
docker compose logs -f chirpstack
docker compose logs -f mosquitto

# Ver últimas 100 líneas de logs
docker compose logs --tail 100 chirpstack
```

### Usar Makefile (Atajos)

```bash
make start                      # docker compose up -d
make stop                       # docker compose down
make restart                    # docker compose restart
make logs                       # docker compose logs -f
make import-lorawan-devices     # Importar repositorio de dispositivos
make generate-certs             # Generar certificados CA
make generate-mqtt-certs        # Generar certs servidor MQTT
make renew-certs                # Renovar certificados
```

### Inspección del Sistema

```bash
# Ver volúmenes de datos
docker volume ls

# Ver uso de disco por contenedor
docker system df

# Ver redes Docker
docker network ls

# Inspeccionar un contenedor específico
docker inspect chirpstack_v4-chirpstack-1

# Ver procesos en un contenedor
docker top chirpstack_v4-chirpstack-1

# Acceder a shell de un contenedor
docker exec -it chirpstack_v4-chirpstack-1 sh
docker exec -it chirpstack_v4-postgres-1 psql -U chirpstack
```

### Backup y Restauración

#### Backup de Base de Datos

```bash
# Backup completo de PostgreSQL
docker exec chirpstack_v4-postgres-1 pg_dump -U chirpstack chirpstack > backup_$(date +%Y%m%d).sql

# Backup de certificados
tar -czf certificates_backup_$(date +%Y%m%d).tar.gz configuration/chirpstack/certs/
```

#### Restauración

```bash
# Restaurar base de datos
cat backup_20251219.sql | docker exec -i chirpstack_v4-postgres-1 psql -U chirpstack chirpstack

# Restaurar certificados
tar -xzf certificates_backup_20251219.tar.gz
docker compose restart
```

---

## 🔧 Resolución de Problemas

### ChirpStack no Inicia

**Síntomas:** El contenedor de ChirpStack se detiene inmediatamente

**Solución:**
```bash
# Ver logs para identificar el error
docker compose logs chirpstack

# Errores comunes:
# - "connection refused" → PostgreSQL no está listo
# - "certificate" errors → Problema con certificados
# - "bind: address already in use" → Puerto 8080 ocupado
```

**Esperar a que PostgreSQL esté listo:**
```bash
# Reiniciar después de 30 segundos
docker compose down
sleep 30
docker compose up -d
```

---

### Gateway no se Conecta

**Verificaciones:**

1. **Gateway está registrado en ChirpStack UI:**
   - Verificar que el Gateway EUI coincide exactamente

2. **Puerto 1700/UDP está abierto:**
```bash
# En el servidor
sudo ufw allow 1700/udp
sudo netstat -ulnp | grep 1700
```

3. **Gateway Bridge está corriendo:**
```bash
docker compose ps | grep gateway-bridge
docker compose logs chirpstack-gateway-bridge-au915-0
```

4. **Configuración de región correcta:**
   - Verificar que el gateway esté configurado para la misma región que ChirpStack

5. **Test de conectividad:**
```bash
# Desde el gateway, hacer ping al servidor
ping IP_SERVIDOR

# Verificar que puede resolver DNS (si usás dominio)
nslookup DOMINIO_SERVIDOR
```

---

### Aplicación Externa no Puede Conectarse a MQTT (Puerto 1884)

**Síntomas:** Timeout, connection refused, o TLS handshake error

**Verificaciones:**

1. **Puerto 1884 está abierto:**
```bash
sudo ufw allow 1884/tcp
sudo netstat -tlnp | grep 1884
```

2. **Mosquitto está escuchando:**
```bash
docker exec chirpstack_v4-mosquitto-1 netstat -tlnp
```

Debe mostrar:
```
tcp  0.0.0.0:1883
tcp  0.0.0.0:1884
```

3. **Certificados correctos:**
```bash
# Verificar que el certificado del servidor tiene la IP pública en SANs
openssl x509 -in configuration/chirpstack/certs/mqtt-server.pem -noout -text | grep -A1 "Subject Alternative Name"

# Verificar certificado de cliente
openssl verify -CAfile configuration/chirpstack/certs/ca.pem client.crt
```

4. **Test manual de conexión TLS:**
```bash
# Desde tu máquina
openssl s_client -connect IP_SERVIDOR:1884 \
  -CAfile ca.crt \
  -cert client.crt \
  -key client.key

# Debe decir: Verify return code: 0 (ok)
```

5. **Si el test manual funciona pero Node-RED no:**
   - Verificar que los archivos subidos en Node-RED son los correctos
   - Probar desactivando "Verify server certificate" temporalmente
   - Revisar logs de Node-RED: `~/.node-red/`

---

### Downlinks no Funcionan

**Síntomas:** Los comandos enviados desde Node-RED o aplicaciones no llegan al dispositivo

**Verificaciones:**

1. **El tópico es correcto:**
```
application/[APPLICATION_ID]/device/[DEV_EUI]/command/down
```

2. **El payload tiene formato correcto:**
```json
{
  "devEui": "0004a30b001a2b3c",
  "confirmed": true,
  "fPort": 10,
  "data": "AQIDBAUGBwg="
}
```

3. **El mensaje llega a Mosquitto:**
```bash
# Suscribirse al tópico de downlink
docker exec -it chirpstack_v4-mosquitto-1 mosquitto_sub \
  -h localhost -p 1883 \
  -t 'application/+/device/+/command/down' -v

# Enviar desde Node-RED y verificar que aparece aquí
```

4. **ChirpStack procesa el downlink:**
```bash
docker compose logs -f chirpstack | grep -i "down\|queue"
```

5. **El dispositivo soporta downlinks:**
   - Verificar en la documentación del dispositivo
   - Algunos dispositivos solo aceptan downlinks en ventanas RX específicas

6. **La clase del dispositivo es correcta:**
   - **Clase A:** Solo recibe después de un uplink
   - **Clase B:** Recibe en slots programados
   - **Clase C:** Recibe siempre (excepto cuando transmite)

---

### Certificados Expirados

**Síntomas:** Aplicaciones dejan de conectarse, errores de TLS

**Solución:**

1. Verificar expiración:
```bash
openssl x509 -in configuration/chirpstack/certs/ca.pem -noout -dates
```

2. Si están por expirar o expirados:
```bash
./scripts/03_renew-certs.sh
docker compose down
docker compose up -d
```

3. Regenerar certificados de cliente desde ChirpStack UI

---

### Logs para Debugging

```bash
# Habilitar debug en ChirpStack
# Editar: configuration/chirpstack/chirpstack.toml
[logging]
level="debug"

# Reiniciar
docker compose restart chirpstack

# Habilitar logs detallados en Mosquitto
docker exec chirpstack_v4-mosquitto-1 sh -c \
  'echo "log_type all" >> /mosquitto/config/mosquitto.conf'
docker compose restart mosquitto
```

---

## 📂 Estructura de Directorios

```
chirpstack_v4/
├── docker-compose.yml                 # Definición de servicios Docker
├── Makefile                           # Comandos útiles (make start, make stop, etc.)
├── README.md                          # Esta documentación
├── LICENSE                            # Licencia del proyecto
│
├── configuration/
│   ├── chirpstack/
│   │   ├── chirpstack.toml           # Configuración principal ChirpStack
│   │   ├── region_*.toml             # Configuraciones por región
│   │   └── certs/                    # Certificados (no incluidos en git)
│   │       ├── ca.pem
│   │       ├── ca-key.pem
│   │       ├── mqtt-server.pem
│   │       └── mqtt-server-key.pem
│   │
│   ├── chirpstack-gateway-bridge/
│   │   ├── chirpstack-gateway-bridge.toml  # Config Gateway Bridge base
│   │   └── chirpstack-gateway-bridge-*.toml # Configs por región
│   │
│   ├── mosquitto/
│   │   └── config/
│   │       └── mosquitto.conf        # Configuración broker MQTT
│   │
│   └── postgresql/
│       └── initdb/                   # Scripts inicialización DB
│
└── scripts/
    ├── setup.sh                       # Instalación completa automática
    ├── 01_install_docker.sh          # Instalar solo Docker
    ├── 02_generate-certs.sh          # Generar certificados CA
    ├── 03_renew-certs.sh             # Renovar certificados
    └── 04_generate-mqtt-server-certs.sh  # Certificados servidor MQTT
```

---

## 🔐 Consideraciones de Seguridad

### Protección de Certificados

1. **Permisos de archivos:**
```bash
chmod 644 configuration/chirpstack/certs/ca.pem
chmod 600 configuration/chirpstack/certs/ca-key.pem
chmod 600 configuration/chirpstack/certs/*-key.pem
```

2. **Backups cifrados:**
```bash
# Backup con cifrado
tar -czf - configuration/chirpstack/certs/ | \
  openssl enc -aes-256-cbc -salt -out certs_backup.tar.gz.enc

# Restaurar
openssl enc -d -aes-256-cbc -in certs_backup.tar.gz.enc | \
  tar xz
```

3. **No subir certificados privados a Git:**
   - El archivo `.gitignore` ya excluye `configuration/chirpstack/certs/`

### Firewall

```bash
# Permitir solo puertos necesarios
sudo ufw allow 1700/udp    # Gateway UDP
sudo ufw allow 1884/tcp    # MQTT TLS externo
sudo ufw allow 8080/tcp    # ChirpStack Web UI

# NO exponer estos puertos externamente:
# 1883  - MQTT interno sin cifrado
# 5432  - PostgreSQL
# 6379  - Redis
```

### Actualizaciones

```bash
# Actualizar imágenes Docker
docker compose pull

# Reiniciar con nuevas imágenes
docker compose down
docker compose up -d

# Ver versiones actuales
docker compose images
```

---

## 📚 Referencias

- [Documentación Oficial ChirpStack v4](https://www.chirpstack.io/docs/)
- [ChirpStack Community Forum](https://forum.chirpstack.io/)
- [Repositorio GitHub ChirpStack](https://github.com/chirpstack/chirpstack)
- [LoRaWAN Specification](https://lora-alliance.org/lorawan-for-developers/)
- [Mosquitto MQTT Broker](https://mosquitto.org/)

---

## 📄 Licencia

Este proyecto está basado en ChirpStack (MIT License) con modificaciones y scripts propios.

---

## 👥 Soporte

Para problemas o consultas:
1. Revisar la sección [Resolución de Problemas](#resolución-de-problemas)
2. Consultar [ChirpStack Community Forum](https://forum.chirpstack.io/)
3. Abrir un issue en el repositorio GitHub

---

**Última actualización:** Diciembre 2025  
**Versión ChirpStack:** 4.x  
**Autor:** Guillaume Ferrú
