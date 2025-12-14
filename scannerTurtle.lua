-- =============================================================
-- STATIC SCANNER v1
-- =============================================================

local ID = os.getComputerID()
local NAME_FILE = "storage_name.dat"
local PROTOCOL_SCAN = "filo_scan" 
local PROTOCOL_REGISTER_SCAN = "filo_register_scan"

local STORAGE_NAME = nil
local MANAGER_ID = nil 

peripheral.find("modem", rednet.open)

-- =====================
-- FUNÇÕES ÚTEIS
-- =====================
local function loadName()
    if not fs.exists(NAME_FILE) then return nil end
    local f = fs.open(NAME_FILE, "r")
    local data = f.readAll()
    f.close()
    if type(data) ~= "string" or #data == 0 or data:find("table:") then return nil end
    return data:gsub("^%s*(.-)%s*$", "%1")
end

local function saveName(n)
    local f = fs.open(NAME_FILE, "w")
    f.write(tostring(n):gsub("^%s*(.-)%s*$", "%1"))
    f.close()
end

local function runSetup()
    term.clear(); term.setCursorPos(1,1)
    print("--- CONFIG SCANNER ---")
    local name = loadName()
    if not name then
        write("Nome deste Storage: ")
        local input = read()
        if input and #input > 0 then
            saveName(input); name = loadName(); print("Salvo: "..name)
        else
            print("Invalido."); sleep(2); return nil
        end
    else print("Carregado: " .. name) end
    sleep(1); return name
end

-- =====================
-- SCAN 360 GRAUS (Procura em todos os lados)
-- =====================
local function scanInventory()
    local sides = {"top", "bottom", "front", "back", "left", "right"}
    
    for _, side in pairs(sides) do
        local p = peripheral.wrap(side)
        if p and p.list then
            return p.list(), side 
        end
    end
    return nil, "Nenhum bau conectado."
end

-- =====================
-- INICIALIZAÇÃO
-- =====================
STORAGE_NAME = runSetup()
if not STORAGE_NAME then return end

print("Scanner: "..STORAGE_NAME.." (#"..ID..")")
print("Buscando Manager...")

while MANAGER_ID == nil do
    rednet.broadcast({protocol=PROTOCOL_REGISTER_SCAN, cmd="SCANNER_READY", storageName=STORAGE_NAME}, PROTOCOL_REGISTER_SCAN)
    local sender, msg = rednet.receive(PROTOCOL_REGISTER_SCAN, 5)
    if sender and msg and msg.cmd == "MANAGER_CONFIRM" then
        MANAGER_ID = sender
        print("Conectado ao Manager #"..MANAGER_ID)
        break
    end
    write(".")
end

-- =====================
-- LOOP PRINCIPAL
-- =====================
while true do
    local sender, msg = rednet.receive(PROTOCOL_SCAN)

    if sender == MANAGER_ID and type(msg) == "table" then
        
        if msg.cmd == "REQUEST_INVENTORY" and msg.storageName == STORAGE_NAME then
            print("Recebido pedido de scan...")
            local items, reason = scanInventory()

            if items then
                rednet.send(MANAGER_ID, {
                    protocol=PROTOCOL_SCAN, 
                    cmd="INVENTORY_REPORT", 
                    storageName=STORAGE_NAME, 
                    items=items 
                }, PROTOCOL_SCAN)
                print("Enviado. ("..reason..")")
            else
                rednet.send(MANAGER_ID, {
                    protocol=PROTOCOL_SCAN, 
                    cmd="SCAN_FAIL", 
                    storageName=STORAGE_NAME, 
                    reason=reason 
                }, PROTOCOL_SCAN)
                print("Erro: "..reason)
            end
        end
    end
end
