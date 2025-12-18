#!/bin/bash
# =============================================================================
# Script maestro de instalación de ChirpStack
# Ejecutar como root en una VM limpia
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
LOG_FILE="/var/log/chirpstack-setup.log"

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a $LOG_FILE
}

log_warn() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}" | tee -a $LOG_FILE
}

log_error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ❌ $1${NC}" | tee -a $LOG_FILE
}

log_step() {
    echo -e "\n${BLUE}========================================${NC}" | tee -a $LOG_FILE
    echo -e "${BLUE}  $1${NC}" | tee -a $LOG_FILE
    echo -e "${BLUE}========================================${NC}\n" | tee -a $LOG_FILE
}

# Verificar que se ejecuta como root
if [ "$EUID" -ne 0 ]; then
    log_error "Este script debe ejecutarse como root"
    echo "Ejecuta: sudo $0"
    exit 1
fi

echo ""
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║        ChirpStack - Instalación Automática                ║"
echo "║                                                           ║"
echo "║  Este script instalará:                                   ║"
echo "║    1. Docker y Docker Compose                             ║"
echo "║    2. Herramientas necesarias (make, cfssl, etc)          ║"
echo "║    3. Certificados CA (válidos por 5 años)                ║"
echo "║    4. ChirpStack con todos sus servicios                  ║"
echo "║    5. Importación de dispositivos LoRaWAN                 ║"
echo "║                                                           ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

read -p "¿Deseas continuar con la instalación? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Instalación cancelada."
    exit 0
fi

# =============================================================================
# PASO 1: Instalar Docker
# =============================================================================
log_step "PASO 1/5: Instalando Docker y Docker Compose"

if command -v docker &> /dev/null; then
    log "Docker ya está instalado: $(docker --version)"
else
    log "Instalando Docker..."
    
    apt-get update
    apt-get install -y \
        apt-transport-https \
        ca-certificates \
        curl \
        gnupg \
        lsb-release

    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \
      $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    systemctl enable docker
    systemctl start docker

    log "Docker instalado: $(docker --version)"
fi

# Verificar Docker Compose
if docker compose version &> /dev/null; then
    log "Docker Compose disponible: $(docker compose version)"
else
    log_error "Docker Compose plugin no está disponible"
    exit 1
fi

# =============================================================================
# PASO 2: Instalar herramientas necesarias
# =============================================================================
log_step "PASO 2/5: Instalando herramientas necesarias"

log "Instalando make, curl, git, jq y otras herramientas..."
apt-get install -y make curl git jq openssl wget nano vim unzip

# Instalar cfssl si no está disponible
if ! command -v cfssl &> /dev/null; then
    log "Instalando cfssl..."
    ARCH=$(uname -m)
    case $ARCH in
        x86_64) ARCH="amd64" ;;
        aarch64) ARCH="arm64" ;;
    esac
    
    CFSSL_VERSION="1.6.4"
    curl -sL "https://github.com/cloudflare/cfssl/releases/download/v${CFSSL_VERSION}/cfssl_${CFSSL_VERSION}_linux_${ARCH}" -o /usr/local/bin/cfssl
    curl -sL "https://github.com/cloudflare/cfssl/releases/download/v${CFSSL_VERSION}/cfssljson_${CFSSL_VERSION}_linux_${ARCH}" -o /usr/local/bin/cfssljson
    chmod +x /usr/local/bin/cfssl /usr/local/bin/cfssljson
    log "cfssl instalado correctamente"
else
    log "cfssl ya está instalado: $(cfssl version 2>/dev/null | head -1)"
fi

# =============================================================================
# PASO 3: Generar certificados
# =============================================================================
log_step "PASO 3/5: Generando certificados CA (válidos por 5 años)"

CERTS_DIR="$PROJECT_DIR/configuration/chirpstack/certs"
TEMP_CERTS_DIR="/tmp/chirpstack-certificates"

mkdir -p "$CERTS_DIR"

# Verificar si ya existen certificados
if [ -f "$CERTS_DIR/ca.pem" ] && [ -f "$CERTS_DIR/ca-key.pem" ]; then
    log_warn "Los certificados ya existen en $CERTS_DIR"
    read -p "¿Deseas regenerarlos? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "Usando certificados existentes."
    else
        rm -f "$CERTS_DIR/ca.pem" "$CERTS_DIR/ca-key.pem"
    fi
