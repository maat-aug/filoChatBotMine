-- =============================================================
-- FLEET DRONE v1
-- =============================================================

local ID = os.getComputerID()
local NAME
local MANAGER_ID
local PROTOCOL_FLEET = "filo_fleet"
local PROTOCOL_REGISTER = "filo_register"
local PROTOCOL_SCAN = "filo_scan"
local PROTOCOL_REGISTER_SCAN = "filo_register_scan"

local nameFile = "name.dat"
local obstacleFile = "obstacles.dat"

local currentX, currentY, currentZ, currentDirection, garageData
local obstacles = {}
local FUEL_LIMIT = 500
local CRITICAL_FUEL = 100
local ATTEMPT_TIMEOUT = 60
local TRASH_SLOT_LIMIT = 32 

peripheral.find("modem", rednet.open)

-- =====================
-- 1. FUNÇÕES BASE
-- =====================
local function loadName()
    if not fs.exists(nameFile) then return nil end
    local f = fs.open(nameFile, "r")
    local data = f.readAll()
    f.close()
    if type(data) ~= "string" or #data == 0 or string.find(data, "table:") then return nil end
    return data:gsub("^%s*(.-)%s*$", "%1")
end

local function saveName(n)
    local f = fs.open(nameFile, "w")
    f.write(tostring(n):gsub("^%s*(.-)%s*$", "%1"))
    f.close()
end

local function loadObstacles()
    if fs.exists(obstacleFile) then
        local f = fs.open(obstacleFile, "r")
        local data = f.readAll()
        f:close()
        if data then
            local s, d = pcall(textutils.unserialize, data)
            if s and type(d) == "table" then obstacles = d end
        end
    end
end

local function saveObstacles()
    local f = fs.open(obstacleFile, "w")
    f:write(textutils.serialize(obstacles))
    f:close()
end

local function runGarageSetup()
    term.clear()
    print("--- CONFIGURACAO DA GARAGEM ---")
    local gx, gy, gz, gdir
    repeat 
        write("Digite as coords X Y Z: ")
        local input = read()
        if input then gx, gy, gz = input:match("^(%-?%d+)%s+(%-?%d+)%s+(%-?%d+)$") end
        if not gx then print("Invalido. Ex: 10 -5 20") end 
    until gx
    repeat 
        write("Direcao (0=N, 1=L, 2=S, 3=O): ")
        local input = read()
        gdir = tonumber(input)
        if not (gdir and gdir >= 0 and gdir <= 3) then print("Invalido.") end 
    until (gdir and gdir >= 0 and gdir <= 3)
    return {x=tonumber(gx), y=tonumber(gy), z=tonumber(gz), dir=gdir}
end

-- =====================
-- 2. FUNÇÃO DE COLETA
-- =====================
local function smartSuck(itemName, qty)
    local chest = peripheral.wrap("bottom")
    
    if chest then
        print("Analisando bau...")
        local list = chest.list()
        local targetSlot = -1
        local trashCount = 0
        local totalAvailable = 0
        
        for slot, item in pairs(list) do
            if item.name == itemName then
                if targetSlot == -1 then targetSlot = slot end
                totalAvailable = totalAvailable + item.count
            elseif targetSlot == -1 then
                trashCount = trashCount + 1
            end
        end

        if targetSlot == -1 then return 0 end
        if trashCount > TRASH_SLOT_LIMIT then 
            print("Abortando: Item muito fundo ("..trashCount.." lixo).")
            return 0 
        end
    else
        print("Modo cego (sem periferico).")
    end

    local startCount = 0
    for i=1,16 do 
        local d = turtle.getItemDetail(i)
        if d and d.name == itemName then startCount = startCount + d.count end
    end

    local wasteSlots = {} 
    
    while true do
        local currentCount = 0
        for i=1,16 do 
            local d = turtle.getItemDetail(i)
            if d and d.name == itemName then currentCount = currentCount + d.count end
        end
        
        if currentCount >= (startCount + qty) then break end
        
        local freeSlot = -1
        for i=1, 16 do if turtle.getItemCount(i) == 0 then freeSlot = i; break end end
        
        if freeSlot == -1 then
            print("Inventario cheio.")
            break 
        end
        
        turtle.select(freeSlot)
        
        if turtle.suckDown() then
            local detail = turtle.getItemDetail(freeSlot)
            if detail.name == itemName then
                -- Item certo, continua
            else
                table.insert(wasteSlots, freeSlot)
            end
        else
            break
        end
    end
    
    if #wasteSlots > 0 then
        print("Limpando lixo...")
        for _, slot in ipairs(wasteSlots) do turtle.select(slot); turtle.dropDown() end
    end
    
    turtle.select(1)
    
    local finalCount = 0
    for i=1,16 do 
        local d = turtle.getItemDetail(i)
        if d and d.name == itemName then finalCount = finalCount + d.count end
    end
    
    return finalCount - startCount
