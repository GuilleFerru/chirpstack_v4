#!/bin/bash
# =============================================================================
# Script para generar certificados del servidor MQTT (Mosquitto)
# Ejecutar después de generar los certificados CA
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
CERTS_DIR="$PROJECT_DIR/configuration/chirpstack/certs"

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

log_error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

echo ""
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║     Generador de Certificados MQTT Server                 ║"
echo "║     (Mosquitto Broker)                                    ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

# Verificar que existen los certificados CA
if [ ! -f "$CERTS_DIR/ca.pem" ] || [ ! -f "$CERTS_DIR/ca-key.pem" ]; then
    log_error "No se encontraron los certificados CA en $CERTS_DIR"
    echo ""
    echo "Ejecuta primero:"
    echo "  ./scripts/02_generate-certs.sh"
    echo ""
    exit 1
fi

cd "$CERTS_DIR"

# Verificar si ya existen certificados del servidor MQTT
if [ -f "$CERTS_DIR/mqtt-server.pem" ] && [ -f "$CERTS_DIR/mqtt-server-key.pem" ]; then
    log "⚠️  Los certificados del servidor MQTT ya existen"
    read -p "¿Deseas regenerarlos? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Usando certificados existentes."
        exit 0
    fi
    rm -f mqtt-server.pem mqtt-server-key.pem mqtt-server.csr mqtt-server.conf
fi

# Obtener información del servidor
SERVER_IP=$(hostname -I | awk '{print $1}')
SERVER_HOSTNAME=$(hostname)

log "Generando certificados para servidor MQTT Mosquitto..."
log "IP del servidor: $SERVER_IP"
log "Hostname: $SERVER_HOSTNAME"
echo ""

# Crear configuración OpenSSL para el certificado del servidor
cat > mqtt-server.conf << EOF
[req]
default_bits = 2048
prompt = no
default_md = sha256
distinguished_name = dn
req_extensions = req_ext

[dn]
C = AR
ST = Buenos Aires
L = Buenos Aires
O = ChirpStack
OU = MQTT Server
CN = mosquitto

[req_ext]
subjectAltName = @alt_names

[alt_names]
DNS.1 = mosquitto
DNS.2 = localhost
DNS.3 = $SERVER_HOSTNAME
IP.1 = 127.0.0.1
IP.2 = $SERVER_IP
EOF

# Generar clave privada del servidor MQTT
log "1/4 - Generando clave privada del servidor..."
openssl genrsa -out mqtt-server-key.pem 2048

# Generar CSR (Certificate Signing Request)
log "2/4 - Generando Certificate Signing Request (CSR)..."
openssl req -new -key mqtt-server-key.pem -out mqtt-server.csr -config mqtt-server.conf

# Firmar el certificado con el CA (válido por 5 años = 1825 días)
log "3/4 - Firmando certificado con CA (válido por 5 años)..."
openssl x509 -req -in mqtt-server.csr \
    -CA ca.pem -CAkey ca-key.pem -CAcreateserial \
    -out mqtt-server.pem -days 1825 \
    -extfile mqtt-server.conf -extensions req_ext

# Limpiar archivos temporales
log "4/4 - Limpiando archivos temporales..."
rm -f mqtt-server.csr mqtt-server.conf

# Establecer permisos correctos
chmod 644 mqtt-server.pem
chmod 600 mqtt-server-key.pem

echo ""
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║     ✅ Certificados MQTT Server generados                 ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

# Verificar certificado generado
CERT_START=$(openssl x509 -in mqtt-server.pem -noout -startdate | cut -d= -f2)
CERT_END=$(openssl x509 -in mqtt-server.pem -noout -enddate | cut -d= -f2)

echo "  📁 Ubicación:       $CERTS_DIR"
echo "  📅 Válido desde:    $CERT_START"
echo "  📅 Válido hasta:    $CERT_END"
echo ""
echo "  📄 Archivos generados:"
echo "     - mqtt-server.pem      (certificado público del servidor)"
echo "     - mqtt-server-key.pem  (clave privada del servidor)"
echo ""

# Verificar certificado
log "Verificando certificado contra CA..."
if openssl verify -CAfile ca.pem mqtt-server.pem > /dev/null 2>&1; then
    log "✅ Certificado verificado correctamente"
else
    log_error "Error al verificar el certificado"
    exit 1
fi

echo ""
echo "  ⚠️  Pasos siguientes:"
echo ""
echo "  1. Reiniciar servicios Docker:"
echo "     cd $PROJECT_DIR"
echo "     docker compose down"
echo "     docker compose up -d"
echo ""
echo "  2. Verificar que Mosquitto está escuchando en puerto 1884:"
echo "     docker compose logs mosquitto"
echo "     netstat -tulpn | grep 1884"
echo ""
echo "  3. Generar certificado de cliente desde ChirpStack UI:"
echo "     Applications → [Tu App] → Integrations → MQTT"
echo "     → Generate TLS Certificate"
echo ""
