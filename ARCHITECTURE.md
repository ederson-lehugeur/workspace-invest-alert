# Invest Alert - Arquitetura

## Visao Geral

O Invest Alert e um sistema de monitoramento de ativos de renda variavel (acoes e FIIs) que permite ao usuario configurar regras de alerta baseadas em indicadores financeiros. Quando uma regra e satisfeita, o sistema dispara uma notificacao por e-mail.

A arquitetura e orientada a microsservicos, com comunicacao assincrona via mensageria (RabbitMQ) entre os servicos de processamento, e um banco de dados MySQL centralizado compartilhado por todos os servicos.

---

## Diagrama de Arquitetura

```
                        ┌─────────────────────────────────────────────────────────────────┐
                        │                        Sistema Invest Alert                      │
                        │                                                                  │
  ┌──────────┐          │  ┌──────────────────┐        ┌──────────────────────────────┐   │
  │  Usuario │──────────┼─▶│ invest-alert-    │        │                              │   │
  └──────────┘  HTTP    │  │ front            │        │         MySQL                │   │
                        │  │ :4200            │        │         :3307                │   │
                        │  └────────┬─────────┘        │                              │   │
                        │           │ REST              └──────────────────────────────┘   │
                        │           ▼                     ▲        ▲        ▲        ▲     │
                        │  ┌──────────────────┐           │        │        │        │     │
                        │  │ invest-alert-api │───────────┘        │        │        │     │
                        │  │ :8080            │                    │        │        │     │
                        │  └──────────────────┘                    │        │        │     │
                        │                                          │        │        │     │
                        │  ┌──────────────────┐                    │        │        │     │
                        │  │ scheduler-       │───────────────────-┘        │        │     │
                        │  │ service          │                              │        │     │
                        │  └────────┬─────────┘                             │        │     │
                        │           │                                        │        │     │
                        │    ┌──────┴──────┐  RabbitMQ                      │        │     │
                        │    ▼             ▼  :5672                          │        │     │
                        │  [asset.update] [alert.notify]                     │        │     │
                        │    │             │                                 │        │     │
                        │    ▼             ▼                                 │        │     │
                        │  ┌──────────┐  ┌──────────────┐                   │        │     │
                        │  │ asset-   │  │ dispatcher-  │───────────────────┘        │     │
                        │  │ update-  │  │ service      │                            │     │
                        │  │ service  │  └──────┬───────┘                            │     │
                        │  └──────────┘         │                                    │     │
                        │       │               │ SMTP                               │     │
                        │       └───────────────┼────────────────────────────────────┘     │
                        │                       ▼                                          │
                        │                  ┌─────────┐                                    │
                        │                  │  E-MAIL │                                    │
                        │                  └─────────┘                                    │
                        └─────────────────────────────────────────────────────────────────┘
```

---

## Servicos

### invest-alert-front
Interface web Angular servida via Nginx. Permite ao usuario se cadastrar, autenticar, visualizar ativos, criar grupos de regras e acompanhar o historico de alertas disparados.

- Porta: `4200`
- Tecnologia: Angular + Nginx

---

### invest-alert-api
API REST principal do sistema. Responsavel pelo CRUD de todos os recursos e pela autenticacao JWT.

- Porta: `8080`
- Tecnologia: Spring Boot

Endpoints disponiveis:

| Recurso       | Operacoes                                      |
|---------------|------------------------------------------------|
| Auth          | Registro e login de usuarios                   |
| Assets        | Listagem e consulta de ativos                  |
| Rules         | Criacao, edicao, ativacao e remocao de regras  |
| Rule Groups   | Agrupamento de regras por ativo                |
| Alerts        | Historico de alertas disparados                |

---

### scheduler-service
Servico de agendamento responsavel por dois jobs periodicos executados via Quartz Scheduler. O intervalo e configuravel via variavel de ambiente `SCHEDULER_INTERVAL_MS` (padrao: 5 minutos).

- Tecnologia: Spring Boot + Quartz

**Job 1 - RuleEvaluationJob**
Busca todas as regras ativas no banco, avalia cada uma contra os valores atuais do ativo correspondente e, para as regras satisfeitas, publica uma mensagem na fila `alert.notify` do RabbitMQ para o `dispatcher-service` processar.

