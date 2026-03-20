-- ════════════════════════════════════════════════════
-- VANILLA4 — AutoBuy Tab
-- Execute AFTER Vanilla1, Vanilla2, Vanilla3
-- ════════════════════════════════════════════════════

if not _G.VH then
    warn("[VanillaHub] Vanilla4: _G.VH not found. Execute Vanilla1 first.")
    return
end

local TweenService     = _G.VH.TweenService
local UserInputService = _G.VH.UserInputService
local player           = _G.VH.player
local cleanupTasks     = _G.VH.cleanupTasks
local pages            = _G.VH.pages

local RS = game:GetService("ReplicatedStorage")

-- ════════════════════════════════════════════════════
-- THEME  (Black / Grey / White — mirrors Vanilla1)
-- ════════════════════════════════════════════════════
local C = {
    CARD        = Color3.fromRGB(16,  16,  16),
    BTN         = Color3.fromRGB(14,  14,  14),
    BTN_HV      = Color3.fromRGB(32,  32,  32),
    BG_ROW      = Color3.fromRGB(22,  22,  22),
    BG_INPUT    = Color3.fromRGB(32,  32,  32),
    BORDER      = Color3.fromRGB(55,  55,  55),
    BORDER_FOC  = Color3.fromRGB(100, 100, 100),
    TEXT        = Color3.fromRGB(210, 210, 210),
    TEXT_MID    = Color3.fromRGB(155, 155, 155),
    TEXT_DIM    = Color3.fromRGB(90,  90,  90),
    TEXT_WHITE  = Color3.fromRGB(240, 240, 240),
}

local autoBuyPage = pages["AutoBuyTab"]
if not autoBuyPage then
    warn("[VanillaHub] Vanilla4: AutoBuyTab page not found.")
    return
end

-- ════════════════════════════════════════════════════
-- STATE
-- ════════════════════════════════════════════════════
local AB_aborted     = false
local AB_buying      = false
local AB_amount      = 10
local AB_item        = nil
local AB_isBlueprint = false
local AB_statusLbl   = nil
local AB_progLbl     = nil
local AB_startBtn    = nil
local AB_stopBtn     = nil

-- ════════════════════════════════════════════════════
-- STORE COUNTER REGISTRY
-- ════════════════════════════════════════════════════
-- Each entry drives the dialog sequence for its store.
-- WoodRUs uses the direct workspace reference method (matches provided snippet).
-- All others use the generic {char, id} approach.
local AB_Counters = {
    { name="WoodRUs",          pos=Vector3.new(267.90,   5.20,    67.43),  useWorkspaceRef=true                                         },
    { name="BobsShack",        pos=Vector3.new(260.36,   10.40, -2551.25), char="Bob",          id=12, preSeq=nil                        },
    { name="FineArt",          pos=Vector3.new(5237.58, -164.00,  739.66), char="Timothy",      id=13, preSeq=nil                        },
    { name="FancyFurnishings", pos=Vector3.new(477.62,    5.60, -1721.34), char="Corey",        id=10, preSeq=nil                        },
    { name="LinksLogic",       pos=Vector3.new(4595.43,   9.40,  -785.02), char="Lincoln",      id=14, preSeq=nil                        },
    { name="BoxedCars",        pos=Vector3.new(528.04,    5.60, -1460.43), char="Jenny",        id=11, preSeq="SetChattingValue1"         },
}

local AB_Services = {
    { label="Toll Bridge",   char="Seranok",     id=7,  wConfirm=0.85, wEnd=0.45              },
    { label="Ferry Ticket",  char="Hoover",      id=15, wConfirm=0.85, wEnd=0.45              },
    { label="Power of Ease", char="Strange Man", id=6,  wConfirm=0.85, wEnd=0.45, wFinal=true },
}

-- ════════════════════════════════════════════════════
-- HELPERS
-- ════════════════════════════════════════════════════
local function tw(obj, props, t)
    TweenService:Create(obj, TweenInfo.new(t or 0.18, Enum.EasingStyle.Quint), props):Play()
end

local function setStatus(msg, active)
    if AB_statusLbl and AB_statusLbl.Parent then
        AB_statusLbl.Text       = msg
        AB_statusLbl.TextColor3 = active and C.TEXT or C.TEXT_DIM
    end
end

local function setProgress(cur, total)
    if AB_progLbl and AB_progLbl.Parent then
        if cur and total then
            AB_progLbl.Text    = cur .. " / " .. total
            AB_progLbl.Visible = true
        else
            AB_progLbl.Visible = false
        end
    end
end

local function refreshActionButtons()
    if AB_startBtn and AB_startBtn.Parent then
        local canStart = AB_item ~= nil and not AB_buying
        AB_startBtn.TextColor3       = canStart and C.TEXT   or C.TEXT_DIM
        AB_startBtn.BackgroundColor3 = canStart and C.BTN_HV or C.BTN
    end
    if AB_stopBtn and AB_stopBtn.Parent then
        AB_stopBtn.TextColor3       = AB_buying and C.TEXT   or C.TEXT_DIM
        AB_stopBtn.BackgroundColor3 = AB_buying and C.BG_ROW or C.BTN
    end
end

local function isnetworkowner(part)
    local ok, res = pcall(function() return part.ReceiveAge end)
    return ok and res == 0
end

