#!/bin/bash
# Script para generar certificados de ChirpStack
# Ejecutar en la VM antes de docker-compose up -d

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
CERTS_DIR="$PROJECT_DIR/configuration/chirpstack/certs"
CHIRPSTACK_CERTS_REPO="https://github.com/chirpstack/chirpstack-certificates.git"

# Duración de los certificados en horas (50 años = 438000 horas)
CERT_EXPIRY_HOURS="438000h"

echo "=== Generador de Certificados ChirpStack ==="
echo "Duración: 50 años"
echo "Destino: $CERTS_DIR"
echo ""

# Verificar si ya existen los certificados
if [ -f "$CERTS_DIR/ca.pem" ] && [ -f "$CERTS_DIR/ca-key.pem" ]; then
    echo "⚠️  Los certificados ya existen en $CERTS_DIR"
    read -p "¿Deseas regenerarlos? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Usando certificados existentes."
        exit 0
    fi
fi

# Crear directorio de certs si no existe
mkdir -p "$CERTS_DIR"

# Instalar cfssl si no está disponible
if ! command -v cfssl &> /dev/null; then
    echo "Instalando cfssl..."
    # Detectar arquitectura
    ARCH=$(uname -m)
    case $ARCH in
        x86_64) ARCH="amd64" ;;
        aarch64) ARCH="arm64" ;;
    esac
    
    CFSSL_VERSION="1.6.4"
    curl -sL "https://github.com/cloudflare/cfssl/releases/download/v${CFSSL_VERSION}/cfssl_${CFSSL_VERSION}_linux_${ARCH}" -o /usr/local/bin/cfssl
    curl -sL "https://github.com/cloudflare/cfssl/releases/download/v${CFSSL_VERSION}/cfssljson_${CFSSL_VERSION}_linux_${ARCH}" -o /usr/local/bin/cfssljson
    chmod +x /usr/local/bin/cfssl /usr/local/bin/cfssljson
    echo "cfssl instalado correctamente."
fi

# Clonar repositorio de certificados si no existe
TEMP_CERTS_DIR="/tmp/chirpstack-certificates"
if [ -d "$TEMP_CERTS_DIR" ]; then
    echo "Actualizando repositorio de certificados..."
    cd "$TEMP_CERTS_DIR" && git pull
else
    echo "Clonando repositorio de certificados..."
    git clone "$CHIRPSTACK_CERTS_REPO" "$TEMP_CERTS_DIR"
fi

cd "$TEMP_CERTS_DIR"

# Modificar la expiración de certificados a 50 años (438000 horas)
echo "Configurando expiración de certificados a 50 años..."
# Reemplazar TODAS las expiraciones encontradas en los archivos JSON
find . -name "*.json" -exec sed -i 's/"expiry": "[0-9]*h"/"expiry": "'"$CERT_EXPIRY_HOURS"'"/g' {} \;
sed -i "s/\"expiry\": \"8760h\"/\"expiry\": \"$CERT_EXPIRY_HOURS\"/g" config/ca-config.json

# Limpiar certificados anteriores si existen
make clean 2>/dev/null || true

# Generar certificados usando cfssl directamente
echo "Generando certificados..."
make

# Copiar certificados CA al directorio de ChirpStack
echo "Copiando certificados..."
cp "$TEMP_CERTS_DIR/certs/ca/ca.pem" "$CERTS_DIR/"
cp "$TEMP_CERTS_DIR/certs/ca/ca-key.pem" "$CERTS_DIR/"

# Establecer permisos correctos (importante para Linux)
chmod 644 "$CERTS_DIR/ca.pem"
chmod 600 "$CERTS_DIR/ca-key.pem"

echo ""
echo "✅ Certificados generados exitosamente en: $CERTS_DIR"
echo ""
echo "Archivos creados:"
ls -la "$CERTS_DIR"
echo ""
echo "Ahora puedes ejecutar: docker-compose up -d"
