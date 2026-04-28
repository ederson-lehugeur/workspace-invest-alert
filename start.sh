#!/usr/bin/env bash
# =============================================================================
# Invest Alert - Script de inicializacao (Linux/macOS)
#
# Este script:
#   1. Verifica/instala Docker e Docker Compose
#   2. Sobe todos os containers do Invest Alert
#   3. Abre o navegador no frontend (http://localhost:4200)
#   4. Aguarda o usuario pressionar ENTER para encerrar tudo
#
# Uso: chmod +x start.sh && ./start.sh
# =============================================================================

set -e

FRONTEND_URL="http://localhost:4200"
COMPOSE_FILE="docker-compose.yml"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
warn()  { echo -e "${YELLOW}[AVISO]${NC} $1"; }
error() { echo -e "${RED}[ERRO]${NC} $1"; }

# -------------------------------------------------------------------------
# Detectar gerenciador de pacotes
# -------------------------------------------------------------------------
detect_package_manager() {
    if command -v apt-get &>/dev/null; then
        echo "apt"
    elif command -v dnf &>/dev/null; then
        echo "dnf"
    elif command -v yum &>/dev/null; then
        echo "yum"
    elif command -v pacman &>/dev/null; then
        echo "pacman"
    elif command -v brew &>/dev/null; then
        echo "brew"
    else
        echo "unknown"
    fi
}

# -------------------------------------------------------------------------
# Instalar Docker
# -------------------------------------------------------------------------
install_docker() {
    local pkg_manager
    pkg_manager=$(detect_package_manager)

    info "Instalando Docker..."

    case "$pkg_manager" in
        apt)
            sudo apt-get update
            sudo apt-get install -y ca-certificates curl gnupg
            sudo install -m 0755 -d /etc/apt/keyrings
            curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg 2>/dev/null || true
            sudo chmod a+r /etc/apt/keyrings/docker.gpg
            echo \
              "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
              $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
              sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
            sudo apt-get update
            sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
            ;;
        dnf)
            sudo dnf -y install dnf-plugins-core
            sudo dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo
            sudo dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
            ;;
        yum)
            sudo yum install -y yum-utils
            sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
            sudo yum install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
            ;;
        pacman)
            sudo pacman -Sy --noconfirm docker docker-compose docker-buildx
            ;;
        brew)
            brew install --cask docker
            info "Docker Desktop instalado. Abra o Docker Desktop antes de continuar."
            info "Pressione ENTER quando o Docker Desktop estiver rodando..."
            read -r
            ;;
        *)
            error "Gerenciador de pacotes nao detectado."
            error "Instale o Docker manualmente: https://docs.docker.com/engine/install/"
            exit 1
            ;;
    esac

    if [[ "$pkg_manager" != "brew" ]]; then
        sudo systemctl start docker 2>/dev/null || true
        sudo systemctl enable docker 2>/dev/null || true

        if ! groups "$USER" | grep -q docker; then
            sudo usermod -aG docker "$USER"
            warn "Voce foi adicionado ao grupo 'docker'."
            warn "Pode ser necessario fazer logout/login para que funcione sem sudo."
        fi
    fi

    info "Docker instalado com sucesso!"
}

# -------------------------------------------------------------------------
# Verificar Docker
# -------------------------------------------------------------------------
check_docker() {
    if ! command -v docker &>/dev/null; then
        warn "Docker nao encontrado."
        read -rp "Deseja instalar o Docker automaticamente? (s/n): " resposta
        if [[ "$resposta" =~ ^[sS]$ ]]; then
            install_docker
        else
            error "Docker e necessario para rodar o projeto."
            error "Instale manualmente: https://docs.docker.com/engine/install/"
            exit 1
        fi
    else
        info "Docker encontrado: $(docker --version)"
    fi

    if ! docker info &>/dev/null; then
        warn "O Docker daemon nao esta rodando. Tentando iniciar..."
        sudo systemctl start docker 2>/dev/null || true
        sleep 3
        if ! docker info &>/dev/null; then
            error "Nao foi possivel iniciar o Docker daemon."
            error "Tente: sudo systemctl start docker"
            exit 1
        fi
    fi
    info "Docker daemon esta rodando."
}