-- ════════════════════════════════════════════════════
-- ITEM DATA
-- ════════════════════════════════════════════════════
local function getPrice(itemName)
    local price = 0
    pcall(function()
        for _, v in next, RS:WaitForChild("ClientItemInfo", 5):GetDescendants() do
            if v.Name == itemName and v:FindFirstChild("Price") then
                price = v.Price.Value; break
            end
        end
    end)
    return price
end

local function grabAllItems()
    local list, seen = {}, {}
    pcall(function()
        for _, store in next, workspace.Stores:GetChildren() do
            if store.Name ~= "ShopItems" then continue end
            for _, item in next, store:GetChildren() do
                local bin = item:FindFirstChild("BoxItemName")
                local typ = item:FindFirstChild("Type")
                if bin and not seen[bin.Value] then
                    seen[bin.Value] = true
                    table.insert(list, {
                        name        = bin.Value,
                        price       = getPrice(bin.Value),
                        isBlueprint = typ and typ.Value == "Blueprint",
                    })
                end
            end
        end
        table.sort(list, function(a, b) return a.name < b.name end)
    end)
    return list
end

local function grabBlueprintNames()
    local list, seen = {}, {}
    pcall(function()
        for _, store in next, workspace.Stores:GetChildren() do
            if store.Name ~= "ShopItems" then continue end
            for _, item in next, store:GetChildren() do
                local bin = item:FindFirstChild("BoxItemName")
                local typ = item:FindFirstChild("Type")
                if bin and typ and typ.Value == "Blueprint" and not seen[bin.Value] then
                    seen[bin.Value] = true
                    table.insert(list, bin.Value)
                end
            end
        end
    end)
    return list
end

-- ════════════════════════════════════════════════════
-- DIALOG  (per-counter)
-- ════════════════════════════════════════════════════
local function fireDialog(c)
    local PlayerChatted  = RS:FindFirstChild("PlayerChatted",    true)
    local SetChattingVal = RS:FindFirstChild("SetChattingValue", true)
    if not (PlayerChatted and SetChattingVal) then return end

    if c.useWorkspaceRef then
        -- Direct workspace reference method (WoodRUs / Thom)
        local Thom   = workspace.Stores.WoodRUs.Thom
        local Dialog = Thom.Dialog
        local args   = { Character=Thom, Name="Thom", ID=9, Dialog=Dialog }
        PlayerChatted:InvokeServer(args, "Initiate")
        SetChattingVal:InvokeServer(2)
        PlayerChatted:InvokeServer(args, "ConfirmPurchase")
        SetChattingVal:InvokeServer(2)
        PlayerChatted:InvokeServer(args, "EndChat")
        SetChattingVal:InvokeServer(0)
    else
        -- Generic method for all other counters
        local args = { Character=c.char, Name=c.char, ID=c.id, Dialog="Dialog" }
        if c.preSeq == "SetChattingValue1" then
            SetChattingVal:InvokeServer(1); task.wait(0.05)
        end
        PlayerChatted:InvokeServer(args, "Initiate")
        task.wait(0.05); SetChattingVal:InvokeServer(2)
        task.wait(0.85)
        PlayerChatted:InvokeServer(args, "ConfirmPurchase")
        task.wait(0.05); SetChattingVal:InvokeServer(2)
        task.wait(0.45)
        PlayerChatted:InvokeServer(args, "EndChat")
        task.wait(0.05); SetChattingVal:InvokeServer(0)
        if c.preSeq == "SetChattingValue1" then
            task.wait(0.05); SetChattingVal:InvokeServer(1)
        end
    end
end

-- ════════════════════════════════════════════════════
-- OPEN-BOX HELPER
-- ════════════════════════════════════════════════════
local function openBoxFor(itemName, teleportDestPos)
    local ClientInteracted   = RS:FindFirstChild("ClientInteracted",         true)
    local ClientGetUserPerms = RS:FindFirstChild("ClientGetUserPermissions", true)
    local Dragging           = RS.Interaction and RS.Interaction:FindFirstChild("ClientIsDragging")
    local playerName         = player.Name

    local box = RS:FindFirstChild("Box Purchased by " .. playerName, true)
             or workspace:FindFirstChild("Box Purchased by " .. playerName, true)
    if not box then
        for _, v in next, workspace:GetDescendants() do
            local iv    = v:FindFirstChild("ItemName")
            local owner = v:FindFirstChild("Owner")
            if iv and iv.Value == itemName and owner and owner.Value == player then
                box = v; break
            end
        end
    end
    if not box then return end

    local uid = tostring(player.UserId)
    if ClientGetUserPerms then
        ClientGetUserPerms:InvokeServer(uid, "Interact")
        ClientGetUserPerms:InvokeServer(uid, "MoveStructure")
        ClientGetUserPerms:InvokeServer(uid, "Destroy")
        task.wait(0.017)
        ClientGetUserPerms:InvokeServer(uid, "Grab")
    end
    task.wait(0.004)
    if ClientInteracted then ClientInteracted:FireServer(box, "Open box") end
    task.wait(0.3)

    if not teleportDestPos then return end
    local found, deadline = nil, tick() + 10
    repeat
        task.wait(0.05)
        for _, v in next, workspace:GetDescendants() do
            local iv    = v:FindFirstChild("ItemName")
            local owner = v:FindFirstChild("Owner")
            if iv and iv.Value == itemName and owner and owner.Value == player then
                found = v; break
            end
        end
    until found or tick() > deadline
    if not found then return end

    local m = found:FindFirstChild("Main")
    if not m then return end
    task.wait(0.1)
    pcall(function()
        if not found.PrimaryPart then found.PrimaryPart = m end
        local t = 0
        while not isnetworkowner(m) and t < 3 do
            if Dragging then Dragging:FireServer(found) end
            task.wait(0.05); t += 0.05
        end
        if Dragging then Dragging:FireServer(found) end
        m:PivotTo(CFrame.new(teleportDestPos)); task.wait(0.05)
    end)
