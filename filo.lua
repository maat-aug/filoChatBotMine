-- =============================================================
-- FILO - v1
-- =============================================================

-- =====================
-- 1. PERIFÉRICOS E CONSTANTES
-- =====================
local chat = peripheral.find("chat_box")
local playerDetector = peripheral.find("player_detector")
local monitor = peripheral.find("monitor") -- Simplificado para UM monitor
local modemWireless = peripheral.find("modem", function(n, o) return o.isWireless() end)

if modemWireless then 
    rednet.open(peripheral.getName(modemWireless)) 
else 
    error("ERRO CRITICO: Requer Modem Wireless!") 
end

if monitor then monitor.setTextScale(0.5) end

-- CONFIGURACOES DE IA
local GEMINI_API_KEY = "" -- <<< EDITE AQUI
local GEMINI_URL = "https://generativelanguage.googleapis.com/v1beta/models/gemini-flash-latest:generateContent?key=" .. GEMINI_API_KEY
local ADMINS = { ["SeuNick"] = true, ["yMatPvP_"] = true }
local BOT_PREFIX = "&4Filo&r"

-- PROTOCOLOS
local PROTOCOL_FLEET = "filo_fleet"
local PROTOCOL_REDSTONE = "filo_redstone"
local PROTOCOL_REGISTER = "filo_register"
local PROTOCOL_SCAN = "filo_scan"
local PROTOCOL_REGISTER_SCAN = "filo_register_scan"

local SYSTEM_PROMPT = [[Voce e o Filo, IA Especialista em Minecraft Modded. Seja direta mas amigavel, deve responder todas as duvidas de forma que deixe claro o que foi perguntado, e instruindo o que for que seja para que o usuario chegue ao objetivo. NUNCA USE CARACTERES ESPECIAIS, ACENTOS, OU ALGO DO TIPO]]

-- =====================
-- 2. DADOS
-- =====================
local dataFile = "filo_data.txt"
local fleetFile = "filo_fleet.txt"

local Storage = { data = {}, pings = {} } 
local Switches = {} 
local Fleet = { turtles = {} } 
local ObstacleMap = {} 
local JobQueue = {} 
local GlobalConfig = { fuelStation = nil } 

local CurrentQuiz = { answer=nil, active=false, timerID=nil }
local ButtonMap = {}
local IA_MEMORY = {} 
local PingCooldowns = {} 
local ScannerMap = {} 
local currentPage = 1
local totalPages = 4 -- Geral, Logistica, Scanner, Switches

-- AJUDA ATUALIZADA
local HELP_SECTIONS = {
    config={title="CONFIG",commands={"!addStorage <Nome> <Tipo> [Modem/NA] <X> <Y> <Z>","!setFuelStation <X> <Y> <Z>"}},
    logistica={title="LOGISTICA",commands={"!moveStorage <AE2/Bau> <Dest> <Item> <Qtd>","!emptyStorage <Bau> <Dest>"}},
    monitor={title="MONITOR",commands={"!statsStorage <Nome> [Filtro]","!pingStorage <Item> < > <Qtd> <Storage>"}},
    switches={title="SWITCHES",commands={"!addSwitch <Nome>","!delSwitch <Nome>","!redstone <Nome> <ON/OFF>"}}, 
    frota={title="FROTA",commands={"!fleet list","!fleet reset <Nome>","!fleet remove <Nome>"}},
    diversos={title="OUTROS",commands={"!quiz","!sorteio","!help"}}
}

-- =====================
-- 3. UTILITÁRIOS E PERSISTÊNCIA
-- =====================
local function sendChat(msg) 
    if chat then sleep(0.1); chat.sendMessage(tostring(msg):gsub("&%x", ""), BOT_PREFIX) 
    else print("[CHAT]: "..tostring(msg)) end 
end

local function sendTell(player, msg) 
    if chat then sleep(0.1); chat.sendMessageToPlayer(tostring(msg):gsub("&%x", ""), player, BOT_PREFIX) 
    else print("[TELL " .. player .. "]: " .. tostring(msg)) end 
end