end

-- =====================
-- 3. NAVEGAÇÃO
-- =====================
local function heuristic(x1,y1,z1,x2,y2,z2) return math.abs(x1-x2) + math.abs(y1-y2) + math.abs(z1-z2) end
local function face(dir)
    local turns = (dir - currentDirection + 4) % 4
    if turns == 1 then turtle.turnRight() elseif turns == 2 then turtle.turnRight(); turtle.turnRight() elseif turns == 3 then turtle.turnLeft() end
    currentDirection = dir
end

function findPathAStar(startX, startY, startZ, endX, endY, endZ, blocked, attemptNum, startTime)
    local startNode = {x=startX, y=startY, z=startZ, g=0, h=heuristic(startX,startY,startZ,endX,endY,endZ), p=nil}
    startNode.f = startNode.g + startNode.h
    local openSet = {startNode}; local closedSet = {}; local openKeys = {[startX..":"..startY..":"..startZ] = true}
    local lastPrintTime = -1
    while #openSet > 0 do 
        local elapsed = math.floor(os.clock() - startTime)
        if elapsed > ATTEMPT_TIMEOUT then return "TIMEOUT" end
        if elapsed > lastPrintTime then
            local _, yCursor = term.getCursorPos()
            term.setCursorPos(1, yCursor); term.clearLine()
            write("Calc rota ("..attemptNum..") "..elapsed.."s"); lastPrintTime = elapsed
        end
        sleep(0); table.sort(openSet, function(a,b) return a.f < b.f end)
        local current = table.remove(openSet, 1); local currentKey = current.x..":"..current.y..":"..current.z
        openKeys[currentKey] = nil
        if current.x == endX and current.y == endY and current.z == endZ then 
            print(""); local path = {}; local temp = current; while temp do table.insert(path, 1, temp); temp = temp.p end; return path 
        end
        closedSet[currentKey] = true
        local neighbors = {{0,1,0}, {0,-1,0}, {0,0,-1}, {0,0,1}, {1,0,0}, {-1,0,0}}
        for _, n in ipairs(neighbors) do 
            local nX, nY, nZ = current.x + n[1], current.y + n[2], current.z + n[3]
            local nKey = nX..":"..nY..":"..nZ
            if not closedSet[nKey] and not blocked[nKey] then 
                local g = current.g + 1
                if not openKeys[nKey] then 
                    local h = heuristic(nX, nY, nZ, endX, endY, endZ)
                    local newNode = {x=nX, y=nY, z=nZ, g=g, h=h, f=g+h, p=current}
                    table.insert(openSet, newNode); openKeys[nKey] = true 
                end 
            end 
        end 
    end
    print(""); return nil
end