end

-- ════════════════════════════════════════════════════
-- BUY LOOP
-- ════════════════════════════════════════════════════
local function AB_buy(itemName, amount, isBlueprint, isBatch)
    if not itemName then setStatus("No item selected.", false); return end
    if not isBatch then
        AB_aborted = false; AB_buying = true
        setProgress(0, amount)
        refreshActionButtons()
    end

    local Dragging = RS.Interaction and RS.Interaction:FindFirstChild("ClientIsDragging")

    local char = player.Character
    if not (char and char:FindFirstChild("HumanoidRootPart")) then
        if not isBatch then AB_buying = false; refreshActionButtons() end
        return
    end
    local origin = char.HumanoidRootPart.CFrame

    local function findShopItem()
        for _, store in next, workspace.Stores:GetChildren() do
            if store.Name ~= "ShopItems" then continue end
            for _, v in next, store:GetChildren() do
                local box   = v:FindFirstChild("BoxItemName")
                local owner = v:FindFirstChild("Owner")
                if box and box.Value == itemName then
                    if not owner or owner.Value == nil or owner.Value == "" then
                        return v
                    end
                end
            end
        end
        return nil
    end

    local function waitForShopItem(timeout)
        local deadline = tick() + (timeout or 20)
        local found    = findShopItem()
        while not found and tick() < deadline do
            if AB_aborted then return nil end
            task.wait(0.03)
            found = findShopItem()
        end
        return found
    end

    for i = 1, amount do
        if AB_aborted then break end

        setStatus("Waiting for " .. itemName .. "...", true)
        local item = waitForShopItem(20)
        if not item then setStatus("'" .. itemName .. "' not found - timed out.", false); break end
        if AB_aborted then break end

        local main = item:FindFirstChild("Main")
        if not main then setStatus("Missing Main part.", false); break end

        -- Resolve nearest counter
        local counterPart = item.Parent:FindFirstChild("counter")
        if not counterPart then
            local bestDist = math.huge
            for _, store in next, workspace.Stores:GetChildren() do
                for _, child in next, store:GetChildren() do
                    if child.Name:lower() == "counter" and child:IsA("BasePart") then
                        local d = (child.Position - main.Position).Magnitude
                        if d < bestDist then bestDist = d; counterPart = child end
                    end
                end
            end
        end

        local refPos = counterPart and counterPart.Position or main.Position
        local closest, closestDist = nil, math.huge
        for _, c in ipairs(AB_Counters) do
            local d = (refPos - c.pos).Magnitude
            if d < closestDist then closestDist = d; closest = c end
        end
        if not closest then setStatus("No counter found.", false); break end

        local counterCF = counterPart and counterPart.CFrame or CFrame.new(closest.pos)

        setStatus("Buying " .. itemName .. "...", true)
        local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
        if not hrp then break end

        -- tp YOU to item
        hrp.CFrame = main.CFrame + Vector3.new(5, 0, 5)
        task.wait(0.016)

        -- tp ITEM to counter
        for _ = 1, 4 do
            if Dragging then Dragging:FireServer(item) end
            main.CFrame = counterCF + Vector3.new(0, main.Size.Y, 0.5)
            task.wait(0.016)
        end

        fireDialog(closest)

        -- tp ITEM back to origin, you stay
        task.wait(0.1)
        pcall(function()
            local t = 0
            while not isnetworkowner(main) and t < 1 do
                if Dragging then Dragging:FireServer(item) end
                task.wait(0.016); t += 0.016
            end
            if Dragging then Dragging:FireServer(item) end
            main.CFrame = origin
        end)

        if isBlueprint then
            task.wait(0.1)
            openBoxFor(itemName, nil)
        end

        task.wait(0.05)

        if not isBatch then
            setProgress(i, amount)
            setStatus("Bought " .. i .. " / " .. amount, true)
        end
    end

    if not isBatch then
        AB_buying = false
        setProgress(nil)
        setStatus(AB_aborted and "Stopped." or "Done!", false)
        refreshActionButtons()
        task.wait(0.01)
        local hrpFinal = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
        if hrpFinal then
            hrpFinal.CFrame = origin
        end
    end
end

-- ════════════════════════════════════════════════════
-- UI WIDGET HELPERS
-- ════════════════════════════════════════════════════
local function mkLabel(text)
    local lbl = Instance.new("TextLabel", autoBuyPage)
    lbl.Size               = UDim2.new(1, -12, 0, 20)
    lbl.BackgroundTransparency = 1
    lbl.Font               = Enum.Font.GothamBold
    lbl.TextSize           = 10
    lbl.TextColor3         = C.TEXT_DIM
    lbl.TextXAlignment     = Enum.TextXAlignment.Left
    lbl.Text               = "  " .. string.upper(text)
    Instance.new("UIPadding", lbl).PaddingLeft = UDim.new(0, 4)
end

