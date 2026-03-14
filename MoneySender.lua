local Fluent = loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()
local lp = game.Players.LocalPlayer
local rem = game:GetService("ReplicatedStorage"):WaitForChild("Transactions"):WaitForChild("ClientToServer"):WaitForChild("Donate")
local win = Fluent:CreateWindow({Title = "Auto Send Money", SubTitle = "", TabWidth = 120, Size = UDim2.fromOffset(420, 420), Acrylic = false, Theme = "Dark", MinimizeKey = Enum.KeyCode.LeftControl})
local main = win:AddTab({Title = "Sender", Icon = "coins"})
local logs = win:AddTab({Title = "Logs", Icon = "list"})
local status = main:AddButton({Title = "Status: Idle", Description = "Toggle 'Auto Send' to start"})
local last_sent = main:AddParagraph({Title = "Last Donation → None"})
local log_list = {}
local target = nil
local active = false

local p_drop = main:AddDropdown("pick", {
    Title = "Pick Player",
    Values = {},
    Callback = function(v) target = game.Players:FindFirstChild(v) end
})

local function get_plrs()
    local names = {}
    local first = nil
    for _, v in pairs(game.Players:GetPlayers()) do
        if v ~= lp then
            table.insert(names, v.Name)
            if not first then first = v end
        end
    end
    table.sort(names)
    p_drop:SetValues(names)
    if not target and first then
        target = first
        p_drop:SetValue(first.Name)
    end
end

get_plrs()
game.Players.PlayerAdded:Connect(get_plrs)
game.Players.PlayerRemoving:Connect(function(p)
    if target == p then target = nil end
    get_plrs()
end)

local amt_box = main:AddInput("amt", {Title = "Amount", Placeholder = "e.g. 500k or 1m", Default = nil})

local function clean_amt(str)
    if not str then return 1 end
    local s = str:lower():gsub(",", "")
    local n = tonumber(s:match("[%d%.]+")) or 1
    if s:find("m") then return math.floor(n * 1000000) end
    if s:find("k") then return math.floor(n * 1000) end
    return math.floor(n)
end

local function add_log(txt)
    last_sent:SetTitle("Last: " .. txt)
    local l = logs:AddParagraph({Title = txt})
    table.insert(log_list, 1, l)
    if #log_list > 10 then
        local old = table.remove(log_list)
        if old then old:Destroy() end
    end
end

main:AddToggle("auto", {
    Title = "Auto Send",
    Default = false,
    Callback = function(state)
        active = state
        if state then
            if not target then 
                active = false
                Fluent:Notify({Title = "Error", Content = "No players found"})
                return 
            end
            
            task.spawn(function()
                while active and target and target.Parent do
                    local val = clean_amt(amt_box.Value)
                    
                    rem:InvokeServer(target, val, 4)
                    add_log(string.format("[%s] $%s -> %s", os.date("%X"), val, target.Name))
                    
                    local finish = os.clock() + 150
                    while active and os.clock() < finish do
                        local diff = math.ceil(finish - os.clock())
                        status:SetTitle("Cooldown → " .. math.floor(diff/60) .. "m " .. string.format("%02ds", diff%60))
                        task.wait(1)
                    end
                    status:SetTitle("Cooldown → 0m 00s")
                    task.wait(0.1)
                end
                status:SetTitle("Status: Idle")
            end)
        end
    end
})

win:SelectTab(main)
Fluent:Notify({Title = "Loaded", Content = "Script Ready", Duration = 3})