#!/bin/bash
# =============================================================================
# Script de renovación de certificados ChirpStack
# Este script FUERZA la regeneración de certificados sin preguntar
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
CERTS_DIR="$PROJECT_DIR/configuration/chirpstack/certs"
TEMP_CERTS_DIR="/tmp/chirpstack-certificates"
CHIRPSTACK_CERTS_REPO="https://github.com/chirpstack/chirpstack-certificates.git"
CERT_EXPIRY_HOURS="438000h"  # 50 años

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

echo ""
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║     Renovación de Certificados ChirpStack                  ║"
echo "║                                                           ║"
echo "║  ⚠️  ADVERTENCIA:                                         ║"
echo "║  Este script regenerará los certificados CA.              ║"
echo "║  Los certificados de aplicaciones deberán regenerarse     ║"
echo "║  desde la UI de ChirpStack después de este proceso.       ║"
echo "║                                                           ║"
echo "║  Duración de nuevos certificados: 50 años                 ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

read -p "¿Deseas continuar con la renovación? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Renovación cancelada."
    exit 0
fi

# Verificar herramientas necesarias
if ! command -v cfssl &> /dev/null; then
    log_error "cfssl no está instalado. Instálalo primero con:"
    echo "  sudo apt-get install -y cfssl"
    echo "  O ejecuta: sudo ./scripts/setup.sh"
    exit 1
fi

# Backup de certificados existentes
if [ -f "$CERTS_DIR/ca.pem" ] || [ -f "$CERTS_DIR/ca-key.pem" ]; then
    BACKUP_DIR="$CERTS_DIR/backup_$(date +%Y%m%d_%H%M%S)"
    log "Haciendo backup de certificados existentes..."
    mkdir -p "$BACKUP_DIR"
    
    if [ -f "$CERTS_DIR/ca.pem" ]; then
        cp "$CERTS_DIR/ca.pem" "$BACKUP_DIR/"
        log "Backup: ca.pem -> $BACKUP_DIR/ca.pem"
    fi
    
    if [ -f "$CERTS_DIR/ca-key.pem" ]; then
        cp "$CERTS_DIR/ca-key.pem" "$BACKUP_DIR/"
        log "Backup: ca-key.pem -> $BACKUP_DIR/ca-key.pem"
    fi
    
    # Eliminar certificados antiguos
    log "Eliminando certificados antiguos..."
    rm -f "$CERTS_DIR/ca.pem" "$CERTS_DIR/ca-key.pem"
fi

# Crear directorio de certificados si no existe
mkdir -p "$CERTS_DIR"

# Clonar o actualizar repositorio de certificados
if [ -d "$TEMP_CERTS_DIR" ]; then
    log "Actualizando repositorio de certificados..."
    cd "$TEMP_CERTS_DIR" && git pull
else
    log "Clonando repositorio de certificados..."
    git clone "$CHIRPSTACK_CERTS_REPO" "$TEMP_CERTS_DIR"
fi

cd "$TEMP_CERTS_DIR"

# Modificar expiración a 50 años
log "Configurando expiración a 50 años (438000 horas)..."
# Reemplazar TODAS las expiraciones encontradas en los archivos JSON
find . -name "*.json" -exec sed -i 's/"expiry": "[0-9]*h"/"expiry": "'"$CERT_EXPIRY_HOURS"'"/g' {} \;

# Limpiar certificados temporales anteriores
log "Limpiando certificados temporales..."
make clean 2>/dev/null || true

# Generar nuevos certificados
log "Generando nuevos certificados..."
make

# Copiar certificados al directorio de ChirpStack
log "Copiando nuevos certificados..."
cp "$TEMP_CERTS_DIR/certs/ca/ca.pem" "$CERTS_DIR/"
cp "$TEMP_CERTS_DIR/certs/ca/ca-key.pem" "$CERTS_DIR/"

# Establecer permisos correctos
chmod 644 "$CERTS_DIR/ca.pem"
chmod 600 "$CERTS_DIR/ca-key.pem"

# Verificar certificado generado
CERT_START=$(openssl x509 -in "$CERTS_DIR/ca.pem" -noout -startdate | cut -d= -f2)
CERT_END=$(openssl x509 -in "$CERTS_DIR/ca.pem" -noout -enddate | cut -d= -f2)

echo ""
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║        ✅ Certificados renovados exitosamente             ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""
echo "  📁 Ubicación:       $CERTS_DIR"
echo "  📅 Válido desde:    $CERT_START"
echo "  📅 Válido hasta:    $CERT_END"
echo ""
echo "  ⚠️  IMPORTANTE - Pasos siguientes:"
echo ""
echo "  1. Reiniciar ChirpStack:"
echo "     cd $PROJECT_DIR"
echo "     docker compose restart chirpstack"
echo ""
echo "  2. Regenerar certificados de aplicaciones:"
echo "     - Ir a Applications → [Tu App] → Integrations"
echo "     - Generar nuevo certificado MQTT"
echo "     - Actualizar tu cliente MQTT con el nuevo certificado"
echo ""
echo "  3. Si usas Gateway Bridges, también regenerar sus certificados"
echo ""

if [ -d "$BACKUP_DIR" ]; then
    echo "  💾 Backup de certificados antiguos en:"
    echo "     $BACKUP_DIR"
    echo ""
fi

log "Renovación completada exitosamente"