fi

# Generar certificados si no existen
if [ ! -f "$CERTS_DIR/ca.pem" ] || [ ! -f "$CERTS_DIR/ca-key.pem" ]; then
    # Clonar o actualizar repositorio de certificados
    if [ -d "$TEMP_CERTS_DIR" ]; then
        log "Actualizando repositorio de certificados..."
        cd "$TEMP_CERTS_DIR" && git pull
    else
        log "Clonando repositorio de certificados..."
        git clone https://github.com/chirpstack/chirpstack-certificates.git "$TEMP_CERTS_DIR"
    fi

    cd "$TEMP_CERTS_DIR"

    # Modificar expiración a 5 años (43800 horas)
    log "Configurando expiración a 5 años..."
    # Reemplazar TODAS las expiraciones encontradas en los archivos JSON
    find . -name "*.json" -exec sed -i 's/"expiry": "[0-9]*h"/"expiry": "43800h"/g' {} \;

    # Generar certificados
    log "Generando certificados..."
    make clean 2>/dev/null || true
    make

    # Copiar certificados
    log "Copiando certificados a $CERTS_DIR"
    cp "$TEMP_CERTS_DIR/certs/ca/ca.pem" "$CERTS_DIR/"
    cp "$TEMP_CERTS_DIR/certs/ca/ca-key.pem" "$CERTS_DIR/"

    # Establecer permisos
    chmod 644 "$CERTS_DIR/ca.pem"
    chmod 600 "$CERTS_DIR/ca-key.pem"

    log "✅ Certificados generados (válidos hasta $(date -d '+5 years' '+%Y-%m-%d'))"
fi

# =============================================================================
# PASO 4: Iniciar ChirpStack
# =============================================================================
log_step "PASO 4/5: Iniciando ChirpStack"

cd "$PROJECT_DIR"

log "Descargando imágenes Docker..."
docker compose pull

log "Iniciando servicios..."
docker compose up -d

# Esperar a que ChirpStack esté listo
log "Esperando a que ChirpStack esté listo..."
MAX_RETRIES=30
RETRY_COUNT=0

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    if docker compose logs chirpstack 2>&1 | grep -q "Starting API server"; then
        log "ChirpStack está listo"
        break
    fi
    RETRY_COUNT=$((RETRY_COUNT + 1))
    echo -n "."
    sleep 2
done
echo ""

if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
    log_warn "Timeout esperando ChirpStack, pero puede que aún esté iniciando..."
fi

# =============================================================================
# PASO 5: Importar dispositivos LoRaWAN
# =============================================================================
log_step "PASO 5/5: Importando dispositivos LoRaWAN"

log "Este proceso puede tardar varios minutos..."

docker compose run --rm --entrypoint sh --user root chirpstack -c '
    apk add --no-cache git && \
    git clone https://github.com/brocaar/lorawan-devices /tmp/lorawan-devices && \
    chirpstack -c /etc/chirpstack import-legacy-lorawan-devices-repository -d /tmp/lorawan-devices
' 2>&1 | tee -a $LOG_FILE

# =============================================================================
# Resumen final
# =============================================================================
echo ""
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║        ✅ Instalación completada exitosamente             ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""
echo "  📊 ChirpStack UI:      http://$(hostname -I | awk '{print $1}'):8080"
echo "  📊 REST API:           http://$(hostname -I | awk '{print $1}'):8090"
echo ""
echo "  🔑 Credenciales por defecto:"
echo "     Usuario: admin"
echo "     Contraseña: admin"
echo ""
echo "  📁 Certificados:       $CERTS_DIR"
echo "  📁 Logs:               $LOG_FILE"
echo ""
echo "  🔧 Comandos útiles:"
echo "     docker compose ps          - Ver estado de servicios"
echo "     docker compose logs -f     - Ver logs en tiempo real"
echo "     docker compose down        - Detener servicios"
echo "     docker compose up -d       - Iniciar servicios"
echo ""
log "Instalación completada exitosamente"