local function mkSep()
    local s = Instance.new("Frame", autoBuyPage)
    s.Size             = UDim2.new(1, -12, 0, 1)
    s.BackgroundColor3 = C.BORDER
    s.BorderSizePixel  = 0
end

local function mkBtn(text, cb)
    local btn = Instance.new("TextButton", autoBuyPage)
    btn.Size             = UDim2.new(1, -12, 0, 34)
    btn.BackgroundColor3 = C.BTN
    btn.Text             = text
    btn.Font             = Enum.Font.GothamSemibold
    btn.TextSize         = 13
    btn.TextColor3       = C.TEXT
    btn.BorderSizePixel  = 0
    btn.AutoButtonColor  = false
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)
    local stroke = Instance.new("UIStroke", btn)
    stroke.Color = C.BORDER; stroke.Thickness = 1; stroke.Transparency = 0
    btn.MouseEnter:Connect(function() tw(btn, { BackgroundColor3 = C.BTN_HV }) end)
    btn.MouseLeave:Connect(function() tw(btn, { BackgroundColor3 = C.BTN   }) end)
    if cb then btn.MouseButton1Click:Connect(cb) end
    return btn
end

local function mkNumberInput(text, minV, maxV, defV, cb)
    local fr = Instance.new("Frame", autoBuyPage)
    fr.Size             = UDim2.new(1, -12, 0, 40)
    fr.BackgroundColor3 = C.CARD
    fr.BorderSizePixel  = 0
    Instance.new("UICorner", fr).CornerRadius = UDim.new(0, 6)

    local lbl = Instance.new("TextLabel", fr)
    lbl.Size               = UDim2.new(1, -130, 1, 0)
    lbl.Position           = UDim2.new(0, 10, 0, 0)
    lbl.BackgroundTransparency = 1
    lbl.Text               = text
    lbl.Font               = Enum.Font.GothamSemibold
    lbl.TextSize           = 13
    lbl.TextColor3         = C.TEXT
    lbl.TextXAlignment     = Enum.TextXAlignment.Left

    local function makeArrow(xOff, label)
        local b = Instance.new("TextButton", fr)
        b.Size             = UDim2.new(0, 28, 0, 28)
        b.Position         = UDim2.new(1, xOff, 0.5, -14)
        b.BackgroundColor3 = C.BTN
        b.Text             = label
        b.Font             = Enum.Font.GothamBold
        b.TextSize         = 16
        b.TextColor3       = C.TEXT
        b.BorderSizePixel  = 0
        b.AutoButtonColor  = false
        Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
        local s = Instance.new("UIStroke", b)
        s.Color = C.BORDER; s.Thickness = 1; s.Transparency = 0
        b.MouseEnter:Connect(function() tw(b, { BackgroundColor3 = C.BTN_HV }) end)
        b.MouseLeave:Connect(function() tw(b, { BackgroundColor3 = C.BTN   }) end)
        return b
    end

    local minusBtn = makeArrow(-122, "-")
    local plusBtn  = makeArrow(-30,  "+")

    local box = Instance.new("TextBox", fr)
    box.Size             = UDim2.new(0, 56, 0, 28)
    box.Position         = UDim2.new(1, -90, 0.5, -14)
    box.BackgroundColor3 = Color3.fromRGB(22, 22, 22)
    box.BorderSizePixel  = 0
    box.Font             = Enum.Font.GothamBold
    box.TextSize         = 14
    box.TextColor3       = C.TEXT
    box.Text             = tostring(defV)
    box.ClearTextOnFocus = false
    box.TextXAlignment   = Enum.TextXAlignment.Center
    Instance.new("UICorner", box).CornerRadius = UDim.new(0, 6)
    local bs = Instance.new("UIStroke", box)
    bs.Color = C.BORDER; bs.Thickness = 1; bs.Transparency = 0.4

    local curVal = defV
    local function applyVal(v)
        curVal   = math.clamp(math.floor(tonumber(v) or minV), minV, maxV)
        box.Text = tostring(curVal)
        if cb then cb(curVal) end
    end
    minusBtn.MouseButton1Click:Connect(function() applyVal(curVal - 1) end)
    plusBtn.MouseButton1Click:Connect(function()  applyVal(curVal + 1) end)
    box.FocusLost:Connect(function() applyVal(box.Text) end)
    box:GetPropertyChangedSignal("Text"):Connect(function()
        local clean = box.Text:gsub("[^%d]", "")
        if clean ~= box.Text then box.Text = clean end
    end)
end

-- ════════════════════════════════════════════════════
-- STATUS BAR
-- ════════════════════════════════════════════════════
local statusCard = Instance.new("Frame", autoBuyPage)
statusCard.Size             = UDim2.new(1, -12, 0, 38)
statusCard.BackgroundColor3 = C.CARD
statusCard.BorderSizePixel  = 0
Instance.new("UICorner", statusCard).CornerRadius = UDim.new(0, 6)
local scStroke = Instance.new("UIStroke", statusCard)
scStroke.Color = C.BORDER; scStroke.Thickness = 1; scStroke.Transparency = 0.3

local statusLbl = Instance.new("TextLabel", statusCard)
statusLbl.Size               = UDim2.new(1, -80, 1, 0)
statusLbl.Position           = UDim2.new(0, 10, 0, 0)
statusLbl.BackgroundTransparency = 1
statusLbl.Font               = Enum.Font.GothamSemibold
statusLbl.TextSize           = 12
statusLbl.TextColor3         = C.TEXT_DIM
statusLbl.TextXAlignment     = Enum.TextXAlignment.Left
statusLbl.Text               = "Select an item to get started."
AB_statusLbl                 = statusLbl