local function jsonEscape(str) return str:gsub('\\','\\\\'):gsub('"','\\"'):gsub('\n',' '):gsub('\r','') end
local function limparTexto(str) 
    if not str then return "" end
    local s=str; s=s:gsub("Ã¡","a"):gsub("Ã©","e"):gsub("Ãed","i"):gsub("Ã³","o"):gsub("Ãº","u"):gsub("Ã£","a"):gsub("Ãµ","o"):gsub("Ã¢","a"):gsub("Ãª","e"):gsub("Ã´","o"):gsub("Ã§","c"):gsub("Ã‡","C"):gsub("Ã ","A"):gsub("&%x","")
    local res=""; for i=1, #s do local b=string.byte(s,i); if b>=32 and b<=126 then res=res..string.sub(s,i,i) end end
    return res 
end

local function saveAll()
    local f_data = fs.open(dataFile,"w")
    f_data.write(textutils.serialize({storage=Storage.data, pings=Storage.pings, switches=Switches, config=GlobalConfig}))
    f_data.close()
    local f_fleet = fs.open(fleetFile, "w")
    f_fleet.write(textutils.serialize({turtles=Fleet.turtles, obstacles=ObstacleMap}))
    f_fleet.close()
end

local function loadAll()
    if fs.exists(dataFile) then 
        local f=fs.open(dataFile,"r"); local d=textutils.unserialize(f.readAll()); f.close()
        if d then Storage.data=d.storage or {}; Storage.pings=d.pings or {}; Switches=d.switches or {}; GlobalConfig=d.config or {fuelStation=nil} end 
    end
    if fs.exists(fleetFile) then 
        local f=fs.open(fleetFile,"r"); local d=textutils.unserialize(f.readAll()); f.close()
        if d then Fleet.turtles=d.turtles or {}; ObstacleMap=d.obstacles or {} end 
    end
end

-- =====================
-- 4. SCANNER LOCAL E ALERTAS
-- =====================
local function checkPings(storageName, newItems)
    if Storage.pings[storageName] then
        for itemKey, pingData in pairs(Storage.pings[storageName]) do
            local limit = 0; local operator = "<"
            if type(pingData) == "table" then limit = pingData.limit; operator = pingData.op else limit = pingData end
            local currentQty = newItems[itemKey] or 0; local trigger = false
            if operator == "<" and currentQty < limit then trigger = true end
            if operator == ">" and currentQty > limit then trigger = true end
            if trigger then
                local key = storageName..":"..itemKey; local now = os.clock()
                if not PingCooldowns[key] or (now - PingCooldowns[key] > 600) then
                    local symbol = (operator == "<") and "BAIXO" or "ALTO"
                    sendChat("[ALERTA] Estoque "..symbol.." de "..itemKey.." em "..storageName..": "..currentQty.." (Limite: "..operator.." "..limit..")")
                    PingCooldowns[key] = now
                end
            end
        end
    end
end

function Storage.updateLocalPeripherals()
    for name, data in pairs(Storage.data) do
        if data.source and peripheral.isPresent(data.source) and not data.source:find("me_bridge") then
            local p = peripheral.wrap(data.source)
            if p and p.listItems then
                local list = p.listItems(); local newItems = {}
                for _, item in pairs(list) do if item.name and item.amount then newItems[item.name] = (newItems[item.name] or 0) + item.amount end end
                data.items = newItems; checkPings(name, newItems)
            end
        end
    end
end

-- =====================
-- 5. INTELIGÊNCIA ARTIFICIAL
-- =====================
local function gerarPerguntaQuiz() 
    if GEMINI_API_KEY:find("COLE_SUA") then sendChat("IA Offline."); return end
    if CurrentQuiz.active then sendChat("Quiz ativo!"); return end
    sendChat("Gerando pergunta..."); local prompt="Gere 1 pergunta simples sobre conhecimentos basicos SEM USAR CARACTER ESPECIAL OU ACENTO e também sem pontos finais, a resposta deve ser de uma palavra. Formato: PERGUNTA: (pergunta)|(resposta)."; local body='{"contents":[{"role":"user","parts":[{"text":"'..jsonEscape(prompt)..'"}]}]}'; local response=http.post(GEMINI_URL, body, {["Content-Type"]="application/json"})
    if not response then sendChat("Erro IA."); return end
    local raw=response.readAll(); response.close(); local txt=raw:match('"text"%s*:%s*"(.-[^\\])"') or raw:match('"text"%s*:%s*"(.-)"')
    if txt then txt=limparTexto(txt:gsub('\\n',' '):gsub('\\"','"')); local p,r=txt:match("^(.-)|(.*)$")
        if p and r then local cleanAnswer=r:match("^%s*(.-)%s*$"):lower(); CurrentQuiz.active=true; CurrentQuiz.answer=cleanAnswer; CurrentQuiz.timerID=os.startTimer(30); sendChat("[QUIZ] "..p); print("Resp: "..cleanAnswer) else sendChat("Erro formato IA.") end
    end
