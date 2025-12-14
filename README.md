🤖 FILO AI - Sistema de ChatBot e Logística v1

<img width="640" height="640" alt="image" src="https://github.com/user-attachments/assets/e6b026a6-ca89-4d91-9d1d-c7e9265e4da4" />

## 🚨 AVISOS 🚨

> **Uso**
> *   **Chave API Exposta:** Sua chave do Gemini fica no arquivo principal. **NÃO COMPARTILHE** o arquivo `filo.lua` publicamente após inserir sua chave.
> *   **Apenas jogadores listados na tabela `ADMINS` dentro do `filo.lua` podem executar comandos.**


---

## 📦 Download do Projeto (Pastebins)

Use o comando `pastebin get <ID> <nome_do_arquivo>` para baixar cada script.

| Arquivo | Link | ID do Pastebin |
| :--- | :--- | :--- |
| **`filo.lua`** | https://pastebin.com/9PHxCbc2 | `9PHxCbc2` |
| **`fleetTurtle.lua`** | https://pastebin.com/biDiu192 | `biDiu192` |
| **`scannerTurtle.lua`** | https://pastebin.com/2dUMU16c | `2dUMU16c` |
| **`redstoneTurtle.lua`** | https://pastebin.com/axWVu3yk | `axWVu3yk` |

## 🔑 1. Configuração Crítica da API

O recurso de IA requer que você obtenha sua chave no [Google AI Studio](https://ai.google.dev/) e a insira no arquivo **`filo.lua`**.

```
local GEMINI_API_KEY = "SUA_CHAVE_AQUI" -- <<< ❌ EDITE AQUI COM SUA CHAVE! ❌
```

---

## 🌟 2. Recursos do Sistema

| Categoria | Recurso | Descrição Detalhada |
| :---: | :--- | :--- |
| **Logística** | 🐢 Frota Autônoma | Gerenciamento de fila de tarefas (`!moveStorage`, `!emptyStorage`) e despacho do Turtle mais próximo disponível. |
| **Navegação** | 🗺️ Pathfinding A* 3D | Turtles navegam com A* (o algoritmo de menor caminho), mapeando e desviando dinamicamente de blocos. |
| **Controle** | ⚡ Redstone Remoto | Acionamento de qualquer dispositivo Redstone da base via chat (`!redstone <Nome> <ON/OFF>`). |
| **Inventário** | 📦 Pings e Relatórios | Scanners estáticos e periféricos locais reportam inventário. `!pingStorage` envia alertas se o item estiver **abaixo ou acima** do limite. |
| **Interface** | 🧠 IA e Dashboard | Respostas no chat sobre Minecraft Modded via Gemini. Dashboard interativo no monitor para gerenciamento de frota e switches. |

---

## 🧱 3. Arquitetura e Instalação

O FILO é composto por 4 scripts que trabalham juntos via Rednet. Todos os scripts clientes (Drone, Scanner, Node) devem ser salvos como `startup` para iniciar automaticamente.

| Script | Local de Instalação | Finalidade | Salve como |
| :--- | :--- | :--- | :--- |
| **`filo.lua`** | 🖥️ PC Central (com periféricos) | Lógica principal, IA, Fila de Tarefas, Dashboard. | `startup` |
| **`drone_fleet.lua`** | 🐢 Turtle de Logística | Execução de Pathfinding, coleta, entrega e auto-reabastecimento. | `startup` |
| **`static_scanner.lua`** | 🔬 PC/Turtle ao lado do Storage | Coleta dados de inventários de Baús, barris, AE2, etc. | `startup` |
| **`redstone_node.lua`** | 💡 PC/Turtle ao lado do Redstone | Ativa/Desativa um bloco de Redstone específico. | `startup` |

### 3.1. Periféricos do Manager

O PC Central (`filo.lua`) deve ter os seguintes periféricos conectados:

*   `chat_box`
*   `monitor`
*   `modem` (Wireless)
*   `player_detector` (Opcional, para `!sorteio`)

---

## 📝 4. Comandos de Configuração e Uso

### 4.1. Configuração de Base

| Comando | Descrição | Exemplo |
| :--- | :--- | :--- |
| `!addStorage` | Cadastra um novo inventário no sistema. | `!addStorage bauTeste Bau NA 100 64 200` |
| `!setFuelStation` | Define as coordenadas da estação de reabastecimento. | `!setFuelStation 105 64 205` |
| `!addSwitch` | Registra um Redstone Node no dashboard. | `!addSwitch redstoneLamp` |

### 4.2. Logística e Transporte

| Comando | Descrição | Exemplo |
| :--- | :--- | :--- |
| `!moveStorage` | Move uma quantidade específica de **Item** entre Storages. | `!moveStorage Fornalha RedeAE2 ferro_ingot 64` |
| `!emptyStorage` | Esvazia **todo** o conteúdo de um Baú (Fonte) para um Destino. | `!emptyStorage Lixo BasePrincipal` |

### 4.3. Monitoramento e Alertas

| Comando | Descrição | Exemplo |
| :--- | :--- | :--- |
| `!statsStorage` | Relatório de inventário em tempo real (pode sincronizar o Scanner). | `!statsStorage RedeAE2 diamante` |
| `!pingStorage` | Cria/Atualiza um alerta de quantidade de item. | `!pingStorage carvão < 1000 Combustivel` |

### 4.4. Controle Remoto e IA

| Comando | Descrição | Exemplo |
| :--- | :--- | :--- |
| `!redstone` | Controla um Redstone Node já configurado. | `!redstone LuzCorredor ON` |
| `Filo, <pergunta>` | Inicia a interação com a IA (não precisa de `!`). | `Filo, como eu automatizo a producao de eletricidade?` |
