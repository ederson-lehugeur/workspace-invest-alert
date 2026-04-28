# Invest Alert - Como executar

## Requisitos

- [Docker](https://docs.docker.com/engine/install/) instalado e rodando
- [Docker Compose](https://docs.docker.com/compose/install/) (incluido no Docker Desktop)

---

## Linux / macOS

O script `start.sh` verifica e instala o Docker automaticamente se necessario, sobe todos os containers e abre o navegador no frontend.

```bash
chmod +x start.sh
./start.sh
```

Pressione **ENTER** no terminal para encerrar todos os containers quando quiser parar.

---

## Windows

O script `start.ps1` verifica e instala o Docker Desktop automaticamente via `winget` se necessario, sobe todos os containers e abre o navegador no frontend.

Abra o PowerShell na pasta do projeto e execute:

```powershell
powershell -ExecutionPolicy Bypass -File start.ps1
```

Ou clique com o botao direito no arquivo `start.ps1` e selecione **"Executar com PowerShell"**.

Pressione **ENTER** no terminal para encerrar todos os containers quando quiser parar.

---

## Execucao manual com Docker Compose

Se preferir controlar os containers diretamente:

**Subir todos os servicos:**
```bash
docker compose up --build -d
```

**Acompanhar os logs em tempo real:**
```bash
docker compose logs -f
```

**Encerrar todos os containers:**
```bash
docker compose down
```

---

## Servicos e portas

| Servico            | URL                                      |
|--------------------|------------------------------------------|
| Frontend           | http://localhost:4200                    |
| API                | http://localhost:8080                    |
| RabbitMQ (painel)  | http://localhost:15672                   |
| MySQL              | localhost:3307                           |

> Credenciais padrao do RabbitMQ: `guest` / `guest`

---

## Variaveis de ambiente

As configuracoes ficam no arquivo `.env` na raiz do projeto. Edite-o antes de subir os containers para ajustar SMTP, JWT secret, timezone e outros parametros.
