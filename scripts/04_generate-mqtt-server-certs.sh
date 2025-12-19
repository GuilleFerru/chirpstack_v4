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

log_warn() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

# Función para obtener IP pública
get_public_ip() {
    # Intentar obtener IP pública desde servicios externos
    local public_ip=""
    public_ip=$(curl -s --connect-timeout 5 https://api.ipify.org 2>/dev/null) || \
    public_ip=$(curl -s --connect-timeout 5 https://ifconfig.me 2>/dev/null) || \
    public_ip=$(curl -s --connect-timeout 5 https://icanhazip.com 2>/dev/null) || \
    public_ip=""
    echo "$public_ip"
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
    log_warn "Los certificados del servidor MQTT ya existen"
    echo ""
    echo "  Certificados actuales:"
    echo "  - mqtt-server.pem"
    echo "  - mqtt-server-key.pem"
    echo ""
    
    # Mostrar información del certificado actual
    if command -v openssl &> /dev/null; then
        echo "  📋 Información del certificado actual:"
        echo "  ────────────────────────────────────────"
        CURRENT_EXPIRY=$(openssl x509 -in mqtt-server.pem -noout -enddate 2>/dev/null | cut -d= -f2)
        CURRENT_SANS=$(openssl x509 -in mqtt-server.pem -noout -text 2>/dev/null | grep -A1 "Subject Alternative Name" | tail -1 | xargs)
        echo "  Expira: $CURRENT_EXPIRY"
        echo "  SANs:   $CURRENT_SANS"
        echo ""
    fi
    
    read -p "¿Deseas ELIMINAR los certificados existentes y regenerarlos? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Manteniendo certificados existentes."
        exit 0
    fi
    
    log "Eliminando certificados antiguos..."
    rm -f mqtt-server.pem mqtt-server-key.pem mqtt-server.csr mqtt-server.conf ca.srl
    log "✅ Certificados antiguos eliminados"
    echo ""
fi

# Obtener información del servidor
SERVER_IP_INTERNAL=$(hostname -I | awk '{print $1}')
SERVER_HOSTNAME=$(hostname)

# Intentar obtener IP pública automáticamente
log "Detectando IP pública..."
SERVER_IP_PUBLIC=$(get_public_ip)

echo ""
echo "  ┌─────────────────────────────────────────────────────────┐"
echo "  │  Configuración de IPs para el certificado              │"
echo "  ├─────────────────────────────────────────────────────────┤"
echo "  │  IP Interna detectada:  $SERVER_IP_INTERNAL"
echo "  │  IP Pública detectada:  ${SERVER_IP_PUBLIC:-No detectada}"
echo "  │  Hostname:              $SERVER_HOSTNAME"
echo "  └─────────────────────────────────────────────────────────┘"
echo ""

# Preguntar por IP pública si no se detectó o para confirmar
if [ -z "$SERVER_IP_PUBLIC" ]; then
    log_warn "No se pudo detectar la IP pública automáticamente"
fi

read -p "¿Deseas ingresar/modificar la IP pública manualmente? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    read -p "Ingresa la IP pública del servidor: " MANUAL_IP
    if [ -n "$MANUAL_IP" ]; then
        SERVER_IP_PUBLIC="$MANUAL_IP"
        log "✅ IP pública configurada: $SERVER_IP_PUBLIC"
    fi
fi

# Validar que tenemos al menos una IP
if [ -z "$SERVER_IP_INTERNAL" ] && [ -z "$SERVER_IP_PUBLIC" ]; then
    log_error "No se pudo obtener ninguna IP del servidor"
    exit 1
fi

echo ""
log "Generando certificados para servidor MQTT Mosquitto..."
echo ""
echo "  📋 Resumen de configuración:"
echo "  ────────────────────────────────────────"
echo "  IP Interna:  $SERVER_IP_INTERNAL"
echo "  IP Pública:  ${SERVER_IP_PUBLIC:-No configurada}"
echo "  Hostname:    $SERVER_HOSTNAME"
echo ""

# Construir alt_names dinámicamente
ALT_NAMES="DNS.1 = mosquitto
DNS.2 = localhost
DNS.3 = $SERVER_HOSTNAME
IP.1 = 127.0.0.1"

IP_INDEX=2
if [ -n "$SERVER_IP_INTERNAL" ]; then
    ALT_NAMES="$ALT_NAMES
IP.$IP_INDEX = $SERVER_IP_INTERNAL"
    ((IP_INDEX++))
fi

if [ -n "$SERVER_IP_PUBLIC" ] && [ "$SERVER_IP_PUBLIC" != "$SERVER_IP_INTERNAL" ]; then
    ALT_NAMES="$ALT_NAMES
IP.$IP_INDEX = $SERVER_IP_PUBLIC"
fi

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
$ALT_NAMES
EOF

log "Configuración OpenSSL generada:"
echo "  ────────────────────────────────────────"
grep -A20 "\[alt_names\]" mqtt-server.conf | head -10
echo "  ────────────────────────────────────────"
echo ""

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

# Mostrar SANs del certificado generado
echo ""
log "Subject Alternative Names (SANs) incluidos en el certificado:"
echo "  ────────────────────────────────────────"
openssl x509 -in mqtt-server.pem -noout -text 2>/dev/null | grep -A1 "Subject Alternative Name" | tail -1 | tr ',' '\n' | sed 's/^/  /'
echo ""

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
echo "  4. En Node-RED, asegúrate de usar en 'Server Name':"
if [ -n "$SERVER_IP_PUBLIC" ]; then
echo "     → $SERVER_IP_PUBLIC (IP Pública)"
fi
echo "     → $SERVER_IP_INTERNAL (IP Interna)"
echo "     → mosquitto (si estás dentro de Docker)"
echo ""