# -------------------------------------------------------------------------
# Verificar Docker Compose
# -------------------------------------------------------------------------
check_docker_compose() {
    if docker compose version &>/dev/null; then
        info "Docker Compose (plugin) encontrado: $(docker compose version --short)"
    elif command -v docker-compose &>/dev/null; then
        info "Docker Compose (standalone) encontrado: $(docker-compose --version)"
        warn "Recomendado atualizar para o plugin: docker compose"
    else
        error "Docker Compose nao encontrado."
        error "Instale via: https://docs.docker.com/compose/install/"
        exit 1
    fi
}

# -------------------------------------------------------------------------
# Abrir navegador
# -------------------------------------------------------------------------
open_browser() {
    local url="$1"
    if command -v xdg-open &>/dev/null; then
        xdg-open "$url" &>/dev/null &
    elif command -v open &>/dev/null; then
        open "$url"
    elif command -v wslview &>/dev/null; then
        wslview "$url"
    else
        warn "Nao foi possivel abrir o navegador automaticamente."
        info "Acesse manualmente: $url"
    fi
}

# -------------------------------------------------------------------------
# Aguardar URL ficar pronta
# -------------------------------------------------------------------------
wait_for_url() {
    local url="$1"
    local label="$2"
    info "Aguardando $label ficar pronto..."
    local max_attempts=60
    local attempt=0

    while [ $attempt -lt $max_attempts ]; do
        local status
        status=$(curl -s -o /dev/null -w "%{http_code}" "$url" 2>/dev/null || echo "000")
        if [[ "$status" =~ ^[23] ]]; then
            return 0
        fi
        attempt=$((attempt + 1))
        sleep 3
        printf "."
    done
    echo ""
    return 1
}

# -------------------------------------------------------------------------
# Encerrar todos os containers
# -------------------------------------------------------------------------
stop_all() {
    echo ""
    info "Encerrando todos os containers..."
    docker compose down
    info "Containers encerrados."
}

# =========================================================================
# MAIN
# =========================================================================
main() {
    echo ""
    echo -e "${CYAN}==========================================${NC}"
    echo -e "${CYAN}  Invest Alert - Inicializacao${NC}"
    echo -e "${CYAN}==========================================${NC}"
    echo ""

    if [ ! -f "$COMPOSE_FILE" ]; then
        error "Arquivo $COMPOSE_FILE nao encontrado."
        error "Execute este script na raiz do projeto."
        exit 1
    fi

    # 1. Verificar Docker e Docker Compose
    check_docker
    check_docker_compose
    echo ""

    # 2. Subir containers
    info "Subindo todos os containers do Invest Alert..."
    info "Isso pode levar alguns minutos na primeira vez (download de imagens + build)."
    echo ""

    docker compose up --build -d

    echo ""
    info "Containers iniciados!"
    echo ""

    # 3. Aguardar frontend e abrir navegador
    if wait_for_url "$FRONTEND_URL" "Frontend (invest-alert-front)"; then
        echo ""
        info "Frontend pronto!"
        info "Abrindo navegador em $FRONTEND_URL ..."
        open_browser "$FRONTEND_URL"
    else
        echo ""
        warn "O frontend ainda esta iniciando."
        warn "Aguarde mais alguns segundos e acesse: $FRONTEND_URL"
    fi

    echo ""
    echo -e "${CYAN}==========================================${NC}"
    info "Frontend:  $FRONTEND_URL"
    info "API:       http://localhost:8080"
    info "RabbitMQ:  http://localhost:15672"
    info "Logs:      docker compose logs -f"
    echo -e "${CYAN}==========================================${NC}"
    echo ""

    # 4. Aguardar comando para encerrar
    read -rp "Pressione ENTER para encerrar todos os containers..."

    stop_all
}

main