end

local function handleInteractionIA(player, msg)
    if GEMINI_API_KEY:find("COLE_SUA") then sendChat("IA Offline."); return end
    local clean = msg:gsub("[Ff]ilo,?", ""):match("^%s*(.-)%s*$"); if not clean or clean == "" then return end
    local parts = {}; table.insert(parts, '{"role":"user","parts":[{"text":"'..jsonEscape(SYSTEM_PROMPT)..'"}]}')
    for _, m in ipairs(IA_MEMORY) do table.insert(parts, '{"role":"'..m.role..'","parts":[{"text":"'..jsonEscape(m.text)..'"}]}') end
    table.insert(parts, '{"role":"user","parts":[{"text":"User ('..player..'): '..jsonEscape(clean)..'"}]}'); local body = '{"contents":['..table.concat(parts, ",")..']}'
    if chat then chat.sendMessage("Thinking...", BOT_PREFIX) end
    local response = http.post(GEMINI_URL, body, {["Content-Type"]="application/json"}); if not response then sendChat("Erro IA."); return end
    local raw = response.readAll(); response.close(); local txt = raw:match('"text"%s*:%s*"(.-[^\\])"') or raw:match('"text"%s*:%s*"(.-)"')
    if txt then txt = txt:gsub('\\n', ' '):gsub('\\"', '"'); local final = limparTexto(txt); table.insert(IA_MEMORY, {role="user", text=clean}); table.insert(IA_MEMORY, {role="model", text=final}); if #IA_MEMORY > 6 then table.remove(IA_MEMORY, 1) end; sendChat(final) end
end


-- =====================
-- 6. DASHBOARD
-- =====================
local function centerText(text, width)
  local x = math.floor((width - string.len(text)) / 2) + 1
  if x < 1 then x = 1 end
  return x
end