local progLbl = Instance.new("TextLabel", statusCard)
progLbl.Size               = UDim2.new(0, 68, 1, 0)
progLbl.Position           = UDim2.new(1, -72, 0, 0)
progLbl.BackgroundTransparency = 1
progLbl.Font               = Enum.Font.GothamBold
progLbl.TextSize           = 12
progLbl.TextColor3         = C.TEXT
progLbl.TextXAlignment     = Enum.TextXAlignment.Right
progLbl.Visible            = false
AB_progLbl                 = progLbl

-- ════════════════════════════════════════════════════
-- ITEM DROPDOWN
-- ════════════════════════════════════════════════════
mkSep()
mkLabel("Item")

local ITEM_H   = 30
local MAX_SHOW = 6
local HEADER_H = 38

local dropIsOpen   = false
local dropSelected = ""
local dropItems    = {}

-- Outer collapsible frame
local dropOuter = Instance.new("Frame", autoBuyPage)
dropOuter.Size             = UDim2.new(1, -12, 0, HEADER_H)
dropOuter.BackgroundColor3 = C.BG_ROW
dropOuter.BorderSizePixel  = 0
dropOuter.ClipsDescendants = true
Instance.new("UICorner", dropOuter).CornerRadius = UDim.new(0, 7)
local dropOuterStroke = Instance.new("UIStroke", dropOuter)
dropOuterStroke.Color        = C.BORDER
dropOuterStroke.Thickness    = 1
dropOuterStroke.Transparency = 0.3

-- Header row
local dropHeader = Instance.new("Frame", dropOuter)
dropHeader.Size                   = UDim2.new(1, 0, 0, HEADER_H)
dropHeader.BackgroundTransparency = 1

local dropLabelLeft = Instance.new("TextLabel", dropHeader)
dropLabelLeft.Size               = UDim2.new(0, 50, 1, 0)
dropLabelLeft.Position           = UDim2.new(0, 10, 0, 0)
dropLabelLeft.BackgroundTransparency = 1
dropLabelLeft.Text               = "Item"
dropLabelLeft.Font               = Enum.Font.GothamBold
dropLabelLeft.TextSize           = 11
dropLabelLeft.TextColor3         = C.TEXT_DIM
dropLabelLeft.TextXAlignment     = Enum.TextXAlignment.Left

local selFrame = Instance.new("Frame", dropHeader)
selFrame.Size             = UDim2.new(1, -66, 0, 26)
selFrame.Position         = UDim2.new(0, 58, 0.5, -13)
selFrame.BackgroundColor3 = C.BG_INPUT
selFrame.BorderSizePixel  = 0
Instance.new("UICorner", selFrame).CornerRadius = UDim.new(0, 5)
local selStroke = Instance.new("UIStroke", selFrame)
selStroke.Color        = C.BORDER
selStroke.Thickness    = 1
selStroke.Transparency = 0.3

local selLbl = Instance.new("TextLabel", selFrame)
selLbl.Size               = UDim2.new(1, -30, 1, 0)
selLbl.Position           = UDim2.new(0, 8, 0, 0)
selLbl.BackgroundTransparency = 1
selLbl.Text               = "Select item..."
selLbl.Font               = Enum.Font.GothamSemibold
selLbl.TextSize           = 11
selLbl.TextColor3         = C.TEXT_DIM
selLbl.TextXAlignment     = Enum.TextXAlignment.Left
selLbl.TextTruncate       = Enum.TextTruncate.AtEnd

local arrowLbl = Instance.new("TextLabel", selFrame)
arrowLbl.Size               = UDim2.new(0, 20, 1, 0)
arrowLbl.Position           = UDim2.new(1, -22, 0, 0)
arrowLbl.BackgroundTransparency = 1
arrowLbl.Text               = "v"
arrowLbl.Font               = Enum.Font.GothamBold
arrowLbl.TextSize           = 11
arrowLbl.TextColor3         = C.TEXT_DIM
arrowLbl.TextXAlignment     = Enum.TextXAlignment.Center

local headerBtn = Instance.new("TextButton", selFrame)
headerBtn.Size               = UDim2.new(1, 0, 1, 0)
headerBtn.BackgroundTransparency = 1
headerBtn.Text               = ""
headerBtn.AutoButtonColor    = false
headerBtn.ZIndex             = 5

-- Divider between header and list
local divider = Instance.new("Frame", dropOuter)
divider.Size             = UDim2.new(1, -14, 0, 1)
divider.Position         = UDim2.new(0, 7, 0, HEADER_H)
divider.BackgroundColor3 = C.BORDER
divider.BorderSizePixel  = 0
divider.Visible          = false

-- Scrolling list
local listScroll = Instance.new("ScrollingFrame", dropOuter)
listScroll.Position               = UDim2.new(0, 0, 0, HEADER_H + 2)
listScroll.Size                   = UDim2.new(1, 0, 0, 0)
listScroll.BackgroundTransparency = 1
listScroll.BorderSizePixel        = 0
listScroll.ScrollBarThickness     = 3
listScroll.ScrollBarImageColor3   = C.BORDER_FOC
listScroll.CanvasSize             = UDim2.new(0, 0, 0, 0)
listScroll.ClipsDescendants       = true

