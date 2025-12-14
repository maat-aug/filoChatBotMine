-- =============================================================
-- REDSTONE NODE v1
-- =============================================================


local CONFIG_FILE = "redstone_config.txt"
local PROTOCOL = "filo_redstone"
local DEVICE_NAME = ""
local SIDE = ""

-- =====================
-- 1. FUNÇÕES DE CONFIGURAÇÃO
-- =====================

local function loadConfig()
    if fs.exists(CONFIG_FILE) then
        local file = fs.open(CONFIG_FILE, "r")
        local data = file.readAll()
        file.close()
        
        local config = textutils.unserialize(data)
        if config and type(config) == "table" then
            DEVICE_NAME = config.name
            SIDE = config.side
            return true
        end
    end
    return false
end

local function saveConfig(name, side)
    local file = fs.open(CONFIG_FILE, "w")
    file.write(textutils.serialize({name = name, side = side}))
    file.close()
end

local function runSetup()
    term.clear()
    term.setCursorPos(1,1)
    print("--- CONFIGURACAO DO NODE REDSTONE ---")
    
    local name
    repeat
        write("Nome deste dispositivo (ex: LuzSala): ")
        name = read()
    until (name and #name > 0)
    
    local side
    repeat
        write("Lado da redstone (ex: back, top): ")
        side = read()
    until (side and #side > 0)
    
    -- Salva as configurações
    saveConfig(name, side)
    
    -- Atualiza as variáveis globais
    DEVICE_NAME = name
    SIDE = side
    
    print("\nConfiguracao salva!")
    sleep(2)
end

-- =====================
-- 2. INICIALIZAÇÃO
-- =====================

if not loadConfig() then
    runSetup()
end

local modem = peripheral.find("modem", function(n, o) return o.isWireless() end)
if not modem then error("Requer Modem Wireless!") end
rednet.open(peripheral.getName(modem))

term.clear()
term.setCursorPos(1,1)
print("NODE REDSTONE: " .. DEVICE_NAME)
print("Lado Ativo: " .. SIDE)
print("Protocolo: " .. PROTOCOL)
print("--------------------------")
print("Aguardando comandos...")

-- =====================
-- 3. LOOP PRINCIPAL
-- =====================
while true do
    local senderId, msg = rednet.receive(PROTOCOL)
    
    if type(msg) == "table" and msg.target and msg.target:lower() == DEVICE_NAME:lower() then
        local action = msg.action:upper()
        
        print("Recebido: " .. action)
        
        if action == "ON" then
            redstone.setOutput(SIDE, true)
            print("Estado: LIGADO")
            
        elseif action == "OFF" then
            redstone.setOutput(SIDE, false)
            print("Estado: DESLIGADO")
            
        elseif action == "TOGGLE" then
            local currentState = redstone.getOutput(SIDE)
            redstone.setOutput(SIDE, not currentState)
            print("Estado: " .. (not currentState and "LIGADO" or "DESLIGADO"))
            
        elseif action == "PULSE" then
            redstone.setOutput(SIDE, true)
            sleep(1)
            redstone.setOutput(SIDE, false)
            print("Pulso enviado.")
        end
    end
end
