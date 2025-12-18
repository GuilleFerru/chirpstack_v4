#!/bin/bash
# =============================================================================
# Script para generar certificados del Gateway Bridge (Basics Station Server)
# Ejecutar después de generar los certificados CA
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
CERTS_DIR="$PROJECT_DIR/configuration/chirpstack/certs"

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

log_error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

echo ""
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║     Generador de Certificados Basics Station Server       ║"
echo "║     (Para Gateway Bridge WebSocket TLS)                   ║"
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
    log "⚠️  Los certificados del servidor Basics Station ya existen"
    read -p "¿Deseas regenerarlos? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Usando certificados existentes."
        exit 0
    fi
    rm -f basicstation-server.pem basicstation-server-key.pem
fi

# Obtener información del servidor
SERVER_IP=$(hostname -I | awk '{print $1}')
SERVER_HOSTNAME=$(hostname)

log "Generando certificados para Basics Station Server..."
log "IP del servidor: $SERVER_IP"
log "Hostname: $SERVER_HOSTNAME"
echo ""

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
DNS.1 = localhost
DNS.2 = $SERVER_HOSTNAME
DNS.3 = chirpstack-gateway-bridge-basicstation-au915-0
DNS.4 = chirpstack-gateway-bridge-basicstation-au915-1
DNS.5 = chirpstack-gateway-bridge-basicstation-au915-2
IP.1 = 127.0.0.1
IP.2 = $SERVER_IP
EOF

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
echo "     - LNS Server: wss://TU_IP:3001"
echo "     - Subir certificados descargados de ChirpStack"
echo ""