function drawDashboard()
    if not monitor then return end

    -- GUARDA/REINICIA BUTTON MAP
    ButtonMap = {}

    -- Limpa usando escala base (1.0)
    monitor.setTextScale(1.0)
    local w, h = monitor.getSize()
    monitor.setBackgroundColor(colors.black)
    monitor.clear()

    -- HEADER (Agora usa escala 1.0 para garantir visibilidade)
    local headerY = 1
    
    -- 1. Desenha a barra azul do cabeçalho
    monitor.setCursorPos(1, headerY)
    monitor.setBackgroundColor(colors.blue)
    monitor.setTextColor(colors.white)
    monitor.clearLine() 
    
    -- 2. Escreve o texto do cabeçalho
    local headerText = "FILO v1.6"
    monitor.setCursorPos(centerText(headerText, w), headerY)
    monitor.write(headerText)
    
    -- STATUS BAR (Linha 2, usa escala 1.0)
    local statusBarY = 2 
    monitor.setCursorPos(1, statusBarY) 
    
    -- 3. Desenha a barra cinza de status
    monitor.setBackgroundColor(colors.gray)
    monitor.setTextColor(colors.yellow)
    monitor.clearLine()
    local statusText = "Fila: " .. (#JobQueue or 0)
    monitor.setCursorPos(centerText(statusText, w), statusBarY) 
    monitor.write(statusText)

    -- RESTAURA COR DE FUNDO GLOBAL APÓS O STATUS BAR (garante o preto para o resto da tela)
    monitor.setBackgroundColor(colors.black)
    monitor.setTextColor(colors.white)
    
    local y = 4 -- Conteúdo começa na linha 4 (Título)
    
    -- CABEÇALHO PAGINADO (Linha 4, usa escala padrão)
    local titleHeaderY = y
    monitor.setCursorPos(1, titleHeaderY)
    monitor.setTextColor(colors.cyan)
    monitor.write("<--")
    ButtonMap[titleHeaderY] = ButtonMap[titleHeaderY] or {}
    for i=1,3 do ButtonMap[titleHeaderY][i] = "prev_page" end

    monitor.setCursorPos(w - 2, titleHeaderY)
    monitor.write("-->")
    ButtonMap[titleHeaderY] = ButtonMap[titleHeaderY] or {}
    for i=w-2, w do ButtonMap[titleHeaderY][i] = "next_page" end

    local title = ""
    if currentPage == 1 then title = "|| PAINEL GERAL ||" 
    elseif currentPage == 2 then title = "|| FROTA LOGISTICA ||" 
    elseif currentPage == 3 then title = "|| FROTA SCANNER ||" 
    elseif currentPage == 4 then title = "|| SWITCHES ||" 
    end

    monitor.setTextColor(colors.lightBlue)
    monitor.setCursorPos(centerText(title, w), titleHeaderY)
    monitor.write(title)
    y = y + 2

    -- CONTEÚDO
    if currentPage == 1 then -- GERAL
        local col1_x = 2
        local col2_x = math.floor(w/2) + 2
        local col1_w = col2_x - 2
        local col2_w = w - col2_x + 1
        local y_switches = y

        -- LOGISTICA (coluna 1)
        monitor.setTextColor(colors.white)
        monitor.setCursorPos(col1_x + centerText("Logistica", col1_w) - 1, y-1)
        monitor.write("Logistica")
        monitor.setBackgroundColor(colors.black)
        for name, info in pairs(Fleet.turtles) do
            if info.coords and info.coords.x then
                if y >= h then break end
                monitor.setCursorPos(col1_x, y)
                local c = (info.status=="idle") and colors.lime or ((info.status=="busy") and colors.orange or colors.red)
                monitor.setTextColor(c)
                local shortStatus = tostring(info.status):match("^(%w+)") or "?"
                monitor.write(name .. ": " .. shortStatus)
                y = y + 1
            end
        end

        -- SWITCHES (coluna 2)
        monitor.setBackgroundColor(colors.black)
        monitor.setTextColor(colors.white)
        monitor.setCursorPos(col2_x + centerText("Switches", col2_w)-1, y_switches-1)
        monitor.write("Switches")
        for switchName, state in pairs(Switches) do
            if y_switches >= h then break end
            monitor.setCursorPos(col2_x, y_switches)
            monitor.setTextColor(colors.white)
            monitor.write(switchName .. " ")
            local x_btn, _ = monitor.getCursorPos()
            
            -- Define e restaura o background do botão
            if state then
                monitor.setBackgroundColor(colors.lime)
                monitor.setTextColor(colors.white)
                monitor.write("[ ON ]")
            else
                monitor.setBackgroundColor(colors.red)
                monitor.setTextColor(colors.white)
                monitor.write("[ OFF ]")
            end
            monitor.setBackgroundColor(colors.black) -- Restaurado
            
            ButtonMap[y_switches] = ButtonMap[y_switches] or {}
            for i=x_btn, w do ButtonMap[y_switches][i] = "switch:"..switchName end
            y_switches = y_switches + 2
        end

    elseif currentPage == 2 then -- LOGISTICA
        local y_log = y
        monitor.setBackgroundColor(colors.black)
        for name, info in pairs(Fleet.turtles) do
            if info.coords and info.coords.x then
                if y_log >= h then break end
                monitor.setCursorPos(2, y_log)
                local c = (info.status=="idle") and colors.lime or ((info.status=="busy") and colors.orange or colors.red)
                monitor.setTextColor(c)
                local shortStatus = tostring(info.status):match("^(%w+)") or "?"
                monitor.write(name .. ": " .. shortStatus)
                y_log = y_log + 1
            end
        end

    elseif currentPage == 3 then -- SCANNER
        local y_scan = y
        monitor.setBackgroundColor(colors.black)
        for name, info in pairs(Fleet.turtles) do
            if info.status == "static_scanner" then
                if y_scan >= h then break end
                monitor.setCursorPos(2, y_scan)
                monitor.setTextColor(colors.cyan)
                monitor.write(name .. ": online")
                y_scan = y_scan + 1
            end
        end

    elseif currentPage == 4 then -- SWITCHES (página dedicada)
        local y_sw = y
        monitor.setBackgroundColor(colors.black)
        for switchName, state in pairs(Switches) do
            if y_sw >= h then break end
            monitor.setCursorPos(2, y_sw)
            monitor.setTextColor(colors.white)
            monitor.write(switchName .. " ")
            local x, _ = monitor.getCursorPos()
            
            -- Define e restaura o background do botão
            if state then
                monitor.setBackgroundColor(colors.lime)
                monitor.setTextColor(colors.white)
                monitor.write("[ ON ]")
            else
                monitor.setBackgroundColor(colors.red)
                monitor.setTextColor(colors.white)
                monitor.write("[ OFF ]")
            end
            monitor.setBackgroundColor(colors.black) -- Restaurado

            ButtonMap[y_sw] = ButtonMap[y_sw] or {}
            for i=2, w do ButtonMap[y_sw][i] = "switch:"..switchName end
            y_sw = y_sw + 2
        end
    end

    -- restaura cores finais (por redundância)
    monitor.setBackgroundColor(colors.black)
    monitor.setTextColor(colors.white)
end


-- =====================
-- 7. LÓGICA DE FROTA
-- =====================
local function getDistance(c1, c2) if not c1 or not c2 then return 999999 end; return math.sqrt((c2.x-c1.x)^2 + (c2.y-c1.y)^2 + (c2.z-c1.z)^2) end
local function findClosestAvailableTurtle(targetCoords)
    local closest, minDst = nil, math.huge
    for name, data in pairs(Fleet.turtles) do
        if data.status == "idle" and data.coords and data.id then
            local dst = getDistance(data.coords, targetCoords)
            if dst < minDst then minDst = dst; closest = name end
        end
    end
    return closest
end
local function verifyTurtle(turtleID)
    rednet.send(turtleID, {cmd="PING"}, PROTOCOL_FLEET); local sender, msg = rednet.receive(PROTOCOL_FLEET, 1.5)
    if sender == turtleID and type(msg) == "table" and msg.cmd == "PONG" then return true end
    return false
end
local function addJob(jobData) jobData.fuelStation = GlobalConfig.fuelStation; table.insert(JobQueue, jobData); print("Job adicionado.") end
local function registerScanner(id, storageName) ScannerMap[storageName] = id; print("Scanner '"..storageName.."' registrado.") end
local function pollStaticScanners() for name, data in pairs(Storage.data) do if not data.source and data.coords and ScannerMap[name] then rednet.send(ScannerMap[name], {protocol = PROTOCOL_SCAN, cmd = "REQUEST_INVENTORY", storageName = name}, PROTOCOL_SCAN) end end end
local function handleStaticScanReport(senderId, msg)
    local sName = msg.storageName
    if Storage.data[sName] and ScannerMap[sName] == senderId then
        local newItems = {}; for _, itemInfo in pairs(msg.items or {}) do if itemInfo.name and itemInfo.count then newItems[itemInfo.name] = (newItems[itemInfo.name] or 0) + itemInfo.count end end
        Storage.data[sName].items = newItems; checkPings(sName, newItems); saveAll()
    end
end

-- =====================
-- 8. PROCESSAMENTO DE COMANDOS (BLOCO MOVESTORAGE CORRIGIDO)
-- =====================
local function handleCommand(player, msg)
    if not ADMINS[player:gsub("%s+","")] then sendTell(player, "Sem permissao."); return end
    local cmd, args = msg:match("^!([^%s]+)%s*(.*)"); cmd = cmd and cmd:lower() or ""
    
    if cmd == "help" then
        local secName = args:match("%S+"); if secName and HELP_SECTIONS[secName:lower()] then local sec = HELP_SECTIONS[secName:lower()]; sendTell(player,"--- "..sec.title.." ---"); for _,c in ipairs(sec.commands) do sendTell(player,c) end else sendTell(player,"Secoes: config, logistica, monitor, switches, frota") end

    elseif cmd == "addstorage" then
        local n,t,s,x,y,z = args:match("(%S+)%s+(%S+)%s+(%S+)%s+(-?%d+)%s+(%-?%d+)%s+(%-?%d+)")
        if not n then n,t,s,x,y,z = args:match("(%S+)%s+(%S+)%s+(-?%d+)%s+(%-?%d+)%s+(%-?%d+)"); s=nil end
        if n and x and y and z then
            local c = {x=tonumber(x), y=tonumber(y), z=tonumber(z)}; if s and s:upper() == "NA" then s = nil end
            Storage.data[n] = {type=t, source=s, coords=c, items={}}; saveAll(); sendTell(player, "Storage salvo.")
        else sendTell(player, "Uso: !addStorage <Nome> <Tipo> [Fonte/NA] <X> <Y> <Z>") end

    elseif cmd == "setfuelstation" then local x,y,z = args:match("(%-?%d+)%s+(%-?%d+)%s+(%-?%d+)"); if x then GlobalConfig.fuelStation={x=tonumber(x), y=tonumber(y), z=tonumber(z)}; saveAll(); sendTell(player,"Posto ok.") end
    elseif cmd == "addswitch" then local n = args:match("(%S+)"); if n then Switches[n] = false; saveAll(); drawDashboard(); sendTell(player, "Switch add.") end
    elseif cmd == "delswitch" then 
        local n = args:match("(%S+)"); if n and Switches[n] ~= nil then Switches[n] = nil; saveAll(); drawDashboard(); sendTell(player, "Switch removido.") else sendTell(player, "Switch nao existe.") end

    elseif cmd == "movestorage" then
        -- NOVO PATTERN: Mais robusto para espaços no início/fim e garante que o item pode ter ':' e '_'
        local f,t,i,q = args:match("^%s*(%S+)%s+(%S+)%s+([%w:_]+)%s+(%d+)%s*$") 
        local fd, td = Storage.data[f], Storage.data[t]
        local qty = tonumber(q)

        -- 1. Verifica se a sintaxe está correta (4 argumentos)
        if not (f and t and i and q and qty > 0) then
            sendTell(player, "Uso: !moveStorage <Storage_Origem> <Storage_Destino> <Item> <Qtd>")
            return
        end
        
        -- 2. Verifica se os storages estão registrados
        if not (fd and td and fd.coords and td.coords) then
            sendTell(player, "Erro dados storage: Verifique se os nomes (Origem/Destino) existem.")
            return
        end
            
        local jobData = {
            protocol=PROTOCOL_FLEET, 
            cmd="JOB_ASSIGN", 
            mode="specific", 
            fromCoords=fd.coords, 
            toCoords=td.coords, 
            item=i, 
            qty=qty
        }
        
        local isAE2Source = fd.source and fd.source:find("me_bridge")
        local isAE2Target = td.source and td.source:find("me_bridge")

        -- Lógica de Coleta (Fonte)
        if isAE2Source then
            jobData.collect_type = "AE2_API_PULL"
            jobData.collect_peripheral = fd.source -- Passa o nome específico (ex: me_bridge_1)
        end

        -- Lógica de Entrega (Destino)
        if isAE2Target then
            jobData.deliver_type = "AE2_API_PUSH"
            jobData.deliver_peripheral = td.source -- Passa o nome específico (ex: me_bridge_1)
        end
        
        -- Verifica se é uma transação válida para !moveStorage (deve envolver pelo menos 1 AE2)
        if not isAE2Source and not isAE2Target then
             sendTell(player, "Erro: Use !emptyStorage para transferir entre dois baús. !moveStorage requer pelo menos um Storage AE2.")
             return
        end

        addJob(jobData)
        sendTell(player, string.format("Job: %s -> %s (%dx %s) adicionado à fila.", f, t, qty, i))

    elseif cmd == "emptystorage" then
        local f, t = args:match("(%S+)%s+(%S+)")
        local fd, td = Storage.data[f], Storage.data[t]
        if fd and td and fd.coords and td.coords then
            if fd.source and fd.source:find("me_bridge") then sendTell(player, "Erro: Nao esvazie o AE2."); return end
            local deliverType = nil
            local deliverPeripheral = nil -- Garantindo que o peripheral AE2 seja passado
            if td.source and td.source:find("me_bridge") then 
                deliverType = "AE2_API_PUSH"
                deliverPeripheral = td.source
            end
            addJob({protocol=PROTOCOL_FLEET, cmd="JOB_ASSIGN", mode="empty_blind", fromCoords=fd.coords, toCoords=td.coords, deliver_type=deliverType, deliver_peripheral=deliverPeripheral})
            sendTell(player, "Esvaziando "..f.." -> "..t)
        else sendTell(player, "Storages invalidos.") end

    elseif cmd == "statsstorage" then 
        local n,f=args:match("^(%S+)%s*(.*)")
        if n and Storage.data[n] then 
            if ScannerMap[n] then
                sendTell(player, "Sincronizando..."); rednet.send(ScannerMap[n], {protocol=PROTOCOL_SCAN, cmd="REQUEST_INVENTORY", storageName=n}, PROTOCOL_SCAN)
                local s, m = rednet.receive(PROTOCOL_SCAN, 2); if s and m and m.cmd=="INVENTORY_REPORT" then handleStaticScanReport(s,m) end
            end
            sendTell(player,"Itens "..n..":")
            if Storage.data[n].items then for k,v in pairs(Storage.data[n].items) do if not f or f=="" or k:lower():find(f:lower()) then sendTell(player,v.."x "..k) end end end
        end

    elseif cmd == "pingstorage" then 
        local i,op,q,n=args:match("(%S+)%s+([<>])%s+(%d+)%s+(%S+)"); if i and op and q and n then 
            Storage.pings[n]=Storage.pings[n] or {}; Storage.pings[n][i] = {limit=tonumber(q), op=op}; saveAll(); sendTell(player,"Ping: "..i.." "..op.." "..q) 
        else sendTell(player, "Uso: !pingStorage <Item> < > <Qtd> <Storage>") end

    elseif cmd == "redstone" then local t,a=args:match("(%S+)%s+(%S+)"); if t then rednet.broadcast({target=t,action=a:upper()}, PROTOCOL_REDSTONE); sendTell(player,"Enviado.") end
    
    elseif cmd == "fleet" then
        local action, name = args:match("^(%S+)%s*(.*)")
        if action == "reset" and name and Fleet.turtles[name] then Fleet.turtles[name].status = "idle"; saveAll(); sendTell(player, name .. " resetado.")
        elseif action == "remove" and name and Fleet.turtles[name] then Fleet.turtles[name] = nil; saveAll(); sendTell(player, name .. " removido.")
        else sendTell(player, "--- FROTA ---"); for n,d in pairs(Fleet.turtles) do sendTell(player, n..": "..(d.status or "?")) end end
    
    elseif cmd == "quiz" then gerarPerguntaQuiz()
    elseif cmd == "sorteio" then local p=playerDetector.getOnlinePlayers(); if #p>0 then sendChat("Vencedor: "..p[math.random(#p)]) end
    end
end

local function handleRednetMessage(senderId, msg)
    if type(msg) ~= "table" then return end
    local proto = msg.protocol; local turtleName = msg.name and tostring(msg.name):gsub("^%s*(.-)%s*$", "%1") or nil
    
    if proto == PROTOCOL_FLEET and turtleName then
        if Fleet.turtles[turtleName] then
            if msg.cmd == "JOB_DONE" then Fleet.turtles[turtleName].status="idle"; saveAll()
            elseif msg.cmd == "JOB_FAIL" then Fleet.turtles[turtleName].status="idle"; print("Falha: "..tostring(msg.reason)); saveAll()
            elseif msg.cmd == "REQUEST_OBSTACLES" then rednet.send(senderId, {map=ObstacleMap}, PROTOCOL_FLEET)
            elseif msg.cmd == "REPORT_OBSTACLE" and msg.key and not ObstacleMap[msg.key] then ObstacleMap[msg.key]=true; saveAll() end
        end
    
    elseif proto == PROTOCOL_REGISTER and turtleName then
        if msg.cmd == "REQUEST_REGISTRATION" then
            if Fleet.turtles[turtleName] and Fleet.turtles[turtleName].coords then
                Fleet.turtles[turtleName].id=senderId; Fleet.turtles[turtleName].status="idle"; rednet.send(senderId, {cmd="REGISTRATION_SUCCESS", garage=Fleet.turtles[turtleName].coords}, PROTOCOL_REGISTER); saveAll()
            else
                Fleet.turtles[turtleName] = {id=senderId, status="setup", coords=nil}; rednet.send(senderId, {cmd="FIRST_TIME_SETUP"}, PROTOCOL_REGISTER)
            end; saveAll()
        elseif msg.cmd == "SUBMIT_SETUP" and Fleet.turtles[turtleName] then
            Fleet.turtles[turtleName].coords=msg.garage; Fleet.turtles[turtleName].status="idle"; rednet.send(senderId, {cmd="SETUP_COMPLETE"}, PROTOCOL_REGISTER); saveAll()
        end
    
    elseif proto == PROTOCOL_SCAN then
        if msg.cmd == "INVENTORY_REPORT" then handleStaticScanReport(senderId, msg)
        elseif msg.cmd == "SCAN_FAIL" and ScannerMap[msg.storageName] == senderId then print("Scan falhou: "..tostring(msg.reason)) end

    elseif proto == PROTOCOL_REGISTER_SCAN and msg.cmd == "SCANNER_READY" then
        if msg.storageName then
            local sName = tostring(msg.storageName):gsub("^%s*(.-)%s*$", "%1")
            registerScanner(senderId, sName); Fleet.turtles[sName] = {id=senderId, status="static_scanner", coords={}}
            rednet.send(senderId, {cmd="MANAGER_CONFIRM", protocol=PROTOCOL_REGISTER_SCAN}, PROTOCOL_REGISTER_SCAN); saveAll()
        end
    end
end

-- =====================
-- 9. MAIN LOOP (ESTÁVEL)
-- =====================
term.clear(); term.setCursorPos(1,1); print("FILO v1.6 (Stable) ONLINE"); loadAll()

local jobDispatchTimer = os.startTimer(5)
local staticScanTimer = os.startTimer(30)
local lastStorageScan = os.clock()

while true do
    drawDashboard()
    
    local event, p1, p2, p3 = os.pullEvent()

    if event == "timer" and p1 == jobDispatchTimer then
        if #JobQueue > 0 then
            local job = JobQueue[1]
            local turtleName = findClosestAvailableTurtle(job.fromCoords)
            if turtleName then
                local tData = Fleet.turtles[turtleName]
                if verifyTurtle(tData.id) then
                    print("Despachando para "..turtleName); tData.status = "busy"; table.remove(JobQueue, 1); rednet.send(tData.id, job, PROTOCOL_FLEET)
                else
                    print("Turtle off. INACTIVE."); Fleet.turtles[turtleName].status = "inactive"; saveAll()
                end
            end
        end
        jobDispatchTimer = os.startTimer(5)
    
    elseif event == "timer" and p1 == staticScanTimer then
        pcall(pollStaticScanners)
        staticScanTimer = os.startTimer(30)
    
    elseif event == "rednet_message" then
        if type(p2) == "table" then handleRednetMessage(p1, p2) end
    
    elseif event == "chat" then
        if CurrentQuiz.active and p2:lower()==CurrentQuiz.answer then CurrentQuiz.active=false; sendChat("Vencedor: "..p1) end
        if p2:sub(1,1) == "!" then handleCommand(p1, p2) elseif p2:lower():find("filo") then handleInteractionIA(p1, p2) end
    
    elseif event == "monitor_touch" and monitor then
        local monitorName, x, y = p1, p2, p3
        if ButtonMap[y] and ButtonMap[y][x] then
            local action = ButtonMap[y][x]
            if action == "prev_page" then currentPage = (currentPage==1) and totalPages or (currentPage-1)
            elseif action == "next_page" then currentPage = (currentPage==totalPages) and 1 or (currentPage+1)
            elseif action:find("switch:") then
                local n = action:match("switch:(.*)"); if n and Switches[n]~=nil then Switches[n]=not Switches[n]; saveAll(); rednet.broadcast({target=n,action=(Switches[n] and "ON" or "OFF")}, PROTOCOL_REDSTONE) end
            end
            drawDashboard() 
        end
    end
    
    if os.clock() - lastStorageScan > 5 then
        pcall(Storage.updateLocalPeripherals)
        lastStorageScan = os.clock()
    end
end