local listLayout = Instance.new("UIListLayout", listScroll)
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Padding   = UDim.new(0, 2)
listLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
    listScroll.CanvasSize = UDim2.new(0, 0, 0, listLayout.AbsoluteContentSize.Y + 6)
end)
local listPad = Instance.new("UIPadding", listScroll)
listPad.PaddingTop    = UDim.new(0, 3)
listPad.PaddingBottom = UDim.new(0, 3)
listPad.PaddingLeft   = UDim.new(0, 5)
listPad.PaddingRight  = UDim.new(0, 5)

-- Selection state
local function applySelection(entry)
    dropSelected   = entry.name
    AB_item        = entry.name
    AB_isBlueprint = entry.isBlueprint

    local priceStr = entry.price > 0 and ("   $" .. entry.price) or ""
    selLbl.Text       = entry.name .. priceStr
    selLbl.TextColor3 = C.TEXT_WHITE

    arrowLbl.TextColor3   = C.TEXT_MID
    dropOuterStroke.Color = C.BORDER_FOC
    refreshActionButtons()
end

local function clearSelection()
    dropSelected   = ""
    AB_item        = nil
    AB_isBlueprint = false

    selLbl.Text       = "Select item..."
    selLbl.TextColor3 = C.TEXT_DIM

    arrowLbl.TextColor3   = C.TEXT_DIM
    dropOuterStroke.Color = C.BORDER
    refreshActionButtons()
end

local function closeList()
    dropIsOpen = false
    tw(arrowLbl,   { Rotation = 0 })
    tw(dropOuter,  { Size = UDim2.new(1, -12, 0, HEADER_H) })
    tw(listScroll, { Size = UDim2.new(1, 0, 0, 0) })
    divider.Visible = false
end

local function buildList()
    for _, child in ipairs(listScroll:GetChildren()) do
        if child:IsA("Frame") or child:IsA("TextButton") then child:Destroy() end
    end

    for i, entry in ipairs(dropItems) do
        local isSel = entry.name == dropSelected

        local row = Instance.new("Frame", listScroll)
        row.Size             = UDim2.new(1, 0, 0, ITEM_H)
        row.BackgroundColor3 = isSel and Color3.fromRGB(50, 50, 50) or C.BG_ROW
        row.BorderSizePixel  = 0
        row.LayoutOrder      = i
        Instance.new("UICorner", row).CornerRadius = UDim.new(0, 5)

        -- Item name (left-aligned, always white)
        local nameLbl = Instance.new("TextLabel", row)
        nameLbl.Size               = UDim2.new(1, -70, 1, 0)
        nameLbl.Position           = UDim2.new(0, 10, 0, 0)
        nameLbl.BackgroundTransparency = 1
        nameLbl.Text               = entry.name
        nameLbl.Font               = Enum.Font.GothamSemibold
        nameLbl.TextSize           = 11
        nameLbl.TextColor3         = C.TEXT_WHITE
        nameLbl.TextXAlignment     = Enum.TextXAlignment.Left
        nameLbl.TextTruncate       = Enum.TextTruncate.AtEnd

        -- Price (right-aligned, white)
        if entry.price > 0 then
            local priceLbl = Instance.new("TextLabel", row)
            priceLbl.Size               = UDim2.new(0, 60, 1, 0)
            priceLbl.Position           = UDim2.new(1, -64, 0, 0)
            priceLbl.BackgroundTransparency = 1
            priceLbl.Text               = "$" .. entry.price
            priceLbl.Font               = Enum.Font.Gotham
            priceLbl.TextSize           = 11
            priceLbl.TextColor3         = C.TEXT_WHITE
            priceLbl.TextXAlignment     = Enum.TextXAlignment.Right
        end

        local rowBtn = Instance.new("TextButton", row)
        rowBtn.Size               = UDim2.new(1, 0, 1, 0)
        rowBtn.BackgroundTransparency = 1
        rowBtn.Text               = ""
        rowBtn.AutoButtonColor    = false
        rowBtn.ZIndex             = 5
        rowBtn.MouseEnter:Connect(function()
            if entry.name ~= dropSelected then
                tw(row, { BackgroundColor3 = Color3.fromRGB(36, 36, 36) })
            end
        end)
        rowBtn.MouseLeave:Connect(function()
            if entry.name ~= dropSelected then
                tw(row, { BackgroundColor3 = C.BG_ROW })
            end
        end)
        rowBtn.MouseButton1Click:Connect(function()
            if entry.name == dropSelected then
                clearSelection()
            else
                applySelection(entry)
            end
            buildList()
            task.delay(0.04, closeList)
        end)
    end
end

local function openList()
    dropIsOpen = true
    dropItems  = grabAllItems()
    buildList()
    local count  = #dropItems
    local listH  = math.min(count, MAX_SHOW) * (ITEM_H + 2) + 8
    local totalH = HEADER_H + 2 + listH
    divider.Visible = true
    tw(arrowLbl,   { Rotation = 180 })
    tw(dropOuter,  { Size = UDim2.new(1, -12, 0, totalH) })
    tw(listScroll, { Size = UDim2.new(1, 0, 0, listH) })
end

