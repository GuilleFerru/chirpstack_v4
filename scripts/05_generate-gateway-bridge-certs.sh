#!/bin/bash
# =============================================================================
# Script para generar certificados del Gateway Bridge (Basics Station Server)
# Ejecutar después de generar los certificados CA (02_generate-certs.sh)
# 
# Este certificado es usado por el Gateway Bridge para aceptar conexiones
# WebSocket TLS (wss://) desde los gateways con Basics Station.
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
    local public_ip=""
    public_ip=$(curl -s --connect-timeout 5 https://api.ipify.org 2>/dev/null) || \
    public_ip=$(curl -s --connect-timeout 5 https://ifconfig.me 2>/dev/null) || \
    public_ip=$(curl -s --connect-timeout 5 https://icanhazip.com 2>/dev/null) || \
    public_ip=""
    echo "$public_ip"
}

echo ""
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║     Generador de Certificados Basics Station Server       ║"
echo "║     (Para Gateway Bridge WebSocket TLS)                   ║"
echo "╠═══════════════════════════════════════════════════════════╣"
echo "║  Este certificado permite a los gateways conectarse       ║"
echo "║  de forma segura al Gateway Bridge via wss://             ║"
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

# Verificar si ya existen certificados
if [ -f "$CERTS_DIR/basicstation-server.pem" ] && [ -f "$CERTS_DIR/basicstation-server-key.pem" ]; then
    log_warn "Los certificados del servidor Basics Station ya existen"
    echo ""
    echo "  Certificados actuales:"
    echo "  - basicstation-server.pem"
    echo "  - basicstation-server-key.pem"
    echo ""
    
    # Mostrar información del certificado actual
    if command -v openssl &> /dev/null; then
        echo "  📋 Información del certificado actual:"
        echo "  ────────────────────────────────────────"
        CURRENT_EXPIRY=$(openssl x509 -in basicstation-server.pem -noout -enddate 2>/dev/null | cut -d= -f2)
        CURRENT_SANS=$(openssl x509 -in basicstation-server.pem -noout -text 2>/dev/null | grep -A1 "Subject Alternative Name" | tail -1 | xargs)
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
    rm -f basicstation-server.pem basicstation-server-key.pem basicstation-server.csr basicstation-server.conf ca.srl
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

log "Generando certificados para Basics Station Server..."
echo ""
echo "  📋 Resumen de configuración:"
echo "  ────────────────────────────────────────"
echo "  IP Interna:  $SERVER_IP_INTERNAL"
echo "  IP Pública:  ${SERVER_IP_PUBLIC:-No configurada}"
echo "  Hostname:    $SERVER_HOSTNAME"
echo ""

# Construir alt_names dinámicamente
# DNS entries para todos los servicios de Gateway Bridge basicstation
ALT_NAMES="DNS.1 = localhost
DNS.2 = $SERVER_HOSTNAME
DNS.3 = chirpstack-gateway-bridge-basicstation-au915-0
DNS.4 = chirpstack-gateway-bridge-basicstation-au915-1
DNS.5 = chirpstack-gateway-bridge-basicstation-au915-2
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

# Crear configuración OpenSSL
cat > basicstation-server.conf << EOF
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
OU = Gateway Bridge
CN = basicstation-server

[req_ext]
subjectAltName = @alt_names

[alt_names]
$ALT_NAMES
EOF

log "Configuración OpenSSL generada:"
echo "  ────────────────────────────────────────"
grep -A20 "\[alt_names\]" basicstation-server.conf | head -15
echo "  ────────────────────────────────────────"
echo ""

# Generar clave privada
log "1/4 - Generando clave privada..."
openssl genrsa -out basicstation-server-key.pem 2048

# Generar CSR
log "2/4 - Generando CSR..."
openssl req -new -key basicstation-server-key.pem -out basicstation-server.csr -config basicstation-server.conf

# Firmar con CA (5 años)
log "3/4 - Firmando certificado con CA (válido por 5 años)..."
openssl x509 -req -in basicstation-server.csr \
    -CA ca.pem -CAkey ca-key.pem -CAcreateserial \
    -out basicstation-server.pem -days 1825 \
    -extfile basicstation-server.conf -extensions req_ext

# Limpiar
log "4/4 - Limpiando archivos temporales..."
rm -f basicstation-server.csr basicstation-server.conf

# Permisos
chmod 644 basicstation-server.pem
chmod 644 basicstation-server-key.pem

echo ""
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║     ✅ Certificados Basics Station Server generados       ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

CERT_END=$(openssl x509 -in basicstation-server.pem -noout -enddate | cut -d= -f2)
echo "  📁 Ubicación:       $CERTS_DIR"
echo "  📅 Válido hasta:    $CERT_END"
echo ""
echo "  📄 Archivos generados:"
echo "     - basicstation-server.pem"
echo "     - basicstation-server-key.pem"
echo ""

# Verificar
if openssl verify -CAfile ca.pem basicstation-server.pem > /dev/null 2>&1; then
    log "✅ Certificado verificado correctamente"
else
    log_error "Error al verificar el certificado"
    exit 1
fi

# Mostrar SANs del certificado generado
echo ""
log "Subject Alternative Names (SANs) incluidos en el certificado:"
echo "  ────────────────────────────────────────"
openssl x509 -in basicstation-server.pem -noout -text 2>/dev/null | grep -A1 "Subject Alternative Name" | tail -1 | tr ',' '\n' | sed 's/^/  /'
echo ""

echo ""
echo "  ⚠️  Pasos siguientes:"
echo ""
echo "  1. Reiniciar servicios:"
echo "     docker compose down && docker compose up -d"
echo ""
echo "  2. En ChirpStack UI → Gateways → [Tu Gateway] → Certificates"
echo "     Generar certificado TLS para el gateway"
echo ""
echo "  3. En el Gateway UG67, configurar Basics Station:"
echo "     - Packet Forwarder: Semtech UDP → Basics Station"
if [ -n "$SERVER_IP_PUBLIC" ]; then
echo "     - LNS Server: wss://$SERVER_IP_PUBLIC:3001 (IP Pública)"
fi
echo "     - LNS Server: wss://$SERVER_IP_INTERNAL:3001 (IP Interna)"
echo "     - Subir certificados descargados de ChirpStack"
echo ""
echo "  4. Puertos expuestos por sub-band:"
echo "     - AU915_0: Puerto 3000 → wss://IP:3000"
echo "     - AU915_1: Puerto 3001 → wss://IP:3001"
echo "     - AU915_2: Puerto 3002 → wss://IP:3002"
echo ""