**Job 2 - AssetUpdateRequestJob**
Busca todos os ativos cadastrados e publica uma mensagem na fila `asset.update` do RabbitMQ para o `asset-update-service` atualizar os valores.

---

### asset-update-service
Consumidor da fila `asset.update`. Recebe a solicitacao de atualizacao de um ativo e aplica uma variacao simulada nos seus indicadores, persistindo os novos valores no banco.

- Tecnologia: Spring Boot + RabbitMQ

A simulacao e feita pelo `PriceVariationEngine`, que aplica variacoes aleatorias dentro de limites definidos:

| Indicador       | Variacao maxima |
|-----------------|-----------------|
| Preco (price)   | ± 5%            |
| Dividend Yield  | ± 1%            |
| P/VP            | ± 1%            |

> Os valores sao simulados pois a integracao com uma API de mercado real e um trabalho futuro.

---

### dispatcher-service
Consumidor da fila `alert.notify`. Recebe o evento de alerta disparado pelo `scheduler-service`, monta o conteudo do e-mail e realiza o envio via SMTP. Apos o envio, atualiza o status do alerta no banco para `SENT`.

- Tecnologia: Spring Boot + RabbitMQ + JavaMail

Canais de notificacao:
- E-mail (implementado)
- SMS (nao implementado)
- WhatsApp / Telegram (nao implementado)

---

### MySQL
Banco de dados centralizado compartilhado por todos os servicos. A decisao de usar um banco unico foi intencional para reduzir a complexidade operacional do projeto.

- Porta: `3307` (mapeada externamente)
- Imagem: `mysql:8.4`
- Charset: `utf8mb4` / `utf8mb4_unicode_ci`

---

### RabbitMQ
Broker de mensagens responsavel pela comunicacao assincrona entre o `scheduler-service`, o `asset-update-service` e o `dispatcher-service`.

- Porta AMQP: `5672`
- Painel de gerenciamento: `15672`

---

## Modelo de Dominio

### Regras de Alerta

Uma **Rule** define uma condicao de disparo para um ativo especifico. Campos monitoraveis:

- `PRICE` - preco atual
- `DIVIDEND_YIELD` - dividend yield
- `P_VP` - relacao preco/valor patrimonial

Operadores suportados: `GREATER_THAN`, `LESS_THAN`, `GREATER_THAN_OR_EQUAL`, `LESS_THAN_OR_EQUAL`, `EQUAL`

Exemplo: _"Disparar alerta quando o preco de MXRF11 for menor que R$ 9,50"_

### Grupos de Regras

Um **RuleGroup** agrupa multiplas regras de um mesmo ativo, facilitando a organizacao pelo usuario.

### Alertas

Um **Alert** e gerado quando uma regra e avaliada como verdadeira. Possui status `PENDING` ate ser processado pelo `dispatcher-service`, quando passa para `SENT`.

---

## Fluxo Principal

```
1. Usuario cria uma Rule via invest-alert-front
        │
        ▼
2. invest-alert-api persiste a regra no MySQL
        │
        ▼
3. scheduler-service (RuleEvaluationJob) avalia periodicamente as regras ativas
        │
        ├── Regra satisfeita?
        │       │
        │       ▼
        │   Publica mensagem em [alert.notify]
        │       │
        │       ▼
        │   dispatcher-service envia e-mail e marca alerta como SENT
        │
        └── Sempre: publica mensagem em [asset.update]
                │
                ▼
            asset-update-service aplica variacao simulada e persiste novos valores
```

---

## Decisoes de Design

- **Banco centralizado** - Um unico MySQL para todos os servicos reduz a complexidade de infraestrutura sem comprometer os objetivos do projeto.
- **Simulacao de precos** - Os valores dos ativos sao atualizados com variacoes aleatorias controladas, eliminando a dependencia de uma API de mercado externa durante o desenvolvimento.
- **Comunicacao assincrona** - O uso de RabbitMQ desacopla o agendamento do envio de notificacoes e da atualizacao de ativos, tornando cada servico independente e resiliente a falhas pontuais.
- **Arquitetura hexagonal** - Todos os servicos seguem o padrao de portas e adaptadores (Hexagonal Architecture), separando dominio, aplicacao e infraestrutura.
- **API Gateway** - Previsto mas nao implementado. O frontend se comunica diretamente com a `invest-alert-api`.