function goTo(targetX, targetY, targetZ)
    if currentX == targetX and currentY == targetY and currentZ == targetZ then return true end
    local attempts = 0
    while true do
        attempts = attempts + 1; local attemptStartTime = os.clock()
        if obstacles[targetX..":"..targetY..":"..targetZ] then print("Destino bloqueado!"); return false, "destination_obstructed" end
        local path = findPathAStar(currentX, currentY, currentZ, targetX, targetY, targetZ, obstacles, attempts, attemptStartTime)
        if path == "TIMEOUT" then print("TIMEOUT rota"); return false, "timeout"
        elseif not path then
            if attempts == 1 and next(obstacles) ~= nil then print("Limpando memoria..."); obstacles = {}; saveObstacles() else print("Rota impossivel."); return false, "no_path" end
        else
            local pathSuccess = true
            for i = 2, #path do
                if (os.clock() - attemptStartTime) > ATTEMPT_TIMEOUT then print("TIMEOUT mov."); return false, "timeout_mov" end
                local node = path[i]; local dx, dy, dz = node.x - currentX, node.y - currentY, node.z - currentZ
                if dy == 0 then if dx == 1 then face(1) elseif dx == -1 then face(3) elseif dz == 1 then face(2) elseif dz == -1 then face(0) end end
                local moveCmd = dy == 1 and "up" or (dy == -1 and "down" or "forward")
                if not turtle[moveCmd]() then
                    local inspectCmd = "inspect" .. (moveCmd == "up" and "Up" or (moveCmd == "down" and "Down" or ""))
                    local isBlock, _ = turtle[inspectCmd]()
                    if isBlock then
                        local obsKey = node.x..":"..node.y..":"..node.z; obstacles[obsKey] = true; saveObstacles(); print("Bloqueio: " .. obsKey)
                        if node.x == targetX and node.y == targetY and node.z == targetZ then return false, "obstructed" end
                        pathSuccess = false; break 
                    else
                        sleep(0.5); if not turtle[moveCmd]() then return false, "entity_block" end
                        currentX, currentY, currentZ = node.x, node.y, node.z
                    end
                else currentX, currentY, currentZ = node.x, node.y, node.z end
                sleep(0.1)
            end
            if pathSuccess then return true end
        end
    end
end

-- =====================
-- 4. COMBUSTIVEL
-- =====================
local function handleRefuel(fuelStationCoords)
    local level = turtle.getFuelLevel(); if level == "unlimited" then return true end
    for i = 1, 16 do turtle.select(i); if turtle.refuel(0) then turtle.refuel() end end; turtle.select(1)
    if turtle.getFuelLevel() < FUEL_LIMIT then
        if not fuelStationCoords then if turtle.getFuelLevel() > CRITICAL_FUEL then return true else return false, "no_fuel" end end
        if not goTo(fuelStationCoords.x, fuelStationCoords.y + 1, fuelStationCoords.z) then return false, "fuel_path_fail" end
        turtle.select(16); turtle.suckDown(64); turtle.refuel(); if turtle.getItemCount(16)>0 then turtle.dropDown() end
    end
    return true
end

-- =====================
-- 5. INICIALIZAÇÃO
-- =====================
term.clear(); term.setCursorPos(1,1); print("Iniciando Drone v1...")
NAME = loadName()
if not NAME then
    write("Nome do Drone: ")
    local input = read()
    if input and #input > 0 then NAME = input; saveName(NAME); NAME = loadName(); print("Nome salvo.") else print("Nome invalido."); return end
else print("Identidade: " .. NAME) end
loadObstacles()
print("ID #"..ID..". Buscando servidor...")

while true do
    rednet.broadcast({protocol = PROTOCOL_REGISTER, cmd = "REQUEST_REGISTRATION", name = NAME}, PROTOCOL_REGISTER)
    local senderId, msg = rednet.receive(PROTOCOL_REGISTER, 5)
    if senderId and msg then
        MANAGER_ID = senderId
        if msg.cmd == "REGISTRATION_SUCCESS" then garageData = msg.garage; print("Registrado!"); break
        elseif msg.cmd == "FIRST_TIME_SETUP" then garageData = runGarageSetup(); rednet.send(MANAGER_ID, {protocol = PROTOCOL_REGISTER, cmd = "SUBMIT_SETUP", name = NAME, garage = garageData}, PROTOCOL_REGISTER)
        elseif msg.cmd == "SETUP_COMPLETE" then print("Setup OK."); break end
    else write(".") end
end
sleep(1)
currentX, currentY, currentZ, currentDirection = garageData.x, garageData.y, garageData.z, garageData.dir
print("\nPronto. Garagem: "..currentX..","..currentY..","..currentZ)

