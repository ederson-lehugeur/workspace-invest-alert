# =============================================================================
# Invest Alert - Script de inicializacao (Windows PowerShell)
#
# Este script:
#   1. Verifica/instala Docker Desktop
#   2. Sobe todos os containers do Invest Alert
#   3. Abre o navegador no frontend (http://localhost:4200)
#   4. Aguarda o usuario pressionar ENTER para encerrar tudo
#
# Uso: clique com botao direito -> "Executar com PowerShell"
#   ou: powershell -ExecutionPolicy Bypass -File start.ps1
# =============================================================================

$ErrorActionPreference = "Stop"

$FRONTEND_URL = "http://localhost:4200"
$COMPOSE_FILE = "docker-compose.yml"

function Write-Info  { param($msg) Write-Host "[INFO]  $msg" -ForegroundColor Green }
function Write-Warn  { param($msg) Write-Host "[AVISO] $msg" -ForegroundColor Yellow }
function Write-Err   { param($msg) Write-Host "[ERRO]  $msg" -ForegroundColor Red }

# -------------------------------------------------------------------------
# Instalar Docker Desktop via winget
# -------------------------------------------------------------------------
function Install-DockerDesktop {
    Write-Info "Tentando instalar Docker Desktop..."

    if (Get-Command winget -ErrorAction SilentlyContinue) {
        Write-Info "Instalando via winget..."
        winget install -e --id Docker.DockerDesktop --accept-source-agreements --accept-package-agreements

        Write-Warn ""
        Write-Warn "Docker Desktop foi instalado."
        Write-Warn "IMPORTANTE: Pode ser necessario reiniciar o computador."
        Write-Warn "Apos reiniciar, abra o Docker Desktop e aguarde ele iniciar."
        Write-Warn "Depois, execute este script novamente."
        Write-Warn ""
        Read-Host "Pressione ENTER para sair"
        exit 0
    }
    else {
        Write-Err "winget nao encontrado."
        Write-Err "Instale o Docker Desktop manualmente:"
        Write-Err "https://docs.docker.com/desktop/install/windows-install/"
        Write-Err ""
        Read-Host "Pressione ENTER para sair"
        exit 1
    }
}

# -------------------------------------------------------------------------
# Verificar Docker
# -------------------------------------------------------------------------
function Test-Docker {
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        Write-Warn "Docker nao encontrado."
        $resposta = Read-Host "Deseja instalar o Docker Desktop automaticamente? (s/n)"
        if ($resposta -match "^[sS]$") {
            Install-DockerDesktop
        }
        else {
            Write-Err "Docker e necessario para rodar o projeto."
            Write-Err "Instale em: https://docs.docker.com/desktop/install/windows-install/"
            Read-Host "Pressione ENTER para sair"
            exit 1
        }
    }

    Write-Info "Docker encontrado: $(docker --version)"

    $dockerRunning = $false
    try {
        docker info 2>$null | Out-Null
        $dockerRunning = $true
    }
    catch { }

    if (-not $dockerRunning) {
        Write-Warn "Docker Desktop nao esta rodando. Tentando iniciar..."

        $dockerPath = "C:\Program Files\Docker\Docker\Docker Desktop.exe"
        if (Test-Path $dockerPath) {
            Start-Process $dockerPath
            Write-Info "Aguardando Docker Desktop iniciar (pode levar ate 60 segundos)..."

            $maxWait = 60
            $waited = 0
            while ($waited -lt $maxWait) {
                Start-Sleep -Seconds 3
                $waited += 3
                try {
                    docker info 2>$null | Out-Null
                    $dockerRunning = $true
                    break
                }
                catch { }
                Write-Host "." -NoNewline
            }
            Write-Host ""
        }

        if (-not $dockerRunning) {
            Write-Err "Nao foi possivel iniciar o Docker Desktop."
            Write-Err "Abra o Docker Desktop manualmente e execute este script novamente."
            Read-Host "Pressione ENTER para sair"
            exit 1
        }
    }

    Write-Info "Docker daemon esta rodando."
}

# -------------------------------------------------------------------------
# Verificar Docker Compose
# -------------------------------------------------------------------------
function Test-DockerCompose {
    try {
        $version = docker compose version 2>$null
        Write-Info "Docker Compose encontrado: $version"
    }
    catch {
        Write-Err "Docker Compose nao encontrado."
        Write-Err "Atualize o Docker Desktop para a versao mais recente."
        Read-Host "Pressione ENTER para sair"
        exit 1
    }
}

# -------------------------------------------------------------------------
# Aguardar URL ficar pronta
# -------------------------------------------------------------------------
function Wait-ForUrl {
    param($url, $label)
    Write-Info "Aguardando $label ficar pronto..."
    $maxAttempts = 60
    $attempt = 0

    while ($attempt -lt $maxAttempts) {
        try {
            $response = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 3 -ErrorAction SilentlyContinue
            if ($response.StatusCode -ge 200 -and $response.StatusCode -lt 400) {
                return $true
            }
        }
        catch { }

        $attempt++
        Start-Sleep -Seconds 3
        Write-Host "." -NoNewline
    }

    Write-Host ""
    return $false
}

# -------------------------------------------------------------------------
# Encerrar todos os containers
# -------------------------------------------------------------------------
function Stop-AllContainers {
    Write-Host ""
    Write-Info "Encerrando todos os containers..."
    docker compose down
    Write-Info "Containers encerrados."
}

# =========================================================================
# MAIN
# =========================================================================
function Main {
    Write-Host ""
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host "  Invest Alert - Inicializacao"            -ForegroundColor Cyan
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host ""

    if (-not (Test-Path $COMPOSE_FILE)) {
        Write-Err "Arquivo $COMPOSE_FILE nao encontrado."
        Write-Err "Execute este script na raiz do projeto."
        Read-Host "Pressione ENTER para sair"
        exit 1
    }

    # 1. Verificar Docker e Docker Compose
    Test-Docker
    Test-DockerCompose
    Write-Host ""

    # 2. Subir containers
    Write-Info "Subindo todos os containers do Invest Alert..."
    Write-Info "Isso pode levar alguns minutos na primeira vez (download de imagens + build)."
    Write-Host ""

    docker compose up --build -d

    Write-Host ""
    Write-Info "Containers iniciados!"
    Write-Host ""

    # 3. Aguardar frontend e abrir navegador
    $ready = Wait-ForUrl -url $FRONTEND_URL -label "Frontend (invest-alert-front)"

    if ($ready) {
        Write-Host ""
        Write-Info "Frontend pronto!"
        Write-Info "Abrindo navegador em $FRONTEND_URL ..."
        Start-Process $FRONTEND_URL
    }
    else {
        Write-Host ""
        Write-Warn "O frontend ainda esta iniciando."
        Write-Warn "Aguarde mais alguns segundos e acesse: $FRONTEND_URL"
    }

    Write-Host ""
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Info "Frontend:  $FRONTEND_URL"
    Write-Info "API:       http://localhost:8080"
    Write-Info "RabbitMQ:  http://localhost:15672"
    Write-Info "Logs:      docker compose logs -f"
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host ""

    # 4. Aguardar comando para encerrar
    Read-Host "Pressione ENTER para encerrar todos os containers"

    Stop-AllContainers

    Write-Host ""
    Read-Host "Pressione ENTER para sair"
}

Main