headerBtn.MouseButton1Click:Connect(function()
    if dropIsOpen then closeList() else openList() end
end)
headerBtn.MouseEnter:Connect(function()
    tw(selFrame, { BackgroundColor3 = Color3.fromRGB(40, 40, 40) })
end)
headerBtn.MouseLeave:Connect(function()
    tw(selFrame, { BackgroundColor3 = C.BG_INPUT })
end)

task.spawn(function()
    task.wait(0.8)
    dropItems = grabAllItems()
end)

-- ════════════════════════════════════════════════════
-- OPTIONS
-- ════════════════════════════════════════════════════
mkSep()
mkLabel("Options")
mkNumberInput("Amount to buy", 1, 9999, AB_amount, function(v) AB_amount = v end)

-- ════════════════════════════════════════════════════
-- START / STOP
-- ════════════════════════════════════════════════════
mkSep()
mkLabel("Actions")

local actionRow = Instance.new("Frame", autoBuyPage)
actionRow.Size               = UDim2.new(1, -12, 0, 36)
actionRow.BackgroundTransparency = 1

local startBtn = Instance.new("TextButton", actionRow)
startBtn.Size             = UDim2.new(0.5, -4, 1, 0)
startBtn.Position         = UDim2.new(0, 0, 0, 0)
startBtn.BackgroundColor3 = C.BTN
startBtn.Text             = "Start"
startBtn.Font             = Enum.Font.GothamBold
startBtn.TextSize         = 13
startBtn.TextColor3       = C.TEXT_DIM
startBtn.BorderSizePixel  = 0
startBtn.AutoButtonColor  = false
Instance.new("UICorner", startBtn).CornerRadius = UDim.new(0, 6)
local startStroke = Instance.new("UIStroke", startBtn)
startStroke.Color = C.BORDER; startStroke.Thickness = 1; startStroke.Transparency = 0

local stopBtn = Instance.new("TextButton", actionRow)
stopBtn.Size             = UDim2.new(0.5, -4, 1, 0)
stopBtn.Position         = UDim2.new(0.5, 4, 0, 0)
stopBtn.BackgroundColor3 = C.BTN
stopBtn.Text             = "Stop"
stopBtn.Font             = Enum.Font.GothamBold
stopBtn.TextSize         = 13
stopBtn.TextColor3       = C.TEXT_DIM
stopBtn.BorderSizePixel  = 0
stopBtn.AutoButtonColor  = false
Instance.new("UICorner", stopBtn).CornerRadius = UDim.new(0, 6)
local stopStroke = Instance.new("UIStroke", stopBtn)
stopStroke.Color = C.BORDER; stopStroke.Thickness = 1; stopStroke.Transparency = 0

AB_startBtn = startBtn
AB_stopBtn  = stopBtn
refreshActionButtons()

startBtn.MouseButton1Click:Connect(function()
    if AB_buying or not AB_item then return end
    task.spawn(function()
        AB_buy(AB_item, AB_amount, AB_isBlueprint, false)
    end)
end)

stopBtn.MouseButton1Click:Connect(function()
    if not AB_buying then return end
    AB_aborted = true
    setStatus("Stopping...", true)
end)

-- ════════════════════════════════════════════════════
-- SPECIAL
-- ════════════════════════════════════════════════════
mkSep()
mkLabel("Special")

