#!/bin/bash
# Script para instalar Docker y Docker Compose
set -e

LOG_FILE="/var/log/tts-tbmq-deployment.log"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a $LOG_FILE
}

log "=== Iniciando instalación de Docker ==="

# Verificar si Docker ya está instalado
if command -v docker &> /dev/null; then
    log "Docker ya está instalado: $(docker --version)"
else
    log "Instalando Docker..."
    
    # Instalar dependencias
    apt-get update
    apt-get install -y \
        apt-transport-https \
        ca-certificates \
        curl \
        gnupg \
        lsb-release

    # Agregar clave GPG de Docker
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

    # Agregar repositorio de Docker
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \
      $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

    # Instalar Docker Engine
    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    # Habilitar y arrancar Docker
    systemctl enable docker
    systemctl start docker

    log "Docker instalado correctamente: $(docker --version)"
fi

# Verificar Docker Compose
if docker compose version &> /dev/null; then
    log "Docker Compose ya está disponible: $(docker compose version)"
else
    log "ERROR: Docker Compose plugin no está disponible"
    exit 1
fi

# Instalar herramientas adicionales
log "Instalando herramientas adicionales..."
apt-get install -y openssl wget jq nano vim unzip

log "=== Instalación de Docker completada ==="