-- =====================
-- 6. LOOP PRINCIPAL (PING PRIORITY + MULTI TRIP)
-- =====================
while true do
    local sender, job = rednet.receive(nil, 0.1)

    if sender and type(job) == "table" then
        
        if job.cmd == "PING" then
            rednet.send(sender, {cmd="PONG"}, PROTOCOL_FLEET)
        
        elseif sender == MANAGER_ID and job.cmd == "JOB_ASSIGN" and (job.protocol == PROTOCOL_FLEET or job.protocol == PROTOCOL_SCAN) then
            print("\n>>> TAREFA: "..tostring(job.mode))
            
            local jobSuccess = true
            local failReason = ""
            local totalNeeded = job.qty or 0
            local totalMoved = 0
            local isInfiniteMode = (job.mode == "empty_blind")
            
            -- Loop Multi-Trip
            while (isInfiniteMode or totalMoved < totalNeeded) and jobSuccess do
                local ok, r = handleRefuel(job.fuelStation)
                if not ok then jobSuccess=false; failReason="Refuel: "..(r or "?"); break end
                
                -- Origem
                print("-> Origem")
                ok, r = goTo(job.fromCoords.x, job.fromCoords.y + 1, job.fromCoords.z)
                if not ok then jobSuccess=false; failReason="Path Origin: "..(r or "?"); break end
                
                -- Coletar
                print("Coletando...")
                local collectedNow = 0
                
                if job.collect_type == "AE2_API_PULL" then
                    local bridge = peripheral.find("me_bridge")
                    if bridge then
                        local needed = totalNeeded - totalMoved
                        local exported = bridge.exportItem({name=job.item, count=needed}, "up")
                        if exported > 0 then collectedNow = exported else if not isInfiniteMode then jobSuccess=false; failReason="AE2 Vazio/Erro" end end
                    else jobSuccess=false; failReason="Sem Bridge" end
                
                elseif job.collect_type == "SUCK_IO" or job.mode == "specific" then
                    local needed = totalNeeded - totalMoved
                    collectedNow = smartSuck(job.item, needed)
                
                elseif isInfiniteMode then
                    for i=1,16 do turtle.suckDown(64) end
                    for i=1,16 do collectedNow = collectedNow + turtle.getItemCount(i) end
                end
                
                if collectedNow == 0 then
                    if isInfiniteMode then break elseif totalMoved < totalNeeded then jobSuccess=false; failReason="Fonte esgotada." end
                    break
                end
                
                totalMoved = totalMoved + collectedNow
                print("Total: "..totalMoved)

                -- Destino
                print("-> Destino")
                ok, r = goTo(job.toCoords.x, job.toCoords.y + 1, job.toCoords.z)
                if not ok then jobSuccess=false; failReason="Path Dest: "..(r or "?"); break end
                
                print("Entregando...")
                if job.deliver_type == "AE2_API_PUSH" then
                    local bridge = peripheral.find("me_bridge")
                    if bridge then 
                        for i=1,16 do 
                            turtle.select(i)
                            local d = turtle.getItemDetail(i)
                            
                            if d and d.count > 0 then 
                                local imported = bridge.importItem(d, "up")
                                if imported == 0 and job.mode ~= "empty_blind" then
                                    print("Aviso: Falha na importacao do item "..d.name)
                                end
                            end 
                        end 
                    else 
                        jobSuccess=false; failReason="Sem Bridge Destino" 
                    end
                else 
                    for i=1,16 do turtle.select(i); turtle.dropDown() end 
                end
                turtle.select(1)
            end
            
            -- Retorno
            print("Retornando...")
            goTo(garageData.x, garageData.y, garageData.z); face(garageData.dir)
            
            if jobSuccess then
                for i=1,3 do rednet.send(MANAGER_ID, {protocol=PROTOCOL_FLEET, cmd="JOB_DONE", name=NAME}, PROTOCOL_FLEET); sleep(0.5) end
                print("TAREFA CONCLUIDA.")
            else
                for i=1,3 do rednet.send(MANAGER_ID, {protocol=PROTOCOL_FLEET, cmd="JOB_FAIL", name=NAME, reason=failReason}, PROTOCOL_FLEET); sleep(0.5) end
                print("FALHA: "..tostring(failReason))
            end
        end
    end
end