mkBtn("Buy All Blueprints", function()
    if AB_buying then return end
    task.spawn(function()
        AB_buying  = true
        AB_aborted = false
        refreshActionButtons()
        local bps = grabBlueprintNames()
        if #bps == 0 then
            setStatus("No blueprints found in stores.", false)
            AB_buying = false; refreshActionButtons(); return
        end
        for i, bp in ipairs(bps) do
            if AB_aborted then break end
            setStatus("[" .. i .. "/" .. #bps .. "]  " .. bp, true)
            AB_buy(bp, 1, true, true)
            if not AB_aborted then
                task.wait(0.3)
                openBoxFor(bp, nil)
            end
        end
        AB_buying = false
        setProgress(nil)
        setStatus(AB_aborted and "Stopped." or ("Done - " .. #bps .. " blueprints"), false)
        refreshActionButtons()
    end)
end)

mkBtn("Buy RukiryAxe  ($7,400)", function()
    if AB_buying then return end
    task.spawn(function()
        AB_buying  = true
        AB_aborted = false
        refreshActionButtons()

        local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
        if not hrp then AB_buying = false; refreshActionButtons(); return end
        local origin = hrp.CFrame

        local Dragging = RS.Interaction and RS.Interaction:FindFirstChild("ClientIsDragging")

        local function openThenTeleport(itemName, destPos)
            openBoxFor(itemName, nil)
            local found, deadline = nil, tick() + 10
            repeat
                task.wait(0.05)
                for _, v in next, workspace:GetDescendants() do
                    local iv    = v:FindFirstChild("ItemName")
                    local owner = v:FindFirstChild("Owner")
                    if iv and iv.Value == itemName and owner and owner.Value == player then
                        found = v; break
                    end
                end
            until found or tick() > deadline
            if not (found and destPos) then return end
            local m = found:FindFirstChild("Main")
            if not m then return end
            local h = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
            if h then h.CFrame = CFrame.new(m.CFrame.p) + Vector3.new(5, 0, 0) end
            task.wait(0.1)
            pcall(function()
                if not found.PrimaryPart then found.PrimaryPart = m end
                local t = 0
                while not isnetworkowner(m) and t < 3 do
                    if Dragging then Dragging:FireServer(found) end
                    task.wait(0.05); t += 0.05
                end
                if Dragging then Dragging:FireServer(found) end
                m:PivotTo(CFrame.new(destPos)); task.wait(0.05)
            end)
        end

        setStatus("Buying LightBulb...",  true); AB_buy("LightBulb",  1, false, true)
        openThenTeleport("LightBulb",  Vector3.new(322.39, 45.96, 1916.45))

        setStatus("Buying BagOfSand...",  true); AB_buy("BagOfSand",  1, false, true)
        openThenTeleport("BagOfSand",  Vector3.new(319.48, 45.96, 1914.38))

        setStatus("Buying CanOfWorms...", true); AB_buy("CanOfWorms", 1, false, true)
        openThenTeleport("CanOfWorms", Vector3.new(317.21, 45.92, 1918.07))

        setStatus("Waiting for RukiryAxe...", true)
        local axe = nil
        for _, v in next, workspace:GetDescendants() do
            if v:IsA("Model") then
                local iv = v:FindFirstChild("ItemName"); local tn = v:FindFirstChild("ToolName")
                if (iv and iv.Value == "Rukiryaxe") or (tn and tn.Value == "Rukiryaxe") then
                    axe = v; break
                end
            end
        end
        if not axe then
            local sig  = Instance.new("BindableEvent")
            local conn
            conn = workspace.DescendantAdded:Connect(function(v)
                if axe then conn:Disconnect(); return end
                local model = v:IsA("Model") and v or v.Parent
                if not (model and model:IsA("Model")) then return end
                local iv = model:FindFirstChild("ItemName"); local tn = model:FindFirstChild("ToolName")
                if (iv and iv.Value == "Rukiryaxe") or (tn and tn.Value == "Rukiryaxe") then
                    axe = model; conn:Disconnect(); sig:Fire()
                end
            end)
            task.delay(30, function()
                if conn.Connected then conn:Disconnect() end; sig:Fire()
            end)
            sig.Event:Wait(); sig:Destroy()
        end

        if axe then
            setStatus("Picking up RukiryAxe...", true)
            local ClientInteracted   = RS:FindFirstChild("ClientInteracted",         true)
            local ClientGetUserPerms = RS:FindFirstChild("ClientGetUserPermissions", true)
            local axeMain = axe:FindFirstChild("Main")
            if axeMain then
                local h = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
                if h then h.CFrame = axeMain.CFrame + Vector3.new(3, 0, 3) end
                task.wait(0.2)
            end
            local uid = tostring(player.UserId)
            if ClientGetUserPerms then
                ClientGetUserPerms:InvokeServer(uid, "Interact")
                ClientGetUserPerms:InvokeServer(uid, "MoveStructure")
                ClientGetUserPerms:InvokeServer(uid, "Destroy")
                ClientGetUserPerms:InvokeServer(uid, "Grab")
            end
            task.wait(0.608)
            if ClientInteracted then
                ClientInteracted:FireServer(
                    RS:FindFirstChild("Model", true) or workspace:FindFirstChild("Model", true),
                    "Pick up tool"
                )
            end
            task.wait(0.211)
            local ConfirmIdentity = RS:FindFirstChild("ConfirmIdentity", true)
            if ConfirmIdentity then
                ConfirmIdentity:InvokeServer(
                    RS:FindFirstChild("Tool", true) or workspace:FindFirstChild("Tool", true),
                    "Rukiryaxe"
                )
            end
            task.wait(0.243)
            local TestPing = RS:FindFirstChild("TestPing", true)
            if TestPing then TestPing:InvokeServer() end
            task.wait(0.5)
            local h2 = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
            if h2 then h2.CFrame = origin end
            setStatus("RukiryAxe obtained.", false)
        else
            setStatus("RukiryAxe did not appear in time.", false)
        end

        AB_buying = false
        refreshActionButtons()
    end)
end)

-- ════════════════════════════════════════════════════
-- SERVICES
-- ════════════════════════════════════════════════════
mkSep()
mkLabel("Services  (pay at counter)")

for _, svc in ipairs(AB_Services) do
    local btn = mkBtn(svc.label)
    btn.TextColor3 = C.TEXT_MID
    btn.MouseButton1Click:Connect(function()
        task.spawn(function()
            local PC  = RS:FindFirstChild("PlayerChatted",    true)
            local SCV = RS:FindFirstChild("SetChattingValue", true)
            if not (PC and SCV) then return end
            local args = { Character=svc.char, Name=svc.char, ID=svc.id, Dialog="Dialog" }
            PC:InvokeServer(args, "Initiate")
            task.wait(0.05); SCV:InvokeServer(2)
            task.wait(svc.wConfirm)
            PC:InvokeServer(args, "ConfirmPurchase")
            task.wait(0.05); SCV:InvokeServer(2)
            task.wait(svc.wEnd)
            PC:InvokeServer(args, "EndChat")
            task.wait(0.05); SCV:InvokeServer(0)
            if svc.wFinal then task.wait(0.05); SCV:InvokeServer(1) end
            setStatus("Paid: " .. svc.label, false)
        end)
    end)
end

-- ════════════════════════════════════════════════════
-- CLEANUP
-- ════════════════════════════════════════════════════
table.insert(cleanupTasks, function()
    AB_aborted = true
    AB_buying  = false
end)

print("[VanillaHub] Vanilla4 (AutoBuy) loaded.")
