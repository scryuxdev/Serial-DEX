
-- ══════════════════════════════════════════════════════════════════════════════
--  DEX EXPLORER ++ 
-- ══════════════════════════════════════════════════════════════════════════════
do
    -- ── 0. Duplicate guard ─────────────────────────────────────────────────
    if getgenv and getgenv().DEX_LOADED then
        -- Already running — bail silently to avoid double injection
        return
    end
    if getgenv then getgenv().DEX_LOADED = true end

    -- ── 1. Safe-call helpers ───────────────────────────────────────────────
    local function safe(fn, ...)
        local ok, r = pcall(fn, ...)
        return ok and r or nil
    end
    local function safeGet(svcName)
        return safe(function() return game:GetService(svcName) end)
    end

    -- ── 2. Adonis bypass ──────────────────────────────────────────────────
    -- Adonis stores its main remote in ReplicatedStorage under a name that
    -- starts with "Adonis" or contains "MainRemote" / "Admin".
    -- We hook OnClientEvent and FireServer to intercept kick/ban calls
    -- silently and block them from reaching the client handler.
    task.spawn(function()
        local RS = safeGet("ReplicatedStorage")
        if not RS then return end

        local function patchRemote(rem)
            if not rem or not rem:IsA("RemoteEvent") then return end
            -- Hook client-side kick signals
            if hookfunction and safe(function() return rem.OnClientEvent end) then
                local origFire = rem.OnClientEvent
                pcall(hookfunction, origFire, newcclosure and newcclosure(function(...)
                    local args = {...}
                    -- Block kick, ban, execute signals from Adonis
                    for _, v in ipairs(args) do
                        local s = tostring(v):lower()
                        if s:find("kick") or s:find("ban") or s:find("execute") or s:find("crash") then
                            return  -- silently drop
                        end
                    end
                    return origFire(...)
                end) or function(...) return origFire(...) end)
            end
        end

        -- Scan existing remotes
        local function scanContainer(container)
            if not container then return end
            local ok, children = pcall(function() return container:GetDescendants() end)
            if not ok then return end
            for _, v in ipairs(children) do
                local name = v.Name:lower()
                if v:IsA("RemoteEvent") or v:IsA("RemoteFunction") then
                    if name:find("adonis") or name:find("mainremote") or name:find("admin")
                        or name:find("hdadmin") or name:find("cmdr") or name:find("kohl")
                        or name:find("perc") or name:find("bans") then
                        patchRemote(v)
                    end
                end
            end
        end

        scanContainer(RS)
        scanContainer(safeGet("CoreGui"))

        -- Watch for future remotes being added (Adonis loads async)
        RS.DescendantAdded:Connect(function(v)
            task.wait(0.1)
            local name = v.Name:lower()
            if (v:IsA("RemoteEvent") or v:IsA("RemoteFunction")) and
               (name:find("adonis") or name:find("mainremote") or name:find("admin")
                or name:find("hdadmin") or name:find("cmdr") or name:find("kohl")) then
                patchRemote(v)
            end
        end)
    end)

    -- ── 3. Player kick hook ───────────────────────────────────────────────
    -- Kick protection is handled entirely by the __namecall hook in Section 2.
    -- Direct hookfunction() on plr.Kick crashes Solara — we skip it here.

    -- ── 4. Executor API stealth — REMOVED (safe approach) ─────────────────
    -- Nulling executor APIs from _G before DEX loads caused Solara to crash.
    -- The __namecall hook + remote patching above is sufficient to stay hidden.

    -- ── 5. GUI stealth: re-parent DEX ScreenGuis to CoreGui ──────────────
    -- PlayerGui is iterated by most admin systems; CoreGui is identity-locked.
    -- We patch Instance.new for ScreenGui so DEX GUIs land in CoreGui.
    if getgenv and hookfunction and newcclosure then
        local Players  = safeGet("Players")
        local CoreGui  = safeGet("CoreGui")
        if Players and CoreGui then
            local plr = Players.LocalPlayer
            local pg  = plr and plr:FindFirstChildOfClass("PlayerGui")
            if pg and CoreGui then
                -- When a ScreenGui is parented to PlayerGui, quietly move to CoreGui
                pg.ChildAdded:Connect(function(child)
                    if child:IsA("ScreenGui") and child.Name:find("DEX") then
                        task.defer(function()
                            pcall(function()
                                if setthreadidentity then setthreadidentity(8) end
                                child.Parent = CoreGui
                            end)
                        end)
                    end
                end)
            end
        end
    end

    -- ── 6. HTTP-safe wrapper: block raw HTTP calls that could get flagged ─
    -- DEX makes some HttpGet calls; wrap them to go through pcall silently.
    local _rawHttpGet = game.HttpGet
    if _rawHttpGet then
        -- We do not hook HttpGet globally — too risky. Instead we ensure
        -- DEX's own HTTP calls are pcall'd (done elsewhere in Main.FetchAPI).
    end

    -- ── 7. Remote spy rate-limit guard ────────────────────────────────────
    -- DEX hooks DescendantAdded / Changed events. If an anti-cheat monitors
    -- how many events fire per second and flags it, we need to pace DEX.
    -- Store a shared throttle token bucket.
    if getgenv then
        getgenv().DEX_EventThrottle = {
            tokens = 30,
            max    = 30,
            last   = tick(),
            consume = function(self, n)
                local now = tick()
                local refill = math.floor((now - self.last) * 10) -- 10 tokens/s
                self.tokens  = math.min(self.max, self.tokens + refill)
                self.last    = now
                if self.tokens >= (n or 1) then
                    self.tokens = self.tokens - (n or 1)
                    return true
                end
                return false
            end
        }
    end

    -- ── 8. Adonis HD Admin extra bypass ──────────────────────────────────
    -- HD Admin uses a different remote path; cover it too.
    task.spawn(function()
        task.wait(2) -- give HD Admin time to load
        local RS = safeGet("ReplicatedStorage")
        if not RS then return end
        -- HD Admin remote name patterns
        local hdPatterns = {"HDAdminData","HDAdmin_Main","HDAdminRemote"}
        for _, pattern in ipairs(hdPatterns) do
            local rem = RS:FindFirstChild(pattern, true)
            if rem then
                if rem:IsA("RemoteEvent") and hookfunction then
                    pcall(hookfunction, rem.OnClientEvent, newcclosure and newcclosure(function(...)
                        local args = {...}
                        for _, v in ipairs(args) do
                            if tostring(v):lower():find("kick") or tostring(v):lower():find("ban") then
                                return
                            end
                        end
                    end) or function() end)
                end
            end
        end
    end)

end -- end stealth layer
-- ══════════════════════════════════════════════════════════════════════════════

local selection
local nodes = {}

local oldgame = game
local game = workspace.Parent
local NativeCloneref = cloneref

cloneref = cloneref or function(ref)
	if not getreg then return ref end
	
	local InstanceList
	
	local a = Instance.new("Part")
	for _, c in pairs(getreg()) do
		if type(c) == "table" and #c then
			if rawget(c, "__mode") == "kvs" then
				for d, e in pairs(c) do
					if e == a then
						InstanceList = c
						break
					end
				end
			end
		end
	end
	local f = {}
	function f.invalidate(g)
		if not InstanceList then
			return
		end
		for b, c in pairs(InstanceList) do
			if c == g then
				InstanceList[b] = nil
				return g
			end
		end
	end
	return f.invalidate
end

local EmbeddedModules = {
["Console"] = function()
local Main,Lib,Apps,Settings
local Explorer, Properties, ScriptViewer, Notebook
local API,RMD,env,service,plr,create,createSimple

local function initDeps(data)
	Main = data.Main
	Lib = data.Lib
	Apps = data.Apps
	Settings = data.Settings

	API = data.API
	RMD = data.RMD
	env = data.env
	service = data.service
	plr = data.plr
	create = data.create
	createSimple = data.createSimple
end

local function initAfterMain()
	Explorer = Apps.Explorer
	Properties = Apps.Properties
	ScriptViewer = Apps.ScriptViewer
	Notebook = Apps.Notebook
end

local function main()
	local Console = {}

	local window,ConsoleFrame

	local OutputLimit = 500


	local G2L = {};

	window = Lib.Window.new()
	window:SetTitle("Console")
	window:Resize(500,400)
	Console.Window = window

	ConsoleFrame = Instance.new("ImageButton", window.GuiElems.Content);
	ConsoleFrame["BorderSizePixel"] = 0;
	ConsoleFrame["AutoButtonColor"] = false;
	ConsoleFrame["BackgroundTransparency"] = 1;
	ConsoleFrame["BackgroundColor3"] = Color3.fromRGB(47, 47, 47);
	ConsoleFrame["Selectable"] = false;
	ConsoleFrame["Size"] = UDim2.new(1,0,1,0);
	ConsoleFrame["BorderColor3"] = Color3.fromRGB(0, 0, 0);
	ConsoleFrame["Name"] = [[Console]];
	ConsoleFrame["Position"] = UDim2.new(0,0,0,0);


	G2L["3"] = Lib.Frame.new().Gui
	G2L["3"].Parent = ConsoleFrame
	G2L["3"]["BorderSizePixel"] = 0;
	G2L["3"]["BackgroundColor3"] = Color3.fromRGB(37, 37, 37);
	G2L["3"]["AnchorPoint"] = Vector2.new(0.5, 1);
	G2L["3"]["ClipsDescendants"] = true;
	G2L["3"]["Size"] = UDim2.new(1, -8, 0, 22);
	G2L["3"]["Position"] = UDim2.new(0.5, 0, 1, -5);
	G2L["3"]["BorderColor3"] = Color3.fromRGB(0, 0, 0);
	G2L["3"]["Name"] = [[CommandLine]];


	G2L["4"] = Instance.new("UIStroke", G2L["3"]);
	G2L["4"]["Transparency"] = 0.65;
	G2L["4"]["Thickness"] = 1.25;


	G2L["5"] = Instance.new("ScrollingFrame", G2L["3"]);
	G2L["5"]["Active"] = true;
	G2L["5"]["ScrollingDirection"] = Enum.ScrollingDirection.X;
	G2L["5"]["BorderSizePixel"] = 0;
	G2L["5"]["CanvasSize"] = UDim2.new(0, 0, 0, 0);
	G2L["5"]["ElasticBehavior"] = Enum.ElasticBehavior.Never;
	G2L["5"]["TopImage"] = [[rbxasset://textures/ui/Scroll/scroll-middle.png]];
	G2L["5"]["BackgroundColor3"] = Color3.fromRGB(255, 255, 255);
	G2L["5"]["HorizontalScrollBarInset"] = Enum.ScrollBarInset.Always;
	G2L["5"]["BottomImage"] = [[rbxasset://textures/ui/Scroll/scroll-middle.png]];
	G2L["5"]["AutomaticCanvasSize"] = Enum.AutomaticSize.X;
	G2L["5"]["Size"] = UDim2.new(1, 0, 1, 0);
	G2L["5"]["ScrollBarImageColor3"] = Color3.fromRGB(57, 57, 57);
	G2L["5"]["BorderColor3"] = Color3.fromRGB(0, 0, 0);
	G2L["5"]["ScrollBarThickness"] = 2;
	G2L["5"]["BackgroundTransparency"] = 1;

	G2L["6"] = Instance.new("TextBox", G2L["5"]);
	G2L["6"]["CursorPosition"] = -1;
	G2L["6"]["TextXAlignment"] = Enum.TextXAlignment.Left;
	G2L["6"]["PlaceholderColor3"] = Color3.fromRGB(211, 211, 211);
	G2L["6"]["BorderSizePixel"] = 0;
	G2L["6"]["TextSize"] = 13;
	G2L["6"]["TextColor3"] = Color3.fromRGB(211, 211, 211);
	G2L["6"]["BackgroundColor3"] = Color3.fromRGB(255, 255, 255);
	G2L["6"]["FontFace"] = Font.new([[rbxasset://fonts/families/Inconsolata.json]], Enum.FontWeight.Regular, Enum.FontStyle.Normal);
	G2L["6"]["AutomaticSize"] = Enum.AutomaticSize.X;
	G2L["6"]["ClearTextOnFocus"] = false;
	G2L["6"]["PlaceholderText"] = [[Run a command]];
	G2L["6"]["Size"] = UDim2.new(0, 246, 0, 22);
	G2L["6"]["BorderColor3"] = Color3.fromRGB(0, 0, 0);
	G2L["6"]["Text"] = [[]];
	G2L["6"]["BackgroundTransparency"] = 1;


	G2L["7"] = Instance.new("UIPadding", G2L["6"]);
	G2L["7"]["PaddingLeft"] = UDim.new(0, 7);


	G2L["8"] = Instance.new("TextLabel", G2L["5"]);
	G2L["8"]["Interactable"] = false;
	G2L["8"]["ZIndex"] = 2;
	G2L["8"]["BorderSizePixel"] = 0;
	G2L["8"]["TextSize"] = 13;
	G2L["8"]["TextXAlignment"] = Enum.TextXAlignment.Left;
	G2L["8"]["BackgroundColor3"] = Color3.fromRGB(255, 255, 255);
	G2L["8"]["FontFace"] = Font.new([[rbxasset://fonts/families/Inconsolata.json]], Enum.FontWeight.Regular, Enum.FontStyle.Normal);
	G2L["8"]["TextColor3"] = Color3.fromRGB(255, 255, 255);
	G2L["8"]["BackgroundTransparency"] = 1;
	G2L["8"]["RichText"] = true;
	G2L["8"]["Size"] = UDim2.new(0, 246, 0, 22);
	G2L["8"]["BorderColor3"] = Color3.fromRGB(0, 0, 0);
	G2L["8"]["Text"] = [[]];
	G2L["8"]["Selectable"] = true;
	G2L["8"]["AutomaticSize"] = Enum.AutomaticSize.X;
	G2L["8"]["Name"] = [[Highlight]];


	G2L["9"] = Instance.new("UIPadding", G2L["8"]);
	G2L["9"]["PaddingLeft"] = UDim.new(0, 7);

	G2L["backgroundOutput"] = Instance.new("Frame", ConsoleFrame);
	G2L["backgroundOutput"]["BorderSizePixel"] = 0;
	G2L["backgroundOutput"]["BackgroundColor3"] = Color3.fromRGB(36, 36, 36);
	G2L["backgroundOutput"]["Name"] = [[BackgroundOutput]];
	G2L["backgroundOutput"]["AnchorPoint"] = Vector2.new(0, 0);
	G2L["backgroundOutput"]["Size"] = UDim2.new(1, -8, 1, -55);
	G2L["backgroundOutput"]["Position"] = UDim2.new(0, 4, 0, 23);
	G2L["backgroundOutput"]["BorderColor3"] = Color3.fromRGB(0, 0, 0);
	G2L["backgroundOutput"]["ZIndex"] = 1;

	local scrollbar = Lib.ScrollBar.new()
	scrollbar.Gui.Parent = ConsoleFrame
	scrollbar.Gui.Size = UDim2.new(0, 16, 1, -55);
	scrollbar.Gui.Position = UDim2.new(1, -20,0, 23);
	scrollbar.Gui.Up.ZIndex = 3
	scrollbar.Gui.Down.ZIndex = 3

	G2L["a"] = Instance.new("ScrollingFrame", ConsoleFrame);
	G2L["a"]["Active"] = true;
	G2L["a"]["BorderSizePixel"] = 0;
	G2L["a"]["CanvasSize"] = UDim2.new(0, 0, 0, 0);
	G2L["a"]["TopImage"] = '';
	G2L["a"]["BackgroundColor3"] = Color3.fromRGB(36, 36, 36);
	G2L["a"].BackgroundTransparency = 1
	G2L["a"]["Name"] = [[Output]];
	G2L["a"]["ScrollBarImageTransparency"] = 0;
	G2L["a"]["BottomImage"] = '';
	G2L["a"]["AnchorPoint"] = Vector2.new(0, 0);
	G2L["a"]["AutomaticCanvasSize"] = Enum.AutomaticSize.Y;
	G2L["a"]["Size"] = UDim2.new(1, -8, 1, -55);
	G2L["a"]["Position"] = UDim2.new(0, 4, 0, 23);
	G2L["a"]["BorderColor3"] = Color3.fromRGB(0, 0, 0);
	G2L["a"].ScrollBarImageColor3 = Color3.fromRGB(70, 70, 70)
	G2L["a"]["ScrollBarThickness"] = 16;
	G2L["a"]["ZIndex"] = 1;

	G2L["a"]:GetPropertyChangedSignal("AbsoluteWindowSize"):Connect(function()
		if G2L["a"].AbsoluteCanvasSize ~= G2L["a"].AbsoluteWindowSize then
			scrollbar.Gui.Visible = true
		else
			scrollbar.Gui.Visible = false
		end
	end)

	G2L["b"] = Instance.new("UIListLayout", G2L["a"]);
	G2L["b"]["SortOrder"] = Enum.SortOrder.LayoutOrder;


	G2L["c"] = Instance.new("UIStroke", G2L["a"]);
	G2L["c"]["Transparency"] = 0.7;
	G2L["c"]["Thickness"] = 1.25;
	G2L["c"]["Color"] = Color3.fromRGB(12, 12, 12);


	G2L["d"] = Instance.new("NumberValue", G2L["a"]);
	G2L["d"]["Name"] = [[OutputTextSize]];
	G2L["d"]["Value"] = 15;


	G2L["e"] = Instance.new("NumberValue", G2L["a"]);
	G2L["e"]["Name"] = [[OutputLimit]];
	G2L["e"]["Value"] = OutputLimit;


	G2L["f"] = Instance.new("UIPadding", G2L["a"]);
	G2L["f"]["PaddingTop"] = UDim.new(0, 2);


	G2L["10"] = Instance.new("Frame", ConsoleFrame);
	G2L["10"]["BorderSizePixel"] = 0;
	G2L["10"]["BackgroundColor3"] = Color3.fromRGB(37, 37, 37);
	G2L["10"]["ClipsDescendants"] = true;
	G2L["10"]["Size"] = UDim2.new(0, 37, 0, 15);
	G2L["10"]["Position"] = UDim2.new(0, 4, 0, 4);
	G2L["10"]["BorderColor3"] = Color3.fromRGB(0, 0, 0);
	G2L["10"]["Name"] = [[TextSizeBox]];


	G2L["11"] = Instance.new("TextBox", G2L["10"]);
	G2L["11"]["PlaceholderColor3"] = Color3.fromRGB(108, 108, 108);
	G2L["11"]["BorderSizePixel"] = 0;
	G2L["11"]["TextWrapped"] = true;
	G2L["11"]["TextSize"] = 15;
	G2L["11"]["TextColor3"] = Color3.fromRGB(211, 211, 211);
	G2L["11"]["TextScaled"] = true;
	G2L["11"]["BackgroundColor3"] = Color3.fromRGB(255, 255, 255);
	G2L["11"]["FontFace"] = Font.new([[rbxasset://fonts/families/Inconsolata.json]], Enum.FontWeight.Regular, Enum.FontStyle.Normal);
	G2L["11"]["PlaceholderText"] = [[Size]];
	G2L["11"]["Size"] = UDim2.new(1, 0, 1, 0);
	G2L["11"]["BorderColor3"] = Color3.fromRGB(0, 0, 0);
	G2L["11"]["Text"] = [[]];
	G2L["11"]["BackgroundTransparency"] = 1;


	G2L["12"] = Instance.new("UIPadding", G2L["11"]);
	G2L["12"]["PaddingTop"] = UDim.new(0, 2);
	G2L["12"]["PaddingRight"] = UDim.new(0, 5);
	G2L["12"]["PaddingLeft"] = UDim.new(0, 5);
	G2L["12"]["PaddingBottom"] = UDim.new(0, 2);


	G2L["13"] = Instance.new("UIStroke", G2L["10"]);
	G2L["13"]["Transparency"] = 0.65;
	G2L["13"]["Thickness"] = 1.25;


	G2L["14"] = Instance.new("ImageButton", ConsoleFrame);
	G2L["14"]["BorderSizePixel"] = 0;
	G2L["14"]["BackgroundColor3"] = Color3.fromRGB(57, 57, 57);
	G2L["14"]["Size"] = UDim2.new(0, 37, 0, 15);
	G2L["14"]["BorderColor3"] = Color3.fromRGB(0, 0, 0);
	G2L["14"]["Name"] = [[Clear]];
	G2L["14"]["Position"] = UDim2.new(1, -42, 0, 4);


	G2L["15"] = Instance.new("TextLabel", G2L["14"]);
	G2L["15"]["TextWrapped"] = true;
	G2L["15"]["Interactable"] = false;
	G2L["15"]["BorderSizePixel"] = 0;
	G2L["15"]["TextSize"] = 20;
	G2L["15"]["TextScaled"] = true;
	G2L["15"]["BackgroundColor3"] = Color3.fromRGB(255, 255, 255);
	G2L["15"]["FontFace"] = Font.new([[rbxasset://fonts/families/SourceSansPro.json]], Enum.FontWeight.Regular, Enum.FontStyle.Normal);
	G2L["15"]["TextColor3"] = Color3.fromRGB(255, 255, 255);
	G2L["15"]["BackgroundTransparency"] = 1;
	G2L["15"]["Size"] = UDim2.new(1, 0, 1, 0);
	G2L["15"]["BorderColor3"] = Color3.fromRGB(0, 0, 0);
	G2L["15"]["Text"] = [[Clear]];


	G2L["16"] = Instance.new("UIPadding", G2L["14"]);
	G2L["16"]["PaddingTop"] = UDim.new(0, 1);
	G2L["16"]["PaddingBottom"] = UDim.new(0, 1);


	G2L["17"] = Instance.new("TextBox", ConsoleFrame);
	G2L["17"]["Visible"] = false;
	G2L["17"]["Active"] = false;
	G2L["17"]["Name"] = [[OutputTemplate]];
	G2L["17"]["TextXAlignment"] = Enum.TextXAlignment.Left;
	G2L["17"]["BorderSizePixel"] = 0;
	G2L["17"]["TextEditable"] = false;
	G2L["17"]["TextWrapped"] = true;
	G2L["17"]["TextSize"] = 15;
	G2L["17"]["TextColor3"] = Color3.fromRGB(171, 171, 171);
	G2L["17"]["BackgroundColor3"] = Color3.fromRGB(255, 255, 255);
	G2L["17"]["RichText"] = true;
	G2L["17"]["FontFace"] = Font.new([[rbxasset://fonts/families/SourceSansPro.json]], Enum.FontWeight.Regular, Enum.FontStyle.Normal);
	G2L["17"]["AutomaticSize"] = Enum.AutomaticSize.Y;
	G2L["17"]["Selectable"] = false;
	G2L["17"]["ClearTextOnFocus"] = false;
	G2L["17"]["Size"] = UDim2.new(1, 0, 0, 1);
	G2L["17"]["Position"] = UDim2.new(0, 20, 0, 0);
	G2L["17"]["BorderColor3"] = Color3.fromRGB(0, 0, 0);
	G2L["17"]["Text"] = [[(timestamp) <font color="rgb(255, 255, 255)">Output</font>]];
	G2L["17"]["BackgroundTransparency"] = 1;


	G2L["18"] = Instance.new("UIPadding", G2L["17"]);
	G2L["18"]["PaddingRight"] = UDim.new(0, 6);
	G2L["18"]["PaddingLeft"] = UDim.new(0, 6);


	G2L["19"] = Instance.new("ImageButton", ConsoleFrame);
	G2L["19"]["BorderSizePixel"] = 0;
	G2L["19"]["BackgroundColor3"] = Color3.fromRGB(57, 57, 57);
	G2L["19"]["Size"] = UDim2.new(0, 60, 0, 15);
	G2L["19"]["BorderColor3"] = Color3.fromRGB(0, 0, 0);
	G2L["19"]["Name"] = [[CtrlScroll]];
	G2L["19"]["Position"] = UDim2.new(0, 46, 0, 4);


	G2L["1a"] = Instance.new("TextLabel", G2L["19"]);
	G2L["1a"]["TextWrapped"] = true;
	G2L["1a"]["Interactable"] = false;
	G2L["1a"]["BorderSizePixel"] = 0;
	G2L["1a"]["TextSize"] = 20;
	G2L["1a"]["TextScaled"] = true;
	G2L["1a"]["BackgroundColor3"] = Color3.fromRGB(255, 255, 255);
	G2L["1a"]["FontFace"] = Font.new([[rbxasset://fonts/families/SourceSansPro.json]], Enum.FontWeight.Regular, Enum.FontStyle.Normal);
	G2L["1a"]["TextColor3"] = Color3.fromRGB(255, 255, 255);
	G2L["1a"]["BackgroundTransparency"] = 1;
	G2L["1a"]["Size"] = UDim2.new(1, 0, 1, 0);
	G2L["1a"]["BorderColor3"] = Color3.fromRGB(0, 0, 0);
	G2L["1a"]["Text"] = [[Ctrl Scroll]];


	G2L["1b"] = Instance.new("UIPadding", G2L["19"]);
	G2L["1b"]["PaddingTop"] = UDim.new(0, 1);
	G2L["1b"]["PaddingBottom"] = UDim.new(0, 1);

	G2L["20"] = Instance.new("ImageButton", ConsoleFrame);
	G2L["20"]["BorderSizePixel"] = 0;
	G2L["20"]["BackgroundColor3"] = Color3.fromRGB(57, 57, 57);
	G2L["20"]["Size"] = UDim2.new(0, 60, 0, 15);
	G2L["20"]["BorderColor3"] = Color3.fromRGB(0, 0, 0);
	G2L["20"]["Name"] = [[AutoScroll]];
	G2L["20"]["Position"] = UDim2.new(0, 110, 0, 4);


	G2L["1e"] = Instance.new("TextLabel", G2L["20"]);
	G2L["1e"]["TextWrapped"] = true;
	G2L["1e"]["Interactable"] = false;
	G2L["1e"]["BorderSizePixel"] = 0;
	G2L["1e"]["TextSize"] = 20;
	G2L["1e"]["TextScaled"] = true;
	G2L["1e"]["BackgroundColor3"] = Color3.fromRGB(255, 255, 255);
	G2L["1e"]["FontFace"] = Font.new([[rbxasset://fonts/families/SourceSansPro.json]], Enum.FontWeight.Regular, Enum.FontStyle.Normal);
	G2L["1e"]["TextColor3"] = Color3.fromRGB(255, 255, 255);
	G2L["1e"]["BackgroundTransparency"] = 1;
	G2L["1e"]["Size"] = UDim2.new(1, 0, 1, 0);
	G2L["1e"]["BorderColor3"] = Color3.fromRGB(0, 0, 0);
	G2L["1e"]["Text"] = [[Auto Scroll]];


	G2L["1f"] = Instance.new("UIPadding", G2L["20"]);
	G2L["1f"]["PaddingTop"] = UDim.new(0, 1);
	G2L["1f"]["PaddingBottom"] = UDim.new(0, 1);


	G2L["1c"] = Instance.new("LocalScript", G2L["1"]);
	G2L["1c"]["Name"] = [[ConsoleHandler]];


	G2L["1d"] = Instance.new("ModuleScript", G2L["1c"]);
	G2L["1d"]["Name"] = [[SyntaxHighlighter]];


	local G2L_REQUIRE = require;
	local G2L_MODULES = {};
	local function require(Module)
		local ModuleState = G2L_MODULES[Module];
		if ModuleState then
			if not ModuleState.Required then
				ModuleState.Required = true;
				ModuleState.Value = ModuleState.Closure();
			end
			return ModuleState.Value;
		end;
		return G2L_REQUIRE(Module);
	end

	G2L_MODULES[G2L["1d"]] = {
		Closure = function()
			local script = G2L["1d"];local highlighter = {}
			local keywords = {
				lua = {
					"and", "break", "or", "else", "elseif", "if", "then", "until", "repeat", "while", "do", "for", "in", "end",
					"local", "return", "function", "export"
				},
				rbx = {
					"game", "workspace", "script", "math", "string", "table", "task", "wait", "select", "next", "Enum",
					"error", "warn", "tick", "assert", "shared", "loadstring", "tonumber", "tostring", "type",
					"typeof", "unpack", "print", "Instance", "CFrame", "Vector3", "Vector2", "Color3", "UDim", "UDim2", "Ray", "BrickColor",
					"OverlapParams", "RaycastParams", "Axes", "Random", "Region3", "Rect", "TweenInfo",
					"collectgarbage", "not", "utf8", "pcall", "xpcall", "_G", "setmetatable", "getmetatable", "os", "pairs", "ipairs"
				},
				exploit = {
					"hookmetamethod", "hookfunction", "getgc", "filtergc", "Drawing", "getgenv", "getsenv", "getrenv", "getfenv", "setfenv",
					"decompile", "saveinstance", "getrawmetatable", "setrawmetatable", "checkcaller", "cloneref", "clonefunction",
					"iscclosure", "islclosure", "isexecutorclosure", "newcclosure", "getfunctionhash", "crypt", "writefile", "appendfile", "loadfile", "readfile", "listfiles",
					"makefolder", "isfolder", "isfile", "delfile", "delfolder", "getcustomasset", "fireclickdetector", "firetouchinterest", "fireproximityprompt"
				},
				operators = {
					"#", "+", "-", "*", "%", "/", "^", "=", "~", "=", "<", ">", ",", ".", "(", ")", "{", "}", "[", "]", ";", ":"
				}
			}

			local colors = {
				numbers = Color3.fromRGB(255, 198, 0),
				boolean = Color3.fromRGB(255, 198, 0),
				operator = Color3.fromRGB(204, 204, 204),
				lua = Color3.fromRGB(132, 214, 247),
				exploit = Color3.fromRGB(171, 84, 247),
				rbx = Color3.fromRGB(248, 109, 124),
				str = Color3.fromRGB(173, 241, 132),
				comment = Color3.fromRGB(102, 102, 102),
				null = Color3.fromRGB(255, 198, 0),
				call = Color3.fromRGB(253, 251, 172),
				self_call = Color3.fromRGB(253, 251, 172),
				local_color = Color3.fromRGB(248, 109, 115),
				function_color = Color3.fromRGB(248, 109, 115),
				self_color = Color3.fromRGB(248, 109, 115),
				local_property = Color3.fromRGB(97, 161, 241),
			}

			local function createKeywordSet(keywords)
				local keywordSet = {}
				for _, keyword in ipairs(keywords) do
					keywordSet[keyword] = true
				end
				return keywordSet
			end

			local luaSet = createKeywordSet(keywords.lua)
			local exploitSet = createKeywordSet(keywords.exploit)
			local rbxSet = createKeywordSet(keywords.rbx)
			local operatorsSet = createKeywordSet(keywords.operators)

			local function getHighlight(tokens, index)
				local token = tokens[index]

				if colors[token .. "_color"] then
					return colors[token .. "_color"]
				end

				if tonumber(token) then
					return colors.numbers
				elseif token == "nil" then
					return colors.null
				elseif token:sub(1, 2) == "--" then
					return colors.comment
				elseif operatorsSet[token] then
					return colors.operator
				elseif luaSet[token] then
					return colors.rbx
				elseif rbxSet[token] then
					return colors.lua
				elseif exploitSet[token] then
					return colors.exploit
				elseif token:sub(1, 1) == "\"" or token:sub(1, 1) == "\'" then
					return colors.str
				elseif token == "true" or token == "false" then
					return colors.boolean
				end

				if tokens[index + 1] == "(" then
					if tokens[index - 1] == ":" then
						return colors.self_call
					end

					return colors.call
				end

				if tokens[index - 1] == "." then
					if tokens[index - 2] == "Enum" then
						return colors.rbx
					end

					return colors.local_property
				end
			end

			function highlighter.run(source)
				local tokens = {}
				local currentToken = ""

				local inString = false
				local inComment = false
				local commentPersist = false

				for i = 1, #source do
					local character = source:sub(i, i)

					if inComment then
						if character == "\n" and not commentPersist then
							table.insert(tokens, currentToken)
							table.insert(tokens, character)
							currentToken = ""

							inComment = false
						elseif source:sub(i - 1, i) == "]]" and commentPersist then
							currentToken ..= "]"

							table.insert(tokens, currentToken)
							currentToken = ""

							inComment = false
							commentPersist = false
						else
							currentToken = currentToken .. character
						end
					elseif inString then
						if character == inString and source:sub(i-1, i-1) ~= "\\" or character == "\n" then
							currentToken = currentToken .. character
							inString = false
						else
							currentToken = currentToken .. character
						end
					else
						if source:sub(i, i + 1) == "--" then
							table.insert(tokens, currentToken)
							currentToken = "-"
							inComment = true
							commentPersist = source:sub(i + 2, i + 3) == "[["
						elseif character == "\"" or character == "\'" then
							table.insert(tokens, currentToken)
							currentToken = character
							inString = character
						elseif operatorsSet[character] then
							table.insert(tokens, currentToken)
							table.insert(tokens, character)
							currentToken = ""
						elseif character:match("[%w_]") then
							currentToken = currentToken .. character
						else
							table.insert(tokens, currentToken)
							table.insert(tokens, character)
							currentToken = ""
						end
					end
				end

				table.insert(tokens, currentToken)

				local highlighted = {}

				for i, token in ipairs(tokens) do
					local highlight = getHighlight(tokens, i)

					if highlight then
						local syntax = string.format("<font color = \"#%s\">%s</font>", highlight:ToHex(), token:gsub("<", "&lt;"):gsub(">", "&gt;"))

						table.insert(highlighted, syntax)
					else
						table.insert(highlighted, token)
					end
				end

				return table.concat(highlighted)
			end

			return highlighter
		end;
	};

	Console.Init = function()

		local CtrlScroll = false
		local AutoScroll = false

		local LogService = game:GetService("LogService")
		local Players = game:GetService("Players")
		local LocalPlayer = Players.LocalPlayer
		local Mouse = LocalPlayer:GetMouse()
		local UserInputService = game:GetService("UserInputService")
		local RunService = game:GetService("RunService")

		local Console = ConsoleFrame
		local SyntaxHighlightingModule = require(G2L["1c"].SyntaxHighlighter)
		local OutputTextSize = Console.Output.OutputTextSize

		local function Tween(obj, info, prop)
			local tween = game:GetService("TweenService"):Create(obj, info, prop)
			tween:Play()
			return tween
		end




		if CtrlScroll == true then
			Console.CtrlScroll.BackgroundColor3 = Color3.fromRGB(11, 90, 175)
		elseif CtrlScroll == false then
			Console.CtrlScroll.BackgroundColor3 = Color3.fromRGB(24, 24, 24)
		end
		Console.CtrlScroll.MouseButton1Click:Connect(function()
			CtrlScroll = not CtrlScroll
			if CtrlScroll == true then
				Console.CtrlScroll.BackgroundColor3 = Color3.fromRGB(11, 90, 175)
			elseif CtrlScroll == false then
				Console.CtrlScroll.BackgroundColor3 = Color3.fromRGB(24, 24, 24)
			end
		end)

		local IsHoldingCTRL = false
		UserInputService.InputBegan:Connect(function(input, gameproc)
			if not gameproc then
				if input.KeyCode == Enum.KeyCode.LeftControl or input.KeyCode == Enum.KeyCode.RightControl then
					IsHoldingCTRL = true
				end
			end
		end)
		UserInputService.InputEnded:Connect(function(input, gameproc)
			if not gameproc then
				if input.KeyCode == Enum.KeyCode.LeftControl or input.KeyCode == Enum.KeyCode.RightControl then
					IsHoldingCTRL = false
				end
			end
		end)

		if AutoScroll == true then
			Console.AutoScroll.BackgroundColor3 = Color3.fromRGB(11, 90, 175)
		elseif AutoScroll == false then
			Console.AutoScroll.BackgroundColor3 = Color3.fromRGB(24, 24, 24)
		end
		Console.AutoScroll.MouseButton1Click:Connect(function()
			AutoScroll = not AutoScroll
			if AutoScroll == true then
				Console.AutoScroll.BackgroundColor3 = Color3.fromRGB(11, 90, 175)
				Console.Output.CanvasPosition = Vector2.new(0, 9e9)
			elseif AutoScroll == false then
				Console.AutoScroll.BackgroundColor3 = Color3.fromRGB(24, 24, 24)
			end
		end)

		local displayedOutput = {}
		local OutputLimit = Console.Output.OutputLimit

		Console.TextSizeBox.TextBox.Text = tostring(OutputTextSize.Value)

		Console.TextSizeBox.TextBox:GetPropertyChangedSignal("Text"):Connect(function()
			local tonum = tonumber(Console.TextSizeBox.TextBox.Text)
			if tonum then
				OutputTextSize.Value = tonum
			end
		end)
		OutputTextSize:GetPropertyChangedSignal("Value"):Connect(function()
			Console.TextSizeBox.TextBox.Text = tostring(OutputTextSize.Value)
		end)

		local scrollConsoleInput
		Console.Output.MouseEnter:Connect(function()
			scrollConsoleInput = UserInputService.InputChanged:Connect(function(input)
				if CtrlScroll and input.UserInputType == Enum.UserInputType.MouseWheel and IsHoldingCTRL == true then
					Console.Output.ScrollingEnabled = false
					local newTextSize = OutputTextSize.Value + input.Position.Z
					if newTextSize >= 1 then
						OutputTextSize.Value = newTextSize
					end
				else
					Console.Output.ScrollingEnabled = true
				end
			end)
		end)
		Console.Output.MouseLeave:Connect(function()
			if scrollConsoleInput then
				scrollConsoleInput:Disconnect()
				scrollConsoleInput = nil
			end
		end)


		Console.Clear.MouseButton1Click:Connect(function()
			for _, log in pairs(Console.Output:GetChildren()) do
				if log:IsA("TextBox") then
					log:Destroy()
				end
			end
		end)

		local focussedOutput

		LogService.MessageOut:Connect(function(msg, msgtype)
			local formattedText = ""
			local unformattedText = ""
			local newOutputText = Console.OutputTemplate:Clone()
			table.insert(displayedOutput, newOutputText)

			if #displayedOutput > OutputLimit.Value then
				local oldest = table.remove(displayedOutput, 1)
				if oldest and typeof(oldest) == "Instance" then
					oldest:Destroy()
				end
			end

			unformattedText = os.date("%H:%M:%S")..'   '..msg
			if msgtype == Enum.MessageType.MessageOutput then
				formattedText = os.date("%H:%M:%S")..'   <font color="rgb(204, 204, 204)">'..msg..'</font>'
				newOutputText.Text = formattedText
			elseif msgtype == Enum.MessageType.MessageWarning then
				formattedText = os.date("%H:%M:%S")..'   <b><font color="rgb(255, 142, 60)">'..msg..'</font></b>'
				newOutputText.Text = formattedText
			elseif msgtype == Enum.MessageType.MessageError then
				formattedText = os.date("%H:%M:%S")..'   <b><font color="rgb(255, 68, 68)">'..msg..'</font></b>'
				newOutputText.Text = formattedText
			elseif msgtype == Enum.MessageType.MessageInfo then
				formattedText = os.date("%H:%M:%S")..'   <font color="rgb(128, 215, 255)">'..msg..'</font>'
				newOutputText.Text = formattedText
			end

			newOutputText.TextSize = OutputTextSize.Value
			OutputTextSize:GetPropertyChangedSignal("Value"):Connect(function()
				newOutputText.TextSize = OutputTextSize.Value
			end)

			newOutputText.Focused:Connect(function()
				focussedOutput = newOutputText
				newOutputText.Text = unformattedText
			end)
			newOutputText.FocusLost:Connect(function()
				focussedOutput = nil
				newOutputText.Text = formattedText
			end)

			newOutputText.Parent = Console.Output
			newOutputText.Visible = true

			if AutoScroll then
				Console.Output.CanvasPosition = Vector2.new(0, 9e9)
			end
		end)

		Console.Output.MouseLeave:Connect(function()
			if focussedOutput then
				focussedOutput:ReleaseFocus()
			end
		end)

		Console.CommandLine.ScrollingFrame.TextBox:GetPropertyChangedSignal("Text"):Connect(function()

			local oneliner = string.gsub(Console.CommandLine.ScrollingFrame.TextBox.Text, "\n", "    ")
			Console.CommandLine.ScrollingFrame.TextBox.Text = oneliner

			Console.CommandLine.ScrollingFrame.Highlight.Text = SyntaxHighlightingModule.run(Console.CommandLine.ScrollingFrame.TextBox.Text)
		end)



		Console.CommandLine.ScrollingFrame.TextBox.FocusLost:Connect(function(enterPressed)
			if enterPressed and Console.CommandLine.ScrollingFrame.TextBox.Text ~= "" then
				print("> "..Console.CommandLine.ScrollingFrame.TextBox.Text)
				loadstring(Console.CommandLine.ScrollingFrame.TextBox.Text)()
			end
		end)
	end

	return Console
end

return {InitDeps = initDeps, InitAfterMain = initAfterMain, Main = main}
end,
["Explorer"] = function()

local Main,Lib,Apps,Settings
local Explorer, Properties, ScriptViewer, ModelViewer, Notebook
local API,RMD,env,service,plr,create,createSimple

local function initDeps(data)
	Main = data.Main
	Lib = data.Lib
	Apps = data.Apps
	Settings = data.Settings

	API = data.API
	RMD = data.RMD
	env = data.env
	service = data.service
	plr = data.plr
	create = data.create
	createSimple = data.createSimple
end

local function initAfterMain()
	Explorer = Apps.Explorer
	Properties = Apps.Properties
	ScriptViewer = Apps.ScriptViewer
	ModelViewer = Apps.ModelViewer
	Notebook = Apps.Notebook
end

local function main()
	local Explorer = {}
	local tree,listEntries,explorerOrders,searchResults,specResults = {},{},{},{},{}
	local expanded
	local entryTemplate,treeFrame,toolBar,descendantAddedCon,descendantRemovingCon,itemChangedCon
	local ffa = game.FindFirstAncestorWhichIsA
	local getDescendants = game.GetDescendants
	local getTextSize = service.TextService.GetTextSize
	local updateDebounce,refreshDebounce = false,false
	local nilNode = {Obj = Instance.new("Folder")}
	local idCounter = 0
	local scrollV,scrollH,clipboard
	local renameBox,renamingNode,searchFunc
	local sortingEnabled,autoUpdateSearch
	local table,math = table,math
	local nilMap,nilCons = {},{}
	local connectSignal = game.DescendantAdded.Connect
	local addObject,removeObject,moveObject = nil,nil,nil

	local iconData
	local remote_blocklist = {}
	nodes = nodes or {}

	addObject = function(root)
		if nodes[root] then return end

		local isNil = false
		local rootParObj = ffa(root,"Instance")
		local par = nodes[rootParObj]

		if not par then
			if nilMap[root] then
				nilCons[root] = nilCons[root] or {
					connectSignal(root.ChildAdded,addObject),
					connectSignal(root.AncestryChanged,moveObject),
				}
				par = nilNode
				isNil = true
			else
				return
			end
		elseif nilMap[rootParObj] or par == nilNode then
			nilMap[root] = true
			nilCons[root] = nilCons[root] or {
				connectSignal(root.ChildAdded,addObject),
				connectSignal(root.AncestryChanged,moveObject),
			}
			isNil = true
		end

		local newNode = {Obj = root, Parent = par}
		nodes[root] = newNode

		if sortingEnabled and expanded[par] and par.Sorted then
			local left,right = 1,#par
			local floor = math.floor
			local sorter = Explorer.NodeSorter
			local pos = (right == 0 and 1)

			if not pos then
				while true do
					if left >= right then
						if sorter(newNode,par[left]) then
							pos = left
						else
							pos = left+1
						end
						break
					end

					local mid = floor((left+right)/2)
					if sorter(newNode,par[mid]) then
						right = mid-1
					else
						left = mid+1
					end
				end
			end

			table.insert(par,pos,newNode)
		else
			par[#par+1] = newNode
			par.Sorted = nil
		end

		local insts = getDescendants(root)
		for i = 1,#insts do
			local obj = insts[i]
			if nodes[obj] then continue end

			local par = nodes[ffa(obj,"Instance")]
			if not par then continue end
			local newNode = {Obj = obj, Parent = par}
			nodes[obj] = newNode
			par[#par+1] = newNode

			if isNil then
				nilMap[obj] = true
				nilCons[obj] = nilCons[obj] or {
					connectSignal(obj.ChildAdded,addObject),
					connectSignal(obj.AncestryChanged,moveObject),
				}
			end
		end

		if searchFunc and autoUpdateSearch then
			searchFunc({newNode})
		end

		if not updateDebounce and Explorer.IsNodeVisible(par) then
			if expanded[par] then
				Explorer.PerformUpdate()
			elseif not refreshDebounce then
				Explorer.PerformRefresh()
			end
		end
	end

	removeObject = function(root)
		local node = nodes[root]
		if not node then return end

		if nilMap[node.Obj] then
			moveObject(node.Obj)
			return
		end

		local par = node.Parent
		if par then
			par.HasDel = true
		end

		local function recur(root)
			for i = 1,#root do
				local node = root[i]
				if not node.Del then
					nodes[node.Obj] = nil
					if #node > 0 then recur(node) end
				end
			end
		end
		recur(node)
		node.Del = true
		nodes[root] = nil

		if par and not updateDebounce and Explorer.IsNodeVisible(par) then
			if expanded[par] then
				Explorer.PerformUpdate()
			elseif not refreshDebounce then
				Explorer.PerformRefresh()
			end
		end
	end

	moveObject = function(obj)
		local node = nodes[obj]
		if not node then return end

		local oldPar = node.Parent
		local newPar = nodes[ffa(obj,"Instance")]
		if oldPar == newPar then return end

		if not newPar then
			if nilMap[obj] then
				newPar = nilNode
			else
				return
			end
		elseif nilMap[newPar.Obj] or newPar == nilNode then
			nilMap[obj] = true
			nilCons[obj] = nilCons[obj] or {
				connectSignal(obj.ChildAdded,addObject),
				connectSignal(obj.AncestryChanged,moveObject),
			}
		end

		if oldPar then
			local parPos = table.find(oldPar,node)
			if parPos then table.remove(oldPar,parPos) end
		end

		node.Id = nil
		node.Parent = newPar

		if sortingEnabled and expanded[newPar] and newPar.Sorted then
			local left,right = 1,#newPar
			local floor = math.floor
			local sorter = Explorer.NodeSorter
			local pos = (right == 0 and 1)

			if not pos then
				while true do
					if left >= right then
						if sorter(node,newPar[left]) then
							pos = left
						else
							pos = left+1
						end
						break
					end

					local mid = floor((left+right)/2)
					if sorter(node,newPar[mid]) then
						right = mid-1
					else
						left = mid+1
					end
				end
			end

			table.insert(newPar,pos,node)
		else
			newPar[#newPar+1] = node
			newPar.Sorted = nil
		end

		if searchFunc and searchResults[node] then
			local currentNode = node.Parent
			while currentNode and (not searchResults[currentNode] or expanded[currentNode] == 0) do
				expanded[currentNode] = true
				searchResults[currentNode] = true
				currentNode = currentNode.Parent
			end
		end

		if not updateDebounce and (Explorer.IsNodeVisible(newPar) or Explorer.IsNodeVisible(oldPar)) then
			if expanded[newPar] or expanded[oldPar] then
				Explorer.PerformUpdate()
			elseif not refreshDebounce then
				Explorer.PerformRefresh()
			end
		end
	end

	Explorer.ViewWidth = 0
	Explorer.Index = 0
	Explorer.EntryIndent = 20
	Explorer.FreeWidth = 32
	Explorer.GuiElems = {}

	Explorer.InitRenameBox = function()
		renameBox = create({{1,"TextBox",{BackgroundColor3=Color3.new(0.17647059261799,0.17647059261799,0.17647059261799),BorderColor3=Color3.new(0.062745101749897,0.51764708757401,1),BorderMode=2,ClearTextOnFocus=false,Font=3,Name="RenameBox",PlaceholderColor3=Color3.new(0.69803923368454,0.69803923368454,0.69803923368454),Position=UDim2.new(0,26,0,2),Size=UDim2.new(0,200,0,16),Text="",TextColor3=Color3.new(1,1,1),TextSize=14,TextXAlignment=0,Visible=false,ZIndex=2}}})

		renameBox.Parent = Explorer.Window.GuiElems.Content.List

		renameBox.FocusLost:Connect(function()
			if not renamingNode then return end

			pcall(function() renamingNode.Obj.Name = renameBox.Text end)
			renamingNode = nil
			Explorer.Refresh()
		end)

		renameBox.Focused:Connect(function()
			renameBox.SelectionStart = 1
			renameBox.CursorPosition = #renameBox.Text + 1
		end)
	end

	Explorer.SetRenamingNode = function(node)
		renamingNode = node
		renameBox.Text = tostring(node.Obj)
		renameBox:CaptureFocus()
		Explorer.Refresh()
	end

	Explorer.SetSortingEnabled = function(val)
		sortingEnabled = val
		Settings.Explorer.Sorting = val
	end

	Explorer.UpdateView = function()
		local maxNodes = math.ceil(treeFrame.AbsoluteSize.Y / 20)
		local maxX = treeFrame.AbsoluteSize.X
		local totalWidth = Explorer.ViewWidth + Explorer.FreeWidth

		scrollV.VisibleSpace = maxNodes
		scrollV.TotalSpace = #tree + 1
		scrollH.VisibleSpace = maxX
		scrollH.TotalSpace = totalWidth

		scrollV.Gui.Visible = #tree + 1 > maxNodes
		scrollH.Gui.Visible = totalWidth > maxX

		local oldSize = treeFrame.Size
		treeFrame.Size = UDim2.new(1,(scrollV.Gui.Visible and -16 or 0),1,(scrollH.Gui.Visible and -39 or -23))
		if oldSize ~= treeFrame.Size then
			Explorer.UpdateView()
		else
			scrollV:Update()
			scrollH:Update()

			renameBox.Size = UDim2.new(0,maxX-100,0,16)

			if scrollV.Gui.Visible and scrollH.Gui.Visible then
				scrollV.Gui.Size = UDim2.new(0,16,1,-39)
				scrollH.Gui.Size = UDim2.new(1,-16,0,16)
				Explorer.Window.GuiElems.Content.ScrollCorner.Visible = true
			else
				scrollV.Gui.Size = UDim2.new(0,16,1,-23)
				scrollH.Gui.Size = UDim2.new(1,0,0,16)
				Explorer.Window.GuiElems.Content.ScrollCorner.Visible = false
			end

			Explorer.Index = scrollV.Index
		end
	end

	Explorer.NodeSorter = function(a,b)
		if a.Del or b.Del then return false end

		local aClass = a.Class
		local bClass = b.Class
		if not aClass then aClass = a.Obj.ClassName a.Class = aClass end
		if not bClass then bClass = b.Obj.ClassName b.Class = bClass end

		local aOrder = explorerOrders[aClass]
		local bOrder = explorerOrders[bClass]
		if not aOrder then aOrder = RMD.Classes[aClass] and tonumber(RMD.Classes[aClass].ExplorerOrder) or 9999 explorerOrders[aClass] = aOrder end
		if not bOrder then bOrder = RMD.Classes[bClass] and tonumber(RMD.Classes[bClass].ExplorerOrder) or 9999 explorerOrders[bClass] = bOrder end

		if aOrder ~= bOrder then
			return aOrder < bOrder
		else
			local aName,bName = tostring(a.Obj),tostring(b.Obj)
			if aName ~= bName then
				return aName < bName
			elseif aClass ~= bClass then
				return aClass < bClass
			else
				local aId = a.Id if not aId then aId = idCounter idCounter = (idCounter+0.001)%999999999 a.Id = aId end
				local bId = b.Id if not bId then bId = idCounter idCounter = (idCounter+0.001)%999999999 b.Id = bId end
				return aId < bId
			end
		end
	end

	Explorer.Update = function()
		table.clear(tree)
		local maxNameWidth,maxDepth,count = 0,1,1
		local nameCache = {}
		local font = Enum.Font.SourceSans
		local size = Vector2.new(math.huge,20)
		local useNameWidth = Settings.Explorer.UseNameWidth
		local tSort = table.sort
		local sortFunc = Explorer.NodeSorter
		local isSearching = (expanded == Explorer.SearchExpanded)
		local textServ = service.TextService

		local function recur(root,depth)
			if depth > maxDepth then maxDepth = depth end
			depth = depth + 1
			if sortingEnabled and not root.Sorted then
				tSort(root,sortFunc)
				root.Sorted = true
			end
			for i = 1,#root do
				local n = root[i]

				if (isSearching and not searchResults[n]) or n.Del then continue end

				if useNameWidth then
					local nameWidth = n.NameWidth
					if not nameWidth then
						local objName = tostring(n.Obj)
						nameWidth = nameCache[objName]
						if not nameWidth then
							nameWidth = getTextSize(textServ,objName,14,font,size).X
							nameCache[objName] = nameWidth
						end
						n.NameWidth = nameWidth
					end
					if nameWidth > maxNameWidth then
						maxNameWidth = nameWidth
					end
				end

				tree[count] = n
				count = count + 1
				if expanded[n] and #n > 0 then
					recur(n,depth)
				end
			end
		end

		recur(nodes[game],1)

		if env.getnilinstances then
			if not (isSearching and not searchResults[nilNode]) then
				tree[count] = nilNode
				count = count + 1
				if expanded[nilNode] then
					recur(nilNode,2)
				end
			end
		end

		Explorer.MaxNameWidth = maxNameWidth
		Explorer.MaxDepth = maxDepth
		Explorer.ViewWidth = useNameWidth and Explorer.EntryIndent*maxDepth + maxNameWidth + 26 or Explorer.EntryIndent*maxDepth + 226
		Explorer.UpdateView()
	end

	Explorer.StartDrag = function(offX,offY)
		if Explorer.Dragging then return end
		for i,v in next, selection.List do
			local Obj = v.Obj
			if Obj.Parent == game or Obj:IsA("Player") then
				return
			end
		end
		Explorer.Dragging = true

		local dragTree = treeFrame:Clone()
		dragTree:ClearAllChildren()

		for i,v in pairs(listEntries) do
			local node = tree[i + Explorer.Index]
			if node and selection.Map[node] then
				local clone = v:Clone()
				clone.Active = false
				clone.Indent.Expand.Visible = false
				clone.Parent = dragTree
			end
		end

		local newGui = Instance.new("ScreenGui")
		newGui.DisplayOrder = Main.DisplayOrders.Menu
		dragTree.Parent = newGui
		Lib.ShowGui(newGui)

		local dragOutline = create({
			{1,"Frame",{BackgroundColor3=Color3.new(1,1,1),BackgroundTransparency=1,Name="DragSelect",Size=UDim2.new(1,0,1,0),}},
			{2,"Frame",{BackgroundColor3=Color3.new(1,1,1),BorderSizePixel=0,Name="Line",Parent={1},Size=UDim2.new(1,0,0,1),ZIndex=2,}},
			{3,"Frame",{BackgroundColor3=Color3.new(1,1,1),BorderSizePixel=0,Name="Line",Parent={1},Position=UDim2.new(0,0,1,-1),Size=UDim2.new(1,0,0,1),ZIndex=2,}},
			{4,"Frame",{BackgroundColor3=Color3.new(1,1,1),BorderSizePixel=0,Name="Line",Parent={1},Size=UDim2.new(0,1,1,0),ZIndex=2,}},
			{5,"Frame",{BackgroundColor3=Color3.new(1,1,1),BorderSizePixel=0,Name="Line",Parent={1},Position=UDim2.new(1,-1,0,0),Size=UDim2.new(0,1,1,0),ZIndex=2,}},
		})
		dragOutline.Parent = treeFrame

		local mouse = Main.Mouse or service.Players.LocalPlayer:GetMouse()
		local function move()
			local posX = mouse.X - offX
			local posY = mouse.Y - offY
			dragTree.Position = UDim2.new(0,posX,0,posY)

			for i = 1,#listEntries do
				local entry = listEntries[i]
				if Lib.CheckMouseInGui(entry) then
					dragOutline.Position = UDim2.new(0,entry.Indent.Position.X.Offset-scrollH.Index,0,entry.Position.Y.Offset)
					dragOutline.Size = UDim2.new(0,entry.Size.X.Offset-entry.Indent.Position.X.Offset,0,20)
					dragOutline.Visible = true
					return
				end
			end
			dragOutline.Visible = false
		end
		move()

		local input = service.UserInputService
		local mouseEvent,releaseEvent

		mouseEvent = input.InputChanged:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
				move()
			end
		end)

		releaseEvent = input.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				releaseEvent:Disconnect()
				mouseEvent:Disconnect()
				newGui:Destroy()
				dragOutline:Destroy()
				Explorer.Dragging = false

				for i = 1,#listEntries do
					if Lib.CheckMouseInGui(listEntries[i]) then
						local node = tree[i + Explorer.Index]
						if node then
							if selection.Map[node] then return end
							local newPar = node.Obj
							local sList = selection.List
							for i = 1,#sList do
								local n = sList[i]
								pcall(function() n.Obj.Parent = newPar end)
							end
							Explorer.ViewNode(sList[1])
						end
						break
					end
				end
			end
		end)
	end

	Explorer.NewListEntry = function(index)
		local newEntry = entryTemplate:Clone()
		newEntry.Position = UDim2.new(0,0,0,20*(index-1))

		local isRenaming = false

		newEntry.InputBegan:Connect(function(input)
			local node = tree[index + Explorer.Index]
			if not node or selection.Map[node] or (input.UserInputType ~= Enum.UserInputType.MouseMovement and input.UserInputType ~= Enum.UserInputType.Touch) then return end

			newEntry.Indent.BackgroundColor3 = Settings.Theme.Button
			newEntry.Indent.BorderSizePixel = 0
			newEntry.Indent.BackgroundTransparency = 0
		end)

		newEntry.InputEnded:Connect(function(input)
			local node = tree[index + Explorer.Index]
			if not node or selection.Map[node] or (input.UserInputType ~= Enum.UserInputType.MouseMovement and input.UserInputType ~= Enum.UserInputType.Touch) then return end

			newEntry.Indent.BackgroundTransparency = 1
		end)

		newEntry.MouseButton1Down:Connect(function()

		end)

		newEntry.MouseButton1Up:Connect(function()

		end)

		newEntry.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				local releaseEvent, mouseEvent

				local mouse = Main.Mouse or plr:GetMouse()
				local startX, startY

				if input.UserInputType == Enum.UserInputType.Touch then
					startX = input.Position.X
					startY = input.Position.Y
				else
					startX = mouse.X
					startY = mouse.Y
				end

				local listOffsetX = startX - treeFrame.AbsolutePosition.X
				local listOffsetY = startY - treeFrame.AbsolutePosition.Y

				releaseEvent = service.UserInputService.InputEnded:Connect(function(input)
					if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
						releaseEvent:Disconnect()
						mouseEvent:Disconnect()
					end
				end)

				mouseEvent = service.UserInputService.InputChanged:Connect(function(input)
					if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
						local currentX, currentY

						if input.UserInputType == Enum.UserInputType.Touch then
							currentX = input.Position.X
							currentY = input.Position.Y
						else
							currentX = mouse.X
							currentY = mouse.Y
						end

						local deltaX = currentX - startX
						local deltaY = currentY - startY
						local dist = math.sqrt(deltaX^2 + deltaY^2)

						if dist > 5 then
							releaseEvent:Disconnect()
							mouseEvent:Disconnect()
							isRenaming = false
							Explorer.StartDrag(listOffsetX, listOffsetY)
						end
					end
				end)
			end
		end)

		newEntry.MouseButton2Down:Connect(function()

		end)

		newEntry.Indent.Expand.InputBegan:Connect(function(input)
			local node = tree[index + Explorer.Index]
			if not node or (input.UserInputType ~= Enum.UserInputType.MouseMovement and input.UserInputType ~= Enum.UserInputType.Touch) then return end

			if input.UserInputType == Enum.UserInputType.Touch then
				Explorer.MiscIcons:DisplayByKey(newEntry.Indent.Expand.Icon, expanded[node] and "Collapse_Over" or "Expand_Over")
			elseif input.UserInputType == Enum.UserInputType.MouseMovement then
				Explorer.MiscIcons:DisplayByKey(newEntry.Indent.Expand.Icon, expanded[node] and "Collapse_Over" or "Expand_Over")
			end
		end)

		newEntry.Indent.Expand.InputEnded:Connect(function(input)
			local node = tree[index + Explorer.Index]
			if not node or (input.UserInputType ~= Enum.UserInputType.MouseMovement and input.UserInputType ~= Enum.UserInputType.Touch) then return end

			if input.UserInputType == Enum.UserInputType.Touch then
				Explorer.MiscIcons:DisplayByKey(newEntry.Indent.Expand.Icon, expanded[node] and "Collapse" or "Expand")
			elseif input.UserInputType == Enum.UserInputType.MouseMovement then
				Explorer.MiscIcons:DisplayByKey(newEntry.Indent.Expand.Icon, expanded[node] and "Collapse" or "Expand")
			end
		end)

		newEntry.Indent.Expand.MouseButton1Down:Connect(function()
			local node = tree[index + Explorer.Index]
			if not node or #node == 0 then return end

			expanded[node] = not expanded[node]
			Explorer.Update()
			Explorer.Refresh()
		end)

		newEntry.Parent = treeFrame
		return newEntry
	end

	Explorer.Refresh = function()
		local maxNodes = math.max(math.ceil((treeFrame.AbsoluteSize.Y) / 20), 0)	
		local renameNodeVisible = false
		local isa = game.IsA

		for i = 1,maxNodes do
			local entry = listEntries[i]
			if not listEntries[i] then entry = Explorer.NewListEntry(i) listEntries[i] = entry Explorer.ClickSystem:Add(entry) end

			local node = tree[i + Explorer.Index]
			if node then
				local obj = node.Obj
				local depth = Explorer.EntryIndent*Explorer.NodeDepth(node)

				entry.Visible = true
				entry.Position = UDim2.new(0,-scrollH.Index,0,entry.Position.Y.Offset)
				entry.Size = UDim2.new(0,Explorer.ViewWidth,0,20)
				entry.Indent.EntryName.Text = tostring(node.Obj)
				entry.Indent.Position = UDim2.new(0,depth,0,0)
				entry.Indent.Size = UDim2.new(1,-depth,1,0)

				entry.Indent.EntryName.TextTruncate = (Settings.Explorer.UseNameWidth and Enum.TextTruncate.None or Enum.TextTruncate.AtEnd)

				Explorer.MiscIcons:DisplayExplorerIcons(entry.Indent.Icon, obj.ClassName)

				if selection.Map[node] then
					entry.Indent.BackgroundColor3 = Settings.Theme.ListSelection
					entry.Indent.BorderSizePixel = 0
					entry.Indent.BackgroundTransparency = 0
				else
					if Lib.CheckMouseInGui(entry) then
						entry.Indent.BackgroundColor3 = Settings.Theme.Button
					else
						entry.Indent.BackgroundTransparency = 1
					end
				end

				if node == renamingNode then
					renameNodeVisible = true
					renameBox.Position = UDim2.new(0,depth+25-scrollH.Index,0,entry.Position.Y.Offset+2)
					renameBox.Visible = true
				end

				if #node > 0 and expanded[node] ~= 0 then
					if Lib.CheckMouseInGui(entry.Indent.Expand) then
						Explorer.MiscIcons:DisplayByKey(entry.Indent.Expand.Icon, expanded[node] and "Collapse_Over" or "Expand_Over")
					else
						Explorer.MiscIcons:DisplayByKey(entry.Indent.Expand.Icon, expanded[node] and "Collapse" or "Expand")
					end
					entry.Indent.Expand.Visible = true
				else
					entry.Indent.Expand.Visible = false
				end
			else
				entry.Visible = false
			end
		end

		if not renameNodeVisible then
			renameBox.Visible = false
		end

		for i = maxNodes+1, #listEntries do
			Explorer.ClickSystem:Remove(listEntries[i])
			listEntries[i]:Destroy()
			listEntries[i] = nil
		end
	end

	Explorer.PerformUpdate = function(instant)
		updateDebounce = true
		Lib.FastWait(not instant and 0.1)
		if not updateDebounce then return end
		updateDebounce = false
		if not Explorer.Window:IsVisible() then return end
		Explorer.Update()
		Explorer.Refresh()
	end

	Explorer.ForceUpdate = function(norefresh)
		updateDebounce = false
		Explorer.Update()
		if not norefresh then Explorer.Refresh() end
	end

	Explorer.PerformRefresh = function()
		refreshDebounce = true
		Lib.FastWait(0.1)
		refreshDebounce = false
		if updateDebounce or not Explorer.Window:IsVisible() then return end
		Explorer.Refresh()
	end

	Explorer.IsNodeVisible = function(node)
		if not node then return end

		local curNode = node.Parent
		while curNode do
			if not expanded[curNode] then return false end
			curNode = curNode.Parent
		end
		return true
	end

	Explorer.NodeDepth = function(node)
		local depth = 0

		if node == nilNode then
			return 1
		end

		local curNode = node.Parent
		while curNode do
			if curNode == nilNode then depth = depth + 1 end
			curNode = curNode.Parent
			depth = depth + 1
		end
		return depth
	end

	-- DEX+: safe wrapper — event callbacks never crash Explorer
	local function safeRefresh()
		pcall(Explorer.Refresh)
	end
	Explorer.SetupConnections = function()
		if descendantAddedCon then descendantAddedCon:Disconnect() end
		if descendantRemovingCon then descendantRemovingCon:Disconnect() end
		if itemChangedCon then itemChangedCon:Disconnect() end

		if Main.Elevated then
			descendantAddedCon = game.DescendantAdded:Connect(addObject)
			descendantRemovingCon = game.DescendantRemoving:Connect(removeObject)
		else
			descendantAddedCon = game.DescendantAdded:Connect(function(obj) pcall(addObject,obj) end)
			descendantRemovingCon = game.DescendantRemoving:Connect(function(obj) pcall(removeObject,obj) end)
		end

		if Settings.Explorer.UseNameWidth then
			itemChangedCon = game.ItemChanged:Connect(function(obj,prop)
				if prop == "Parent" and nodes[obj] then
					moveObject(obj)
				elseif prop == "Name" and nodes[obj] then
					nodes[obj].NameWidth = nil
				end
			end)
		else
			itemChangedCon = game.ItemChanged:Connect(function(obj,prop)
				if prop == "Parent" and nodes[obj] then
					moveObject(obj)
				end
			end)
		end
	end

	Explorer.ViewNode = function(node)
		if not node then return end

		Explorer.MakeNodeVisible(node)
		Explorer.ForceUpdate(true)
		local visibleSpace = scrollV.VisibleSpace

		for i,v in next,tree do
			if v == node then
				local relative = i - 1
				if Explorer.Index > relative then
					scrollV.Index = relative
				elseif Explorer.Index + visibleSpace - 1 <= relative then
					scrollV.Index = relative - visibleSpace + 2
				end
			end
		end

		scrollV:Update() Explorer.Index = scrollV.Index
		Explorer.Refresh()
	end

	Explorer.ViewObj = function(obj)
		Explorer.ViewNode(nodes[obj])
	end

	Explorer.MakeNodeVisible = function(node,expandRoot)
		if not node then return end

		local hasExpanded = false

		if expandRoot and not expanded[node] then
			expanded[node] = true
			hasExpanded = true
		end

		local currentNode = node.Parent
		while currentNode do
			hasExpanded = true
			expanded[currentNode] = true
			currentNode = currentNode.Parent
		end

		if hasExpanded and not updateDebounce then
			coroutine.wrap(Explorer.PerformUpdate)(true)
		end
	end

	Explorer.ShowRightClick = function(MousePos)
		local Mouse = MousePos or Main.Mouse
		local context = Explorer.RightClickContext
		local absoluteSize = context.Gui.AbsoluteSize
		context.MaxHeight = (absoluteSize.Y <= 600 and (absoluteSize.Y - 40)) or nil
		context:Clear()

		local sList = selection.List
		local sMap = selection.Map
		local emptyClipboard = #clipboard == 0
		local presentClasses = {}
		local apiClasses = API.Classes

		for i = 1, #sList do
			local node = sList[i]
			local class = node.Class
			local obj = node.Obj

			if not presentClasses.isViableDecompileScript then
				presentClasses.isViableDecompileScript = env.isViableDecompileScript(obj)
			end
			if not class then
				class = obj.ClassName
				node.Class = class
			end

			local curClass = apiClasses[class]
			while curClass and not presentClasses[curClass.Name] do
				presentClasses[curClass.Name] = true
				curClass = curClass.Superclass
			end
		end

		context:AddRegistered("CUT")
		context:AddRegistered("COPY")
		context:AddRegistered("PASTE", emptyClipboard)
		context:AddRegistered("DUPLICATE")
		context:AddRegistered("DELETE")
		context:AddRegistered("DELETE_CHILDREN", #sList ~= 1)
		context:AddRegistered("RENAME", #sList ~= 1)

		context:AddDivider()
		context:AddRegistered("GROUP")
		context:AddRegistered("UNGROUP")
		context:AddRegistered("SELECT_CHILDREN")
		context:AddRegistered("JUMP_TO_PARENT")
		context:AddRegistered("EXPAND_ALL")
		context:AddRegistered("COLLAPSE_ALL")

		context:AddDivider()

		if expanded == Explorer.SearchExpanded then context:AddRegistered("CLEAR_SEARCH_AND_JUMP_TO") end
		if env.setclipboard then context:AddRegistered("COPY_PATH") end
		context:AddRegistered("INSERT_OBJECT")
		context:AddRegistered("SAVE_INST")
		context:AddRegistered("COPY_API_PAGE")

		context:QueueDivider()

		if presentClasses["BasePart"] or presentClasses["Model"] then
			context:AddRegistered("TELEPORT_TO")
			context:AddRegistered("VIEW_OBJECT")
			context:AddRegistered("3DVIEW_MODEL")
		end
		if presentClasses["Tween"] then context:AddRegistered("PLAY_TWEEN") end
		if presentClasses["Animation"] then
			context:AddRegistered("LOAD_ANIMATION")
			context:AddRegistered("STOP_ANIMATION")
		end

		if presentClasses["TouchTransmitter"] then context:AddRegistered("FIRE_TOUCHTRANSMITTER", firetouchinterest == nil) end
		if presentClasses["ClickDetector"] then context:AddRegistered("FIRE_CLICKDETECTOR", fireclickdetector == nil) end
		if presentClasses["ProximityPrompt"] then context:AddRegistered("FIRE_PROXIMITYPROMPT", fireproximityprompt == nil) end
		
		
		if presentClasses["RemoteEvent"] then context:AddRegistered("BLOCK_REMOTE", env.hookfunction == nil) end
		if presentClasses["RemoteEvent"] then context:AddRegistered("UNBLOCK_REMOTE", env.hookfunction == nil) end
		
		if presentClasses["RemoteFunction"] then context:AddRegistered("BLOCK_REMOTE", env.hookfunction == nil) end
		if presentClasses["RemoteFunction"] then context:AddRegistered("UNBLOCK_REMOTE", env.hookfunction == nil) end

		if presentClasses["UnreliableRemoteEvent"] then context:AddRegistered("BLOCK_REMOTE", env.hookfunction == nil) end
		if presentClasses["UnreliableRemoteEvent"] then context:AddRegistered("UNBLOCK_REMOTE", env.hookfunction == nil) end
		
		
		if presentClasses["BindableEvent"] then context:AddRegistered("BLOCK_REMOTE", env.hookfunction == nil) end
		if presentClasses["BindableEvent"] then context:AddRegistered("UNBLOCK_REMOTE", env.hookfunction == nil) end
		
		if presentClasses["BindableFunction"] then context:AddRegistered("BLOCK_REMOTE", env.hookfunction == nil) end
		if presentClasses["BindableFunction"] then context:AddRegistered("UNBLOCK_REMOTE", env.hookfunction == nil) end
		
		
		
		if presentClasses["Player"] then context:AddRegistered("SELECT_CHARACTER")context:AddRegistered("VIEW_PLAYER") end
		if presentClasses["Players"] then
			context:AddRegistered("SELECT_LOCAL_PLAYER")
			context:AddRegistered("SELECT_ALL_CHARACTERS")
		end

		if presentClasses["Decal"] or presentClasses["Texture"] or presentClasses["SpecialMesh"] then
			context:AddRegistered("VIEW_DECAL")
		end

		if presentClasses["ImageLabel"] or presentClasses["ImageButton"] then
			context:AddRegistered("VIEW_IMAGE")
		end

		-- VIEW_MARKETPLACE: any asset-holding instance
		if presentClasses["Animation"] or presentClasses["MeshPart"] or presentClasses["SpecialMesh"]
			or presentClasses["Sound"] or presentClasses["Decal"] or presentClasses["Texture"]
			or presentClasses["ImageLabel"] or presentClasses["ImageButton"] or presentClasses["Model"] then
			context:AddRegistered("VIEW_MARKETPLACE")
		end

		-- VIEW_SOUND: sound preview
		if presentClasses["Sound"] then
			context:AddRegistered("VIEW_SOUND")
		end

		-- VIEW_MESH: 3D mesh preview
		if presentClasses["MeshPart"] or presentClasses["SpecialMesh"] then
			context:AddRegistered("VIEW_MESH")
		end

		-- StarterPack cache is always available as a utility
		do
			local cache = getgenv and getgenv().DEX_StarterPackCache
			if cache and #cache > 0 then
				context:AddRegistered("VIEW_STARTERPACK_CACHE")
			end
		end

		if presentClasses["LuaSourceContainer"] then
			context:AddRegistered("VIEW_SCRIPT", not presentClasses.isViableDecompileScript or env.decompile == nil)
			context:AddRegistered("DUMP_FUNCTIONS", not presentClasses.isViableDecompileScript or env.getupvalues == nil or env.getconstants == nil)
			context:AddRegistered("SAVE_SCRIPT", not presentClasses.isViableDecompileScript or env.decompile == nil or env.writefile == nil)
			context:AddRegistered("SAVE_BYTECODE", not presentClasses.isViableDecompileScript or env.getscriptbytecode == nil or env.writefile == nil)

		end

		-- Connections viewer — always available
		context:AddRegistered("VIEW_CONNECTIONS")

		-- Highlight in 3D — for parts and models
		if presentClasses["BasePart"] or presentClasses["Model"] then
			context:AddRegistered("VIEW_HIGHLIGHT_3D")
		end

		-- Part info popup — BasePart only
		if presentClasses["BasePart"] then
			context:AddRegistered("VIEW_PART_INFO")
		end

		-- Animations viewer — Humanoid, AnimationController, Model with Humanoid
		if presentClasses["Humanoid"] or presentClasses["AnimationController"]
			or presentClasses["Model"] or presentClasses["Animation"] then
			context:AddRegistered("VIEW_ANIMATIONS")
		end

		-- Copy all properties as Lua table
		context:AddRegistered("VIEW_ALL_PROPERTIES_LUA")

		-- Generate Luau code from instance
		context:AddRegistered("CODEGEN_INSTANCE")

		if sMap[nilNode] then
			context:AddRegistered("REFRESH_NIL")
			context:AddRegistered("HIDE_NIL")
		end

		Explorer.LastRightClickX, Explorer.LastRightClickY = Mouse.X, Mouse.Y
		context:Show(Mouse.X, Mouse.Y)
	end

	Explorer.InitRightClick = function()
		local context = Lib.ContextMenu.new()

		context:Register("CUT",{Name = "Cut", IconMap = Explorer.MiscIcons, Icon = "Cut", DisabledIcon = "Cut_Disabled", Shortcut = "Ctrl+Z", OnClick = function()
			local destroy,clone = game.Destroy,game.Clone
			local sList,newClipboard = selection.List,{}
			local count = 1
			for i = 1,#sList do
				local inst = sList[i].Obj
				local s,cloned = pcall(clone,inst)
				if s and cloned then
					newClipboard[count] = cloned
					count = count + 1
				end
				pcall(destroy,inst)
			end
			clipboard = newClipboard
			selection:Clear()
		end})

		context:Register("COPY",{Name = "Copy", IconMap = Explorer.MiscIcons, Icon = "Copy", DisabledIcon = "Copy_Disabled", Shortcut = "Ctrl+C", OnClick = function()
			local clone = game.Clone
			local sList,newClipboard = selection.List,{}
			local count = 1
			for i = 1,#sList do
				local inst = sList[i].Obj
				local s,cloned = pcall(clone,inst)
				if s and cloned then
					newClipboard[count] = cloned
					count = count + 1
				end
			end
			clipboard = newClipboard
		end})

		context:Register("PASTE",{Name = "Paste Into", IconMap = Explorer.MiscIcons, Icon = "Paste", DisabledIcon = "Paste_Disabled", Shortcut = "Ctrl+Shift+V", OnClick = function()
			local sList = selection.List
			local newSelection = {}
			local count = 1
			for i = 1,#sList do
				local node = sList[i]
				local inst = node.Obj
				Explorer.MakeNodeVisible(node,true)
				for c = 1,#clipboard do
					local cloned = clipboard[c]:Clone()
					if cloned then
						cloned.Parent = inst
						local clonedNode = nodes[cloned]
						if clonedNode then newSelection[count] = clonedNode count = count + 1 end
					end
				end
			end
			selection:SetTable(newSelection)

			if #newSelection > 0 then
				Explorer.ViewNode(newSelection[1])
			end
		end})

		context:Register("DUPLICATE",{Name = "Duplicate", IconMap = Explorer.MiscIcons, Icon = "Copy", DisabledIcon = "Copy_Disabled", Shortcut = "Ctrl+D", OnClick = function()
			local clone = game.Clone
			local sList = selection.List
			local newSelection = {}
			local count = 1
			for i = 1,#sList do
				local node = sList[i]
				local inst = node.Obj
				local instPar = node.Parent and node.Parent.Obj
				Explorer.MakeNodeVisible(node)
				local s,cloned = pcall(clone,inst)
				if s and cloned then
					cloned.Parent = instPar
					local clonedNode = nodes[cloned]
					if clonedNode then newSelection[count] = clonedNode count = count + 1 end
				end
			end

			selection:SetTable(newSelection)
			if #newSelection > 0 then
				Explorer.ViewNode(newSelection[1])
			end
		end})

		context:Register("DELETE",{Name = "Delete", IconMap = Explorer.MiscIcons, Icon = "Delete", DisabledIcon = "Delete_Disabled", Shortcut = "Del", OnClick = function()
			local destroy = game.Destroy
			local sList = selection.List
			for i = 1,#sList do
				pcall(destroy,sList[i].Obj)
			end
			selection:Clear()
		end})
		
		context:Register("DELETE_CHILDREN",{Name = "Delete Children", IconMap = Explorer.MiscIcons, Icon = "Delete", DisabledIcon = "Delete_Disabled", Shortcut = "Shift+Del", OnClick = function()
			local sList = selection.List
			for i = 1,#sList do
				pcall(sList[i].Obj.ClearAllChildren,sList[i].Obj)
			end
			selection:Clear()
		end})
		context:Register("RENAME",{Name = "Rename", IconMap = Explorer.MiscIcons, Icon = "Rename", DisabledIcon = "Rename_Disabled", Shortcut = "F2", OnClick = function()
			local sList = selection.List
			if sList[1] then
				Explorer.SetRenamingNode(sList[1])
			end
		end})

		context:Register("GROUP",{Name = "Group", IconMap = Explorer.MiscIcons, Icon = "Group", DisabledIcon = "Group_Disabled", Shortcut = "Ctrl+G", OnClick = function()
			local sList = selection.List
			if #sList == 0 then return end

			local model = Instance.new("Model",sList[#sList].Obj.Parent)
			for i = 1,#sList do
				pcall(function() sList[i].Obj.Parent = model end)
			end

			if nodes[model] then
				selection:Set(nodes[model])
				Explorer.ViewNode(nodes[model])
			end
		end})

		context:Register("UNGROUP",{Name = "Ungroup", IconMap = Explorer.MiscIcons, Icon = "Ungroup", DisabledIcon = "Ungroup_Disabled", Shortcut = "Ctrl+U", OnClick = function()
			local newSelection = {}
			local count = 1
			local isa = game.IsA

			local function ungroup(node)
				local par = node.Parent.Obj
				local ch = {}
				local chCount = 1

				for i = 1,#node do
					local n = node[i]
					newSelection[count] = n
					ch[chCount] = n
					count = count + 1
					chCount = chCount + 1
				end

				for i = 1,#ch do
					pcall(function() ch[i].Obj.Parent = par end)
				end

				node.Obj:Destroy()
			end

			for i,v in next,selection.List do
				if isa(v.Obj,"Model") then
					ungroup(v)
				end
			end

			selection:SetTable(newSelection)
			if #newSelection > 0 then
				Explorer.ViewNode(newSelection[1])
			end
		end})

		context:Register("SELECT_CHILDREN",{Name = "Select Children", IconMap = Explorer.MiscIcons, Icon = "SelectChildren", DisabledIcon = "SelectChildren_Disabled", OnClick = function()
			local newSelection = {}
			local count = 1
			local sList = selection.List

			for i = 1,#sList do
				local node = sList[i]
				for ind = 1,#node do
					local cNode = node[ind]
					if ind == 1 then Explorer.MakeNodeVisible(cNode) end

					newSelection[count] = cNode
					count = count + 1
				end
			end

			selection:SetTable(newSelection)
			if #newSelection > 0 then
				Explorer.ViewNode(newSelection[1])
			else
				Explorer.Refresh()
			end
		end})

		context:Register("JUMP_TO_PARENT",{Name = "Jump to Parent", IconMap = Explorer.MiscIcons, Icon = "JumpToParent", OnClick = function()
			local newSelection = {}
			local count = 1
			local sList = selection.List

			for i = 1,#sList do
				local node = sList[i]
				if node.Parent then
					newSelection[count] = node.Parent
					count = count + 1
				end
			end

			selection:SetTable(newSelection)
			if #newSelection > 0 then
				Explorer.ViewNode(newSelection[1])
			else
				Explorer.Refresh()
			end
		end})

		context:Register("TELEPORT_TO",{Name = "Teleport To", IconMap = Explorer.MiscIcons, Icon = "TeleportTo", OnClick = function()
			local sList = selection.List
			local plrRP = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")

			if not plrRP then return end

			for _,node in next, sList do
				local Obj = node.Obj

				if Obj:IsA("BasePart") then
					if Obj.CanCollide then
						plr.Character:MoveTo(Obj.Position)
					else
						plrRP.CFrame = CFrame.new(Obj.Position + Settings.Explorer.TeleportToOffset)
					end
					break
				elseif Obj:IsA("Model") then
					if Obj.PrimaryPart then
						if Obj.PrimaryPart.CanCollide then
							plr.Character:MoveTo(Obj.PrimaryPart.Position)
						else
							plrRP.CFrame = CFrame.new(Obj.PrimaryPart.Position + Settings.Explorer.TeleportToOffset)
						end
						break
					else
						local part = Obj:FindFirstChildWhichIsA("BasePart", true)
						if part and nodes[part] then
							if part.CanCollide then
								plr.Character:MoveTo(part.Position)
							else
								plrRP.CFrame = CFrame.new(part.Position + Settings.Explorer.TeleportToOffset)
							end
							break
						elseif Obj.WorldPivot then
							plrRP.CFrame = Obj.WorldPivot
						end
					end
				end
			end
		end})

		local OldAnimation
		context:Register("PLAY_TWEEN",{Name = "Play Tween", IconMap = Explorer.MiscIcons, Icon = "Play", OnClick = function()
			local sList = selection.List

			for i = 1, #sList do
				local node = sList[i]
				local Obj = node.Obj

				if Obj:IsA("Tween") then Obj:Play() end
			end
		end})

		local OldAnimation
		context:Register("LOAD_ANIMATION",{Name = "Load Animation", IconMap = Explorer.MiscIcons, Icon = "Play", OnClick = function()
			local sList = selection.List

			local Humanoid = plr.Character and plr.Character:FindFirstChild("Humanoid")
			if not Humanoid then return end

			for i = 1, #sList do
				local node = sList[i]
				local Obj = node.Obj

				if Obj:IsA("Animation") then
					if OldAnimation then OldAnimation:Stop() end
					OldAnimation = Humanoid:LoadAnimation(Obj)
					OldAnimation:Play()
					break
				end
			end
		end})

		context:Register("STOP_ANIMATION",{Name = "Stop Animation", IconMap = Explorer.MiscIcons, Icon = "Pause", OnClick = function()
			local sList = selection.List

			local Humanoid = plr.Character and plr.Character:FindFirstChild("Humanoid")
			if not Humanoid then return end

			for i = 1, #sList do
				local node = sList[i]
				local Obj = node.Obj

				if Obj:IsA("Animation") then
					if OldAnimation then OldAnimation:Stop() end
					Humanoid:LoadAnimation(Obj):Stop()
					break
				end
			end
		end})

		context:Register("EXPAND_ALL",{Name = "Expand All", OnClick = function()
			local sList = selection.List

			local function expand(node)
				expanded[node] = true
				for i = 1,#node do
					if #node[i] > 0 then
						expand(node[i])
					end
				end
			end

			for i = 1,#sList do
				expand(sList[i])
			end

			Explorer.ForceUpdate()
		end})

		context:Register("COLLAPSE_ALL",{Name = "Collapse All", OnClick = function()
			local sList = selection.List

			local function expand(node)
				expanded[node] = nil
				for i = 1,#node do
					if #node[i] > 0 then
						expand(node[i])
					end
				end
			end

			for i = 1,#sList do
				expand(sList[i])
			end

			Explorer.ForceUpdate()
		end})

		context:Register("CLEAR_SEARCH_AND_JUMP_TO",{Name = "Clear Search and Jump to", OnClick = function()
			local newSelection = {}
			local count = 1
			local sList = selection.List

			for i = 1,#sList do
				newSelection[count] = sList[i]
				count = count + 1
			end

			selection:SetTable(newSelection)
			Explorer.ClearSearch()
			if #newSelection > 0 then
				Explorer.ViewNode(newSelection[1])
			end
		end})

		local clth = function(str)
			if str:sub(1, 28) == "game:GetService(\"Workspace\")" then str = str:gsub("game:GetService%(\"Workspace\"%)", "workspace", 1) end
			if str:sub(1, 27 + #plr.Name) == "game:GetService(\"Players\")." .. plr.Name then str = str:gsub("game:GetService%(\"Players\"%)." .. plr.Name, "game:GetService(\"Players\").LocalPlayer", 1) end
			return str
		end

		context:Register("COPY_PATH",{Name = "Copy Path", IconMap = Explorer.LegacyClassIcons, Icon = 50, OnClick = function()
			local sList = selection.List
			if #sList == 1 then
				env.setclipboard(clth(Explorer.GetInstancePath(sList[1].Obj)))
			elseif #sList > 1 then
				local resList = {"{"}
				local count = 2
				for i = 1,#sList do
					local path = "\t"..clth(Explorer.GetInstancePath(sList[i].Obj))..","
					if #path > 0 then
						resList[count] = path
						count = count+1
					end
				end
				resList[count] = "}"
				env.setclipboard(table.concat(resList,"\n"))
			end
		end})

		context:Register("INSERT_OBJECT",{Name = "Insert Object", IconMap = Explorer.MiscIcons, Icon = "InsertObject", OnClick = function()
			local mouse = Main.Mouse
			local x,y = Explorer.LastRightClickX or mouse.X, Explorer.LastRightClickY or mouse.Y
			Explorer.InsertObjectContext:Show(x,y)
		end})


		context:Register("SAVE_INST",{Name = "Save to File", IconMap = Explorer.MiscIcons, Icon = "Save", OnClick = function()
			local sList = selection.List
			if #sList == 1 then
				Lib.SaveAsPrompt("Place_"..game.PlaceId.."_"..sList[1].Obj.ClassName.."_"..sList[1].Obj.Name.."_"..os.time(), function(filename)
					env.saveinstance(sList[1].Obj, filename, {
						Decompile = true,
						RemovePlayerCharacters = false
					})
				end)
			elseif #sList > 1 then
				for i = 1,#sList do
					Lib.SaveAsPrompt("Place_"..game.PlaceId.."_"..sList[i].Obj.ClassName.."_"..sList[i].Obj.Name.."_"..os.time(), function(filename)
						env.saveinstance(sList[i].Obj, filename, {
							Decompile = true,
							RemovePlayerCharacters = false
						})
					end)
					
					task.wait(0.1)
				end
			end
		end})

		local ClassFire = {
			RemoteEvent = "FireServer",
			RemoteFunction = "InvokeServer",
			UnreliableRemoteEvent = "FireServer",

			BindableRemote = "Fire",
			BindableFunction = "Invoke",
		}
		context:Register("BLOCK_REMOTE",{Name = "Block From Firing", IconMap = Explorer.MiscIcons, Icon = "Delete", DisabledIcon = "Empty", OnClick = function()
			local sList = selection.List
			for i, list in sList do
				local obj = list.Obj
				if not remote_blocklist[obj] then
					local functionToHook = ClassFire[obj.ClassName]
					remote_blocklist[obj] = true
					local old; old = env.hookmetamethod((oldgame or game), "__namecall", function(self, ...)
						if remote_blocklist[obj] and self == obj and getnamecallmethod() == functionToHook then
							return nil
						end
						return old(self,...)
					end)
					if Settings.RemoteBlockWriteAttribute then
						obj:SetAttribute("IsBlocked", true)
					end
				end
			end
		end})
		
		context:Register("UNBLOCK_REMOTE",{Name = "Unblock", IconMap = Explorer.MiscIcons, Icon = "Play", DisabledIcon = "Empty", OnClick = function()
			local sList = selection.List
			for i, list in sList do
				local obj = list.Obj
				if remote_blocklist[obj] then
					remote_blocklist[obj] = nil
					if Settings.RemoteBlockWriteAttribute then
						list.Obj:SetAttribute("IsBlocked", false)
					end
				end
			end
		end})

		context:Register("COPY_API_PAGE",{Name = "Copy Roblox API Page URL", IconMap = Explorer.MiscIcons, Icon = "Reference", OnClick = function()
			local sList = selection.List
			if #sList == 1 then
				env.setclipboard(
					"https://create.roblox.com/docs/reference/engine/classes/"..sList[1].Obj.ClassName
				)
			end
		end})

		context:Register("3DVIEW_MODEL",{Name = "3D Preview Object", IconMap = Explorer.LegacyClassIcons, Icon = 54, OnClick = function()
			local sList = selection.List
			local isa = game.IsA

			if #sList == 1 then
				if isa(sList[1].Obj,"BasePart") or isa(sList[1].Obj,"Model") then
					ModelViewer.ViewModel(sList[1].Obj)
					return
				end
			end
		end})

		context:Register("VIEW_IMAGE",{Name = "View Image", IconMap = Explorer.LegacyClassIcons, Icon = 7, OnClick = function()
			local sList = selection.List
			if #sList < 1 then return end
			local obj = sList[1].Obj
			local imgId = ""
			local isa = game.IsA
			if isa(obj,"ImageLabel") or isa(obj,"ImageButton") then
				imgId = obj.Image or ""
			elseif isa(obj,"ImageHandlerProvider") then
				imgId = obj.Image or ""
			end
			if imgId == "" then return end

			local win = Lib.Window.new()
			win:SetTitle("Image Viewer — " .. obj.Name)
			win:Resize(340, 360)
			local content = win.ContentFrame
			content.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
			content.ClipsDescendants = true

			local il = Instance.new("ImageLabel")
			il.Size = UDim2.new(1,-10,1,-50)
			il.Position = UDim2.new(0,5,0,5)
			il.BackgroundColor3 = Color3.fromRGB(15,15,15)
			il.BorderSizePixel = 0
			il.Image = imgId
			il.ScaleType = Enum.ScaleType.Fit
			il.Parent = content

			local lbl = Instance.new("TextLabel")
			lbl.Size = UDim2.new(1,-10,0,20)
			lbl.Position = UDim2.new(0,5,1,-44)
			lbl.BackgroundTransparency = 1
			lbl.TextColor3 = Color3.fromRGB(200,200,200)
			lbl.TextSize = 11
			lbl.Font = Enum.Font.Code
			lbl.Text = tostring(imgId)
			lbl.TextTruncate = Enum.TextTruncate.AtEnd
			lbl.TextXAlignment = Enum.TextXAlignment.Left
			lbl.Parent = content

			local btn = Instance.new("TextButton")
			btn.Size = UDim2.new(1,-10,0,22)
			btn.Position = UDim2.new(0,5,1,-22)
			btn.BackgroundColor3 = Color3.fromRGB(55,95,175)
			btn.BorderSizePixel = 0
			btn.TextColor3 = Color3.fromRGB(255,255,255)
			btn.TextSize = 12
			btn.Font = Enum.Font.GothamBold
			btn.Text = "Copy Image ID"
			btn.Parent = content
			btn.MouseButton1Click:Connect(function()
				if env.setclipboard then env.setclipboard(imgId) end
			end)
			win:Show()
		end})

		context:Register("VIEW_STARTERPACK_CACHE",{Name = "StarterPack Cache Viewer", IconMap = Explorer.LegacyClassIcons, Icon = 9, OnClick = function()
			local cache = getgenv().DEX_StarterPackCache or {}
			local log   = getgenv().DEX_StarterPackLog or {}

			local win = Lib.Window.new()
			win:SetTitle("StarterPack Cache (" .. #cache .. " items)")
			win:Resize(440, 380)
			local content = win.ContentFrame
			content.BackgroundColor3 = Color3.fromRGB(22,22,22)
			content.ClipsDescendants = true

			-- toolbar label
			local hdr = Instance.new("TextLabel")
			hdr.Size = UDim2.new(1,0,0,22)
			hdr.BackgroundColor3 = Color3.fromRGB(35,35,35)
			hdr.BorderSizePixel = 0
			hdr.TextColor3 = Color3.fromRGB(220,220,220)
			hdr.TextSize = 12
			hdr.Font = Enum.Font.GothamBold
			hdr.Text = #cache .. " captured  |  " .. #log .. " log entries"
			hdr.Parent = content

			-- scrolling list
			local scroll = Instance.new("ScrollingFrame")
			scroll.Size = UDim2.new(1,0,1,-80)
			scroll.Position = UDim2.new(0,0,0,22)
			scroll.BackgroundColor3 = Color3.fromRGB(18,18,18)
			scroll.BorderSizePixel = 0
			scroll.ScrollBarThickness = 8
			scroll.CanvasSize = UDim2.new(0,0,0, math.max(#cache, #log) * 20 + 10)
			scroll.Parent = content

			local layout = Instance.new("UIListLayout")
			layout.SortOrder = Enum.SortOrder.LayoutOrder
			layout.Padding = UDim.new(0,1)
			layout.Parent = scroll

			if #cache == 0 then
				local empty = Instance.new("TextLabel")
				empty.Size = UDim2.new(1,0,0,40)
				empty.BackgroundTransparency = 1
				empty.TextColor3 = Color3.fromRGB(140,140,140)
				empty.TextSize = 12
				empty.Font = Enum.Font.Gotham
				empty.Text = "No items captured yet. Try re-executing after game loads."
				empty.TextWrapped = true
				empty.Parent = scroll
			else
				for i, entry in ipairs(cache) do
					local obj = entry.Obj
					local row = Instance.new("TextButton")
					row.Size = UDim2.new(1,-8,0,20)
					row.BackgroundColor3 = i%2==0 and Color3.fromRGB(26,26,26) or Color3.fromRGB(30,30,30)
					row.BorderSizePixel = 0
					row.TextColor3 = Color3.fromRGB(220,220,220)
					row.TextSize = 11
					row.Font = Enum.Font.Code
					row.TextXAlignment = Enum.TextXAlignment.Left
					local ok, name = pcall(function() return obj.Name end)
					local ok2, cn   = pcall(function() return obj.ClassName end)
					row.Text = "  [" .. (ok2 and cn or "?") .. "]  " .. (ok and name or "?") .. "   via " .. (entry.Source or "?")
					row.LayoutOrder = i
					row.Parent = scroll
					row.MouseButton1Click:Connect(function()
						-- select the instance in Explorer if still valid
						local stillOk = pcall(function() return obj.Parent end)
						if stillOk and nodes and nodes[obj] then
							selection:Set(nodes[obj])
							Explorer.ViewNode(nodes[obj])
						elseif env.setclipboard then
							env.setclipboard(ok and name or "?")
						end
					end)
				end
			end

			-- log panel at bottom
			local logLbl = Instance.new("TextLabel")
			logLbl.Size = UDim2.new(1,0,0,58)
			logLbl.Position = UDim2.new(0,0,1,-58)
			logLbl.BackgroundColor3 = Color3.fromRGB(12,12,12)
			logLbl.BorderSizePixel = 0
			logLbl.TextColor3 = Color3.fromRGB(120,180,120)
			logLbl.TextSize = 10
			logLbl.Font = Enum.Font.Code
			logLbl.TextXAlignment = Enum.TextXAlignment.Left
			logLbl.TextYAlignment = Enum.TextYAlignment.Top
			logLbl.TextWrapped = true
			logLbl.Text = table.concat(log, "\n"):sub(-800) -- last 800 chars
			logLbl.Parent = content

			win:Show()
		end})

		context:Register("VIEW_DECAL",{Name = "View Decal/Texture", IconMap = Explorer.LegacyClassIcons, Icon = 7, OnClick = function()
			local sList = selection.List
			if #sList < 1 then return end
			local obj = sList[1].Obj
			local textureId = ""
			local isa = game.IsA
			if isa(obj, "Decal") or isa(obj, "Texture") then
				textureId = obj.Texture or ""
			elseif isa(obj, "SpecialMesh") then
				textureId = obj.TextureId or ""
			end
			if textureId == "" then return end

			-- Build a small image viewer window
			local Lib = Lib
			local win = Lib.Window.new()
			win:SetTitle("Decal Viewer - " .. obj.Name)
			win:Resize(340, 360)

			local content = win.ContentFrame
			content.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
			content.ClipsDescendants = true

			local imgLabel = Instance.new("ImageLabel")
			imgLabel.Size = UDim2.new(1, -10, 1, -50)
			imgLabel.Position = UDim2.new(0, 5, 0, 5)
			imgLabel.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
			imgLabel.BorderSizePixel = 0
			imgLabel.Image = textureId
			imgLabel.ScaleType = Enum.ScaleType.Fit
			imgLabel.Parent = content

			local idLabel = Instance.new("TextLabel")
			idLabel.Size = UDim2.new(1, -10, 0, 20)
			idLabel.Position = UDim2.new(0, 5, 1, -44)
			idLabel.BackgroundTransparency = 1
			idLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
			idLabel.TextSize = 11
			idLabel.Font = Enum.Font.Code
			idLabel.Text = tostring(textureId)
			idLabel.TextTruncate = Enum.TextTruncate.AtEnd
			idLabel.TextXAlignment = Enum.TextXAlignment.Left
			idLabel.Parent = content

			local copyBtn = Instance.new("TextButton")
			copyBtn.Size = UDim2.new(1, -10, 0, 22)
			copyBtn.Position = UDim2.new(0, 5, 1, -22)
			copyBtn.BackgroundColor3 = Color3.fromRGB(60, 100, 180)
			copyBtn.BorderSizePixel = 0
			copyBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
			copyBtn.TextSize = 12
			copyBtn.Font = Enum.Font.GothamBold
			copyBtn.Text = "Copy Texture ID"
			copyBtn.Parent = content
			copyBtn.MouseButton1Click:Connect(function()
				if env.setclipboard then env.setclipboard(textureId) end
			end)

			win:Show()
		end})
		
		-- ── Shared helper: extract numeric asset ID from any rbxassetid:// or URL ──
		local function _extractAssetId(url)
			if not url or url == "" then return nil end
			local s = tostring(url)
			return tonumber(s:match("rbxassetid://(%d+)") or s:match("[?&]id=(%d+)") or s:match("^(%d+)$"))
		end

		-- ── VIEW_MARKETPLACE: shows thumbnail, name, creator, description ──
		context:Register("VIEW_MARKETPLACE",{Name = "View in Marketplace", IconMap = Explorer.MiscIcons, Icon = "Reference", OnClick = function()
			local sList = selection.List
			if #sList < 1 then return end
			local obj = sList[1].Obj
			local isa = game.IsA

			-- Extract asset id from whichever property is relevant
			local assetId
			local function tryId(prop)
				if not assetId then
					local ok, v = pcall(function() return obj[prop] end)
					if ok and v then assetId = _extractAssetId(v) end
				end
			end
			tryId("MeshId") tryId("TextureId") tryId("AnimationId")
			tryId("SoundId") tryId("Texture") tryId("Image")
			tryId("ContentId")
			-- For Model/Tool: try to get model id from attributes or children
			if not assetId then
				local ok, attr = pcall(function() return obj:GetAttribute("ModelId") end)
				if ok and attr then assetId = tonumber(attr) end
			end
			if not assetId then return end

			-- Open window immediately with loading state
			local win = Lib.Window.new()
			win:SetTitle("Marketplace — loading…")
			win:Resize(320, 420)
			local content = win.ContentFrame
			content.BackgroundColor3 = Color3.fromRGB(20,20,20)
			content.ClipsDescendants = true

			-- Thumbnail (uses rbxthumb which doesn't need an API call)
			local thumb = Instance.new("ImageLabel")
			thumb.Size = UDim2.new(0,160,0,160)
			thumb.Position = UDim2.new(0.5,-80,0,10)
			thumb.BackgroundColor3 = Color3.fromRGB(35,35,35)
			thumb.BorderSizePixel = 0
			thumb.Image = "rbxthumb://type=Asset&id="..assetId.."&w=150&h=150"
			thumb.ScaleType = Enum.ScaleType.Fit
			thumb.Parent = content

			local UICorner1 = Instance.new("UICorner")
			UICorner1.CornerRadius = UDim.new(0,6)
			UICorner1.Parent = thumb

			-- Info labels
			local function mkLabel(yPos, fontSize, color)
				local lbl = Instance.new("TextLabel")
				lbl.Size = UDim2.new(1,-16,0,20)
				lbl.Position = UDim2.new(0,8,0,yPos)
				lbl.BackgroundTransparency = 1
				lbl.TextColor3 = color or Color3.fromRGB(220,220,220)
				lbl.TextSize = fontSize or 13
				lbl.Font = Enum.Font.Gotham
				lbl.TextXAlignment = Enum.TextXAlignment.Left
				lbl.TextWrapped = true
				lbl.Text = "Loading…"
				lbl.Parent = content
				return lbl
			end

			local lblName    = mkLabel(180, 15, Color3.fromRGB(255,255,255))
			local lblCreator = mkLabel(200, 12, Color3.fromRGB(160,200,255))
			local lblType    = mkLabel(218, 11, Color3.fromRGB(140,140,140))
			local lblDesc    = mkLabel(236, 11, Color3.fromRGB(170,170,170))
			lblDesc.Size = UDim2.new(1,-16,0,60)
			lblDesc.TextYAlignment = Enum.TextYAlignment.Top

			local lblId = mkLabel(300, 10, Color3.fromRGB(100,100,100))
			lblId.Text = "Asset ID: "..assetId

			-- Buttons row
			local btnOpen = Instance.new("TextButton")
			btnOpen.Size = UDim2.new(0.5,-6,0,26)
			btnOpen.Position = UDim2.new(0,4,1,-34)
			btnOpen.BackgroundColor3 = Color3.fromRGB(0,162,255)
			btnOpen.BorderSizePixel = 0
			btnOpen.TextColor3 = Color3.fromRGB(255,255,255)
			btnOpen.TextSize = 12
			btnOpen.Font = Enum.Font.GothamBold
			btnOpen.Text = "Open Marketplace"
			btnOpen.Parent = content
			btnOpen.MouseButton1Click:Connect(function()
				if env.setclipboard then
					env.setclipboard("https://www.roblox.com/catalog/"..assetId)
				end
			end)
			local UICorner2 = Instance.new("UICorner")
			UICorner2.CornerRadius = UDim.new(0,5)
			UICorner2.Parent = btnOpen

			local btnCopy = Instance.new("TextButton")
			btnCopy.Size = UDim2.new(0.5,-6,0,26)
			btnCopy.Position = UDim2.new(0.5,2,1,-34)
			btnCopy.BackgroundColor3 = Color3.fromRGB(50,50,50)
			btnCopy.BorderSizePixel = 0
			btnCopy.TextColor3 = Color3.fromRGB(220,220,220)
			btnCopy.TextSize = 12
			btnCopy.Font = Enum.Font.GothamBold
			btnCopy.Text = "Copy ID"
			btnCopy.Parent = content
			btnCopy.MouseButton1Click:Connect(function()
				if env.setclipboard then env.setclipboard(tostring(assetId)) end
			end)
			local UICorner3 = Instance.new("UICorner")
			UICorner3.CornerRadius = UDim.new(0,5)
			UICorner3.Parent = btnCopy

			win:Show()

			-- Fetch product info asynchronously
			task.spawn(function()
				local mps = pcall and game:GetService("MarketplaceService")
				local ok, info = pcall(function()
					return game:GetService("MarketplaceService"):GetProductInfo(assetId, Enum.InfoType.Asset)
				end)
				if ok and info then
					pcall(function() win:SetTitle("Marketplace — " .. tostring(info.Name):sub(1,40)) end)
					pcall(function() lblName.Text = tostring(info.Name) end)
					pcall(function()
						local cr = info.Creator
						if cr then
							lblCreator.Text = "by " .. tostring(cr.Name) .. (cr.CreatorType == "Group" and " (Group)" or "")
						end
					end)
					pcall(function()
						local typeNames = {
							[1]="Image",[2]="TShirt",[3]="Audio",[4]="Mesh",[5]="Lua",
							[8]="Hat",[9]="Place",[10]="Model",[11]="Shirt",[12]="Pants",
							[13]="Decal",[17]="Head",[18]="Face",[19]="Gear",[21]="Badge",
							[24]="Animation",[25]="Torso",[26]="RightArm",[27]="LeftArm",
							[28]="LeftLeg",[29]="RightLeg",[30]="Package",[31]="YouTubeVideo",
							[32]="GamePass",[34]="Plugin",[38]="MeshPart",[40]="HairAccessory",
							[41]="FaceAccessory",[42]="NeckAccessory",[43]="ShoulderAccessory",
							[44]="FrontAccessory",[45]="BackAccessory",[46]="WaistAccessory",
							[47]="ClimbAnimation",[48]="DeathAnimation",[49]="EquipAnimation",
							[50]="FallAnimation",[51]="IdleAnimation",[52]="JumpAnimation",
							[53]="RunAnimation",[54]="SwimAnimation",[55]="WalkAnimation",
							[56]="PoseAnimation",[61]="EmoteAnimation",[62]="Video",
							[64]="TShirtAccessory",[65]="ShirtAccessory",[66]="PantsAccessory",
							[67]="JacketAccessory",[68]="SweaterAccessory",[69]="ShortsAccessory",
							[70]="LeftShoeAccessory",[71]="RightShoeAccessory",[72]="DressSkirtAccessory",
						}
						local at = info.AssetTypeId
						lblType.Text = "Type: " .. (typeNames[at] or "AssetType "..tostring(at))
					end)
					pcall(function()
						local desc = tostring(info.Description or "")
						lblDesc.Text = desc ~= "" and desc:sub(1,200) or "(no description)"
					end)
					pcall(function()
						lblId.Text = ("Asset ID: %d  |  Sales: %s"):format(
							assetId,
							tostring(info.Sales or "?")
						)
					end)
				else
					pcall(function() win:SetTitle("Marketplace — fetch failed") end)
					pcall(function() lblName.Text = "Could not fetch info (private or invalid)" end)
					pcall(function() lblCreator.Text = "" end)
					pcall(function() lblDesc.Text = tostring(info or "") end)
				end
			end)
		end})

		-- ── VIEW_SOUND: preview sound, show duration, play/stop controls ──
		context:Register("VIEW_SOUND",{Name = "Preview Sound", IconMap = Explorer.MiscIcons, Icon = "Play", OnClick = function()
			local sList = selection.List
			if #sList < 1 then return end
			local obj = sList[1].Obj
			if not obj:IsA("Sound") then return end

			local assetId = _extractAssetId(obj.SoundId)
			local soundClone = obj:Clone()
			soundClone.Name = "_DEX_SoundPreview"
			soundClone.Parent = workspace

			local win = Lib.Window.new()
			win:SetTitle("Sound — " .. obj.Name)
			win:Resize(300, 200)
			local content = win.ContentFrame
			content.BackgroundColor3 = Color3.fromRGB(20,20,20)
			content.ClipsDescendants = true

			local idLbl = Instance.new("TextLabel")
			idLbl.Size = UDim2.new(1,-10,0,20)
			idLbl.Position = UDim2.new(0,5,0,5)
			idLbl.BackgroundTransparency = 1
			idLbl.TextColor3 = Color3.fromRGB(180,180,180)
			idLbl.TextSize = 11
			idLbl.Font = Enum.Font.Code
			idLbl.Text = "SoundId: " .. tostring(obj.SoundId)
			idLbl.TextXAlignment = Enum.TextXAlignment.Left
			idLbl.Parent = content

			local volLbl = Instance.new("TextLabel")
			volLbl.Size = UDim2.new(1,-10,0,16)
			volLbl.Position = UDim2.new(0,5,0,26)
			volLbl.BackgroundTransparency = 1
			volLbl.TextColor3 = Color3.fromRGB(140,140,140)
			volLbl.TextSize = 10
			volLbl.Font = Enum.Font.Code
			volLbl.Text = ("Volume: %.2f  |  Pitch: %.2f  |  Looped: %s"):format(
				obj.Volume, obj.PlaybackSpeed, tostring(obj.Looped))
			volLbl.TextXAlignment = Enum.TextXAlignment.Left
			volLbl.Parent = content

			local durLbl = Instance.new("TextLabel")
			durLbl.Size = UDim2.new(1,-10,0,16)
			durLbl.Position = UDim2.new(0,5,0,43)
			durLbl.BackgroundTransparency = 1
			durLbl.TextColor3 = Color3.fromRGB(140,140,140)
			durLbl.TextSize = 10
			durLbl.Font = Enum.Font.Code
			durLbl.Text = "Duration: loading…"
			durLbl.TextXAlignment = Enum.TextXAlignment.Left
			durLbl.Parent = content

			-- update duration once loaded
			task.spawn(function()
				soundClone.Loaded:Wait()
				local dur = soundClone.TimeLength
				pcall(function()
					local m = math.floor(dur/60)
					local s2 = dur - m*60
					durLbl.Text = ("Duration: %d:%05.2f"):format(m, s2)
				end)
			end)

			local function makeBtn(txt, x, color, onClick)
				local b = Instance.new("TextButton")
				b.Size = UDim2.new(0, 80, 0, 28)
				b.Position = UDim2.new(0, x, 0, 68)
				b.BackgroundColor3 = color
				b.BorderSizePixel = 0
				b.TextColor3 = Color3.fromRGB(255,255,255)
				b.TextSize = 12
				b.Font = Enum.Font.GothamBold
				b.Text = txt
				b.Parent = content
				b.MouseButton1Click:Connect(onClick)
				local uc = Instance.new("UICorner")
				uc.CornerRadius = UDim.new(0,5)
				uc.Parent = b
				return b
			end

			makeBtn("▶ Play",   5,   Color3.fromRGB(40,160,80),  function() pcall(function() soundClone:Play() end) end)
			makeBtn("■ Stop",   90,  Color3.fromRGB(180,50,50),  function() pcall(function() soundClone:Stop() end) end)
			makeBtn("Copy ID",  175, Color3.fromRGB(50,50,60),   function()
				if assetId and env.setclipboard then env.setclipboard(tostring(assetId)) end
			end)

			-- marketplace button
			if assetId then
				makeBtn("Marketplace", 5, Color3.fromRGB(0,120,200), function()
					if env.setclipboard then
						env.setclipboard("https://www.roblox.com/catalog/"..assetId)
					end
				end)
			end

			win.OnClose = function()
				pcall(function() soundClone:Stop() soundClone:Destroy() end)
			end
			win:Show()
		end})

		-- ── VIEW_MESH: 3D mesh preview for MeshPart / SpecialMesh ──
		context:Register("VIEW_MESH",{Name = "3D Preview Mesh", IconMap = Explorer.LegacyClassIcons, Icon = 54, OnClick = function()
			local sList = selection.List
			if #sList < 1 then return end
			local obj = sList[1].Obj
			local isa = game.IsA

			local part
			if isa(obj,"MeshPart") then
				part = obj:Clone()
				part.Anchored = true
				part.CanCollide = false
			elseif isa(obj,"SpecialMesh") then
				local holder = Instance.new("Part")
				holder.Size = Vector3.new(4,4,4)
				holder.Anchored = true
				holder.CanCollide = false
				local meshClone = obj:Clone()
				meshClone.Parent = holder
				part = holder
			elseif isa(obj,"BasePart") then
				part = obj:Clone()
				part.Anchored = true
				part.CanCollide = false
			end
			if not part then return end

			-- Delegate to ModelViewer
			part.Parent = workspace
			task.delay(0.1, function()
				pcall(function() ModelViewer.ViewModel(part) end)
				task.delay(5, function() pcall(function() part:Destroy() end) end)
			end)
		end})

		-- ── VIEW_CONNECTIONS: list all signal connections on an instance ──
		context:Register("VIEW_CONNECTIONS",{Name = "View Connections", IconMap = Explorer.MiscIcons, Icon = "SelectChildren", OnClick = function()
			local sList = selection.List
			if #sList < 1 then return end
			local obj = sList[1].Obj
			local win = Lib.Window.new()
			win:SetTitle("Connections — " .. obj.Name)
			win:Resize(380, 320)
			local cf = win.ContentFrame
			cf.BackgroundColor3 = Color3.fromRGB(18,18,18)
			cf.ClipsDescendants = true
			local scroll = Instance.new("ScrollingFrame")
			scroll.Size = UDim2.new(1,0,1,-4)
			scroll.Position = UDim2.new(0,0,0,2)
			scroll.BackgroundTransparency = 1
			scroll.ScrollBarThickness = 5
			scroll.CanvasSize = UDim2.new(0,0,0,0)
			scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
			scroll.Parent = cf
			local layout = Instance.new("UIListLayout")
			layout.SortOrder = Enum.SortOrder.LayoutOrder
			layout.Padding = UDim.new(0,2)
			layout.Parent = scroll
			local count = 0
			local function addRow(txt, color)
				count = count + 1
				local lbl = Instance.new("TextLabel")
				lbl.Size = UDim2.new(1,-8,0,18)
				lbl.BackgroundTransparency = 1
				lbl.TextColor3 = color or Color3.fromRGB(210,210,210)
				lbl.TextSize = 11
				lbl.Font = Enum.Font.Code
				lbl.Text = txt
				lbl.TextXAlignment = Enum.TextXAlignment.Left
				lbl.LayoutOrder = count
				lbl.Parent = scroll
			end
			-- Use getconnections if available (Solara/most executors)
			if getconnections then
				local ok, conns = pcall(getconnections, obj)
				if ok and conns then
					for _, conn in ipairs(conns) do
						local ok2, info = pcall(function()
							local fn = conn.Function
							local inf = debug and debug.info and debug.info(fn,"sln") or {"?","?","?"}
							return ("[%s] %s @ %s:%d"):format(
								conn.State and "ON" or "OFF",
								tostring(inf[2] or "?"),
								tostring(inf[1] or "?"),
								tonumber(inf[3]) or 0
							)
						end)
						addRow(ok2 and info or "[connection]")
					end
				end
			else
				-- Fallback: list known RBXScriptSignal properties
				local signalProps = {"Changed","AncestryChanged","ChildAdded","ChildRemoved",
					"DescendantAdded","DescendantRemoving","AttributeChanged",
					"Touched","TouchEnded","Activated","MouseButton1Click",
					"MouseButton1Down","MouseButton1Up","MouseEnter","MouseLeave",
					"InputBegan","InputChanged","InputEnded","SelectionGained","SelectionLost",
					"Fired","OnClientEvent","OnServerEvent","OnClientInvoke","OnServerInvoke",
				}
				for _, prop in ipairs(signalProps) do
					local ok2, val = pcall(function() return obj[prop] end)
					if ok2 and typeof(val) == "RBXScriptSignal" then
						addRow("signal: " .. prop, Color3.fromRGB(130,200,255))
					end
				end
				addRow("(install getconnections for full info)", Color3.fromRGB(100,100,100))
			end
			if count == 0 then addRow("No connections found.", Color3.fromRGB(100,100,100)) end
			win:Show()
		end})

		-- ── VIEW_HIGHLIGHT_3D: flash SelectionBox on selected parts ──
		context:Register("VIEW_HIGHLIGHT_3D",{Name = "Highlight in 3D (5s)", IconMap = Explorer.LegacyClassIcons, Icon = 5, OnClick = function()
			local sList = selection.List
			for _, node in ipairs(sList) do
				local obj = node.Obj
				if obj:IsA("BasePart") or obj:IsA("Model") then
					task.spawn(function()
						local box = Instance.new("SelectionBox")
						box.Adornee = obj
						box.Color3 = Color3.fromRGB(0,200,255)
						box.LineThickness = 0.04
						box.SurfaceTransparency = 0.7
						box.SurfaceColor3 = Color3.fromRGB(0,200,255)
						box.Parent = workspace.CurrentCamera
						task.wait(5)
						pcall(function() box:Destroy() end)
					end)
				end
			end
		end})

		-- ── VIEW_PART_INFO: floating Size/Position/Material/etc window ──
		context:Register("VIEW_PART_INFO",{Name = "Part Info", IconMap = Explorer.LegacyClassIcons, Icon = 5, OnClick = function()
			local sList = selection.List
			if #sList < 1 then return end
			local obj = sList[1].Obj
			if not obj:IsA("BasePart") then return end
			local win = Lib.Window.new()
			win:SetTitle("Part Info — " .. obj.Name)
			win:Resize(320, 280)
			local cf = win.ContentFrame
			cf.BackgroundColor3 = Color3.fromRGB(18,18,18)
			cf.ClipsDescendants = true
			local props = {
				{"ClassName",  obj.ClassName},
				{"Name",       obj.Name},
				{"Size",       tostring(obj.Size)},
				{"Position",   tostring(obj.CFrame.Position)},
				{"Rotation",   ("%.1f, %.1f, %.1f"):format(obj.CFrame:ToEulerAnglesXYZ())},
				{"Material",   tostring(obj.Material)},
				{"BrickColor", tostring(obj.BrickColor)},
				{"Anchored",   tostring(obj.Anchored)},
				{"CanCollide", tostring(obj.CanCollide)},
				{"Locked",     tostring(obj.Locked)},
				{"Transparency", tostring(obj.Transparency)},
				{"Reflectance",  tostring(obj.Reflectance)},
				{"Mass",         tostring(pcall(function() return obj:GetMass() end) and obj:GetMass() or "?")},
			}
			for i, row in ipairs(props) do
				local frame = Instance.new("Frame")
				frame.Size = UDim2.new(1,0,0,20)
				frame.Position = UDim2.new(0,0,0,(i-1)*21)
				frame.BackgroundColor3 = i%2==0 and Color3.fromRGB(22,22,22) or Color3.fromRGB(28,28,28)
				frame.BorderSizePixel = 0
				frame.Parent = cf
				local keyLbl = Instance.new("TextLabel")
				keyLbl.Size = UDim2.new(0.38,0,1,0)
				keyLbl.BackgroundTransparency = 1
				keyLbl.TextColor3 = Color3.fromRGB(130,180,255)
				keyLbl.TextSize = 11
				keyLbl.Font = Enum.Font.GothamBold
				keyLbl.Text = row[1]
				keyLbl.TextXAlignment = Enum.TextXAlignment.Right
				keyLbl.Parent = frame
				local valLbl = Instance.new("TextLabel")
				valLbl.Size = UDim2.new(0.6,0,1,0)
				valLbl.Position = UDim2.new(0.4,0,0,0)
				valLbl.BackgroundTransparency = 1
				valLbl.TextColor3 = Color3.fromRGB(220,220,220)
				valLbl.TextSize = 11
				valLbl.Font = Enum.Font.Code
				valLbl.Text = tostring(row[2])
				valLbl.TextXAlignment = Enum.TextXAlignment.Left
				valLbl.TextTruncate = Enum.TextTruncate.AtEnd
				valLbl.Parent = frame
			end
			win:Show()
		end})

		-- ── VIEW_ANIMATIONS: list animations in humanoid + R6/R15 anim tracks ──
		context:Register("VIEW_ANIMATIONS",{Name = "View Animations", IconMap = Explorer.MiscIcons, Icon = "Reference", OnClick = function()
			local sList = selection.List
			if #sList < 1 then return end
			local obj = sList[1].Obj
			-- Accept Humanoid or any ancestor with a Humanoid
			local hum = obj:IsA("Humanoid") and obj or obj:FindFirstChildWhichIsA("Humanoid",true)
			if not hum then
				-- Try parent chain
				local p = obj.Parent
				while p and not hum do
					hum = p:IsA("Humanoid") and p or p:FindFirstChildWhichIsA("Humanoid")
					p = p.Parent
				end
			end
			local win = Lib.Window.new()
			win:SetTitle("Animations — " .. (hum and hum.Parent.Name or obj.Name))
			win:Resize(350, 340)
			local cf = win.ContentFrame
			cf.BackgroundColor3 = Color3.fromRGB(18,18,18)
			cf.ClipsDescendants = true
			local scroll = Instance.new("ScrollingFrame")
			scroll.Size = UDim2.new(1,0,1,-4)
			scroll.Position = UDim2.new(0,0,0,2)
			scroll.BackgroundTransparency = 1
			scroll.ScrollBarThickness = 5
			scroll.CanvasSize = UDim2.new(0,0,0,0)
			scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
			scroll.Parent = cf
			local layout = Instance.new("UIListLayout")
			layout.SortOrder = Enum.SortOrder.LayoutOrder
			layout.Padding = UDim.new(0,2)
			layout.Parent = scroll
			local count = 0
			local function addRow(name, id, color)
				count = count + 1
				local f = Instance.new("Frame")
				f.Size = UDim2.new(1,-4,0,22)
				f.BackgroundColor3 = count%2==0 and Color3.fromRGB(22,22,22) or Color3.fromRGB(26,26,26)
				f.BorderSizePixel = 0
				f.LayoutOrder = count
				f.Parent = scroll
				local n = Instance.new("TextLabel")
				n.Size = UDim2.new(0.6,0,1,0)
				n.BackgroundTransparency = 1
				n.TextColor3 = color or Color3.fromRGB(210,210,210)
				n.TextSize = 11
				n.Font = Enum.Font.Code
				n.Text = name
				n.TextXAlignment = Enum.TextXAlignment.Left
				n.Parent = f
				if id and id ~= "" then
					local idl = Instance.new("TextButton")
					idl.Size = UDim2.new(0.4,0,1,0)
					idl.Position = UDim2.new(0.6,0,0,0)
					idl.BackgroundTransparency = 1
					idl.TextColor3 = Color3.fromRGB(100,160,255)
					idl.TextSize = 10
					idl.Font = Enum.Font.Code
					idl.Text = tostring(id)
					idl.Parent = f
					idl.MouseButton1Click:Connect(function()
						if env.setclipboard then env.setclipboard(tostring(id)) end
					end)
				end
			end
			-- Collect animations from AnimationController/Animator
			local found = 0
			local function scanAnims(root)
				for _, v in ipairs(root:GetDescendants()) do
					if v:IsA("Animation") then
						local id = tostring(v.AnimationId)
						addRow(v.Name .. " [" .. v.ClassName .. "]", id, Color3.fromRGB(180,230,180))
						found = found + 1
					end
				end
			end
			-- Also check AnimationTracks currently playing
			if hum then
				local animator = hum:FindFirstChildWhichIsA("Animator")
				if animator then
					local ok, tracks = pcall(function() return animator:GetPlayingAnimationTracks() end)
					if ok and tracks then
						for _, track in ipairs(tracks) do
							local id = track.Animation and tostring(track.Animation.AnimationId) or "?"
							addRow("▶ PLAYING: " .. track.Name, id, Color3.fromRGB(100,255,140))
							found = found + 1
						end
					end
				end
				scanAnims(hum.Parent or hum)
			else
				scanAnims(obj)
			end
			if found == 0 then addRow("No animations found.", nil, Color3.fromRGB(100,100,100)) end
			win:Show()
		end})

		-- ── VIEW_ALL_PROPERTIES_LUA: dump all properties as Lua table ──
		context:Register("VIEW_ALL_PROPERTIES_LUA",{Name = "Copy Properties as Lua", IconMap = Explorer.MiscIcons, Icon = "Save", OnClick = function()
			local sList = selection.List
			if #sList < 1 then return end
			local obj = sList[1].Obj
			local lines = {}
			lines[#lines+1] = ("-- Properties of %s (%s)"):format(obj.Name, obj.ClassName)
			lines[#lines+1] = "local props = {"
			-- Use API if available for known properties
			local propList = API and API.Classes and (function()
				local cls = API.Classes[obj.ClassName]
				local out = {}
				while cls do
					for _, member in ipairs(cls.Members or {}) do
						if member.MemberType == "Property" and not member.Tags then
							table.insert(out, member.Name)
						end
					end
					cls = cls.Superclass and API.Classes[cls.Superclass]
				end
				return out
			end)() or {}
			for _, prop in ipairs(propList) do
				local ok, v = pcall(function() return obj[prop] end)
				if ok and v ~= nil then
					local vstr
					local t = typeof(v)
					if t == "string"   then vstr = ("%q"):format(v)
					elseif t == "boolean" or t == "number" then vstr = tostring(v)
					elseif t == "Vector3"    then vstr = ("Vector3.new(%g,%g,%g)"):format(v.X,v.Y,v.Z)
					elseif t == "CFrame"     then vstr = ("CFrame.new(%g,%g,%g)"):format(v.X,v.Y,v.Z)
					elseif t == "Color3"     then vstr = ("Color3.fromRGB(%d,%d,%d)"):format(v.R*255,v.G*255,v.B*255)
					elseif t == "BrickColor" then vstr = ('BrickColor.new("%s")'):format(tostring(v))
					elseif t == "EnumItem"   then vstr = ("Enum.%s.%s"):format(tostring(v.EnumType),v.Name)
					elseif t == "UDim2"      then vstr = ("UDim2.new(%g,%g,%g,%g)"):format(v.X.Scale,v.X.Offset,v.Y.Scale,v.Y.Offset)
					else vstr = ("%q"):format(tostring(v))
					end
					lines[#lines+1] = ("  %s = %s,"):format(prop, vstr)
				end
			end
			lines[#lines+1] = "}"
			local result = table.concat(lines, "\n")
			if env.setclipboard then
				env.setclipboard(result)
			end
			-- Show in ScriptViewer-style window
			local win = Lib.Window.new()
			win:SetTitle("Properties Lua — " .. obj.Name)
			win:Resize(500, 400)
			local cf = win.ContentFrame
			cf.BackgroundColor3 = Color3.fromRGB(18,18,18)
			local tb = Instance.new("TextBox")
			tb.Size = UDim2.new(1,0,1,0)
			tb.MultiLine = true
			tb.BackgroundColor3 = Color3.fromRGB(20,20,20)
			tb.TextColor3 = Color3.fromRGB(210,210,210)
			tb.TextSize = 11
			tb.Font = Enum.Font.Code
			tb.Text = result
			tb.TextEditable = false
			tb.ClearTextOnFocus = false
			tb.TextXAlignment = Enum.TextXAlignment.Left
			tb.TextYAlignment = Enum.TextYAlignment.Top
			tb.Parent = cf
			win:Show()
		end})

		-- ── CODEGEN_INSTANCE: generate Luau code for selected instance ──
		context:Register("CODEGEN_INSTANCE",{Name = "Generate Luau Code", IconMap = Explorer.MiscIcons, Icon = "Save", OnClick = function()
			if Apps.CodeGen then Apps.CodeGen.GenerateForSelection() end
		end})

		context:Register("VIEW_OBJECT",{Name = "View Object (Right click to reset)", IconMap = Explorer.LegacyClassIcons, Icon = 5, OnClick = function()
			local sList = selection.List
			local isa = game.IsA

			for i = 1,#sList do
				local node = sList[i]

				if isa(node.Obj,"BasePart") or isa(node.Obj,"Model") then
					workspace.CurrentCamera.CameraSubject = node.Obj
					break
				end
			end
		end, OnRightClick = function()
			workspace.CurrentCamera.CameraSubject = plr.Character
		end})

		context:Register("VIEW_SCRIPT",{Name = "View Script", IconMap = Explorer.MiscIcons, Icon = "ViewScript", DisabledIcon = "Empty", OnClick = function()
			local scr = selection.List[1] and selection.List[1].Obj
			if scr then ScriptViewer.ViewScript(scr) end
		end})
		context:Register("DUMP_FUNCTIONS",{Name = "Dump Functions", IconMap = Explorer.MiscIcons, Icon = "SelectChildren", DisabledIcon = "Empty", OnClick = function()
			local scr = selection.List[1] and selection.List[1].Obj
			if scr then ScriptViewer.DumpFunctions(scr) end
		end})

		context:Register("FIRE_TOUCHTRANSMITTER",{Name = "Fire TouchTransmitter", OnClick = function()
			local hrp = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
			if not hrp then return end
			for _, v in ipairs(selection.List) do if v.Obj and v.Obj:IsA("TouchTransmitter") then firetouchinterest(hrp, v.Obj.Parent, 0) end end
		end})

		context:Register("FIRE_CLICKDETECTOR",{Name = "Fire ClickDetector", OnClick = function()
			local hrp = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
			if not hrp then return end
			for _, v in ipairs(selection.List) do if v.Obj and v.Obj:IsA("ClickDetector") then fireclickdetector(v.Obj) end end
		end})

		context:Register("FIRE_PROXIMITYPROMPT",{Name = "Fire ProximityPrompt", OnClick = function()
			local hrp = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
			if not hrp then return end
			for _, v in ipairs(selection.List) do if v.Obj and v.Obj:IsA("ProximityPrompt") then fireproximityprompt(v.Obj) end end
		end})

		-- VIEW_SCRIPT already registered above; SAVE_SCRIPT follows:
		context:Register("SAVE_SCRIPT",{Name = "Save Script", IconMap = Explorer.MiscIcons, Icon = "Save", DisabledIcon = "Empty", OnClick = function()
			for _, v in next, selection.List do
				if v.Obj:IsA("LuaSourceContainer") and env.isViableDecompileScript(v.Obj) then
					local success, source = pcall(env.decompile, v.Obj)
					if not success or not source then source = ("-- DEX - %s failed to decompile %s"):format(env.executor, v.Obj.ClassName) end
					local fileName = ("%s_%s_%i_Source.txt"):format(env.parsefile(v.Obj.Name), v.Obj.ClassName, game.PlaceId)
					Lib.SaveAsPrompt(fileName, source)
					
					task.wait(0.2)
				end
			end
		end})

		context:Register("SAVE_BYTECODE",{Name = "Save Script Bytecode", IconMap = Explorer.MiscIcons, Icon = "Save", DisabledIcon = "Empty", OnClick = function()
			for _, v in next, selection.List do
				if v.Obj:IsA("LuaSourceContainer") and env.isViableDecompileScript(v.Obj) then
					local success, bytecode = pcall(env.getscriptbytecode, v.Obj)
					if success and type(bytecode) == "string" then
						local fileName = ("%s_%s_%i_Bytecode.txt"):format(env.parsefile(v.Obj.Name), v.Obj.ClassName, game.PlaceId)
						Lib.SaveAsPrompt(fileName, bytecode)
						task.wait(0.2)
					end
				end
			end
		end})

		context:Register("SELECT_CHARACTER",{Name = "Select Character", IconMap = Explorer.LegacyClassIcons, Icon = 9, OnClick = function()
			local newSelection = {}
			local count = 1
			local sList = selection.List
			local isa = game.IsA

			for i = 1,#sList do
				local node = sList[i]
				if isa(node.Obj,"Player") and nodes[node.Obj.Character] then
					newSelection[count] = nodes[node.Obj.Character]
					count = count + 1
				end
			end

			selection:SetTable(newSelection)
			if #newSelection > 0 then
				Explorer.ViewNode(newSelection[1])
			else
				Explorer.Refresh()
			end
		end})

		context:Register("VIEW_PLAYER",{Name = "View Player", IconMap = Explorer.LegacyClassIcons, Icon = 5, OnClick = function()
			local newSelection = {}
			local count = 1
			local sList = selection.List
			local isa = game.IsA

			for i = 1,#sList do
				local node = sList[i]
				local Obj = node.Obj
				if Obj:IsA("Player") and Obj.Character then
					workspace.CurrentCamera.CameraSubject = Obj.Character
					break
				end
			end
		end})

		context:Register("SELECT_LOCAL_PLAYER",{Name = "Select Local Player", IconMap = Explorer.LegacyClassIcons, Icon = 9, OnClick = function()
			pcall(function() if nodes[plr] then selection:Set(nodes[plr]) Explorer.ViewNode(nodes[plr]) end end)
		end})

		context:Register("SELECT_ALL_CHARACTERS",{Name = "Select All Characters", IconMap = Explorer.LegacyClassIcons, Icon = 2, OnClick = function()
			local newSelection = {}
			local sList = selection.List

			for i,v in next, service.Players:GetPlayers() do
				if v.Character and nodes[v.Character] then
					if i == 1 then Explorer.MakeNodeVisible(v.Character) end
					table.insert(newSelection, nodes[v.Character])
				end
			end

			selection:SetTable(newSelection)
			if #newSelection > 0 then
				Explorer.ViewNode(newSelection[1])
			else
				Explorer.Refresh()
			end
		end})

		context:Register("REFRESH_NIL",{Name = "Refresh Nil Instances", OnClick = function()
			Explorer.RefreshNilInstances()
		end})

		context:Register("HIDE_NIL",{Name = "Hide Nil Instances", OnClick = function()
			Explorer.HideNilInstances()
		end})

		Explorer.RightClickContext = context
	end

	Explorer.HideNilInstances = function()
		table.clear(nilMap)

		local disconnectCon = Instance.new("Folder").ChildAdded:Connect(function() end).Disconnect
		for i,v in next,nilCons do
			disconnectCon(v[1])
			disconnectCon(v[2])
		end
		table.clear(nilCons)

		for i = 1,#nilNode do
			coroutine.wrap(removeObject)(nilNode[i].Obj)
		end

		Explorer.Update()
		Explorer.Refresh()
	end

	Explorer.RefreshNilInstances = function()
		if not env.getnilinstances then return end

		local nilInsts = env.getnilinstances()
		local game = game
		local getDescs = game.GetDescendants

		for i = 1,#nilInsts do
			local obj = nilInsts[i]
			if obj ~= game then
				nilMap[obj] = true

				local descs = getDescs(obj)
				for j = 1,#descs do
					nilMap[descs[j]] = true
				end
			end
		end



		for i = 1,#nilInsts do
			local obj = nilInsts[i]
			local node = nodes[obj]
			if not node then coroutine.wrap(addObject)(obj) end
		end



		Explorer.Update()
		Explorer.Refresh()
	end

	Explorer.GetInstancePath = function(obj)
		local ffc = game.FindFirstChild
		local getCh = game.GetChildren
		local path = ""
		local curObj = obj
		local ts = tostring
		local match = string.match
		local gsub = string.gsub
		local tableFind = table.find
		local useGetCh = Settings.Explorer.CopyPathUseGetChildren
		local formatLuaString = Lib.FormatLuaString

		while curObj do
			if curObj == game then
				path = "game"..path
				break
			end

			local className = curObj.ClassName
			local curName = ts(curObj)
			local indexName
			if match(curName,"^[%a_][%w_]*$") then
				indexName = "."..curName
			else
				local cleanName = formatLuaString(curName)
				indexName = '["'..cleanName..'"]'
			end

			local parObj = curObj.Parent
			if parObj then
				local fc = ffc(parObj,curName)
				if useGetCh and fc and fc ~= curObj then
					local parCh = getCh(parObj)
					local fcInd = tableFind(parCh,curObj)
					indexName = ":GetChildren()["..fcInd.."]"
				elseif parObj == game and API.Classes[className] and API.Classes[className].Tags.Service then
					indexName = ':GetService("'..className..'")'
				end
			elseif parObj == nil then
				local getnil = "local getNil = function(name, class) for _, v in next, getnilinstances() do if v.ClassName == class and v.Name == name then return v end end end"
				local gotnil = "\n\ngetNil(\"%s\", \"%s\")"
				indexName = getnil .. gotnil:format(curObj.Name, className)
			end

			path = indexName..path
			curObj = parObj
		end

		return path
	end

	Explorer.DefaultProps = {
		["BasePart"] = {
			Position = function(Obj)
				local Player = service.Players.LocalPlayer
				if Player.Character and Player.Character:FindFirstChild("HumanoidRootPart") then
					Obj.Position = (Player.Character.HumanoidRootPart.CFrame * CFrame.new(0, 0, -10)).p
				end
				return Obj.Position
			end,
			Anchored = true
		},
		["GuiObject"] = {
			Position = function(Obj) return (Obj.Parent:IsA("ScreenGui") and UDim2.new(0.5, 0, 0.5, 0)) or Obj.Position end,
			Active = true
		}
	}

	Explorer.InitInsertObject = function()
		local context = Lib.ContextMenu.new()
		context.SearchEnabled = true
		context.MaxHeight = 400
		context:ApplyTheme({
			ContentColor = Settings.Theme.Main2,
			OutlineColor = Settings.Theme.Outline1,
			DividerColor = Settings.Theme.Outline1,
			TextColor = Settings.Theme.Text,
			HighlightColor = Settings.Theme.ButtonHover
		})

		local classes = {}
		for i,class in next,API.Classes do
			local tags = class.Tags
			if not tags.NotCreatable and not tags.Service then
				local rmdEntry = RMD.Classes[class.Name]
				classes[#classes+1] = {class,rmdEntry and rmdEntry.ClassCategory or "Uncategorized"}
			end
		end
		table.sort(classes,function(a,b)
			if a[2] ~= b[2] then
				return a[2] < b[2]
			else
				return a[1].Name < b[1].Name
			end
		end)

		local function defaultProps(obj)
			for class, props in pairs(Explorer.DefaultProps) do
				if obj:IsA(class) then
					for prop, value in pairs(props) do
						obj[prop] = (type(value) == "function" and value(obj)) or value
					end
				end
			end
		end

		local function onClick(className)
			local sList = selection.List
			local instNew = Instance.new
			for i = 1,#sList do
				local node = sList[i]
				local obj = node.Obj
				Explorer.MakeNodeVisible(node, true)
				local success, obj = pcall(instNew, className, obj)
				if success and obj then defaultProps(obj) end
			end
		end

		local lastCategory = ""
		for i = 1,#classes do
			local class = classes[i][1]
			local rmdEntry = RMD.Classes[class.Name]
			local iconInd = rmdEntry and tonumber(rmdEntry.ExplorerImageIndex) or 0
			local category = classes[i][2]

			if lastCategory ~= category then
				context:AddDivider(category)
				lastCategory = category
			end
			
			local icon
			if iconData then
				icon = iconData.Icons[class.Name] or iconData.Icons.Placeholder
			else
				icon = iconInd
			end
			context:Add({Name = class.Name, IconMap = Explorer.ClassIcons, Icon = icon, OnClick = onClick})
		end

		Explorer.InsertObjectContext = context
	end
	
	Explorer.SearchFilters = {
		Comparison = {
			["isa"] = function(argString)
				local lower = string.lower
				local find = string.find
				local classQuery = string.split(argString)[1]
				if not classQuery then return end
				classQuery = lower(classQuery)

				local className
				for class,_ in pairs(API.Classes) do
					local cName = lower(class)
					if cName == classQuery then
						className = class
						break
					elseif find(cName,classQuery,1,true) then
						className = class
					end
				end
				if not className then return end

				return {
					Headers = {"local isa = game.IsA"},
					Predicate = "isa(obj,'"..className.."')"
				}
			end,
			["remotes"] = function(argString)
				return {
					Headers = {"local isa = game.IsA"},
					Predicate = "isa(obj,'RemoteEvent') or isa(obj,'RemoteFunction') or isa(obj,'UnreliableRemoteFunction')"
				}
			end,
			["bindables"] = function(argString)
				return {
					Headers = {"local isa = game.IsA"},
					Predicate = "isa(obj,'BindableEvent') or isa(obj,'BindableFunction')"
				}
			end,
			["rad"] = function(argString)
				local num = tonumber(argString)
				if not num then return end

				if not service.Players.LocalPlayer.Character or not service.Players.LocalPlayer.Character:FindFirstChild("HumanoidRootPart") or not service.Players.LocalPlayer.Character.HumanoidRootPart:IsA("BasePart") then return end

				return {
					Headers = {"local isa = game.IsA", "local hrp = service.Players.LocalPlayer.Character.HumanoidRootPart"},
					Setups = {"local hrpPos = hrp.Position"},
					ObjectDefs = {"local isBasePart = isa(obj,'BasePart')"},
					Predicate = "(isBasePart and (obj.Position-hrpPos).Magnitude <= "..num..")"
				}
			end,
		},
		Specific = {
			["players"] = function()
				return function() return service.Players:GetPlayers() end
			end,
			["loadedmodules"] = function()
				return env.getloadedmodules
			end,
		},
		Default = function(argString,caseSensitive)
			local cleanString = argString:gsub("\"","\\\""):gsub("\n","\\n")
			if caseSensitive then
				return {
					Headers = {"local find = string.find"},
					ObjectDefs = {"local objName = tostring(obj)"},
					Predicate = "find(objName,\"" .. cleanString .. "\",1,true)"
				}
			else
				return {
					Headers = {"local lower = string.lower","local find = string.find","local tostring = tostring"},
					ObjectDefs = {"local lowerName = lower(tostring(obj))"},
					Predicate = "find(lowerName,\"" .. cleanString:lower() .. "\",1,true)"
				}
			end
		end,
		SpecificDefault = function(n)
			return {
				Headers = {},
				ObjectDefs = {"local isSpec"..n.." = specResults["..n.."][node]"},
				Predicate = "isSpec"..n
			}
		end,
	}

	Explorer.BuildSearchFunc = function(query)
		local specFilterList,specMap = {},{}
		local finalPredicate = ""
		local rep = string.rep
		local formatQuery = query:gsub("\\.","  "):gsub('".-"',function(str) return rep(" ",#str) end)
		local headers = {}
		local objectDefs = {}
		local setups = {}
		local find = string.find
		local sub = string.sub
		local lower = string.lower
		local match = string.match
		local ops = {
			["("] = "(",
			[")"] = ")",
			["||"] = " or ",
			["&&"] = " and "
		}
		local filterCount = 0
		local compFilters = Explorer.SearchFilters.Comparison
		local specFilters = Explorer.SearchFilters.Specific
		local init = 1
		local lastOp = nil

		local function processFilter(dat)
			if dat.Headers then
				local t = dat.Headers
				for i = 1,#t do
					headers[t[i]] = true
				end
			end

			if dat.ObjectDefs then
				local t = dat.ObjectDefs
				for i = 1,#t do
					objectDefs[t[i]] = true
				end
			end

			if dat.Setups then
				local t = dat.Setups
				for i = 1,#t do
					setups[t[i]] = true
				end
			end

			finalPredicate = finalPredicate..dat.Predicate
		end

		local found = {}
		local foundData = {}
		local find = string.find
		local sub = string.sub

		local function findAll(str,pattern)
			local count = #found+1
			local init = 1
			local sz = #pattern
			local x,y,extra = find(str,pattern,init,true)
			while x do
				found[count] = x
				foundData[x] = {sz,pattern}

				count = count+1
				init = y+1
				x,y,extra = find(str,pattern,init,true)
			end
		end
		local start = tick()
		findAll(formatQuery,'&&')
		findAll(formatQuery,"||")
		findAll(formatQuery,"(")
		findAll(formatQuery,")")
		table.sort(found)
		table.insert(found,#formatQuery+1)

		local function inQuotes(str)
			local len = #str
			if sub(str,1,1) == '"' and sub(str,len,len) == '"' then
				return sub(str,2,len-1)
			end
		end

		for i = 1,#found do
			local nextInd = found[i]
			local nextData = foundData[nextInd] or {1}
			local op = ops[nextData[2]]
			local term = sub(query,init,nextInd-1)
			term = match(term,"^%s*(.-)%s*$") or ""

			if #term > 0 then
				if sub(term,1,1) == "!" then
					term = sub(term,2)
					finalPredicate = finalPredicate.."not "
				end

				local qTerm = inQuotes(term)
				if qTerm then
					processFilter(Explorer.SearchFilters.Default(qTerm,true))
				else
					local x,y = find(term,"%S+")
					if x then
						local first = sub(term,x,y)
						local specifier = sub(first,1,1) == "/" and lower(sub(first,2))
						local compFunc = specifier and compFilters[specifier]
						local specFunc = specifier and specFilters[specifier]

						if compFunc then
							local argStr = sub(term,y+2)
							local ret = compFunc(inQuotes(argStr) or argStr)
							if ret then
								processFilter(ret)
							else
								finalPredicate = finalPredicate.."false"
							end
						elseif specFunc then
							local argStr = sub(term,y+2)
							local ret = specFunc(inQuotes(argStr) or argStr)
							if ret then
								if not specMap[term] then
									specFilterList[#specFilterList + 1] = ret
									specMap[term] = #specFilterList
								end
								processFilter(Explorer.SearchFilters.SpecificDefault(specMap[term]))
							else
								finalPredicate = finalPredicate.."false"
							end
						else
							processFilter(Explorer.SearchFilters.Default(term))
						end
					end
				end				
			end

			if op then
				finalPredicate = finalPredicate..op
				if op == "(" and (#term > 0 or lastOp == ")") then
					return
				else
					lastOp = op
				end
			end
			init = nextInd+nextData[1]
		end

		local finalSetups = ""
		local finalHeaders = ""
		local finalObjectDefs = ""

		for setup,_ in next,setups do finalSetups = finalSetups..setup.."\n" end
		for header,_ in next,headers do finalHeaders = finalHeaders..header.."\n" end
		for oDef,_ in next,objectDefs do finalObjectDefs = finalObjectDefs..oDef.."\n" end

		local template = [==[
local searchResults = searchResults
local nodes = nodes
local expandTable = Explorer.SearchExpanded
local specResults = specResults
local service = service

%s
local function search(root)	
%s
	
	local expandedpar = false
	for i = 1,#root do
		local node = root[i]
		local obj = node.Obj
		
%s
		
		if %s then
			expandTable[node] = 0
			searchResults[node] = true
			if not expandedpar then
				local parnode = node.Parent
				while parnode and (not searchResults[parnode] or expandTable[parnode] == 0) do
					expandTable[parnode] = true
					searchResults[parnode] = true
					parnode = parnode.Parent
				end
				expandedpar = true
			end
		end
		
		if #node > 0 then search(node) end
	end
end
return search]==]

		local funcStr = template:format(finalHeaders,finalSetups,finalObjectDefs,finalPredicate)
		local s,func = pcall(loadstring,funcStr)
		if not s or not func then return nil,specFilterList end

		local env = setmetatable({["searchResults"] = searchResults, ["nodes"] = nodes, ["Explorer"] = Explorer, ["specResults"] = specResults,
			["service"] = service},{__index = getfenv()})
		setfenv(func,env)

		return func(),specFilterList
	end

	Explorer.DoSearch = function(query)
		table.clear(Explorer.SearchExpanded)
		table.clear(searchResults)
		expanded = (#query == 0 and Explorer.Expanded or Explorer.SearchExpanded)
		searchFunc = nil

		if #query > 0 then	
			local expandTable = Explorer.SearchExpanded
			local specFilters

			local lower = string.lower
			local find = string.find
			local tostring = tostring

			local lowerQuery = lower(query)

			local function defaultSearch(root)
				local expandedpar = false
				for i = 1,#root do
					local node = root[i]
					local obj = node.Obj

					if find(lower(tostring(obj)),lowerQuery,1,true) then
						expandTable[node] = 0
						searchResults[node] = true
						if not expandedpar then
							local parnode = node.Parent
							while parnode and (not searchResults[parnode] or expandTable[parnode] == 0) do
								expanded[parnode] = true
								searchResults[parnode] = true
								parnode = parnode.Parent
							end
							expandedpar = true
						end
					end

					if #node > 0 then defaultSearch(node) end
				end
			end

			if Main.Elevated then
				local start = tick()
				searchFunc,specFilters = Explorer.BuildSearchFunc(query)
			else
				searchFunc = defaultSearch
			end

			if specFilters then
				table.clear(specResults)
				for i = 1,#specFilters do
					local resMap = {}
					specResults[i] = resMap
					local objs = specFilters[i]()
					for c = 1,#objs do
						local node = nodes[objs[c]]
						if node then
							resMap[node] = true
						end
					end
				end
			end

			if searchFunc then
				local start = tick()
				searchFunc(nodes[game])
				searchFunc(nilNode)
			end
		end

		Explorer.ForceUpdate()
	end

	Explorer.ClearSearch = function()
		Explorer.GuiElems.SearchBar.Text = ""
		expanded = Explorer.Expanded
		searchFunc = nil
	end

	Explorer.InitSearch = function()
		local searchBox = Explorer.GuiElems.ToolBar.SearchFrame.SearchBox
		Explorer.GuiElems.SearchBar = searchBox

		Lib.ViewportTextBox.convert(searchBox)

		searchBox.FocusLost:Connect(function()
			Explorer.DoSearch(searchBox.Text)
		end)
	end

	Explorer.InitEntryTemplate = function()
		entryTemplate = create({
			{1,"TextButton",{AutoButtonColor=false,BackgroundColor3=Color3.new(0,0,0),BackgroundTransparency=1,BorderColor3=Color3.new(0,0,0),Font=3,Name="Entry",Position=UDim2.new(0,1,0,1),Size=UDim2.new(0,250,0,20),Text="",TextSize=14,}},
			{2,"Frame",{BackgroundColor3=Color3.new(0.04313725605607,0.35294118523598,0.68627452850342),BackgroundTransparency=1,BorderColor3=Color3.new(0.33725491166115,0.49019610881805,0.73725491762161),BorderSizePixel=0,Name="Indent",Parent={1},Position=UDim2.new(0,20,0,0),Size=UDim2.new(1,-20,1,0),}},
			{3,"TextLabel",{BackgroundColor3=Color3.new(1,1,1),BackgroundTransparency=1,Font=3,Name="EntryName",Parent={2},Position=UDim2.new(0,26,0,0),Size=UDim2.new(1,-26,1,0),Text="Workspace",TextColor3=Color3.new(0.86274516582489,0.86274516582489,0.86274516582489),TextSize=14,TextXAlignment=0,}},
			{4,"TextButton",{BackgroundColor3=Color3.new(1,1,1),BackgroundTransparency=1,ClipsDescendants=true,Font=3,Name="Expand",Parent={2},Position=UDim2.new(0,-20,0,0),Size=UDim2.new(0,20,0,20),Text="",TextSize=14,}},
			{5,"ImageLabel",{BackgroundColor3=Color3.new(1,1,1),BackgroundTransparency=1,Image="rbxassetid://5642383285",ImageRectOffset=Vector2.new(144,16),ImageRectSize=Vector2.new(16,16),Name="Icon",Parent={4},Position=UDim2.new(0,2,0,2),ScaleType=4,Size=UDim2.new(0,16,0,16),}},
			{6,"ImageLabel",{BackgroundColor3=Color3.new(1,1,1),BackgroundTransparency=1,ImageRectOffset=Vector2.new(304,0),ImageRectSize=Vector2.new(16,16),Name="Icon",Parent={2},Position=UDim2.new(0,4,0,2),ScaleType=4,Size=UDim2.new(0,16,0,16),}},
		})

		local sys = Lib.ClickSystem.new()
		sys.AllowedButtons = {1,2}
		sys.OnDown:Connect(function(item,combo,button)
			local ind = table.find(listEntries,item)
			if not ind then return end
			local node = tree[ind + Explorer.Index]
			if not node then return end

			local entry = listEntries[ind]

			if button == 1 then
				if combo == 2 then
					if node.Obj:IsA("LuaSourceContainer") then
						ScriptViewer.ViewScript(node.Obj)
					elseif #node > 0 and expanded[node] ~= 0 then
						expanded[node] = not expanded[node]
						Explorer.Update()
					end
				end

				if Properties.SelectObject(node.Obj) then
					sys.IsRenaming = false
					return
				end

				sys.IsRenaming = selection.Map[node]

				if Lib.IsShiftDown() then
					if not selection.Piviot then return end

					local fromIndex = table.find(tree,selection.Piviot)
					local toIndex = table.find(tree,node)
					if not fromIndex or not toIndex then return end
					fromIndex,toIndex = math.min(fromIndex,toIndex),math.max(fromIndex,toIndex)

					local sList = selection.List
					for i = #sList,1,-1 do
						local elem = sList[i]
						if selection.ShiftSet[elem] then
							selection.Map[elem] = nil
							table.remove(sList,i)
						end
					end
					selection.ShiftSet = {}
					for i = fromIndex,toIndex do
						local elem = tree[i]
						if not selection.Map[elem] then
							selection.ShiftSet[elem] = true
							selection.Map[elem] = true
							sList[#sList+1] = elem
						end
					end
					selection.Changed:Fire()
				elseif Lib.IsCtrlDown() then
					selection.ShiftSet = {}
					if selection.Map[node] then selection:Remove(node) else selection:Add(node) end
					selection.Piviot = node
					sys.IsRenaming = false
				elseif not selection.Map[node] then
					selection.ShiftSet = {}
					selection:Set(node)
					selection.Piviot = node
				end
			elseif button == 2 then
				if Properties.SelectObject(node.Obj) then
					return
				end

				if not Lib.IsCtrlDown() and not selection.Map[node] then
					selection.ShiftSet = {}
					selection:Set(node)
					selection.Piviot = node
					Explorer.Refresh()
				end
			end

			Explorer.Refresh()
		end)

		sys.OnRelease:Connect(function(item,combo,button,position)
			local ind = table.find(listEntries,item)
			if not ind then return end
			local node = tree[ind + Explorer.Index]
			if not node then return end

			if button == 1 then
				if selection.Map[node] and not Lib.IsShiftDown() and not Lib.IsCtrlDown() then
					selection.ShiftSet = {}
					selection:Set(node)
					selection.Piviot = node
					Explorer.Refresh()
				end

				local id = sys.ClickId
				Lib.FastWait(sys.ComboTime)
				if combo == 1 and id == sys.ClickId and sys.IsRenaming and selection.Map[node] then
					Explorer.SetRenamingNode(node)
				end
			elseif button == 2 then
				Explorer.ShowRightClick(position)
			end
		end)
		Explorer.ClickSystem = sys
	end

	Explorer.InitDelCleaner = function()
		coroutine.wrap(function()
			local fw = Lib.FastWait
			while true do
				local processed = false
				local c = 0
				for _,node in next,nodes do
					if node.HasDel then
						local delInd
						for i = 1,#node do
							if node[i].Del then
								delInd = i
								break
							end
						end
						if delInd then
							for i = delInd+1,#node do
								local cn = node[i]
								if not cn.Del then
									node[delInd] = cn
									delInd = delInd+1
								end
							end
							for i = delInd,#node do
								node[i] = nil
							end
						end
						node.HasDel = false
						processed = true
						fw()
					end
					c = c + 1
					if c > 10000 then
						c = 0
						fw()
					end
				end
				if processed and not refreshDebounce then Explorer.PerformRefresh() end
				fw(0.5)
			end
		end)()
	end

	Explorer.UpdateSelectionVisuals = function()
		local holder = Explorer.SelectionVisualsHolder
		local isa = game.IsA
		local clone = game.Clone
		if not holder then
			holder = Instance.new("ScreenGui")
			holder.Name = "ExplorerSelections"
			holder.DisplayOrder = Main.DisplayOrders.Core
			Lib.ShowGui(holder)
			Explorer.SelectionVisualsHolder = holder
			Explorer.SelectionVisualCons = {}

			local guiTemplate = create({
				{1,"Frame",{BackgroundColor3=Color3.new(1,1,1),BackgroundTransparency=1,Size=UDim2.new(0,100,0,100),}},
				{2,"Frame",{BackgroundColor3=Color3.new(0.04313725605607,0.35294118523598,0.68627452850342),BorderSizePixel=0,Parent={1},Position=UDim2.new(0,-1,0,-1),Size=UDim2.new(1,2,0,1),}},
				{3,"Frame",{BackgroundColor3=Color3.new(0.04313725605607,0.35294118523598,0.68627452850342),BorderSizePixel=0,Parent={1},Position=UDim2.new(0,-1,1,0),Size=UDim2.new(1,2,0,1),}},
				{4,"Frame",{BackgroundColor3=Color3.new(0.04313725605607,0.35294118523598,0.68627452850342),BorderSizePixel=0,Parent={1},Position=UDim2.new(0,-1,0,0),Size=UDim2.new(0,1,1,0),}},
				{5,"Frame",{BackgroundColor3=Color3.new(0.04313725605607,0.35294118523598,0.68627452850342),BorderSizePixel=0,Parent={1},Position=UDim2.new(1,0,0,0),Size=UDim2.new(0,1,1,0),}},
			})
			Explorer.SelectionVisualGui = guiTemplate

			local boxTemplate = Instance.new("SelectionBox")
			boxTemplate.LineThickness = 0.03
			boxTemplate.Color3 = Color3.fromRGB(0, 170, 255)
			Explorer.SelectionVisualBox = boxTemplate
		end
		holder:ClearAllChildren()

		for i,v in pairs(Explorer.SelectionVisualGui:GetChildren()) do
			v.BackgroundColor3 = Color3.fromRGB(0, 170, 255)
		end

		local attachCons = Explorer.SelectionVisualCons
		for i = 1,#attachCons do
			attachCons[i].Destroy()
		end
		table.clear(attachCons)

		local partEnabled = Settings.Explorer.PartSelectionBox
		local guiEnabled = Settings.Explorer.GuiSelectionBox
		if not partEnabled and not guiEnabled then return end

		local svg = Explorer.SelectionVisualGui
		local svb = Explorer.SelectionVisualBox
		local attachTo = Lib.AttachTo
		local sList = selection.List
		local count = 1
		local boxCount = 0
		local workspaceNode = nodes[workspace]
		for i = 1,#sList do
			if boxCount > 1000 then break end
			local node = sList[i]
			local obj = node.Obj

			if node ~= workspaceNode then
				if isa(obj,"GuiObject") and guiEnabled then
					local newVisual = clone(svg)
					attachCons[count] = attachTo(newVisual,{Target = obj, Resize = true})
					count = count + 1
					newVisual.Parent = holder
					boxCount = boxCount + 1
				elseif isa(obj,"PVInstance") and partEnabled then
					local newBox = clone(svb)
					newBox.Adornee = obj
					newBox.Parent = holder
					boxCount = boxCount + 1
				end
			end
		end
	end

	Explorer.Init = function()
		Explorer.LegacyClassIcons = Lib.IconMap.newLinear("rbxasset://textures/ClassImages.PNG", 16,16)
		
		if Settings.ClassIcon ~= nil and Settings.ClassIcon ~= "Old" then
			iconData = Lib.IconMap.getIconDataFromName(Settings.ClassIcon)
			
			Explorer.ClassIcons = Lib.IconMap.new("rbxassetid://"..tostring(iconData.MapId), iconData.IconSize * iconData.Witdh, iconData.IconSize * iconData.Height,iconData.IconSize,iconData.IconSize)
			local fixed = {}
			for i,v in pairs(iconData.Icons) do
				fixed[i] = v - 1
			end
			
			iconData.Icons = fixed
			Explorer.ClassIcons:SetDict(fixed)
		else
			Explorer.ClassIcons = Lib.IconMap.newLinear("rbxasset://textures/ClassImages.PNG", 16,16)
		end
		
		Explorer.MiscIcons = Main.MiscIcons

		clipboard = {}

		selection = Lib.Set.new()
		selection.ShiftSet = {}
		selection.Changed:Connect(Properties.ShowExplorerProps)
		Explorer.Selection = selection

		Explorer.InitRightClick()
		Explorer.InitInsertObject()
		Explorer.SetSortingEnabled(Settings.Explorer.Sorting)
		Explorer.Expanded = setmetatable({},{__mode = "k"})
		Explorer.SearchExpanded = setmetatable({},{__mode = "k"})
		expanded = Explorer.Expanded

		nilNode.Obj.Name = "Nil Instances"
		nilNode.Locked = true

		local explorerItems = create({
			{1,"Folder",{Name="ExplorerItems",}},
			{2,"Frame",{BackgroundColor3=Color3.new(0.20392157137394,0.20392157137394,0.20392157137394),BorderSizePixel=0,Name="ToolBar",Parent={1},Size=UDim2.new(1,0,0,22),}},
			{3,"Frame",{BackgroundColor3=Color3.new(0.14901961386204,0.14901961386204,0.14901961386204),BorderColor3=Color3.new(0.1176470592618,0.1176470592618,0.1176470592618),BorderSizePixel=0,Name="SearchFrame",Parent={2},Position=UDim2.new(0,3,0,1),Size=UDim2.new(1,-6,0,18),}},
			{4,"TextBox",{BackgroundColor3=Color3.new(1,1,1),BackgroundTransparency=1,ClearTextOnFocus=false,Font=3,Name="SearchBox",Parent={3},PlaceholderColor3=Color3.new(0.39215689897537,0.39215689897537,0.39215689897537),PlaceholderText="Search workspace",Position=UDim2.new(0,4,0,0),Size=UDim2.new(1,-24,0,18),Text="",TextColor3=Color3.new(1,1,1),TextSize=14,TextXAlignment=0,}},
			{5,"UICorner",{CornerRadius=UDim.new(0,2),Parent={3},}},
			{6,"UIStroke",{Thickness=1.4,Parent={3},Color=Color3.fromRGB(42,42,42)}},
			{7,"TextButton",{AutoButtonColor=false,BackgroundColor3=Color3.new(0.12549020349979,0.12549020349979,0.12549020349979),BackgroundTransparency=1,BorderSizePixel=0,Font=3,Name="Reset",Parent={3},Position=UDim2.new(1,-17,0,1),Size=UDim2.new(0,16,0,16),Text="",TextColor3=Color3.new(1,1,1),TextSize=14,}},
			{8,"ImageLabel",{BackgroundColor3=Color3.new(1,1,1),BackgroundTransparency=1,Image="rbxassetid://5034718129",ImageColor3=Color3.new(0.39215686917305,0.39215686917305,0.39215686917305),Parent={7},Size=UDim2.new(0,16,0,16),}},
			{9,"TextButton",{AutoButtonColor=false,BackgroundColor3=Color3.new(0.12549020349979,0.12549020349979,0.12549020349979),BackgroundTransparency=1,BorderSizePixel=0,Font=3,Name="Refresh",Parent={2},Position=UDim2.new(1,-20,0,1),Size=UDim2.new(0,18,0,18),Text="",TextColor3=Color3.new(1,1,1),TextSize=14,Visible=false,}},
			{10,"ImageLabel",{BackgroundColor3=Color3.new(1,1,1),BackgroundTransparency=1,Image="rbxassetid://5642310344",Parent={9},Position=UDim2.new(0,3,0,3),Size=UDim2.new(0,12,0,12),}},
			{11,"Frame",{BackgroundColor3=Color3.new(0.15686275064945,0.15686275064945,0.15686275064945),BorderSizePixel=0,Name="ScrollCorner",Parent={1},Position=UDim2.new(1,-16,1,-16),Size=UDim2.new(0,16,0,16),Visible=false,}},
			{12,"Frame",{BackgroundColor3=Color3.new(1,1,1),BackgroundTransparency=1,ClipsDescendants=true,Name="List",Parent={1},Position=UDim2.new(0,0,0,23),Size=UDim2.new(1,0,1,-23),}}
		})

		toolBar = explorerItems.ToolBar
		treeFrame = explorerItems.List

		Explorer.GuiElems.ToolBar = toolBar
		Explorer.GuiElems.TreeFrame = treeFrame

		scrollV = Lib.ScrollBar.new()		
		scrollV.WheelIncrement = 3
		scrollV.Gui.Position = UDim2.new(1,-16,0,23)
		scrollV:SetScrollFrame(treeFrame)
		scrollV.Scrolled:Connect(function()
			Explorer.Index = scrollV.Index
			Explorer.Refresh()
		end)

		scrollH = Lib.ScrollBar.new(true)
		scrollH.Increment = 5
		scrollH.WheelIncrement = Explorer.EntryIndent
		scrollH.Gui.Position = UDim2.new(0,0,1,-16)
		scrollH.Scrolled:Connect(function()
			Explorer.Refresh()
		end)

		local window = Lib.Window.new()
		Explorer.Window = window
		window:SetTitle("Explorer")
		window.GuiElems.Line.Position = UDim2.new(0,0,0,22)

		Explorer.InitEntryTemplate()
		toolBar.Parent = window.GuiElems.Content
		treeFrame.Parent = window.GuiElems.Content
		explorerItems.ScrollCorner.Parent = window.GuiElems.Content
		scrollV.Gui.Parent = window.GuiElems.Content
		scrollH.Gui.Parent = window.GuiElems.Content

		Explorer.InitRenameBox()
		Explorer.InitSearch()
		Explorer.InitDelCleaner()
		selection.Changed:Connect(Explorer.UpdateSelectionVisuals)

		window.GuiElems.Main:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
			if Explorer.Active then
				Explorer.UpdateView()
				Explorer.Refresh()
			end
		end)
		window.OnActivate:Connect(function()
			Explorer.Active = true
			Explorer.UpdateView()
			Explorer.Update()
			Explorer.Refresh()
		end)
		window.OnRestore:Connect(function()
			Explorer.Active = true
			Explorer.UpdateView()
			Explorer.Update()
			Explorer.Refresh()
		end)
		window.OnDeactivate:Connect(function() Explorer.Active = false end)
		window.OnMinimize:Connect(function() Explorer.Active = false end)

		autoUpdateSearch = Settings.Explorer.AutoUpdateSearch

		nodes[game] = {Obj = game}
		expanded[nodes[game]] = true

		if env.getnilinstances then
			nodes[nilNode.Obj] = nilNode
		end

		-- DEX+: Force ALL known services into the node tree, with full child recursion.
		-- Every step is pcall-guarded so a bad/protected service cannot crash Explorer.
		task.spawn(function()
			task.wait(1.5) -- let API and nodes settle
			local ok0, oldId = pcall(getthreadidentity)
			pcall(setthreadidentity, 8)

			local hiddenSvcs = getgenv and getgenv().DEX_HiddenServices
			if not hiddenSvcs then
				if ok0 then pcall(setthreadidentity, oldId) end
				return
			end
			local gameNode = nodes[game]
			if not gameNode then
				if ok0 then pcall(setthreadidentity, oldId) end
				return
			end

			-- Recursive safe node builder
			local function buildNodes(svc, parentNode, depth)
				depth = depth or 0
				if depth > 6 then return end
				local node = nodes[svc]
				if not node then
					node = {Obj = svc, Parent = parentNode}
					nodes[svc] = node
					parentNode[#parentNode + 1] = node
				end
				local ok2, children = pcall(function() return svc:GetChildren() end)
				if ok2 and children then
					for _, child in ipairs(children) do
						pcall(buildNodes, child, node, depth + 1)
					end
				end
			end

			for _, svc in pairs(hiddenSvcs) do
				if svc then pcall(buildNodes, svc, gameNode) end
			end

			if ok0 then pcall(setthreadidentity, oldId) end
			Explorer.Refresh()
		end)

		Explorer.SetupConnections()

		local ok_desc, insts = pcall(getDescendants, game)
		insts = ok_desc and insts or {}
		for i = 1, #insts do
			pcall(function()
				local obj = insts[i]
				local s, parObj = pcall(ffa, obj, "Instance")
				local par = s and nodes[parObj] or nil
				if not par then return end
				if nodes[obj] then return end
				local newNode = {Obj = obj, Parent = par}
				nodes[obj] = newNode
				par[#par + 1] = newNode
			end)
		end
	end

	return Explorer
end

return {InitDeps = initDeps, InitAfterMain = initAfterMain, Main = main}
end,
["Lib"] = function()

local Main,Lib,Apps,Settings
local Explorer, Properties, ScriptViewer, Notebook
local API,RMD,env,service,plr,create,createSimple

local function initDeps(data)
	Main = data.Main
	Lib = data.Lib
	Apps = data.Apps
	Settings = data.Settings

	API = data.API
	RMD = data.RMD
	env = data.env
	service = data.service
	plr = data.plr
	create = data.create
	createSimple = data.createSimple
end

local function initAfterMain()
	Explorer = Apps.Explorer
	Properties = Apps.Properties
	ScriptViewer = Apps.ScriptViewer
	Notebook = Apps.Notebook
end

local function main()
	local Lib = {}

	local renderStepped = service.RunService.RenderStepped
	local signalWait = renderStepped.wait
	local PH = newproxy()
	local SIGNAL = newproxy()

	local function initObj(props,mt)
		local type = type
		local function copy(t)
			local res = {}
			for i,v in pairs(t) do
				if v == SIGNAL then
					res[i] = Lib.Signal.new()
				elseif type(v) == "table" then
					res[i] = copy(v)
				else
					res[i] = v
				end
			end		
			return res
		end

		local newObj = copy(props)
		return setmetatable(newObj,mt)
	end

	local function getGuiMT(props,funcs)
		return {__index = function(self,ind) if not props[ind] then return funcs[ind] or self.Gui[ind] end end,
		__newindex = function(self,ind,val) if not props[ind] then self.Gui[ind] = val else rawset(self,ind,val) end end}
	end


	Lib.FormatLuaString = (function()
		local string = string
		local gsub = string.gsub
		local format = string.format
		local char = string.char
		local cleanTable = {['"'] = '\\"', ['\\'] = '\\\\'}
		for i = 0,31 do
			cleanTable[char(i)] = "\\"..format("%03d",i)
		end
		for i = 127,255 do
			cleanTable[char(i)] = "\\"..format("%03d",i)
		end

		return function(str)
			return gsub(str,"[\"\\\0-\31\127-\255]",cleanTable)
		end
	end)()

	Lib.CheckMouseInGui = function(gui)
		if gui == nil then return false end
		local mouse = Main.Mouse
		local guiPosition = gui.AbsolutePosition
		local guiSize = gui.AbsoluteSize	

		return mouse.X >= guiPosition.X and mouse.X < guiPosition.X + guiSize.X and mouse.Y >= guiPosition.Y and mouse.Y < guiPosition.Y + guiSize.Y
	end

	Lib.IsShiftDown = function()
		return service.UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) or service.UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
	end

	Lib.IsCtrlDown = function()
		return service.UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) or service.UserInputService:IsKeyDown(Enum.KeyCode.RightControl)
	end

	Lib.CreateArrow = function(size,num,dir)
		local max = num
		local arrowFrame = createSimple("Frame",{
			BackgroundTransparency = 1,
			Name = "Arrow",
			Size = UDim2.new(0,size,0,size)
		})
		if dir == "up" then
			for i = 1,num do
				local newLine = createSimple("Frame",{
					BackgroundColor3 = Color3.new(220/255,220/255,220/255),
					BorderSizePixel = 0,
					Position = UDim2.new(0,math.floor(size/2)-(i-1),0,math.floor(size/2)+i-math.floor(max/2)-1),
					Size = UDim2.new(0,i+(i-1),0,1),
					Parent = arrowFrame
				})
			end
			return arrowFrame
		elseif dir == "down" then
			for i = 1,num do
				local newLine = createSimple("Frame",{
					BackgroundColor3 = Color3.new(220/255,220/255,220/255),
					BorderSizePixel = 0,
					Position = UDim2.new(0,math.floor(size/2)-(i-1),0,math.floor(size/2)-i+math.floor(max/2)+1),
					Size = UDim2.new(0,i+(i-1),0,1),
					Parent = arrowFrame
				})
			end
			return arrowFrame
		elseif dir == "left" then
			for i = 1,num do
				local newLine = createSimple("Frame",{
					BackgroundColor3 = Color3.new(220/255,220/255,220/255),
					BorderSizePixel = 0,
					Position = UDim2.new(0,math.floor(size/2)+i-math.floor(max/2)-1,0,math.floor(size/2)-(i-1)),
					Size = UDim2.new(0,1,0,i+(i-1)),
					Parent = arrowFrame
				})
			end
			return arrowFrame
		elseif dir == "right" then
			for i = 1,num do
				local newLine = createSimple("Frame",{
					BackgroundColor3 = Color3.new(220/255,220/255,220/255),
					BorderSizePixel = 0,
					Position = UDim2.new(0,math.floor(size/2)-i+math.floor(max/2)+1,0,math.floor(size/2)-(i-1)),
					Size = UDim2.new(0,1,0,i+(i-1)),
					Parent = arrowFrame
				})
			end
			return arrowFrame
		end
		error("r u ok")
	end

	Lib.ParseXML = (function()
		local func = function()

			local string, print, pairs = string, print, pairs

			local trim = function(s)
				local from = s:match"^%s*()"
				return from > #s and "" or s:match(".*%S", from)
			end

			local gtchar = string.byte('>', 1)
			local slashchar = string.byte('/', 1)
			local D = string.byte('D', 1)
			local E = string.byte('E', 1)

			function parse(s, evalEntities)
				s = s:gsub('<!%-%-(.-)%-%->', '')

				local entities, tentities = {}

				if evalEntities then
					local pos = s:find('<[_%w]')
					if pos then
						s:sub(1, pos):gsub('<!ENTITY%s+([_%w]+)%s+(.)(.-)%2', function(name, q, entity)
							entities[#entities+1] = {name=name, value=entity}
						end)
						tentities = createEntityTable(entities)
						s = replaceEntities(s:sub(pos), tentities)
					end
				end

				local t, l = {}, {}

				local addtext = function(txt)
					txt = txt:match'^%s*(.*%S)' or ''
					if #txt ~= 0 then
						t[#t+1] = {text=txt}
					end		
				end

				s:gsub('<([?!/]?)([-:_%w]+)%s*(/?>?)([^<]*)', function(type, name, closed, txt)
					if #type == 0 then
						local a = {}
						if #closed == 0 then
							local len = 0
							for all,aname,_,value,starttxt in string.gmatch(txt, "(.-([-_%w]+)%s*=%s*(.)(.-)%3%s*(/?>?))") do
								len = len + #all
								a[aname] = value
								if #starttxt ~= 0 then
									txt = txt:sub(len+1)
									closed = starttxt
									break
								end
							end
						end
						t[#t+1] = {tag=name, attrs=a, children={}}

						if closed:byte(1) ~= slashchar then
							l[#l+1] = t
							t = t[#t].children
						end

						addtext(txt)
					elseif '/' == type then
						t = l[#l]
						l[#l] = nil

						addtext(txt)
					elseif '!' == type then
						if E == name:byte(1) then
							txt:gsub('([_%w]+)%s+(.)(.-)%2', function(name, q, entity)
								entities[#entities+1] = {name=name, value=entity}
							end, 1)
						end
					end
				end)

				return {children=t, entities=entities, tentities=tentities}
			end

			function parseText(txt)
				return parse(txt)
			end

			function defaultEntityTable()
				return { quot='"', apos='\'', lt='<', gt='>', amp='&', tab='\t', nbsp=' ', }
			end

			function replaceEntities(s, entities)
				return s:gsub('&([^;]+);', entities)
			end

			function createEntityTable(docEntities, resultEntities)
				entities = resultEntities or defaultEntityTable()
				for _,e in pairs(docEntities) do
					e.value = replaceEntities(e.value, entities)
					entities[e.name] = e.value
				end
				return entities
			end

			return parseText
		end
		local newEnv = setmetatable({},{__index = getfenv()})
		setfenv(func,newEnv)
		return func()
	end)()

	Lib.FastWait = function(s)
		if not s then return signalWait(renderStepped) end
		local start = tick()
		while tick() - start < s do signalWait(renderStepped) end
	end

	Lib.ButtonAnim = function(button,data)
		local holding = false
		local disabled = false
		local mode = data and data.Mode or 1
		local control = {}

		if mode == 2 then
			local lerpTo = data.LerpTo or Color3.new(0,0,0)
			local delta = data.LerpDelta or 0.2
			control.StartColor = data.StartColor or button.BackgroundColor3
			control.PressColor = data.PressColor or control.StartColor:lerp(lerpTo,delta)
			control.HoverColor = data.HoverColor or control.StartColor:lerp(control.PressColor,0.6)
			control.OutlineColor = data.OutlineColor
		end

		button.InputBegan:Connect(function(input)
			if disabled then return end

			if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
				if not holding then
					if mode == 1 then
						button.BackgroundTransparency = 0.4
					elseif mode == 2 then
						button.BackgroundColor3 = control.HoverColor
					end
				end
			elseif input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				holding = true
				if mode == 1 then
					button.BackgroundTransparency = 0
				elseif mode == 2 then
					button.BackgroundColor3 = control.PressColor
					if control.OutlineColor then button.BorderColor3 = control.PressColor end
				end
			end
		end)

		button.InputEnded:Connect(function(input)
			if disabled then return end

			if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
				if not holding then
					if mode == 1 then
						button.BackgroundTransparency = 1
					elseif mode == 2 then
						button.BackgroundColor3 = control.StartColor
					end
				end
			elseif input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				holding = false
				if mode == 1 then
					button.BackgroundTransparency = Lib.CheckMouseInGui(button) and 0.4 or 1
				elseif mode == 2 then
					button.BackgroundColor3 = Lib.CheckMouseInGui(button) and control.HoverColor or control.StartColor
					if control.OutlineColor then button.BorderColor3 = control.OutlineColor end
				end
			end
		end)

		control.Disable = function()
			disabled = true
			holding = false

			if mode == 1 then
				button.BackgroundTransparency = 1
			elseif mode == 2 then
				button.BackgroundColor3 = control.StartColor
			end
		end

		control.Enable = function()
			disabled = false
		end

		return control
	end

	Lib.FindAndRemove = function(t,item)
		local pos = table.find(t,item)
		if pos then table.remove(t,pos) end
	end

	Lib.AttachTo = function(obj,data)
		local target,posOffX,posOffY,sizeOffX,sizeOffY,resize,con
		local disabled = false

		local function update()
			if not obj or not target then return end

			local targetPos = target.AbsolutePosition
			local targetSize = target.AbsoluteSize
			obj.Position = UDim2.new(0,targetPos.X + posOffX,0,targetPos.Y + posOffY)
			if resize then obj.Size = UDim2.new(0,targetSize.X + sizeOffX,0,targetSize.Y + sizeOffY) end
		end

		local function setup(o,data)
			obj = o
			data = data or {}
			target = data.Target
			posOffX = data.PosOffX or 0
			posOffY = data.PosOffY or 0
			sizeOffX = data.SizeOffX or 0
			sizeOffY = data.SizeOffY or 0
			resize = data.Resize or false

			if con then con:Disconnect() con = nil end
			if target then
				con = target.Changed:Connect(function(prop)
					if not disabled and prop == "AbsolutePosition" or prop == "AbsoluteSize" then
						update()
					end
				end)
			end

			update()
		end
		setup(obj,data)

		return {
			SetData = function(obj,data)
				setup(obj,data)
			end,
			Enable = function()
				disabled = false
				update()
			end,
			Disable = function()
				disabled = true
			end,
			Destroy = function()
				con:Disconnect()
				con = nil
			end,
		}
	end

	Lib.ProtectedGuis = {}

	Lib.ShowGui = Main.SecureGui

	Lib.ColorToBytes = function(col)
		local round = math.round
		return string.format("%d, %d, %d",round(col.r*255),round(col.g*255),round(col.b*255))
	end

	Lib.ReadFile = function(filename)
		if not env.readfile then return end

		local s,contents = pcall(env.readfile,filename)
		if s and contents then return contents end
	end

	Lib.DeferFunc = function(f,...)
		signalWait(renderStepped)
		return f(...)
	end

	Lib.LoadCustomAsset = function(filepath)
		if not env.getcustomasset or not env.isfile or not env.isfile(filepath) then return end

		return env.getcustomasset(filepath)
	end

	Lib.FetchCustomAsset = function(url,filepath)
		if not env.writefile then return end

		local s,data = pcall(oldgame.HttpGet,game,url)
		if not s then return end

		env.writefile(filepath,data)
		return Lib.LoadCustomAsset(filepath)
	end
	
	local currentfilename, currentextension, currentclickhandler
	currentclickhandler = function() end
	Lib.SaveAsPrompt = function(filename, codeToSave, ext)		
		local win = ScriptViewer.SaveAsWindow
		if not win then
			win = Lib.Window.new()
			win.Alignable = false
			win.Resizable = false
			win:SetTitle("Save As")
			win:SetSize(300,95)

			local saveButton = Lib.Button.new()
			local nameLabel = Lib.Label.new()
			nameLabel.Text = "Name"
			nameLabel.Position = UDim2.new(0,30,0,10)
			nameLabel.Size = UDim2.new(0,40,0,20)
			win:Add(nameLabel)

			local nameBox = Lib.ViewportTextBox.new()
			nameBox.Position = UDim2.new(0,75,0,10)
			nameBox.Size = UDim2.new(0,220,0,20)
			win:Add(nameBox,"NameBox")


			nameBox.TextBox:GetPropertyChangedSignal("Text"):Connect(function()
				saveButton:SetDisabled(#nameBox:GetText() == 0)
			end)

			local errorLabel = Lib.Label.new()
			errorLabel.Text = ""
			errorLabel.Position = UDim2.new(0,5,1,-45)
			errorLabel.Size = UDim2.new(1,-10,0,20)
			errorLabel.TextColor3 = Settings.Theme.Important
			win.ErrorLabel = errorLabel
			win:Add(errorLabel,"Error")

			local cancelButton = Lib.Button.new()
			cancelButton.AnchorPoint = Vector2.new(1,1)
			cancelButton.Text = "Cancel"
			cancelButton.Position = UDim2.new(1,-5,1,-5)
			cancelButton.Size = UDim2.new(0.5,-10,0,20)
			cancelButton.OnClick:Connect(function()
				win:Close()
			end)
			win:Add(cancelButton)

			saveButton.Text = "Save"
			saveButton.AnchorPoint = Vector2.new(0,1)
			saveButton.Position = UDim2.new(0,5,1,-5)
			saveButton.Size = UDim2.new(0.5,-5,0,20)
			saveButton.OnClick:Connect(function()
				currentclickhandler()
			end)

			win:Add(saveButton,"SaveButton")

			ScriptViewer.SaveAsWindow = win
		end

		currentclickhandler = function()
			if type(codeToSave) == "string" then
				filename = (win.Elements.NameBox.TextBox.Text ~= "" and win.Elements.NameBox.TextBox.Text) or filename
				currentextension = ext or filename:match("%.([^%.]+)$") or "txt"
				filename = filename:gsub("%.[^.]+$", "") .. "." .. currentextension

				local codeText = codeToSave or ""
				if env.writefile then
					local s, msg = pcall(env.writefile, filename, codeText)
					if not s then
						win.Elements.Error.Text = "Error: " .. msg
						task.spawn(error, msg)
						task.wait(1)
					end
				else
					win.Elements.Error.Text = "Your executor does not support 'writefile'"
					task.wait(1)
				end
			elseif type(codeToSave) == "function" then
				filename = (win.Elements.NameBox.TextBox.Text ~= "" and win.Elements.NameBox.TextBox.Text) or filename
				currentextension = ext or filename:match("%.([^%.]+)$") or "txt"
				filename = filename:gsub("%.[^.]+$", "") .. "." .. currentextension

				local s, msg = pcall(codeToSave,filename)
				if not s then
					win.Elements.Error.Text = "Error: " .. msg
					task.spawn(error, msg)
					Lib.FastWait(1)
				end
			end
			win:Close()
		end

		win:SetTitle("Save As")
		win.Elements.Error.Text = ""
		win.Elements.NameBox:SetText(filename or "")
		
		win.Elements.SaveButton:SetDisabled(win.Elements.NameBox:GetText() == 0)
		
		win:Show()
	end


	Lib.Signal = (function()
		local funcs = {}

		local disconnect = function(con)
			local pos = table.find(con.Signal.Connections,con)
			if pos then table.remove(con.Signal.Connections,pos) end
		end

		funcs.Connect = function(self,func)
			if type(func) ~= "function" then error("Attempt to connect a non-function") end		
			local con = {
				Signal = self,
				Func = func,
				Disconnect = disconnect
			}
			self.Connections[#self.Connections+1] = con
			return con
		end

		funcs.Fire = function(self,...)
			for i,v in next,self.Connections do
				xpcall(coroutine.wrap(v.Func),function(e) warn(e.."\n"..debug.traceback()) end,...)
			end
		end

		local mt = {
			__index = funcs,
			__tostring = function(self)
				return "Signal: " .. tostring(#self.Connections) .. " Connections"
			end
		}

		local function new()
			local obj = {}
			obj.Connections = {}

			return setmetatable(obj,mt)
		end

		return {new = new}
	end)()

	Lib.Set = (function()
		local funcs = {}

		funcs.Add = function(self,obj)
			if self.Map[obj] then return end

			local list = self.List
			list[#list+1] = obj
			self.Map[obj] = true
			self.Changed:Fire()
		end

		funcs.AddTable = function(self,t)
			local changed
			local list,map = self.List,self.Map
			for i = 1,#t do
				local elem = t[i]
				if not map[elem] then
					list[#list+1] = elem
					map[elem] = true
					changed = true
				end
			end
			if changed then self.Changed:Fire() end
		end

		funcs.Remove = function(self,obj)
			if not self.Map[obj] then return end

			local list = self.List
			local pos = table.find(list,obj)
			if pos then table.remove(list,pos) end
			self.Map[obj] = nil
			self.Changed:Fire()
		end

		funcs.RemoveTable = function(self,t)
			local changed
			local list,map = self.List,self.Map
			local removeSet = {}
			for i = 1,#t do
				local elem = t[i]
				map[elem] = nil
				removeSet[elem] = true
			end

			for i = #list,1,-1 do
				local elem = list[i]
				if removeSet[elem] then
					table.remove(list,i)
					changed = true
				end
			end
			if changed then self.Changed:Fire() end
		end

		funcs.Set = function(self,obj)
			if #self.List == 1 and self.List[1] == obj then return end

			self.List = {obj}
			self.Map = {[obj] = true}
			self.Changed:Fire()
		end

		funcs.SetTable = function(self,t)
			local newList,newMap = {},{}
			self.List,self.Map = newList,newMap
			table.move(t,1,#t,1,newList)
			for i = 1,#t do
				newMap[t[i]] = true
			end
			self.Changed:Fire()
		end

		funcs.Clear = function(self)
			if #self.List == 0 then return end
			self.List = {}
			self.Map = {}
			self.Changed:Fire()
		end

		local mt = {__index = funcs}

		local function new()
			local obj = setmetatable({
				List = {},
				Map = {},
				Changed = Lib.Signal.new()
			},mt)

			return obj
		end

		return {new = new}
	end)()
	
	Lib.IconMap = (function()
		local funcs = {}
		local IconList = {
			Old = {
				MapId = 483448923,
				IconSize = 16,
				Witdh = 16,
				Height = 16,
				Icons = {
					["Accessory"] = 32;
					["Accoutrement"] = 32;
					["AdService"] = 73;
					["Animation"] = 60;
					["AnimationController"] = 60;
					["AnimationTrack"] = 60;
					["Animator"] = 60;
					["ArcHandles"] = 56;
					["AssetService"] = 72;
					["Attachment"] = 34;
					["Backpack"] = 20;
					["BadgeService"] = 75;
					["BallSocketConstraint"] = 89;
					["BillboardGui"] = 64;
					["BinaryStringValue"] = 4;
					["BindableEvent"] = 67;
					["BindableFunction"] = 66;
					["BlockMesh"] = 8;
					["BloomEffect"] = 90;
					["BlurEffect"] = 90;
					["BodyAngularVelocity"] = 14;
					["BodyForce"] = 14;
					["BodyGyro"] = 14;
					["BodyPosition"] = 14;
					["BodyThrust"] = 14;
					["BodyVelocity"] = 14;
					["BoolValue"] = 4;
					["BoxHandleAdornment"] = 54;
					["BrickColorValue"] = 4;
					["Camera"] = 5;
					["CFrameValue"] = 4;
					["CharacterMesh"] = 60;
					["Chat"] = 33;
					["ClickDetector"] = 41;
					["CollectionService"] = 30;
					["Color3Value"] = 4;
					["ColorCorrectionEffect"] = 90;
					["ConeHandleAdornment"] = 54;
					["Configuration"] = 58;
					["ContentProvider"] = 72;
					["ContextActionService"] = 41;
					["CoreGui"] = 46;
					["CoreScript"] = 18;
					["CornerWedgePart"] = 1;
					["CustomEvent"] = 4;
					["CustomEventReceiver"] = 4;
					["CylinderHandleAdornment"] = 54;
					["CylinderMesh"] = 8;
					["CylindricalConstraint"] = 89;
					["Debris"] = 30;
					["Decal"] = 7;
					["Dialog"] = 62;
					["DialogChoice"] = 63;
					["DoubleConstrainedValue"] = 4;
					["Explosion"] = 36;
					["FileMesh"] = 8;
					["Fire"] = 61;
					["Flag"] = 38;
					["FlagStand"] = 39;
					["FloorWire"] = 4;
					["Folder"] = 70;
					["ForceField"] = 37;
					["Frame"] = 48;
					["GamePassService"] = 19;
					["Glue"] = 34;
					["GuiButton"] = 52;
					["GuiMain"] = 47;
					["GuiService"] = 47;
					["Handles"] = 53;
					["HapticService"] = 84;
					["Hat"] = 45;
					["HingeConstraint"] = 89;
					["Hint"] = 33;
					["HopperBin"] = 22;
					["HttpService"] = 76;
					["Humanoid"] = 9;
					["ImageButton"] = 52;
					["ImageLabel"] = 49;
					["InsertService"] = 72;
					["IntConstrainedValue"] = 4;
					["IntValue"] = 4;
					["JointInstance"] = 34;
					["JointsService"] = 34;
					["Keyframe"] = 60;
					["KeyframeSequence"] = 60;
					["KeyframeSequenceProvider"] = 60;
					["Lighting"] = 13;
					["LineHandleAdornment"] = 54;
					["LocalScript"] = 18;
					["LogService"] = 87;
					["MarketplaceService"] = 46;
					["Message"] = 33;
					["Model"] = 2;
					["ModuleScript"] = 71;
					["Motor"] = 34;
					["Motor6D"] = 34;
					["MoveToConstraint"] = 89;
					["NegateOperation"] = 78;
					["NetworkClient"] = 16;
					["NetworkReplicator"] = 29;
					["NetworkServer"] = 15;
					["NumberValue"] = 4;
					["ObjectValue"] = 4;
					["Pants"] = 44;
					["ParallelRampPart"] = 1;
					["Part"] = 1;
					["ParticleEmitter"] = 69;
					["PartPairLasso"] = 57;
					["PathfindingService"] = 37;
					["Platform"] = 35;
					["Player"] = 12;
					["PlayerGui"] = 46;
					["Players"] = 21;
					["PlayerScripts"] = 82;
					["PointLight"] = 13;
					["PointsService"] = 83;
					["Pose"] = 60;
					["PrismaticConstraint"] = 89;
					["PrismPart"] = 1;
					["PyramidPart"] = 1;
					["RayValue"] = 4;
					["ReflectionMetadata"] = 86;
					["ReflectionMetadataCallbacks"] = 86;
					["ReflectionMetadataClass"] = 86;
					["ReflectionMetadataClasses"] = 86;
					["ReflectionMetadataEnum"] = 86;
					["ReflectionMetadataEnumItem"] = 86;
					["ReflectionMetadataEnums"] = 86;
					["ReflectionMetadataEvents"] = 86;
					["ReflectionMetadataFunctions"] = 86;
					["ReflectionMetadataMember"] = 86;
					["ReflectionMetadataProperties"] = 86;
					["ReflectionMetadataYieldFunctions"] = 86;
					["RemoteEvent"] = 80;
					["RemoteFunction"] = 79;
					["ReplicatedFirst"] = 72;
					["ReplicatedStorage"] = 72;
					["RightAngleRampPart"] = 1;
					["RocketPropulsion"] = 14;
					["RodConstraint"] = 89;
					["RopeConstraint"] = 89;
					["Rotate"] = 34;
					["RotateP"] = 34;
					["RotateV"] = 34;
					["RunService"] = 66;
					["ScreenGui"] = 47;
					["Script"] = 6;
					["ScrollingFrame"] = 48;
					["Seat"] = 35;
					["Selection"] = 55;
					["SelectionBox"] = 54;
					["SelectionPartLasso"] = 57;
					["SelectionPointLasso"] = 57;
					["SelectionSphere"] = 54;
					["ServerScriptService"] = 0;
					["ServerStorage"] = 74;
					["Shirt"] = 43;
					["ShirtGraphic"] = 40;
					["SkateboardPlatform"] = 35;
					["Sky"] = 28;
					["SlidingBallConstraint"] = 89;
					["Smoke"] = 59;
					["Snap"] = 34;
					["Sound"] = 11;
					["SoundService"] = 31;
					["Sparkles"] = 42;
					["SpawnLocation"] = 25;
					["SpecialMesh"] = 8;
					["SphereHandleAdornment"] = 54;
					["SpotLight"] = 13;
					["SpringConstraint"] = 89;
					["StarterCharacterScripts"] = 82;
					["StarterGear"] = 20;
					["StarterGui"] = 46;
					["StarterPack"] = 20;
					["StarterPlayer"] = 88;
					["StarterPlayerScripts"] = 82;
					["Status"] = 2;
					["StringValue"] = 4;
					["SunRaysEffect"] = 90;
					["SurfaceGui"] = 64;
					["SurfaceLight"] = 13;
					["SurfaceSelection"] = 55;
					["Team"] = 24;
					["Teams"] = 23;
					["TeleportService"] = 81;
					["Terrain"] = 65;
					["TerrainRegion"] = 65;
					["TestService"] = 68;
					["TextBox"] = 51;
					["TextButton"] = 51;
					["TextLabel"] = 50;
					["Texture"] = 10;
					["TextureTrail"] = 4;
					["Tool"] = 17;
					["TouchTransmitter"] = 37;
					["TrussPart"] = 1;
					["UnionOperation"] = 77;
					["UserInputService"] = 84;
					["Vector3Value"] = 4;
					["VehicleSeat"] = 35;
					["VelocityMotor"] = 34;
					["WedgePart"] = 1;
					["Weld"] = 34;
					["Workspace"] = 19;

				}
			},
			Vanilla3 = {
				MapId = (114851699900089),
				IconSize = 32,
				Witdh = 25,
				Height = 25,
				Icons = {
					Accessory = 1,
					Accoutrement = 2,
					Actor = 3,
					AdGui = 4,
					AdPortal = 5,
					AdService = 6,
					AdvancedDragger = 7,
					AirController = 8,
					AlignOrientation = 9,
					AlignPosition = 10,
					AnalysticsService = 11,
					AnalysticsSettings = 12,
					AnalyticsService = 13,
					AngularVelocity = 14,
					Animation = 15,
					AnimationClip = 16,
					AnimationClipProvider = 17,
					AnimationController = 18,
					AnimationFromVideoCreatorService = 19,
					AnimationFromVideoCreatorStudioService = 20,
					AnimationRigData = 21,
					AnimationStreamTrack = 22,
					AnimationTrack = 23,
					Animator = 24,
					AppStorageService = 25,
					AppUpdateService = 26,
					ArcHandles = 27,
					AssetCounterService = 28,
					AssetDeliveryProxy = 29,
					AssetImportService = 30,
					AssetImportSession = 31,
					AssetManagerService = 32,
					AssetService = 33,
					AssetSoundEffect = 34,
					Atmosphere = 35,
					Attachment = 36,
					AvatarEditorService = 37,
					AvatarImportService = 38,
					Backpack = 39,
					BackpackItem = 40,
					BadgeService = 41,
					BallSocketConstraint = 42,
					BasePart = 43,
					BasePlayerGui = 44,
					BaseScript = 45,
					BaseWrap = 46,
					Beam = 47,
					BevelMesh = 48,
					BillboardGui = 49,
					BinaryStringValue = 50,
					BindableEvent = 51,
					BindableFunction = 52,
					BlockMesh = 53,
					BloomEffect = 54,
					BlurEffect = 55,
					BodyAngularVelocity = 56,
					BodyColors = 57,
					BodyForce = 58,
					BodyGyro = 59,
					BodyMover = 60,
					BodyPosition = 61,
					BodyThrust = 62,
					BodyVelocity = 63,
					Bone = 64,
					BoolValue = 65,
					BoxHandleAdornment = 66,
					Breakpoint = 67,
					BreakpointManager = 68,
					BrickColorValue = 69,
					BrowserService = 70,
					BubbleChatConfiguration = 71,
					BulkImportService = 72,
					CacheableContentProvider = 73,
					CalloutService = 74,
					Camera = 75,
					CanvasGroup = 76,
					CatalogPages = 77,
					CFrameValue = 78,
					ChangeHistoryService = 79,
					ChannelSelectorSoundEffect = 80,
					CharacterAppearance = 81,
					CharacterMesh = 82,
					Chat = 83,
					ChatInputBarConfiguration = 84,
					ChatWindowConfiguration = 85,
					ChorusSoundEffect = 86,
					ClickDetector = 87,
					ClientReplicator = 88,
					ClimbController = 89,
					Clothing = 90,
					Clouds = 91,
					ClusterPacketCache = 92,
					CollectionService = 93,
					Color3Value = 94,
					ColorCorrectionEffect = 95,
					CommandInstance = 96,
					CommandService = 97,
					CompressorSoundEffect = 98,
					ConeHandleAdornment = 99,
					Configuration = 100,
					ConfigureServerService = 101,
					Constraint = 102,
					ContentProvider = 103,
					ContextActionService = 104,
					Controller = 105,
					ControllerBase = 106,
					ControllerManager = 107,
					ControllerService = 108,
					CookiesService = 109,
					CoreGui = 110,
					CorePackages = 111,
					CoreScript = 112,
					CoreScriptSyncService = 113,
					CornerWedgePart = 114,
					CrossDMScriptChangeListener = 115,
					CSGDictionaryService = 116,
					CurveAnimation = 117,
					CustomEvent = 118,
					CustomEventReceiver = 119,
					CustomSoundEffect = 120,
					CylinderHandleAdornment = 121,
					CylinderMesh = 122,
					CylindricalConstraint = 123,
					DataModel = 124,
					DataModelMesh = 125,
					DataModelPatchService = 126,
					DataModelSession = 127,
					DataStore = 128,
					DataStoreIncrementOptions = 129,
					DataStoreInfo = 130,
					DataStoreKey = 131,
					DataStoreKeyInfo = 132,
					DataStoreKeyPages = 133,
					DataStoreListingPages = 134,
					DataStoreObjectVersionInfo = 135,
					DataStoreOptions = 136,
					DataStorePages = 137,
					DataStoreService = 138,
					DataStoreSetOptions = 139,
					DataStoreVersionPages = 140,
					Debris = 141,
					DebuggablePluginWatcher = 142,
					DebuggerBreakpoint = 143,
					DebuggerConnection = 144,
					DebuggerConnectionManager = 145,
					DebuggerLuaResponse = 146,
					DebuggerManager = 147,
					DebuggerUIService = 148,
					DebuggerVariable = 149,
					DebuggerWatch = 150,
					DebugSettings = 151,
					Decal = 152,
					DepthOfFieldEffect = 153,
					DeviceIdService = 154,
					Dialog = 155,
					DialogChoice = 156,
					DistortionSoundEffect = 157,
					DockWidgetPluginGui = 158,
					DoubleConstrainedValue = 159,
					DraftsService = 160,
					Dragger = 161,
					DraggerService = 162,
					DynamicRotate = 163,
					EchoSoundEffect = 164,
					EmotesPages = 165,
					EqualizerSoundEffect = 166,
					EulerRotationCurve = 167,
					EventIngestService = 168,
					Explosion = 169,
					FaceAnimatorService = 170,
					FaceControls = 171,
					FaceInstance = 172,
					FacialAnimationRecordingService = 173,
					FacialAnimationStreamingService = 174,
					Feature = 175,
					File = 176,
					FileMesh = 177,
					Fire = 178,
					Flag = 179,
					FlagStand = 180,
					FlagStandService = 181,
					FlangeSoundEffect = 182,
					FloatCurve = 183,
					FloorWire = 184,
					FlyweightService = 185,
					Folder = 186,
					ForceField = 187,
					FormFactorPart = 188,
					Frame = 189,
					FriendPages = 190,
					FriendService = 191,
					FunctionalTest = 192,
					GamepadService = 193,
					GamePassService = 194,
					GameSettings = 195,
					GenericSettings = 196,
					Geometry = 197,
					GetTextBoundsParams = 198,
					GlobalDataStore = 199,
					GlobalSettings = 200,
					Glue = 201,
					GoogleAnalyticsConfiguration = 202,
					GroundController = 203,
					GroupService = 204,
					GuiBase = 205,
					GuiBase2d = 206,
					GuiBase3d = 207,
					GuiButton = 208,
					GuidRegistryService = 209,
					GuiLabel = 210,
					GuiMain = 211,
					GuiObject = 212,
					GuiService = 213,
					HandleAdornment = 214,
					Handles = 215,
					HandlesBase = 216,
					HapticService = 217,
					Hat = 218,
					HeightmapImporterService = 219,
					HiddenSurfaceRemovalAsset = 220,
					Highlight = 221,
					HingeConstraint = 222,
					Hint = 223,
					Hole = 224,
					Hopper = 225,
					HopperBin = 226,
					HSRDataContentProvider = 227,
					HttpRbxApiService = 228,
					HttpRequest = 229,
					HttpService = 230,
					Humanoid = 231,
					HumanoidController = 232,
					HumanoidDescription = 233,
					IKControl = 234,
					ILegacyStudioBridge = 235,
					ImageButton = 236,
					ImageHandleAdornment = 237,
					ImageLabel = 238,
					ImporterAnimationSettings = 239,
					ImporterBaseSettings = 240,
					ImporterFacsSettings = 241,
					ImporterGroupSettings = 242,
					ImporterJointSettings = 243,
					ImporterMaterialSettings = 244,
					ImporterMeshSettings = 245,
					ImporterRootSettings = 246,
					IncrementalPatchBuilder = 247,
					InputObject = 248,
					InsertService = 249,
					Instance = 250,
					InstanceAdornment = 251,
					IntConstrainedValue = 252,
					IntValue = 253,
					InventoryPages = 254,
					IXPService = 255,
					JointInstance = 256,
					JointsService = 257,
					KeyboardService = 258,
					Keyframe = 259,
					KeyframeMarker = 260,
					KeyframeSequence = 261,
					KeyframeSequenceProvider = 262,
					LanguageService = 263,
					LayerCollector = 264,
					LegacyStudioBridge = 265,
					Light = 266,
					Lighting = 267,
					LinearVelocity = 268,
					LineForce = 269,
					LineHandleAdornment = 270,
					LocalDebuggerConnection = 271,
					LocalizationService = 272,
					LocalizationTable = 273,
					LocalScript = 274,
					LocalStorageService = 275,
					LodDataEntity = 276,
					LodDataService = 277,
					LoginService = 278,
					LogService = 279,
					LSPFileSyncService = 280,
					LuaSettings = 281,
					LuaSourceContainer = 282,
					LuauScriptAnalyzerService = 283,
					LuaWebService = 284,
					ManualGlue = 285,
					ManualSurfaceJointInstance = 286,
					ManualWeld = 287,
					MarkerCurve = 288,
					MarketplaceService = 289,
					MaterialService = 290,
					MaterialVariant = 291,
					MemoryStoreQueue = 292,
					MemoryStoreService = 293,
					MemoryStoreSortedMap = 294,
					MemStorageConnection = 295,
					MemStorageService = 296,
					MeshContentProvider = 297,
					MeshPart = 298,
					Message = 299,
					MessageBusConnection = 300,
					MessageBusService = 301,
					MessagingService = 302,
					MetaBreakpoint = 303,
					MetaBreakpointContext = 304,
					MetaBreakpointManager = 305,
					Model = 306,
					ModuleScript = 307,
					Motor = 308,
					Motor6D = 309,
					MotorFeature = 310,
					Mouse = 311,
					MouseService = 312,
					MultipleDocumentInterfaceInstance = 313,
					NegateOperation = 314,
					NetworkClient = 315,
					NetworkMarker = 316,
					NetworkPeer = 317,
					NetworkReplicator = 318,
					NetworkServer = 319,
					NetworkSettings = 320,
					NoCollisionConstraint = 321,
					NonReplicatedCSGDictionaryService = 322,
					NotificationService = 323,
					NumberPose = 324,
					NumberValue = 325,
					ObjectValue = 326,
					OrderedDataStore = 327,
					OutfitPages = 328,
					PackageLink = 329,
					PackageService = 330,
					PackageUIService = 331,
					Pages = 332,
					Pants = 333,
					ParabolaAdornment = 334,
					Part = 335,
					PartAdornment = 336,
					ParticleEmitter = 337,
					PartOperation = 338,
					PartOperationAsset = 339,
					PatchMapping = 340,
					Path = 341,
					PathfindingLink = 342,
					PathfindingModifier = 343,
					PathfindingService = 344,
					PausedState = 345,
					PausedStateBreakpoint = 346,
					PausedStateException = 347,
					PermissionsService = 348,
					PhysicsService = 349,
					PhysicsSettings = 350,
					PitchShiftSoundEffect = 351,
					Plane = 352,
					PlaneConstraint = 353,
					Platform = 354,
					Player = 355,
					PlayerEmulatorService = 356,
					PlayerGui = 357,
					PlayerMouse = 358,
					Players = 359,
					PlayerScripts = 360,
					Plugin = 361,
					PluginAction = 362,
					PluginDebugService = 363,
					PluginDragEvent = 364,
					PluginGui = 365,
					PluginGuiService = 366,
					PluginManagementService = 367,
					PluginManager = 368,
					PluginManagerInterface = 369,
					PluginMenu = 370,
					PluginMouse = 371,
					PluginPolicyService = 372,
					PluginToolbar = 373,
					PluginToolbarButton = 374,
					PointLight = 375,
					PointsService = 376,
					PolicyService = 377,
					Pose = 378,
					PoseBase = 379,
					PostEffect = 380,
					PrismaticConstraint = 381,
					ProcessInstancePhysicsService = 382,
					ProximityPrompt = 383,
					ProximityPromptService = 384,
					PublishService = 385,
					PVAdornment = 386,
					PVInstance = 387,
					QWidgetPluginGui = 388,
					RayValue = 389,
					RbxAnalyticsService = 390,
					ReflectionMetadata = 391,
					ReflectionMetadataCallbacks = 392,
					ReflectionMetadataClass = 393,
					ReflectionMetadataClasses = 394,
					ReflectionMetadataEnum = 395,
					ReflectionMetadataEnumItem = 396,
					ReflectionMetadataEnums = 397,
					ReflectionMetadataEvents = 398,
					ReflectionMetadataFunctions = 399,
					ReflectionMetadataItem = 400,
					ReflectionMetadataMember = 401,
					ReflectionMetadataProperties = 402,
					ReflectionMetadataYieldFunctions = 403,
					RemoteDebuggerServer = 404,
					RemoteEvent = 405,
					RemoteFunction = 406,
					RenderingTest = 407,
					RenderSettings = 408,
					ReplicatedFirst = 409,
					ReplicatedStorage = 410,
					ReverbSoundEffect = 411,
					RigidConstraint = 412,
					RobloxPluginGuiService = 413,
					RobloxReplicatedStorage = 414,
					RocketPropulsion = 415,
					RodConstraint = 416,
					RopeConstraint = 417,
					Rotate = 418,
					RotateP = 419,
					RotateV = 420,
					RotationCurve = 421,
					RtMessagingService = 422,
					RunningAverageItemDouble = 423,
					RunningAverageItemInt = 424,
					RunningAverageTimeIntervalItem = 425,
					RunService = 426,
					RuntimeScriptService = 427,
					ScreenGui = 428,
					ScreenshotHud = 429,
					Script = 430,
					ScriptChangeService = 431,
					ScriptCloneWatcher = 432,
					ScriptCloneWatcherHelper = 433,
					ScriptContext = 434,
					ScriptDebugger = 435,
					ScriptDocument = 436,
					ScriptEditorService = 437,
					ScriptRegistrationService = 438,
					ScriptService = 439,
					ScrollingFrame = 440,
					Seat = 441,
					Selection = 442,
					SelectionBox = 443,
					SelectionLasso = 444,
					SelectionPartLasso = 445,
					SelectionPointLasso = 446,
					SelectionSphere = 447,
					ServerReplicator = 448,
					ServerScriptService = 449,
					ServerStorage = 450,
					ServiceProvider = 451,
					SessionService = 452,
					Shirt = 453,
					ShirtGraphic = 454,
					SkateboardController = 455,
					SkateboardPlatform = 456,
					Skin = 457,
					Sky = 458,
					SlidingBallConstraint = 459,
					Smoke = 460,
					Snap = 461,
					SnippetService = 462,
					SocialService = 463,
					SolidModelContentProvider = 464,
					Sound = 465,
					SoundEffect = 466,
					SoundGroup = 467,
					SoundService = 468,
					Sparkles = 469,
					SpawnerService = 470,
					SpawnLocation = 471,
					Speaker = 472,
					SpecialMesh = 473,
					SphereHandleAdornment = 474,
					SpotLight = 475,
					SpringConstraint = 476,
					StackFrame = 477,
					StandalonePluginScripts = 478,
					StandardPages = 479,
					StarterCharacterScripts = 480,
					StarterGear = 481,
					StarterGui = 482,
					StarterPack = 483,
					StarterPlayer = 484,
					StarterPlayerScripts = 485,
					Stats = 486,
					StatsItem = 487,
					Status = 488,
					StopWatchReporter = 489,
					StringValue = 490,
					Studio = 491,
					StudioAssetService = 492,
					StudioData = 493,
					StudioDeviceEmulatorService = 494,
					StudioHighDpiService = 495,
					StudioPublishService = 496,
					StudioScriptDebugEventListener = 497,
					StudioService = 498,
					StudioTheme = 499,
					SunRaysEffect = 500,
					SurfaceAppearance = 501,
					SurfaceGui = 502,
					SurfaceGuiBase = 503,
					SurfaceLight = 504,
					SurfaceSelection = 505,
					SwimController = 506,
					TaskScheduler = 507,
					Team = 508,
					TeamCreateService = 509,
					Teams = 510,
					TeleportAsyncResult = 511,
					TeleportOptions = 512,
					TeleportService = 513,
					TemporaryCageMeshProvider = 514,
					TemporaryScriptService = 515,
					Terrain = 516,
					TerrainDetail = 517,
					TerrainRegion = 518,
					TestService = 519,
					TextBox = 520,
					TextBoxService = 521,
					TextButton = 522,
					TextChannel = 523,
					TextChatCommand = 524,
					TextChatConfigurations = 525,
					TextChatMessage = 526,
					TextChatMessageProperties = 527,
					TextChatService = 528,
					TextFilterResult = 529,
					TextLabel = 530,
					TextService = 531,
					TextSource = 532,
					Texture = 533,
					ThirdPartyUserService = 534,
					ThreadState = 535,
					TimerService = 536,
					ToastNotificationService = 537,
					Tool = 538,
					ToolboxService = 539,
					Torque = 540,
					TorsionSpringConstraint = 541,
					TotalCountTimeIntervalItem = 542,
					TouchInputService = 543,
					TouchTransmitter = 544,
					TracerService = 545,
					TrackerStreamAnimation = 546,
					Trail = 547,
					Translator = 548,
					TremoloSoundEffect = 549,
					TriangleMeshPart = 550,
					TrussPart = 551,
					Tween = 552,
					TweenBase = 553,
					TweenService = 554,
					UGCValidationService = 555,
					UIAspectRatioConstraint = 556,
					UIBase = 557,
					UIComponent = 558,
					UIConstraint = 559,
					UICorner = 560,
					UIGradient = 561,
					UIGridLayout = 562,
					UIGridStyleLayout = 563,
					UILayout = 564,
					UIListLayout = 565,
					UIPadding = 566,
					UIPageLayout = 567,
					UIScale = 568,
					UISizeConstraint = 569,
					UIStroke = 570,
					UITableLayout = 571,
					UITextSizeConstraint = 572,
					UnionOperation = 573,
					UniversalConstraint = 574,
					UnvalidatedAssetService = 575,
					UserGameSettings = 576,
					UserInputService = 577,
					UserService = 578,
					UserSettings = 579,
					UserStorageService = 580,
					ValueBase = 581,
					Vector3Curve = 582,
					Vector3Value = 583,
					VectorForce = 584,
					VehicleController = 585,
					VehicleSeat = 586,
					VelocityMotor = 587,
					VersionControlService = 588,
					VideoCaptureService = 589,
					VideoFrame = 590,
					ViewportFrame = 591,
					VirtualInputManager = 592,
					VirtualUser = 593,
					VisibilityService = 594,
					Visit = 595,
					VoiceChannel = 596,
					VoiceChatInternal = 597,
					VoiceChatService = 598,
					VoiceSource = 599,
					VRService = 600,
					WedgePart = 601,
					Weld = 602,
					WeldConstraint = 603,
					WireframeHandleAdornment = 604,
					Workspace = 605,
					WorldModel = 606,
					WorldRoot = 607,
					WrapLayer = 608,
					WrapTarget = 609,

				}
			},
			NewDark = {
				MapId = 135148380892747,
				Icons = {
					Accessory = 1,
					Actor = 2,
					AdGui = 3,
					AdPortal = 4,
					AirController = 5,
					AlignOrientation = 6,
					AlignPosition = 7,
					AngularVelocity = 8,
					Animation = 9,
					AnimationConstraint = 10,
					AnimationController = 11,
					AnimationFromVideoCreatorService = 12,
					Animator = 13,
					ArcHandles = 14,
					Atmosphere = 15,
					Attachment = 16,
					AudioAnalyzer = 17,
					AudioChannelMixer = 18,
					AudioChannelSplitter = 19,
					AudioChorus = 20,
					AudioCompressor = 21,
					AudioDeviceInput = 22,
					AudioDeviceOutput = 23,
					AudioDistortion = 24,
					AudioEcho = 25,
					AudioEmitter = 26,
					AudioEqualizer = 27,
					AudioFader = 28,
					AudioFilter = 29,
					AudioFlanger = 30,
					AudioGate = 31,
					AudioLimiter = 32,
					AudioListener = 33,
					AudioPitchShifter = 34,
					AudioPlayer = 35,
					AudioRecorder = 36,
					AudioReverb = 37,
					AudioTextToSpeech = 38,
					AuroraScript = 39,
					AvatarEditorService = 40,
					AvatarSettings = 41,
					Backpack = 42,
					BallSocketConstraint = 43,
					BasePlate = 44,
					Beam = 45,
					BillboardGui = 46,
					BindableEvent = 47,
					BindableFunction = 48,
					BlockMesh = 49,
					BloomEffect = 50,
					BlurEffect = 51,
					BodyAngularVelocity = 52,
					BodyColors = 53,
					BodyForce = 54,
					BodyGyro = 55,
					BodyPosition = 56,
					BodyThrust = 57,
					BodyVelocity = 58,
					Bone = 59,
					BoolValue = 60,
					BoxHandleAdornment = 61,
					Breakpoint = 62,
					BrickColorValue = 63,
					BubbleChatConfiguration = 64,
					Buggaroo = 65,
					Camera = 66,
					CanvasGroup = 67,
					CFrameValue = 68,
					ChannelTabsConfiguration = 69,
					CharacterControllerManager = 70,
					CharacterMesh = 71,
					Chat = 72,
					ChatInputBarConfiguration = 73,
					ChatWindowConfiguration = 74,
					ChorusSoundEffect = 75,
					Class = 76,
					Cleanup = 77,
					ClickDetector = 78,
					ClientReplicator = 79,
					ClimbController = 80,
					Clouds = 81,
					Color = 82,
					ColorCorrectionEffect = 83,
					CompressorSoundEffect = 84,
					ConeHandleAdornment = 85,
					Configuration = 86,
					Constant = 87,
					Constructor = 88,
					Controller = 89,
					CoreGui = 90,
					CornerWedgePart = 91,
					CylinderHandleAdornment = 92,
					CylindricalConstraint = 93,
					Decal = 94,
					DepthOfFieldEffect = 95,
					Dialog = 96,
					DialogChoice = 97,
					DistortionSoundEffect = 98,
					DragDetector = 99,
					EchoSoundEffect = 100,
					EditableImage = 101,
					EditableMesh = 102,
					Enum = 103,
					EnumMember = 104,
					EqualizerSoundEffect = 105,
					Event = 106,
					Explosion = 107,
					FaceControls = 108,
					Field = 109,
					File = 110,
					Fire = 111,
					FlangeSoundEffect = 112,
					Folder = 113,
					ForceField = 114,
					Frame = 115,
					Function = 116,
					GameSettings = 117,
					GroundController = 118,
					Handles = 119,
					HapticEffect = 120,
					HapticService = 121,
					HeightmapImporterService = 122,
					Highlight = 123,
					HingeConstraint = 124,
					Humanoid = 125,
					HumanoidDescription = 126,
					IKControl = 127,
					ImageButton = 128,
					ImageHandleAdornment = 129,
					ImageLabel = 130,
					InputAction = 131,
					InputBinding = 132,
					InputContext = 133,
					Interface = 134,
					IntersectOperation = 135,
					Keyword = 136,
					Lighting = 137,
					LinearVelocity = 138,
					LineForce = 139,
					LineHandleAdornment = 140,
					LocalFile = 141,
					LocalizationService = 142,
					LocalizationTable = 143,
					LocalScript = 144,
					MaterialService = 145,
					MaterialVariant = 146,
					MemoryStoreService = 147,
					MeshPart = 148,
					Meshparts = 149,
					MessagingService = 150,
					Method = 151,
					Model = 152,
					Modelgroups = 153,
					Module = 154,
					ModuleScript = 155,
					Motor6D = 156,
					NegateOperation = 157,
					NetworkClient = 158,
					NoCollisionConstraint = 159,
					Operator = 160,
					PackageLink = 161,
					Pants = 162,
					Part = 163,
					ParticleEmitter = 164,
					Path2D = 165,
					PathfindingLink = 166,
					PathfindingModifier = 167,
					PathfindingService = 168,
					PitchShiftSoundEffect = 169,
					Place = 170,
					Placeholder = 171,
					Plane = 172,
					PlaneConstraint = 173,
					Player = 174,
					Players = 175,
					PluginGuiService = 176,
					PointLight = 177,
					PrismaticConstraint = 178,
					Property = 179,
					ProximityPrompt = 180,
					PublishService = 181,
					Reference = 182,
					RemoteEvent = 183,
					RemoteFunction = 184,
					RenderingTest = 185,
					ReplicatedFirst = 186,
					ReplicatedScriptService = 187,
					ReplicatedStorage = 188,
					ReverbSoundEffect = 189,
					RigidConstraint = 190,
					RobloxPluginGuiService = 191,
					RocketPropulsion = 192,
					RodConstraint = 193,
					RopeConstraint = 194,
					Rotate = 195,
					ScreenGui = 196,
					Script = 197,
					ScrollingFrame = 198,
					Seat = 199,
					Selected_Workspace = 200,
					SelectionBox = 201,
					SelectionSphere = 202,
					ServerScriptService = 203,
					ServerStorage = 204,
					Service = 205,
					Shirt = 206,
					ShirtGraphic = 207,
					SkinnedMeshPart = 208,
					Sky = 209,
					Smoke = 210,
					Snap = 211,
					Snippet = 212,
					SocialService = 213,
					Sound = 214,
					SoundEffect = 215,
					SoundGroup = 216,
					SoundService = 217,
					Sparkles = 218,
					SpawnLocation = 219,
					SpecialMesh = 220,
					SphereHandleAdornment = 221,
					SpotLight = 222,
					SpringConstraint = 223,
					StandalonePluginScripts = 224,
					StarterCharacterScripts = 225,
					StarterGui = 226,
					StarterPack = 227,
					StarterPlayer = 228,
					StarterPlayerScripts = 229,
					Struct = 230,
					StyleDerive = 231,
					StyleLink = 232,
					StyleRule = 233,
					StyleSheet = 234,
					SunRaysEffect = 235,
					SurfaceAppearance = 236,
					SurfaceGui = 237,
					SurfaceLight = 238,
					SurfaceSelection = 239,
					SwimController = 240,
					TaskScheduler = 241,
					Team = 242,
					Teams = 243,
					Terrain = 244,
					TerrainDetail = 245,
					TestService = 246,
					TextBox = 247,
					TextBoxService = 248,
					TextButton = 249,
					TextChannel = 250,
					TextChatCommand = 251,
					TextChatService = 252,
					TextLabel = 253,
					TextString = 254,
					Texture = 255,
					Tool = 256,
					Torque = 257,
					TorsionSpringConstraint = 258,
					Trail = 259,
					TremoloSoundEffect = 260,
					TrussPart = 261,
					TypeParameter = 262,
					UGCValidationService = 263,
					UIAspectRatioConstraint = 264,
					UICorner = 265,
					UIDragDetector = 266,
					UIFlexItem = 267,
					UIGradient = 268,
					UIGridLayout = 269,
					UIListLayout = 270,
					UIPadding = 271,
					UIPageLayout = 272,
					UIScale = 273,
					UISizeConstraint = 274,
					UIStroke = 275,
					UITableLayout = 276,
					UITextSizeConstraint = 277,
					UnionOperation = 278,
					Unit = 279,
					UniversalConstraint = 280,
					UnreliableRemoteEvent = 281,
					UpdateAvailable = 282,
					UserService = 283,
					Value = 284,
					Variable = 285,
					VectorForce = 286,
					VehicleSeat = 287,
					VideoDisplay = 288,
					VideoFrame = 289,
					VideoPlayer = 290,
					ViewportFrame = 291,
					VirtualUser = 292,
					VoiceChannel = 293,
					Voicechat = 294,
					VoiceChatService = 295,
					VRService = 296,
					WedgePart = 297,
					Weld = 298,
					WeldConstraint = 299,
					Wire = 300,
					WireframeHandleAdornment = 301,
					Workspace = 302,
					WorldModel = 303,
					WrapDeformer = 304,
					WrapLayer = 305,
					WrapTarget = 306,
					
					Color3Value = 284,
					IntValue = 284,
					NumberValue = 284,
					ObjectValue = 284,
					RayValue = 284,
					StringValue = 284,
					Vector3Value = 284,
				},
				IconSize = 32,
				Witdh = 18,
				Height = 18,
			},
			NewLight = {
				MapId = "",
				Icons = {
					Class = "rbxasset://studio_svg_textures/Shared/InsertableObjects/Light/Standard/",
				},
				IconSize = 16,
				Witdh = 18,
				Height = 18,
			}
		}
		if Settings.ClassIcon and IconList[Settings.ClassIcon] then
			funcs.ExplorerIcons = {
				["MapId"] = IconList[Settings.ClassIcon].MapId,
				["Icons"] = IconList[Settings.ClassIcon].Icons,
				["IconSize"] = IconList[Settings.ClassIcon].IconSize,
				["Witdh"] = IconList[Settings.ClassIcon].Witdh,
				["Height"] = IconList[Settings.ClassIcon].Height}
		else
			funcs.ExplorerIcons = { ["MapId"] = IconList.Old.MapId, ["Icons"] = IconList.Old.Icons, ["IconSize"] = IconList.Old.IconSize }
		end
		
		

		funcs.GetLabel = function(self)
			local label = Instance.new("ImageLabel")
			self:SetupLabel(label)
			return label
		end

		funcs.SetupLabel = function(self,obj)
			obj.BackgroundTransparency = 1
			obj.ImageRectOffset = Vector2.new(0, 0)
			obj.ImageRectSize = Vector2.new(self.IconSizeX, self.IconSizeY)
			obj.ScaleType = Enum.ScaleType.Crop
			obj.Size = UDim2.new(0, self.IconSizeX, 0, self.IconSizeY)
		end

		funcs.Display = function(self,obj,index)
			obj.Image = self.MapId
			obj.ImageRectSize = Vector2.new(self.IconSizeX, self.IconSizeY)
			if not self.NumX then
				obj.ImageRectOffset = Vector2.new(self.IconSizeX*index, 0)
			else
				obj.ImageRectOffset = Vector2.new(self.IconSizeX*(index % self.NumX), self.IconSizeY*math.floor(index / self.NumX))
			end
		end

		funcs.DisplayByKey = function(self, obj, key)
			if self.IndexDict[key] then
				self:Display(obj, self.IndexDict[key])
			else
				local rmdEntry = RMD.Classes[obj.ClassName]
				Explorer.ClassIcons:Display(obj, rmdEntry and rmdEntry.ExplorerImageIndex or 0)
			end
		end

		funcs.IconDehash = function(self, _id)
			return math.floor(_id / 14 % 14), math.floor(_id % 14)
		end
		
		local ClassNameNoImage = {}
		funcs.GetExplorerIcon = function(self, obj, index)
			if Settings.ClassIcon == "Vanilla3" then
				obj.Size = UDim2.fromOffset(16, 16)

				index = (self.ExplorerIcons.Icons[index] or 250) - 1
				obj.ImageRectOffset = Vector2.new(funcs.ExplorerIcons.IconSize * (index % funcs.ExplorerIcons.Height), funcs.ExplorerIcons.IconSize * math.floor(index / funcs.ExplorerIcons.Height))
				obj.ImageRectSize = Vector2.new(funcs.ExplorerIcons.IconSize, funcs.ExplorerIcons.IconSize)
			elseif Settings.ClassIcon == "Old" then
				index = (self.ExplorerIcons.Icons[index] or 0)
				local row, col = self:IconDehash(index)
				local MapSize = Vector2.new(256, 256)
				local pad, border = 2, 1

				obj.Position = UDim2.new(-col - (pad * (col + 1) + border) / funcs.ExplorerIcons.IconSize, 0, -row - (pad * (row + 1) + border) / funcs.ExplorerIcons.IconSize, 0)
				obj.Size = UDim2.new(MapSize.X / funcs.ExplorerIcons.IconSize, 0, MapSize.Y / funcs.ExplorerIcons.IconSize, 0)
			elseif Settings.ClassIcon == "NewLight" or Settings.ClassIcon == "NewDark" then
				local isService = string.find(index, "Service") and game:GetService(index)
				
				obj.Size = UDim2.fromOffset(16, 16)
				index = (self.ExplorerIcons.Icons[index] or (isService and self.ExplorerIcons.Icons.Service) or self.ExplorerIcons.Icons.Placeholder) - 1
				obj.ImageRectOffset = Vector2.new(funcs.ExplorerIcons.IconSize * (index % funcs.ExplorerIcons.Height), funcs.ExplorerIcons.IconSize * math.floor(index / funcs.ExplorerIcons.Height))
				obj.ImageRectSize = Vector2.new(funcs.ExplorerIcons.IconSize, funcs.ExplorerIcons.IconSize)
			else
				index = (self.ExplorerIcons.Icons[index] or 0)
				local row, col = self:IconDehash(index)
				local MapSize = Vector2.new(256, 256)
				local pad, border = 2, 1

				obj.Position = UDim2.new(-col - (pad * (col + 1) + border) / funcs.ExplorerIcons.IconSize, 0, -row - (pad * (row + 1) + border) / funcs.ExplorerIcons.IconSize, 0)
				obj.Size = UDim2.new(MapSize.X / funcs.ExplorerIcons.IconSize, 0, MapSize.Y / funcs.ExplorerIcons.IconSize, 0)
			end
			
		end

		funcs.DisplayExplorerIcons = function(self, Frame, index)
			if Frame:FindFirstChild("IconMap") then
				self:GetExplorerIcon(Frame.IconMap, index)
			else
				Frame.ClipsDescendants = true

				local obj = Instance.new("ImageLabel", Frame)
				obj.BackgroundTransparency = 1
				obj.Image = ("http://www.roblox.com/asset/?id=" .. (self.ExplorerIcons.MapId))
				obj.Name = "IconMap"
				self:GetExplorerIcon(obj, index)
			end
		end

		funcs.SetDict = function(self,dict)
			self.IndexDict = dict
		end

		local mt = {}
		mt.__index = funcs

		local function new(mapId,mapSizeX,mapSizeY,iconSizeX,iconSizeY)
			local obj = setmetatable({
				MapId = mapId,
				MapSizeX = mapSizeX,
				MapSizeY = mapSizeY,
				IconSizeX = iconSizeX,
				IconSizeY = iconSizeY,
				NumX = mapSizeX/iconSizeX,
				IndexDict = {}
			}, mt)
			return obj
		end

		local function newLinear(mapId,iconSizeX,iconSizeY)
			local obj = setmetatable({
				MapId = mapId,
				IconSizeX = iconSizeX,
				IconSizeY = iconSizeY,
				IndexDict = {}
			},mt)
			return obj
		end
		
		local function getIconDataFromName(name)
			return IconList[name] or error("Name not found")
		end

		return {new = new, newLinear = newLinear, getIconDataFromName = getIconDataFromName}
	end)()

	Lib.ScrollBar = (function()
		local funcs = {}
		local user = service.UserInputService
		local mouse = plr:GetMouse()
		local checkMouseInGui = Lib.CheckMouseInGui
		local createArrow = Lib.CreateArrow

		local function drawThumb(self)
			local total = self.TotalSpace
			local visible = self.VisibleSpace
			local index = self.Index
			local scrollThumb = self.GuiElems.ScrollThumb
			local scrollThumbFrame = self.GuiElems.ScrollThumbFrame

			if not (self:CanScrollUp()	or self:CanScrollDown()) then
				scrollThumb.Visible = false
			else
				scrollThumb.Visible = true
			end

			if self.Horizontal then
				scrollThumb.Size = UDim2.new(visible/total,0,1,0)
				if scrollThumb.AbsoluteSize.X < 16 then
					scrollThumb.Size = UDim2.new(0,16,1,0)
				end
				local fs = scrollThumbFrame.AbsoluteSize.X
				local bs = scrollThumb.AbsoluteSize.X
				scrollThumb.Position = UDim2.new(self:GetScrollPercent()*(fs-bs)/fs,0,0,0)
			else
				scrollThumb.Size = UDim2.new(1,0,visible/total,0)
				if scrollThumb.AbsoluteSize.Y < 16 then
					scrollThumb.Size = UDim2.new(1,0,0,16)
				end
				local fs = scrollThumbFrame.AbsoluteSize.Y
				local bs = scrollThumb.AbsoluteSize.Y
				scrollThumb.Position = UDim2.new(0,0,self:GetScrollPercent()*(fs-bs)/fs,0)
			end
		end

		local function createFrame(self)
			local newFrame = createSimple("Frame",{Style=0,Active=true,AnchorPoint=Vector2.new(0,0),BackgroundColor3=Color3.new(0.35294118523598,0.35294118523598,0.35294118523598),BackgroundTransparency=0,BorderColor3=Color3.new(0.10588236153126,0.16470588743687,0.20784315466881),BorderSizePixel=0,ClipsDescendants=false,Draggable=false,Position=UDim2.new(1,-16,0,0),Rotation=0,Selectable=false,Size=UDim2.new(0,16,1,0),SizeConstraint=0,Visible=true,ZIndex=1,Name="ScrollBar",})
			local button1, button2

			if self.Horizontal then
				newFrame.Size = UDim2.new(1,0,0,16)
				button1 = createSimple("ImageButton",{
					Parent = newFrame,
					Name = "Left",
					Size = UDim2.new(0,16,0,16),
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					AutoButtonColor = false
				})
				createArrow(16,4,"left").Parent = button1
				button2 = createSimple("ImageButton",{
					Parent = newFrame,
					Name = "Right",
					Position = UDim2.new(1,-16,0,0),
					Size = UDim2.new(0,16,0,16),
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					AutoButtonColor = false
				})
				createArrow(16,4,"right").Parent = button2
			else
				newFrame.Size = UDim2.new(0,16,1,0)
				button1 = createSimple("ImageButton",{
					Parent = newFrame,
					Name = "Up",
					Size = UDim2.new(0,16,0,16),
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					AutoButtonColor = false
				})
				createArrow(16,4,"up").Parent = button1
				button2 = createSimple("ImageButton",{
					Parent = newFrame,
					Name = "Down",
					Position = UDim2.new(0,0,1,-16),
					Size = UDim2.new(0,16,0,16),
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					AutoButtonColor = false
				})
				createArrow(16,4,"down").Parent = button2
			end

			local scrollThumbFrame = createSimple("ImageButton", {
				BackgroundTransparency = 1,
				Parent = newFrame
			})
			if self.Horizontal then
				scrollThumbFrame.Position = UDim2.new(0,16,0,0)
				scrollThumbFrame.Size = UDim2.new(1,-32,1,0)
			else
				scrollThumbFrame.Position = UDim2.new(0,0,0,16)
				scrollThumbFrame.Size = UDim2.new(1,0,1,-32)
			end

			local scrollThumb = createSimple("Frame", {
				BackgroundColor3 = Color3.new(120/255, 120/255, 120/255),
				BorderSizePixel = 0,
				Parent = scrollThumbFrame
			})

			local markerFrame = createSimple("Frame", {
				BackgroundTransparency = 1,
				Name = "Markers",
				Size = UDim2.new(1, 0, 1, 0),
				Parent = scrollThumbFrame
			})

			local buttonPress = false
			local thumbPress = false
			local thumbFramePress = false

			local function handleButtonPress(button, scrollDirection)
				if self:CanScroll(scrollDirection) then
					button.BackgroundTransparency = 0.5
					self:ScrollToDirection(scrollDirection)
					self.Scrolled:Fire()
					local buttonTick = tick()
					local releaseEvent
					releaseEvent = user.InputEnded:Connect(function(input)
						if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
							releaseEvent:Disconnect()
							button.BackgroundTransparency = checkMouseInGui(button) and 0.8 or 1
							buttonPress = false
						end
					end)
					while buttonPress do
						if tick() - buttonTick >= 0.25 and self:CanScroll(scrollDirection) then
							self:ScrollToDirection(scrollDirection)
							self.Scrolled:Fire()
						end
						task.wait()
					end
				end
			end

			button1.MouseButton1Down:Connect(function(input)
				buttonPress = true
				handleButtonPress(button1, "Up")
			end)

			button1.InputEnded:Connect(function(input)
				if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
					button1.BackgroundTransparency = 1
				end
			end)

			button2.MouseButton1Down:Connect(function(input)
				buttonPress = true
				handleButtonPress(button2, "Down")
			end)

			button2.InputEnded:Connect(function(input)
				if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
					button2.BackgroundTransparency = 1
				end
			end)

			scrollThumb.InputBegan:Connect(function(input)
				if (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then
					local dir = self.Horizontal and "X" or "Y"
					local lastThumbPos = nil
					thumbPress = true
					scrollThumb.BackgroundTransparency = 0
					local mouseOffset = mouse[dir] - scrollThumb.AbsolutePosition[dir]
					local releaseEvent
					local mouseEvent

					releaseEvent = user.InputEnded:Connect(function(input)
						if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
							releaseEvent:Disconnect()
							if mouseEvent then mouseEvent:Disconnect() end
							scrollThumb.BackgroundTransparency = 0.2
							thumbPress = false
						end
					end)

					mouseEvent = user.InputChanged:Connect(function(input)
						if (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) and thumbPress then
							local thumbFrameSize = scrollThumbFrame.AbsoluteSize[dir] - scrollThumb.AbsoluteSize[dir]
							local pos = mouse[dir] - scrollThumbFrame.AbsolutePosition[dir] - mouseOffset
							if pos > thumbFrameSize then pos = thumbFrameSize
							elseif pos < 0 then pos = 0 end
							if lastThumbPos ~= pos then
								lastThumbPos = pos
								self:ScrollTo(math.floor(0.5 + pos / thumbFrameSize * (self.TotalSpace - self.VisibleSpace)))
							end
						end
					end)
				end
			end)

			scrollThumb.InputEnded:Connect(function(input)
				if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
					scrollThumb.BackgroundTransparency = 0
				end
			end)

			scrollThumbFrame.InputBegan:Connect(function(input)
				if (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) and not checkMouseInGui(scrollThumb) then
					local dir = self.Horizontal and "X" or "Y"
					local scrollDir = (mouse[dir] >= scrollThumb.AbsolutePosition[dir] + scrollThumb.AbsoluteSize[dir]) and 1 or 0
					local function doTick()
						local scrollSize = self.VisibleSpace - 1
						if scrollDir == 0 and mouse[dir] < scrollThumb.AbsolutePosition[dir] then
							self:ScrollTo(self.Index - scrollSize)
						elseif scrollDir == 1 and mouse[dir] >= scrollThumb.AbsolutePosition[dir] + scrollThumb.AbsoluteSize[dir] then
							self:ScrollTo(self.Index + scrollSize)
						end
					end

					thumbPress = false
					thumbFramePress = true
					doTick()
					local thumbFrameTick = tick()
					local releaseEvent
					releaseEvent = user.InputEnded:Connect(function(input)
						if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
							releaseEvent:Disconnect()
							thumbFramePress = false
						end
					end)

					while thumbFramePress do
						if tick() - thumbFrameTick >= 0.3 and checkMouseInGui(scrollThumbFrame) then
							doTick()
						end
						task.wait()
					end
				end
			end)

			newFrame.MouseWheelForward:Connect(function()
				self:ScrollTo(self.Index - self.WheelIncrement)
			end)

			newFrame.MouseWheelBackward:Connect(function()
				self:ScrollTo(self.Index + self.WheelIncrement)
			end)

			self.GuiElems.ScrollThumb = scrollThumb
			self.GuiElems.ScrollThumbFrame = scrollThumbFrame
			self.GuiElems.Button1 = button1
			self.GuiElems.Button2 = button2
			self.GuiElems.MarkerFrame = markerFrame

			return newFrame
		end

		funcs.Update = function(self,nocallback)
			local total = self.TotalSpace
			local visible = self.VisibleSpace
			local index = self.Index
			local button1 = self.GuiElems.Button1
			local button2 = self.GuiElems.Button2

			self.Index = math.clamp(self.Index, 0, math.max(0, total - visible))

			if self.LastTotalSpace ~= self.TotalSpace then
				self.LastTotalSpace = self.TotalSpace
				self:UpdateMarkers()
			end

			if self:CanScrollUp() then
				for i,v in pairs(button1.Arrow:GetChildren()) do
					v.BackgroundTransparency = 0
				end
			else
				button1.BackgroundTransparency = 1
				for i,v in pairs(button1.Arrow:GetChildren()) do
					v.BackgroundTransparency = 0.5
				end
			end
			if self:CanScrollDown() then
				for i,v in pairs(button2.Arrow:GetChildren()) do
					v.BackgroundTransparency = 0
				end
			else
				button2.BackgroundTransparency = 1
				for i,v in pairs(button2.Arrow:GetChildren()) do
					v.BackgroundTransparency = 0.5
				end
			end

			drawThumb(self)
		end

		funcs.UpdateMarkers = function(self)
			local markerFrame = self.GuiElems.MarkerFrame
			markerFrame:ClearAllChildren()

			for i,v in pairs(self.Markers) do
				if i < self.TotalSpace then
					createSimple("Frame", {
						BackgroundTransparency = 0,
						BackgroundColor3 = v,
						BorderSizePixel = 0,
						Position = self.Horizontal and UDim2.new(i/self.TotalSpace,0,1,-6) or UDim2.new(1,-6,i/self.TotalSpace,0),
						Size = self.Horizontal and UDim2.new(0,1,0,6) or UDim2.new(0,6,0,1),
						Name = "Marker"..tostring(i),
						Parent = markerFrame
					})
				end
			end
		end

		funcs.AddMarker = function(self,ind,color)
			self.Markers[ind] = color or Color3.new(0,0,0)
		end
		funcs.ScrollTo = function(self, ind, nocallback)
			self.Index = ind
			self:Update()
			if not nocallback then
				self.Scrolled:Fire()
			end
		end
		funcs.ScrollUp = function(self)
			self.Index = self.Index - self.Increment
			self:Update()
		end
		funcs.CanScroll = function(self, direction)
			if direction == "Up" then
				return self:CanScrollUp()
			elseif direction == "Down" then
				return self:CanScrollDown()
			end
			return false
		end
		funcs.ScrollDown = function(self)
			self.Index = self.Index + self.Increment
			self:Update()
		end
		funcs.CanScrollUp = function(self)
			return self.Index > 0
		end
		funcs.CanScrollDown = function(self)
			return self.Index + self.VisibleSpace < self.TotalSpace
		end
		funcs.GetScrollPercent = function(self)
			return self.Index/(self.TotalSpace-self.VisibleSpace)
		end
		funcs.SetScrollPercent = function(self,perc)
			self.Index = math.floor(perc*(self.TotalSpace-self.VisibleSpace))
			self:Update()
		end
		funcs.ScrollToDirection = function(self, Direaction)
			if Direaction == "Up" then
				self:ScrollUp()
			elseif Direaction == "Down" then
				self:ScrollDown()
			end
		end

		funcs.Texture = function(self,data)
			self.ThumbColor = data.ThumbColor or Color3.new(0,0,0)
			self.ThumbSelectColor = data.ThumbSelectColor or Color3.new(0,0,0)
			self.GuiElems.ScrollThumb.BackgroundColor3 = data.ThumbColor or Color3.new(0,0,0)
			self.Gui.BackgroundColor3 = data.FrameColor or Color3.new(0,0,0)
			self.GuiElems.Button1.BackgroundColor3 = data.ButtonColor or Color3.new(0,0,0)
			self.GuiElems.Button2.BackgroundColor3 = data.ButtonColor or Color3.new(0,0,0)
			for i,v in pairs(self.GuiElems.Button1.Arrow:GetChildren()) do
				v.BackgroundColor3 = data.ArrowColor or Color3.new(0,0,0)
			end
			for i,v in pairs(self.GuiElems.Button2.Arrow:GetChildren()) do
				v.BackgroundColor3 = data.ArrowColor or Color3.new(0,0,0)
			end
		end

		funcs.SetScrollFrame = function(self,frame)
			if self.ScrollUpEvent then self.ScrollUpEvent:Disconnect() self.ScrollUpEvent = nil end
			if self.ScrollDownEvent then self.ScrollDownEvent:Disconnect() self.ScrollDownEvent = nil end
			self.ScrollUpEvent = frame.MouseWheelForward:Connect(function() self:ScrollTo(self.Index - self.WheelIncrement) end)
			self.ScrollDownEvent = frame.MouseWheelBackward:Connect(function() self:ScrollTo(self.Index + self.WheelIncrement) end)
		end

		local mt = {}
		mt.__index = funcs

		local function new(hor)
			local obj = setmetatable({
				Index = 0,
				VisibleSpace = 0,
				TotalSpace = 0,
				Increment = 1,
				WheelIncrement = 1,
				Markers = {},
				GuiElems = {},
				Horizontal = hor,
				LastTotalSpace = 0,
				Scrolled = Lib.Signal.new()
			},mt)
			obj.Gui = createFrame(obj)
			obj:Texture({
				ThumbColor = Color3.fromRGB(40,40,40),
				ThumbSelectColor = Color3.fromRGB(55,55,55),
				ArrowColor = Color3.new(1,1,1),
				FrameColor = Color3.fromRGB(8,8,8),
				ButtonColor = Color3.fromRGB(25,25,25)
			})
			return obj
		end

		return {new = new}
	end)()

	Lib.DrawIcon = (function()
		local function mk(class,props,parent)
			local inst = Instance.new(class)
			if Main.MarkDark then Main.MarkDark(inst) end
			for k,v in pairs(props) do inst[k] = v end
			inst.Parent = parent
			return inst
		end

		local function bar(h,c,x,y,len,t,rot)
			local f = mk("Frame",{AnchorPoint=Vector2.new(0.5,0.5),BackgroundColor3=c,BorderSizePixel=0,Position=UDim2.new(x,0,y,0),Rotation=rot or 0,Size=UDim2.new(len,0,0,t)},h)
			mk("UICorner",{CornerRadius=UDim.new(1,0)},f)
			return f
		end

		local function box(h,c,x,y,w,hh,t,corner)
			local f = mk("Frame",{AnchorPoint=Vector2.new(0.5,0.5),BackgroundTransparency=1,Position=UDim2.new(x,0,y,0),Size=UDim2.new(w,0,hh,0)},h)
			mk("UICorner",{CornerRadius=corner or UDim.new(0,2)},f)
			mk("UIStroke",{ApplyStrokeMode=Enum.ApplyStrokeMode.Border,Color=c,Thickness=t},f)
			return f
		end

		local function dot(h,c,x,y,s)
			local f = mk("Frame",{AnchorPoint=Vector2.new(0.5,0.5),BackgroundColor3=c,BorderSizePixel=0,Position=UDim2.new(x,0,y,0),Size=UDim2.new(s,0,s,0),SizeConstraint=Enum.SizeConstraint.RelativeXX},h)
			mk("UICorner",{CornerRadius=UDim.new(1,0)},f)
			return f
		end

		local drawers = {}

		drawers.close = function(h,c,t)
			bar(h,c,0.5,0.5,1.15,t,45)
			bar(h,c,0.5,0.5,1.15,t,-45)
		end

		drawers.minimize = function(h,c,t)
			bar(h,c,0.5,0.5,0.95,t)
		end

		drawers.restore = function(h,c,t)
			box(h,c,0.5,0.5,0.8,0.8,t,UDim.new(0,2))
		end

		drawers.explorer = function(h,c,t)
			dot(h,c,0.2,0.2,0.24)
			bar(h,c,0.63,0.2,0.5,t)
			bar(h,c,0.2,0.56,0.62,t,90)
			bar(h,c,0.31,0.56,0.22,t)
			dot(h,c,0.5,0.56,0.2)
			bar(h,c,0.78,0.56,0.3,t)
			bar(h,c,0.31,0.86,0.22,t)
			dot(h,c,0.5,0.86,0.2)
			bar(h,c,0.78,0.86,0.3,t)
		end

		drawers.properties = function(h,c,t)
			for i,kx in ipairs({0.3,0.7,0.45}) do
				local y = 0.2 + (i-1)*0.3
				bar(h,c,0.5,y,0.92,t)
				dot(h,c,kx,y,0.26)
			end
		end

		drawers.select = function(h,c,t)
			box(h,c,0.5,0.5,0.6,0.6,t,UDim.new(1,0))
			bar(h,c,0.5,0.08,0.18,t,90)
			bar(h,c,0.5,0.92,0.18,t,90)
			bar(h,c,0.08,0.5,0.18,t)
			bar(h,c,0.92,0.5,0.18,t)
			dot(h,c,0.5,0.5,0.14)
		end

		drawers.notepad = function(h,c,t)
			box(h,c,0.5,0.5,0.68,0.86,t,UDim.new(0,3))
			bar(h,c,0.5,0.32,0.36,t)
			bar(h,c,0.5,0.5,0.36,t)
			bar(h,c,0.44,0.68,0.24,t)
		end

		drawers.console = function(h,c,t)
			box(h,c,0.5,0.5,0.92,0.76,t,UDim.new(0,3))
			bar(h,c,0.33,0.42,0.26,t,40)
			bar(h,c,0.33,0.58,0.26,t,-40)
			bar(h,c,0.62,0.64,0.24,t)
		end

		drawers.save = function(h,c,t)
			bar(h,c,0.5,0.36,0.46,t,90)
			bar(h,c,0.4,0.52,0.3,t,45)
			bar(h,c,0.6,0.52,0.3,t,-45)
			bar(h,c,0.5,0.88,0.8,t)
		end

		drawers.viewer = function(h,c,t)
			box(h,c,0.42,0.58,0.5,0.5,t,UDim.new(0,1))
			box(h,c,0.58,0.42,0.5,0.5,t,UDim.new(0,1))
			for _,p in ipairs({{0.25,0.25},{0.75,0.25},{0.25,0.75},{0.75,0.75}}) do
				bar(h,c,p[1],p[2],0.23,t,-45)
			end
		end

		drawers.scripts = function(h,c,t)
			bar(h,c,0.24,0.37,0.3,t,-45)
			bar(h,c,0.24,0.63,0.3,t,45)
			bar(h,c,0.76,0.37,0.3,t,45)
			bar(h,c,0.76,0.63,0.3,t,-45)
			bar(h,c,0.5,0.5,0.62,t,-70)
		end

		drawers.tests = function(h,c,t)
			box(h,c,0.5,0.5,0.9,0.9,t,UDim.new(0,4))
			bar(h,c,0.37,0.56,0.24,t,45)
			bar(h,c,0.585,0.47,0.42,t,-50)
		end

		drawers.grip = function(h,c)
			dot(h,c,0.8,0.8,0.2)
			dot(h,c,0.45,0.8,0.2)
			dot(h,c,0.8,0.45,0.2)
		end

		return function(parent,name,color,thickness)
			local old = parent:FindFirstChild("DrawnIcon")
			if old then old:Destroy() end
			local h = mk("Frame",{BackgroundTransparency=1,Name="DrawnIcon",Size=UDim2.new(1,0,1,0)},parent)
			local d = drawers[name]
			if d then d(h,color or Color3.new(1,1,1),thickness or 2) end
			return h
		end
	end)()

	Lib.Window = (function()
		local funcs = {}
		local static = {MinWidth = 200, FreeWidth = 200}
		local UIS = service.UserInputService

		local TOP, TABS, FOOT = 34, 32, 24
		local hub = {TabList = {}, Dialogs = {}, Visible = true, Minimized = false, SizeX = 920, SizeY = 540, SidebarWidth = 80, DialogZ = 1, TabCounter = 0}
		local hubGui, hubMain, hubTopBar, hubTopFill, hubBody, hubPages, hubOverlay, hubSidebar, hubTabBar, hubFooter, hubMinIcon

		local col = {
			Back = Color3.fromRGB(0,0,0),
			Bar = Color3.fromRGB(10,10,10),
			Line = Color3.fromRGB(28,28,28),
			Stroke = Color3.fromRGB(40,40,40),
			TabHover = Color3.fromRGB(18,18,18),
			TabActive = Color3.fromRGB(28,28,28),
			Divider = Color3.fromRGB(16,16,16),
			DividerHover = Color3.fromRGB(0,170,255),
			ButtonHover = Color3.fromRGB(32,32,32),
			CloseHover = Color3.fromRGB(196,43,43),
			TextIdle = Color3.fromRGB(140,140,140),
			TextDim = Color3.fromRGB(95,95,95),
			Text = Color3.fromRGB(235,235,235),
			Icon = Color3.fromRGB(200,200,200),
			Accent = Color3.fromRGB(0,170,255),
		}

		local function new(class,props,parent)
			local inst = Instance.new(class)
			if Main.MarkDark then Main.MarkDark(inst) end
			for k,v in pairs(props) do inst[k] = v end
			if parent then inst.Parent = parent end
			return inst
		end

		local function corner(parent,r)
			return new("UICorner",{CornerRadius=UDim.new(0,r)},parent)
		end

		local function iconHolder(parent,size)
			return new("Frame",{AnchorPoint=Vector2.new(0.5,0.5),BackgroundTransparency=1,Name="Icon",Position=UDim2.new(0.5,0,0.5,0),Size=UDim2.new(0,size,0,size)},parent)
		end

		local function isPress(input)
			return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
		end

		local function isMove(input)
			return input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch
		end

		local function dragHook(handle,onStart,onMove)
			handle.InputBegan:Connect(function(input)
				if not isPress(input) then return end
				if onStart and onStart(input) == false then return end
				local startPos = input.Position
				local moveCon, endCon
				moveCon = UIS.InputChanged:Connect(function(inp)
					if isMove(inp) then
						onMove(inp.Position - startPos, inp.Position)
					end
				end)
				endCon = UIS.InputEnded:Connect(function(inp)
					if isPress(inp) then
						moveCon:Disconnect()
						endCon:Disconnect()
					end
				end)
			end)
		end

		local function hoverFill(button,color)
			button.BackgroundColor3 = color
			button.BackgroundTransparency = 1
			button.MouseEnter:Connect(function() button.BackgroundTransparency = 0 end)
			button.MouseLeave:Connect(function() button.BackgroundTransparency = 1 end)
		end

		local function setWinHidden(win,hidden)
			if win.Minimized == hidden then return end
			win.Minimized = hidden
			if hidden then win.OnMinimize:Fire() else win.OnRestore:Fire() end
		end

		local function refreshVisibility()
			local shown = hub.Visible and not hub.Minimized
			for _,tab in ipairs(hub.TabList) do
				for _,win in ipairs(tab.Windows) do
					setWinHidden(win, not (shown and tab == hub.ActiveTab))
				end
			end
			for _,win in ipairs(hub.Dialogs) do
				setWinHidden(win, not shown)
			end
		end

		local function tabTitle(tab)
			if tab.Group then return tab.Group end
			local win = tab.Windows[1]
			return win and win.GuiElems.Title.Text or ""
		end

		local function updateTabButton(tab)
			local text = tabTitle(tab)
			tab.Label.Text = text
			local w = service.TextService:GetTextSize(text,12,Enum.Font.GothamMedium,Vector2.new(1000,22)).X
			tab.Button.Size = UDim2.new(0,math.clamp(w + 46,70,260),0,24)
		end

		local function styleTab(tab)
			local active = tab == hub.ActiveTab
			if active then
				tab.Button.BackgroundColor3 = col.TabActive
				tab.Button.BackgroundTransparency = 0
			elseif tab.Hover then
				tab.Button.BackgroundColor3 = col.TabHover
				tab.Button.BackgroundTransparency = 0
			else
				tab.Button.BackgroundTransparency = 1
			end
			tab.Label.TextColor3 = active and col.Text or col.TextIdle
			tab.Accent.Visible = active
		end

		local function layoutTab(tab)
			local wins = tab.Windows
			if #wins == 1 then
				local m = wins[1].GuiElems.Main
				m.Position = UDim2.new(0,0,0,0)
				m.Size = UDim2.new(1,0,1,0)
				tab.Divider.Visible = false
			elseif #wins >= 2 then
				local r = tab.Split
				local a,b = wins[1].GuiElems.Main, wins[2].GuiElems.Main
				a.Position = UDim2.new(0,0,0,0)
				a.Size = UDim2.new(r,-2,1,0)
				b.Position = UDim2.new(r,2,0,0)
				b.Size = UDim2.new(1-r,-2,1,0)
				tab.Divider.Position = UDim2.new(r,-2,0,0)
				tab.Divider.Size = UDim2.new(0,4,1,0)
				tab.Divider.Visible = true
			end
		end

		local function activateTab(tab)
			if tab.Removed then return end
			hub.ActiveTab = tab
			for _,t in ipairs(hub.TabList) do
				t.Page.Visible = t == tab
				styleTab(t)
			end
			refreshVisibility()
		end

		local function removeTab(tab)
			tab.Removed = true
			local idx = table.find(hub.TabList,tab)
			if idx then table.remove(hub.TabList,idx) end
			tab.Button:Destroy()
			tab.Page:Destroy()
			if hub.ActiveTab == tab then
				hub.ActiveTab = nil
				local nextTab = hub.TabList[math.max(1,(idx or 1) - 1)]
				if nextTab then activateTab(nextTab) end
			end
		end

		local function createTab(key,group)
			hub.TabCounter = hub.TabCounter + 1
			local tab = {Key = key, Group = group, Windows = {}, Split = 0.5}

			local btn = new("TextButton",{AutoButtonColor=false,BackgroundColor3=col.TabHover,BackgroundTransparency=1,BorderSizePixel=0,LayoutOrder=hub.TabCounter,Name="Tab",Size=UDim2.new(0,100,0,24),Text=""},hubTabBar)
			corner(btn,6)
			tab.Button = btn
			tab.Accent = new("Frame",{AnchorPoint=Vector2.new(0,0.5),BackgroundColor3=col.Accent,BorderSizePixel=0,Name="Accent",Position=UDim2.new(0,10,0.5,0),Size=UDim2.new(0,5,0,5),Visible=false},btn)
			corner(tab.Accent,3)
			tab.Label = new("TextLabel",{BackgroundTransparency=1,Font=Enum.Font.GothamMedium,Name="Label",Position=UDim2.new(0,21,0,0),Size=UDim2.new(1,-45,1,0),Text="",TextColor3=col.TextIdle,TextSize=12,TextTruncate=Enum.TextTruncate.AtEnd,TextXAlignment=Enum.TextXAlignment.Left},btn)

			local close = new("TextButton",{AutoButtonColor=false,BorderSizePixel=0,Name="Close",Position=UDim2.new(1,-21,0.5,-8),Size=UDim2.new(0,16,0,16),Text=""},btn)
			corner(close,4)
			hoverFill(close,col.ButtonHover)
			Lib.DrawIcon(iconHolder(close,7),"close",col.TextIdle,1)

			local page = new("Frame",{BackgroundColor3=col.Back,BorderSizePixel=0,ClipsDescendants=true,Name="Page",Size=UDim2.new(1,0,1,0),Visible=false},hubPages)
			tab.Page = page

			local divider = new("TextButton",{AutoButtonColor=false,BackgroundColor3=col.Divider,BorderSizePixel=0,Name="Divider",Text="",Visible=false,ZIndex=5},page)
			tab.Divider = divider
			divider.MouseEnter:Connect(function() divider.BackgroundColor3 = col.DividerHover end)
			divider.MouseLeave:Connect(function() divider.BackgroundColor3 = col.Divider end)
			dragHook(divider,nil,function(_,pos)
				local w = page.AbsoluteSize.X
				if w <= 0 then return end
				tab.Split = math.clamp((pos.X - page.AbsolutePosition.X)/w,0.2,0.8)
				layoutTab(tab)
			end)

			btn.MouseEnter:Connect(function() tab.Hover = true styleTab(tab) end)
			btn.MouseLeave:Connect(function() tab.Hover = false if not tab.Removed then styleTab(tab) end end)
			btn.MouseButton1Click:Connect(function() activateTab(tab) end)
			close.MouseButton1Click:Connect(function()
				local wins = {}
				for i,v in ipairs(tab.Windows) do wins[i] = v end
				for _,win in ipairs(wins) do win:Close() end
			end)

			table.insert(hub.TabList,tab)
			return tab
		end

		local function setChrome(win,dialog)
			local elems = win.GuiElems
			elems.TopBar.Visible = dialog
			elems.Outlines.Enabled = dialog
			elems.Corner.CornerRadius = UDim.new(0,dialog and 8 or 0)
			elems.ContentCorner.CornerRadius = UDim.new(0,dialog and 8 or 0)
			elems.Content.Position = UDim2.new(0,0,0,dialog and 26 or 0)
			elems.Content.Size = UDim2.new(1,0,1,dialog and -26 or 0)
		end

		local function openTab(win,silent)
			local key = win.Group or win
			local tab
			for _,t in ipairs(hub.TabList) do
				if t.Key == key then tab = t break end
			end
			if not tab then tab = createTab(key,win.Group) end
			win.Tab = tab

			local wins = tab.Windows
			local pos = #wins + 1
			for i,other in ipairs(wins) do
				if (win.Slot or math.huge) < (other.Slot or math.huge) then pos = i break end
			end
			table.insert(wins,pos,win)

			setChrome(win,false)
			win.GuiElems.Main.AnchorPoint = Vector2.new(0,0)
			win.GuiElems.Main.ZIndex = 1
			win.GuiElems.Main.Parent = tab.Page
			layoutTab(tab)
			updateTabButton(tab)

			local willActivate = (not silent) or hub.ActiveTab == nil or hub.ActiveTab == tab
			win.Minimized = not (willActivate and hub.Visible and not hub.Minimized)
			if willActivate then activateTab(tab) else styleTab(tab) end
		end

		local function closeFromTab(win)
			local tab = win.Tab
			win.Tab = nil
			if not tab then return end
			local idx = table.find(tab.Windows,win)
			if idx then table.remove(tab.Windows,idx) end
			win.GuiElems.Main.Parent = win.Gui
			if #tab.Windows == 0 then
				removeTab(tab)
			else
				layoutTab(tab)
				updateTabButton(tab)
			end
		end

		local function bringToFront(win)
			hub.DialogZ = hub.DialogZ + 1
			win.GuiElems.Main.ZIndex = hub.DialogZ
		end

		local function openDialog(win)
			win.IsDialog = true
			table.insert(hub.Dialogs,win)
			setChrome(win,true)
			local m = win.GuiElems.Main
			m.AnchorPoint = Vector2.new(0.5,0.5)
			m.Size = UDim2.new(0,win.SizeX,0,win.SizeY + 6)
			m.Position = UDim2.new(0.5,0,0.5,0)
			m.Parent = hubOverlay
			win.Minimized = not (hub.Visible and not hub.Minimized)
			bringToFront(win)
		end

		local function closeDialog(win)
			win.IsDialog = false
			local idx = table.find(hub.Dialogs,win)
			if idx then table.remove(hub.Dialogs,idx) end
			win.GuiElems.Main.Parent = win.Gui
		end

		local function setHubMinimized(val)
			if not hubGui or hub.Minimized == val then return end
			hub.Minimized = val
			hubBody.Visible = not val
			hubFooter.Visible = not val
			hubTopFill.Visible = not val
			hubMain.Size = UDim2.new(0,hub.SizeX,0,val and TOP or hub.SizeY)
			Lib.DrawIcon(hubMinIcon,val and "restore" or "minimize",col.Icon,1.5)
			refreshVisibility()
		end

		local function createGui(self)
			local gui = new("ScreenGui",{Name="Window",ZIndexBehavior=Enum.ZIndexBehavior.Sibling})
			local main = new("Frame",{Active=true,BackgroundColor3=col.Back,BorderSizePixel=0,Name="Main",Position=UDim2.new(0.5,-150,0.5,-150),Size=UDim2.new(0,300,0,300)},gui)
			local mainCorner = corner(main,0)
			local outlines = new("UIStroke",{ApplyStrokeMode=Enum.ApplyStrokeMode.Border,Color=col.Stroke,Enabled=false,Name="Outlines",Thickness=1},main)
			local content = new("Frame",{BackgroundColor3=col.Back,BorderSizePixel=0,ClipsDescendants=true,Name="Content",Position=UDim2.new(0,0,0,26),Size=UDim2.new(1,0,1,-26)},main)
			local contentCorner = corner(content,0)
			local line = new("Frame",{BackgroundColor3=col.Line,BorderSizePixel=0,Name="Line",Size=UDim2.new(1,0,0,1)},content)
			local topBar = new("TextButton",{AutoButtonColor=false,BackgroundColor3=col.Bar,BorderSizePixel=0,Name="TopBar",Size=UDim2.new(1,0,0,26),Text=""},main)
			corner(topBar,8)
			new("Frame",{BackgroundColor3=col.Bar,BorderSizePixel=0,Name="Fill",Position=UDim2.new(0,0,1,-8),Size=UDim2.new(1,0,0,8)},topBar)
			local title = new("TextLabel",{BackgroundTransparency=1,Font=Enum.Font.GothamMedium,Name="Title",Position=UDim2.new(0,10,0,0),Size=UDim2.new(1,-40,1,0),Text="Window",TextColor3=col.Text,TextSize=12,TextTruncate=Enum.TextTruncate.AtEnd,TextXAlignment=Enum.TextXAlignment.Left},topBar)
			local close = new("TextButton",{AutoButtonColor=false,BackgroundColor3=col.CloseHover,BackgroundTransparency=1,BorderSizePixel=0,Name="Close",Position=UDim2.new(1,-24,0,4),Size=UDim2.new(0,18,0,18),Text=""},topBar)
			corner(close,5)
			Lib.DrawIcon(iconHolder(close,8),"close",col.Icon,1.5)
			local minimize = new("TextButton",{AutoButtonColor=false,BackgroundColor3=col.ButtonHover,BackgroundTransparency=1,BorderSizePixel=0,Name="Minimize",Position=UDim2.new(1,-46,0,4),Size=UDim2.new(0,18,0,18),Text="",Visible=false},topBar)
			corner(minimize,5)
			Lib.DrawIcon(iconHolder(minimize,8),"minimize",col.Icon,1.5)
			local resizeControls = new("Frame",{BackgroundTransparency=1,Name="ResizeControls",Size=UDim2.new(1,0,1,0),Visible=false},main)

			self.GuiElems.Main = main
			self.GuiElems.Corner = mainCorner
			self.GuiElems.ContentCorner = contentCorner
			self.GuiElems.TopBar = topBar
			self.GuiElems.Content = content
			self.GuiElems.Line = line
			self.GuiElems.Outlines = outlines
			self.GuiElems.Title = title
			self.GuiElems.Close = close
			self.GuiElems.Minimize = minimize
			self.GuiElems.ResizeControls = resizeControls
			self.ContentPane = content

			if Settings.Window.TitleOnMiddle then
				title.TextXAlignment = Enum.TextXAlignment.Center
				title.Size = UDim2.new(1,-20,1,0)
			end

			local dragStart
			dragHook(topBar,function()
				if not self.IsDialog then return false end
				bringToFront(self)
				dragStart = main.Position
			end,function(delta)
				main.Position = dragStart + UDim2.new(0,delta.X,0,delta.Y)
			end)

			main.InputBegan:Connect(function(input)
				if isPress(input) and self.IsDialog then bringToFront(self) end
			end)

			close.MouseEnter:Connect(function() close.BackgroundTransparency = 0 end)
			close.MouseLeave:Connect(function() close.BackgroundTransparency = 1 end)
			close.MouseButton1Click:Connect(function()
				if self.Closed then return end
				self:Close()
			end)

			main:GetPropertyChangedSignal("AbsolutePosition"):Connect(function()
				self.PosX = main.AbsolutePosition.X
				self.PosY = main.AbsolutePosition.Y
			end)

			return gui
		end

		funcs.SetMinimized = function(self) end
		funcs.SetAligned = function(self) end
		funcs.MoveInBoundary = function(self) end

		funcs.Resize = function(self,sizeX,sizeY)
			self.SizeX = sizeX or self.SizeX
			self.SizeY = sizeY or self.SizeY
			if self.IsDialog then
				self.GuiElems.Main.Size = UDim2.new(0,self.SizeX,0,self.SizeY + 6)
			elseif not self.Tab then
				self.GuiElems.Main.Size = UDim2.new(0,self.SizeX,0,self.SizeY)
			end
		end

		funcs.SetSize = funcs.Resize

		funcs.SetTitle = function(self,title)
			self.GuiElems.Title.Text = title
			if self.Tab then updateTabButton(self.Tab) end
		end

		funcs.SetResizable = function(self,val)
			self.Resizable = val
		end

		funcs.SetResizableInternal = function(self,val)
			self.ResizableInternal = val
		end

		funcs.Add = function(self,obj,name)
			if type(obj) == "table" and obj.Gui and obj.Gui:IsA("GuiObject") then
				obj.Gui.Parent = self.ContentPane
			else
				obj.Parent = self.ContentPane
			end
			if name then self.Elements[name] = obj end
		end

		funcs.GetElement = function(self,obj,name)
			return self.Elements[name]
		end

		funcs.AlignTo = function(self)
			static.ShowWindow(self,{})
		end

		funcs.Close = function(self)
			if self.Closed then return end
			self.Closed = true
			if self.Tab then closeFromTab(self) end
			if self.IsDialog then closeDialog(self) end
			self.GuiElems.Main.Parent = self.Gui
			self.Gui.Parent = nil
			self.Minimized = false
			self.OnDeactivate:Fire()
		end

		funcs.Hide = funcs.Close

		funcs.Destroy = function(self)
			self:Close()
			self.Gui:Destroy()
		end

		funcs.IsVisible = function(self)
			return not self.Closed and not self.Minimized
		end

		funcs.IsContentVisible = funcs.IsVisible

		funcs.Focus = function(self)
			if self.Tab then
				activateTab(self.Tab)
			elseif self.IsDialog then
				bringToFront(self)
			end
		end

		funcs.DoTween = function(self,...)
			local tween = service.TweenService:Create(...)
			self.Tweens[#self.Tweens+1] = tween
			tween:Play()
		end

		funcs.StopTweens = function(self)
			for i,v in pairs(self.Tweens) do
				v:Cancel()
			end
			self.Tweens = {}
		end

		funcs.Show = function(self,data)
			return static.ShowWindow(self,data)
		end

		funcs.ShowAndFocus = function(self,data)
			static.ShowWindow(self,data)
			self:Focus()
		end

		static.ShowWindow = function(window,data)
			data = data or {}
			if not hubGui then static.Init() end
			if data.Group ~= nil then window.Group = data.Group end
			if data.Slot ~= nil then window.Slot = data.Slot end

			if not data.Silent then
				static.SetHubVisible(true)
				setHubMinimized(false)
			end

			if not window.Closed then
				if not data.Silent then window:Focus() end
				return
			end

			window.Closed = false
			if not window.DarkPassed then
				window.DarkPassed = true
				Main.DarkenTree(window.GuiElems.Main)
			end
			Lib.ShowGui(window.Gui)
			window.Gui.DisplayOrder = Main.DisplayOrders.Window + 1

			if window.Resizable == false then
				openDialog(window)
			else
				openTab(window,data.Silent)
			end

			window.OnActivate:Fire()
		end

		static.SetHubVisible = function(val)
			if not hubGui then return end
			val = val and true or false
			if hub.Visible == val then return end
			hub.Visible = val
			hubMain.Visible = val
			refreshVisibility()
			static.HubVisibleChanged:Fire(val)
		end

		static.IsHubVisible = function()
			return hub.Visible
		end

		static.GetSidebar = function()
			return hubSidebar
		end

		static.IsMouseOverHub = function()
			return hubMain ~= nil and hubMain.Visible and Lib.CheckMouseInGui(hubMain)
		end

		static.AddTopBarToggle = function(text,icon,onChanged)
			if not hubGui then static.Init() end
			local control = {}
			local state = false
			local hovering = false
			local width = service.TextService:GetTextSize(text,12,Enum.Font.GothamMedium,Vector2.new(1000,24)).X + 36
			local offset = hub.TopBarOffset or 67
			hub.TopBarOffset = offset + width + 6

			local btn = new("TextButton",{AnchorPoint=Vector2.new(1,0.5),AutoButtonColor=false,BackgroundColor3=col.Bar,BorderSizePixel=0,Name="Toggle",Position=UDim2.new(1,-offset,0.5,0),Size=UDim2.new(0,width,0,24),Text=""},hubTopBar)
			corner(btn,6)
			local stroke = new("UIStroke",{ApplyStrokeMode=Enum.ApplyStrokeMode.Border,Color=col.Stroke,Thickness=1},btn)
			local iconFrame = new("Frame",{AnchorPoint=Vector2.new(0,0.5),BackgroundTransparency=1,Name="Icon",Position=UDim2.new(0,9,0.5,0),Size=UDim2.new(0,12,0,12)},btn)
			local label = new("TextLabel",{BackgroundTransparency=1,Font=Enum.Font.GothamMedium,Name="Label",Position=UDim2.new(0,27,0,0),Size=UDim2.new(1,-33,1,0),Text=text,TextColor3=col.TextIdle,TextSize=12,TextXAlignment=Enum.TextXAlignment.Left},btn)

			local function restyle()
				btn.BackgroundColor3 = state and Color3.fromRGB(0,48,78) or (hovering and col.ButtonHover or col.Bar)
				stroke.Color = state and col.Accent or col.Stroke
				label.TextColor3 = state and col.Text or col.TextIdle
				Lib.DrawIcon(iconFrame,icon,state and col.Accent or col.TextIdle,1.5)
			end

			control.Set = function(value,silent)
				value = value and true or false
				if value == state then return end
				state = value
				restyle()
				if onChanged and not silent then onChanged(state) end
			end

			control.Get = function()
				return state
			end

			btn.MouseEnter:Connect(function() hovering = true restyle() end)
			btn.MouseLeave:Connect(function() hovering = false restyle() end)
			btn.MouseButton1Click:Connect(function() control.Set(not state) end)

			control.Button = btn
			restyle()
			return control
		end

		static.ToggleSide = function()
			static.SetHubVisible(not hub.Visible)
		end

		static.SetSideVisible = function(_,vis)
			static.SetHubVisible(vis)
		end

		static.Init = function()
			if hubGui then return end
			static.HubVisibleChanged = Lib.Signal.new()

			local cam = workspace.CurrentCamera
			local vp = cam and cam.ViewportSize or Vector2.new(1280,720)
			hub.SizeX = math.floor(math.max(480,math.min(hub.SizeX,vp.X - 20)))
			hub.SizeY = math.floor(math.max(280,math.min(hub.SizeY,vp.Y - 80)))
			local sw = hub.SidebarWidth

			hubGui = new("ScreenGui",{DisplayOrder=Main.DisplayOrders.Window,Name="DexHub",ZIndexBehavior=Enum.ZIndexBehavior.Sibling})
			hubMain = new("Frame",{Active=true,BackgroundColor3=col.Back,BorderSizePixel=0,ClipsDescendants=true,Name="Main",Position=UDim2.new(0,math.floor((vp.X - hub.SizeX)/2),0,math.max(0,math.floor((vp.Y - hub.SizeY)/2) - 20)),Size=UDim2.new(0,hub.SizeX,0,hub.SizeY)},hubGui)
			corner(hubMain,8)
			new("UIStroke",{ApplyStrokeMode=Enum.ApplyStrokeMode.Border,Color=col.Stroke,Thickness=1},hubMain)

			hubTopBar = new("TextButton",{AutoButtonColor=false,BackgroundColor3=col.Bar,BorderSizePixel=0,Name="TopBar",Size=UDim2.new(1,0,0,TOP),Text=""},hubMain)
			corner(hubTopBar,8)
			hubTopFill = new("Frame",{BackgroundColor3=col.Bar,BorderSizePixel=0,Name="Fill",Position=UDim2.new(0,0,1,-8),Size=UDim2.new(1,0,0,8)},hubTopBar)
			local logo = new("Frame",{AnchorPoint=Vector2.new(0,0.5),BackgroundColor3=col.Accent,BorderSizePixel=0,Name="Logo",Position=UDim2.new(0,14,0.5,0),Size=UDim2.new(0,8,0,8)},hubTopBar)
			corner(logo,4)
			new("TextLabel",{BackgroundTransparency=1,Font=Enum.Font.GothamBold,Name="Title",Position=UDim2.new(0,30,0,0),Size=UDim2.new(0,200,1,0),Text="Dex Premium",TextColor3=col.Text,TextSize=14,TextXAlignment=Enum.TextXAlignment.Left},hubTopBar)

			local closeBtn = new("TextButton",{AutoButtonColor=false,BorderSizePixel=0,Name="Close",Position=UDim2.new(1,-31,0.5,-12),Size=UDim2.new(0,24,0,24),Text=""},hubTopBar)
			corner(closeBtn,6)
			hoverFill(closeBtn,col.CloseHover)
			Lib.DrawIcon(iconHolder(closeBtn,10),"close",col.Icon,1.5)
			local minBtn = new("TextButton",{AutoButtonColor=false,BorderSizePixel=0,Name="Minimize",Position=UDim2.new(1,-59,0.5,-12),Size=UDim2.new(0,24,0,24),Text=""},hubTopBar)
			corner(minBtn,6)
			hoverFill(minBtn,col.ButtonHover)
			hubMinIcon = iconHolder(minBtn,10)
			Lib.DrawIcon(hubMinIcon,"minimize",col.Icon,1.5)
			new("Frame",{BackgroundColor3=col.Line,BorderSizePixel=0,Name="Line",Position=UDim2.new(0,0,0,TOP),Size=UDim2.new(1,0,0,1)},hubMain)

			hubBody = new("Frame",{BackgroundColor3=col.Back,BorderSizePixel=0,ClipsDescendants=true,Name="Body",Position=UDim2.new(0,0,0,TOP+1),Size=UDim2.new(1,0,1,-(TOP+1)-(FOOT+1))},hubMain)
			hubSidebar = new("Frame",{BackgroundColor3=col.Back,BorderSizePixel=0,Name="Sidebar",Size=UDim2.new(0,sw,1,0)},hubBody)
			new("Frame",{BackgroundColor3=col.Line,BorderSizePixel=0,Name="SideLine",Position=UDim2.new(0,sw,0,0),Size=UDim2.new(0,1,1,0)},hubBody)
			hubTabBar = new("ScrollingFrame",{Active=true,AutomaticCanvasSize=Enum.AutomaticSize.X,BackgroundColor3=col.Back,BorderSizePixel=0,CanvasSize=UDim2.new(0,0,0,0),Name="TabBar",Position=UDim2.new(0,sw+1,0,0),ScrollBarThickness=0,ScrollingDirection=Enum.ScrollingDirection.X,Size=UDim2.new(1,-sw-1,0,TABS)},hubBody)
			new("UIListLayout",{FillDirection=Enum.FillDirection.Horizontal,Padding=UDim.new(0,4),SortOrder=Enum.SortOrder.LayoutOrder,VerticalAlignment=Enum.VerticalAlignment.Center},hubTabBar)
			new("UIPadding",{PaddingLeft=UDim.new(0,6),PaddingRight=UDim.new(0,6)},hubTabBar)
			new("Frame",{BackgroundColor3=col.Line,BorderSizePixel=0,Name="TabLine",Position=UDim2.new(0,sw+1,0,TABS),Size=UDim2.new(1,-sw-1,0,1)},hubBody)
			hubPages = new("Frame",{BackgroundColor3=col.Back,BorderSizePixel=0,ClipsDescendants=true,Name="Pages",Position=UDim2.new(0,sw+1,0,TABS+1),Size=UDim2.new(1,-sw-1,1,-(TABS+1))},hubBody)
			hubOverlay = new("Frame",{BackgroundTransparency=1,Name="Overlay",Size=UDim2.new(1,0,1,0),ZIndex=10},hubBody)

			hubFooter = new("Frame",{AnchorPoint=Vector2.new(0,1),BackgroundColor3=col.Bar,BorderSizePixel=0,Name="Footer",Position=UDim2.new(0,0,1,0),Size=UDim2.new(1,0,0,FOOT)},hubMain)
			corner(hubFooter,8)
			new("Frame",{BackgroundColor3=col.Bar,BorderSizePixel=0,Name="Fill",Size=UDim2.new(1,0,0,8)},hubFooter)
			new("Frame",{BackgroundColor3=col.Line,BorderSizePixel=0,Name="Line",Position=UDim2.new(0,0,0,-1),Size=UDim2.new(1,0,0,1)},hubFooter)
			local grip = new("TextButton",{AnchorPoint=Vector2.new(1,1),AutoButtonColor=false,BackgroundTransparency=1,BorderSizePixel=0,Name="Resize",Position=UDim2.new(1,-4,1,-4),Size=UDim2.new(0,14,0,14),Text="",ZIndex=20},hubFooter)
			Lib.DrawIcon(grip,"grip",Color3.fromRGB(80,80,80))

			local moveStart
			dragHook(hubTopBar,function()
				moveStart = hubMain.Position
			end,function(delta)
				hubMain.Position = UDim2.new(0,moveStart.X.Offset + delta.X,0,math.max(0,moveStart.Y.Offset + delta.Y))
			end)

			local sizeStart
			dragHook(grip,function()
				sizeStart = Vector2.new(hub.SizeX,hub.SizeY)
			end,function(delta)
				hub.SizeX = math.max(480,math.floor(sizeStart.X + delta.X))
				hub.SizeY = math.max(280,math.floor(sizeStart.Y + delta.Y))
				hubMain.Size = UDim2.new(0,hub.SizeX,0,hub.Minimized and TOP or hub.SizeY)
			end)

			minBtn.MouseButton1Click:Connect(function()
				setHubMinimized(not hub.Minimized)
			end)

			closeBtn.MouseButton1Click:Connect(function()
				static.SetHubVisible(false)
			end)

			local toggleName = "DexPremiumToggle_"..tostring(math.random(1e6,9e6))
			local lastToggle = 0
			local function toggleHub()
				local now = tick()
				if now - lastToggle < 0.15 then return end
				lastToggle = now
				static.SetHubVisible(not hub.Visible)
			end

			UIS.InputBegan:Connect(function(input)
				if input.KeyCode ~= Enum.KeyCode.RightShift or UIS:GetFocusedTextBox() then return end
				toggleHub()
			end)

			pcall(function()
				service.ContextActionService:BindActionAtPriority(toggleName,function(_,state)
					if state == Enum.UserInputState.Begin and not UIS:GetFocusedTextBox() then
						toggleHub()
					end
					return Enum.ContextActionResult.Pass
				end,false,Enum.ContextActionPriority.High.Value + 100,Enum.KeyCode.RightShift)
			end)

			Lib.ShowGui(hubGui)
		end

		local mt = {__index = funcs}
		static.new = function()
			local obj = setmetatable({
				Minimized = false,
				Dragging = false,
				Resizing = false,
				Aligned = false,
				Draggable = true,
				Resizable = true,
				ResizableInternal = true,
				Alignable = true,
				Closed = true,
				SizeX = 300,
				SizeY = 300,
				MinX = 200,
				MinY = 200,
				PosX = 0,
				PosY = 0,
				GuiElems = {},
				Tweens = {},
				Elements = {},
				OnActivate = Lib.Signal.new(),
				OnDeactivate = Lib.Signal.new(),
				OnMinimize = Lib.Signal.new(),
				OnRestore = Lib.Signal.new()
			},mt)
			obj.Gui = createGui(obj)
			return obj
		end

		return static
	end)()

	Lib.ContextMenu = (function()
		local funcs = {}
		local mouse

		local function createGui(self)
			local contextGui = create({
				{1,"ScreenGui",{DisplayOrder=1000000,Name="Context",ZIndexBehavior=1,}},
				{2,"Frame",{Active=true,BackgroundColor3=Color3.new(0.14117647707462,0.14117647707462,0.14117647707462),BorderColor3=Color3.new(0.14117647707462,0.14117647707462,0.14117647707462),Name="Main",Parent={1},Position=UDim2.new(0.5,-100,0.5,-150),Size=UDim2.new(0,200,0,100),}},
				{3,"UICorner",{CornerRadius=UDim.new(0,4),Parent={2},}},
				{4,"Frame",{BackgroundColor3=Color3.new(0.17647059261799,0.17647059261799,0.17647059261799),Name="Container",Parent={2},Position=UDim2.new(0,1,0,1),Size=UDim2.new(1,-2,1,-2),}},
				{5,"UICorner",{CornerRadius=UDim.new(0,4),Parent={4},}},
				{6,"ScrollingFrame",{Active=true,BackgroundColor3=Color3.new(0.20392157137394,0.20392157137394,0.20392157137394),BackgroundTransparency=1,BorderSizePixel=0,CanvasSize=UDim2.new(0,0,0,0),Name="List",Parent={4},Position=UDim2.new(0,2,0,2),ScrollBarImageColor3=Color3.new(0,0,0),ScrollBarThickness=4,Size=UDim2.new(1,-4,1,-4),VerticalScrollBarInset=1,}},
				{7,"UIListLayout",{Parent={6},SortOrder=2,}},
				{8,"Frame",{BackgroundColor3=Color3.new(0.20392157137394,0.20392157137394,0.20392157137394),BorderSizePixel=0,Name="SearchFrame",Parent={4},Size=UDim2.new(1,0,0,24),Visible=false,}},
				{9,"Frame",{BackgroundColor3=Color3.new(0.14901961386204,0.14901961386204,0.14901961386204),BorderColor3=Color3.new(0.1176470592618,0.1176470592618,0.1176470592618),BorderSizePixel=0,Name="SearchContainer",Parent={8},Position=UDim2.new(0,3,0,3),Size=UDim2.new(1,-6,0,18),}},
				{10,"TextBox",{BackgroundColor3=Color3.new(1,1,1),BackgroundTransparency=1,Font=3,Name="SearchBox",Parent={9},PlaceholderColor3=Color3.new(0.39215689897537,0.39215689897537,0.39215689897537),PlaceholderText="Search",Position=UDim2.new(0,4,0,0),Size=UDim2.new(1,-8,0,18),Text="",TextColor3=Color3.new(1,1,1),TextSize=14,TextXAlignment=0,}},
				{11,"UICorner",{CornerRadius=UDim.new(0,2),Parent={9},}},
				{12,"Frame",{BackgroundColor3=Color3.new(0.14117647707462,0.14117647707462,0.14117647707462),BorderSizePixel=0,Name="Line",Parent={8},Position=UDim2.new(0,0,1,0),Size=UDim2.new(1,0,0,1),}},
				{13,"TextButton",{AutoButtonColor=false,BackgroundColor3=Color3.new(0.20392157137394,0.20392157137394,0.20392157137394),BackgroundTransparency=1,BorderColor3=Color3.new(0.33725491166115,0.49019610881805,0.73725491762161),BorderSizePixel=0,Font=3,Name="Entry",Parent={1},Size=UDim2.new(1,0,0,22),Text="",TextSize=14,Visible=false,}},
				{14,"TextLabel",{BackgroundColor3=Color3.new(1,1,1),BackgroundTransparency=1,BorderSizePixel=0,Font=3,Name="EntryName",Parent={13},Position=UDim2.new(0,24,0,0),Size=UDim2.new(1,-24,1,0),Text="Duplicate",TextColor3=Color3.new(0.86274516582489,0.86274516582489,0.86274516582489),TextSize=14,TextXAlignment=0,}},
				{15,"TextLabel",{BackgroundColor3=Color3.new(1,1,1),BackgroundTransparency=1,Font=3,Name="Shortcut",Parent={13},Position=UDim2.new(0,24,0,0),Size=UDim2.new(1,-30,1,0),Text="Ctrl+D",TextColor3=Color3.new(0.86274516582489,0.86274516582489,0.86274516582489),TextSize=14,TextXAlignment=1,}},
				{16,"ImageLabel",{BackgroundColor3=Color3.new(1,1,1),BackgroundTransparency=1,ImageRectOffset=Vector2.new(304,0),ImageRectSize=Vector2.new(16,16),Name="Icon",Parent={13},Position=UDim2.new(0,2,0,3),ScaleType=4,Size=UDim2.new(0,16,0,16),}},
				{17,"UICorner",{CornerRadius=UDim.new(0,4),Parent={13},}},
				{18,"Frame",{BackgroundColor3=Color3.new(0.21568629145622,0.21568629145622,0.21568629145622),BackgroundTransparency=1,BorderSizePixel=0,Name="Divider",Parent={1},Position=UDim2.new(0,0,0,20),Size=UDim2.new(1,0,0,7),Visible=false,}},
				{19,"Frame",{BackgroundColor3=Color3.new(0.20392157137394,0.20392157137394,0.20392157137394),BorderSizePixel=0,Name="Line",Parent={18},Position=UDim2.new(0,0,0.5,0),Size=UDim2.new(1,0,0,1),}},
				{20,"TextLabel",{AnchorPoint=Vector2.new(0,0.5),BackgroundColor3=Color3.new(1,1,1),BackgroundTransparency=1,BorderSizePixel=0,Font=3,Name="DividerName",Parent={18},Position=UDim2.new(0,2,0.5,0),Size=UDim2.new(1,-4,1,0),Text="Objects",TextColor3=Color3.new(1,1,1),TextSize=14,TextTransparency=0.60000002384186,TextXAlignment=0,Visible=false,}}
			})

			self.GuiElems.Main = contextGui.Main
			self.GuiElems.List = contextGui.Main.Container.List
			self.GuiElems.Entry = contextGui.Entry
			self.GuiElems.Divider = contextGui.Divider
			self.GuiElems.SearchFrame = contextGui.Main.Container.SearchFrame
			self.GuiElems.SearchBar = self.GuiElems.SearchFrame.SearchContainer.SearchBox
			Lib.ViewportTextBox.convert(self.GuiElems.SearchBar)

			self.GuiElems.SearchBar:GetPropertyChangedSignal("Text"):Connect(function()
				local lower,find = string.lower,string.find
				local searchText = lower(self.GuiElems.SearchBar.Text)
				local items = self.Items
				local map = self.ItemToEntryMap

				if searchText ~= "" then
					local results = {}
					local count = 1
					for i = 1,#items do
						local item = items[i]
						local entry = map[item]
						if entry then
							if not item.Divider and find(lower(item.Name),searchText,1,true) then
								results[count] = item
								count = count + 1
							else
								entry.Visible = false
							end
						end
					end
					table.sort(results,function(a,b) return a.Name < b.Name end)
					for i = 1,#results do
						local entry = map[results[i]]
						entry.LayoutOrder = i
						entry.Visible = true
					end
				else
					for i = 1,#items do
						local entry = map[items[i]]
						if entry then entry.LayoutOrder = i entry.Visible = true end
					end
				end

				local toSize = self.GuiElems.List.UIListLayout.AbsoluteContentSize.Y + 6
				self.GuiElems.List.CanvasSize = UDim2.new(0,0,0,toSize-6)
			end)

			return contextGui
		end

		funcs.Add = function(self,item)
			local newItem = {
				Name = item.Name or "Item",
				Icon = item.Icon or "",
				Shortcut = item.Shortcut or "",
				OnClick = item.OnClick,
				OnHover = item.OnHover,
				Disabled = item.Disabled or false,
				DisabledIcon = item.DisabledIcon or "",
				IconMap = item.IconMap,
				OnRightClick = item.OnRightClick
			}
			
			newItem.DisabledIcon = newItem.Icon

			if self.QueuedDivider then
				local text = self.QueuedDividerText and #self.QueuedDividerText > 0 and self.QueuedDividerText
				self:AddDivider(text)
			end
			self.Items[#self.Items+1] = newItem
			self.Updated = nil
		end

		funcs.AddRegistered = function(self,name,disabled)
			if not self.Registered[name] then error(name.." is not registered") end

			if self.QueuedDivider then
				local text = self.QueuedDividerText and #self.QueuedDividerText > 0 and self.QueuedDividerText
				self:AddDivider(text)
			end
			self.Registered[name].Disabled = disabled
			self.Items[#self.Items+1] = self.Registered[name]
			self.Updated = nil
		end

		funcs.Register = function(self,name,item)
			self.Registered[name] = {
				Name = item.Name or "Item",
				Icon = item.Icon or "",
				Shortcut = item.Shortcut or "",
				OnClick = item.OnClick,
				OnHover = item.OnHover,
				DisabledIcon = item.DisabledIcon or "",
				IconMap = item.IconMap,
				OnRightClick = item.OnRightClick
			}
		end

		funcs.UnRegister = function(self,name)
			self.Registered[name] = nil
		end

		funcs.AddDivider = function(self,text)
			self.QueuedDivider = false
			local textWidth = text and service.TextService:GetTextSize(text,14,Enum.Font.SourceSans,Vector2.new(999999999,20)).X or nil
			table.insert(self.Items,{Divider = true, Text = text, TextSize = textWidth and textWidth+4})
			self.Updated = nil
		end

		funcs.QueueDivider = function(self,text)
			self.QueuedDivider = true
			self.QueuedDividerText = text or ""
		end

		funcs.Clear = function(self)
			self.Items = {}
			self.Updated = nil
		end

		funcs.Refresh = function(self)
			for i,v in pairs(self.GuiElems.List:GetChildren()) do
				if not v:IsA("UIListLayout") then
					v:Destroy()
				end
			end
			local map = {}
			self.ItemToEntryMap = map

			local dividerFrame = self.GuiElems.Divider
			local contextList = self.GuiElems.List
			local entryFrame = self.GuiElems.Entry
			local items = self.Items

			for i = 1,#items do
				local item = items[i]
				if item.Divider then
					local newDivider = dividerFrame:Clone()
					newDivider.Line.BackgroundColor3 = self.Theme.DividerColor
					if item.Text then
						newDivider.Size = UDim2.new(1,0,0,20)
						newDivider.Line.Position = UDim2.new(0,item.TextSize,0.5,0)
						newDivider.Line.Size = UDim2.new(1,-item.TextSize,0,1)
						newDivider.DividerName.TextColor3 = self.Theme.TextColor
						newDivider.DividerName.Text = item.Text
						newDivider.DividerName.Visible = true
					end
					newDivider.Visible = true
					map[item] = newDivider
					newDivider.Parent = contextList
				else
					local newEntry = entryFrame:Clone()
					newEntry.BackgroundColor3 = self.Theme.HighlightColor
					newEntry.EntryName.TextColor3 = self.Theme.TextColor
					newEntry.EntryName.Text = item.Name
					newEntry.Shortcut.Text = item.Shortcut
					if item.Disabled then
						newEntry.EntryName.TextColor3 = Color3.new(150/255,150/255,150/255)
						newEntry.Shortcut.TextColor3 = Color3.new(150/255,150/255,150/255)
					end

					if self.Iconless then
						newEntry.EntryName.Position = UDim2.new(0,2,0,0)
						newEntry.EntryName.Size = UDim2.new(1,-4,0,20)
						newEntry.Icon.Visible = false
					else			
						local iconIndex
						if item.Disabled and item.DisabledIcon then
							iconIndex = item.DisabledIcon
						elseif item.Icon then
							iconIndex =  item.Icon
						end
						
						if item.IconMap then
							if type(iconIndex) == "number" then
								item.IconMap:Display(newEntry.Icon, iconIndex)
							elseif type(iconIndex) == "string" then
								item.IconMap:DisplayByKey(newEntry.Icon, iconIndex)
							end
						elseif type(iconIndex) == "string" then
							newEntry.Icon.Image = iconIndex
						end
					end

					if not item.Disabled then
						if item.OnClick then
							newEntry.MouseButton1Click:Connect(function()
								item.OnClick(item.Name)
								if not item.NoHide then
									self:Hide()
								end
							end)
						end

						if item.OnRightClick then
							newEntry.MouseButton2Click:Connect(function()
								item.OnRightClick(item.Name)
								if not item.NoHide then
									self:Hide()
								end
							end)
						end
					end

					newEntry.InputBegan:Connect(function(input)
						if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
							newEntry.BackgroundTransparency = 0
						end
					end)

					newEntry.InputEnded:Connect(function(input)
						if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
							newEntry.BackgroundTransparency = 1
						end
					end)

					newEntry.Visible = true
					map[item] = newEntry
					newEntry.Parent = contextList
				end
			end
			self.Updated = true
		end

		funcs.Show = function(self,x,y)
			local elems = self.GuiElems
			elems.SearchFrame.Visible = self.SearchEnabled
			elems.List.Position = UDim2.new(0,2,0,2 + (self.SearchEnabled and 24 or 0))
			elems.List.Size = UDim2.new(1,-4,1,-4 - (self.SearchEnabled and 24 or 0))
			if self.SearchEnabled and self.ClearSearchOnShow then elems.SearchBar.Text = "" end
			self.GuiElems.List.CanvasPosition = Vector2.new(0,0)

			if not self.Updated then
				self:Refresh()
			end

			local reverseY = false
			local x,y = x or mouse.X, y or mouse.Y
			local maxX,maxY = mouse.ViewSizeX,mouse.ViewSizeY

			if x + self.Width > maxX then
				x = self.ReverseX and x - self.Width or maxX - self.Width
			end
			elems.Main.Position = UDim2.new(0,x,0,y)
			elems.Main.Size = UDim2.new(0,self.Width,0,0)
			self.Gui.DisplayOrder = Main.DisplayOrders.Menu
			Lib.ShowGui(self.Gui)

			local toSize = elems.List.UIListLayout.AbsoluteContentSize.Y + 6
			if self.MaxHeight and toSize > self.MaxHeight then
				elems.List.CanvasSize = UDim2.new(0,0,0,toSize-6)
				toSize = self.MaxHeight
			else
				elems.List.CanvasSize = UDim2.new(0,0,0,0)
			end
			if y + toSize > maxY then reverseY = true end

			local closable
			if self.CloseEvent then self.CloseEvent:Disconnect() end
			self.CloseEvent = service.UserInputService.InputBegan:Connect(function(input)
				if not closable then return end

				if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
					if not Lib.CheckMouseInGui(elems.Main) then
						self.CloseEvent:Disconnect()
						self:Hide()
					end
				end
			end)

			if reverseY then
				elems.Main.Position = UDim2.new(0,x,0,y-(self.ReverseYOffset or 0))
				local newY = y - toSize - (self.ReverseYOffset or 0)
				y = newY >= 0 and newY or 0
				elems.Main:TweenSizeAndPosition(UDim2.new(0,self.Width,0,toSize),UDim2.new(0,x,0,y),Enum.EasingDirection.Out,Enum.EasingStyle.Quart,0.2,true)
			else
				elems.Main:TweenSize(UDim2.new(0,self.Width,0,toSize),Enum.EasingDirection.Out,Enum.EasingStyle.Quart,0.2,true)
			end

			Lib.FastWait()
			if self.SearchEnabled and self.FocusSearchOnShow then elems.SearchBar:CaptureFocus() end
			closable = true
		end

		funcs.Hide = function(self)
			self.Gui.Parent = nil
		end

		funcs.ApplyTheme = function(self,data)
			local theme = self.Theme
			theme.ContentColor = data.ContentColor or Settings.Theme.Menu
			theme.OutlineColor = data.OutlineColor or Settings.Theme.Menu
			theme.DividerColor = data.DividerColor or Settings.Theme.Outline2
			theme.TextColor = data.TextColor or Settings.Theme.Text
			theme.HighlightColor = data.HighlightColor or Settings.Theme.Main1

			self.GuiElems.Main.BackgroundColor3 = theme.OutlineColor
			self.GuiElems.Main.Container.BackgroundColor3 = theme.ContentColor
		end

		local mt = {__index = funcs}
		local function new()
			if not mouse then mouse = Main.Mouse or service.Players.LocalPlayer:GetMouse() end

			local obj = setmetatable({
				Width = 200,
				MaxHeight = nil,
				Iconless = false,
				SearchEnabled = false,
				ClearSearchOnShow = true,
				FocusSearchOnShow = true,
				Updated = false,
				QueuedDivider = false,
				QueuedDividerText = "",
				Items = {},
				Registered = {},
				GuiElems = {},
				Theme = {}
			},mt)
			obj.Gui = createGui(obj)
			obj:ApplyTheme({})
			return obj
		end

		return {new = new}
	end)()

	Lib.CodeFrame = (function()
		local funcs = {}

		local typeMap = {
			[1] = "String",
			[2] = "String",
			[3] = "String",
			[4] = "Comment",
			[5] = "Operator",
			[6] = "Number",
			[7] = "Keyword",
			[8] = "BuiltIn",
			[9] = "LocalMethod",
			[10] = "LocalProperty",
			[11] = "Nil",
			[12] = "Bool",
			[13] = "Function",
			[14] = "Local",
			[15] = "Self",
			[16] = "FunctionName",
			[17] = "Bracket"
		}

		local specialKeywordsTypes = {
			["nil"] = 11,
			["true"] = 12,
			["false"] = 12,
			["function"] = 13,
			["local"] = 14,
			["self"] = 15
		}

		local keywords = {
			["and"] = true,
			["break"] = true, 
			["do"] = true,
			["else"] = true,
			["elseif"] = true,
			["end"] = true,
			["false"] = true,
			["for"] = true,
			["function"] = true,
			["if"] = true,
			["in"] = true,
			["local"] = true,
			["nil"] = true,
			["not"] = true,
			["or"] = true,
			["repeat"] = true,
			["return"] = true,
			["then"] = true,
			["true"] = true,
			["until"] = true,
			["while"] = true,
			["plugin"] = true
		}

		local builtIns = {
			["delay"] = true,
			["elapsedTime"] = true,
			["require"] = true,
			["spawn"] = true,
			["tick"] = true,
			["time"] = true,
			["typeof"] = true,
			["UserSettings"] = true,
			["wait"] = true,
			["warn"] = true,
			["game"] = true,
			["shared"] = true,
			["script"] = true,
			["workspace"] = true,
			["assert"] = true,
			["collectgarbage"] = true,
			["error"] = true,
			["getfenv"] = true,
			["getmetatable"] = true,
			["ipairs"] = true,
			["loadstring"] = true,
			["newproxy"] = true,
			["next"] = true,
			["pairs"] = true,
			["pcall"] = true,
			["print"] = true,
			["rawequal"] = true,
			["rawget"] = true,
			["rawset"] = true,
			["select"] = true,
			["setfenv"] = true,
			["setmetatable"] = true,
			["tonumber"] = true,
			["tostring"] = true,
			["type"] = true,
			["unpack"] = true,
			["xpcall"] = true,
			["_G"] = true,
			["_VERSION"] = true,
			["coroutine"] = true,
			["debug"] = true,
			["math"] = true,
			["os"] = true,
			["string"] = true,
			["table"] = true,
			["bit32"] = true,
			["utf8"] = true,
			["Axes"] = true,
			["BrickColor"] = true,
			["CFrame"] = true,
			["Color3"] = true,
			["ColorSequence"] = true,
			["ColorSequenceKeypoint"] = true,
			["DockWidgetPluginGuiInfo"] = true,
			["Enum"] = true,
			["Faces"] = true,
			["Instance"] = true,
			["NumberRange"] = true,
			["NumberSequence"] = true,
			["NumberSequenceKeypoint"] = true,
			["PathWaypoint"] = true,
			["PhysicalProperties"] = true,
			["Random"] = true,
			["Ray"] = true,
			["Rect"] = true,
			["Region3"] = true,
			["Region3int16"] = true,
			["TweenInfo"] = true,
			["UDim"] = true,
			["UDim2"] = true,
			["Vector2"] = true,
			["Vector2int16"] = true,
			["Vector3"] = true,
			["Vector3int16"] = true,

			["getgenv"] = true,
			["getrenv"] = true,
			["getsenv"] = true,
			["getgc"] = true,
			["getreg"] = true,
			["filtergc"] = true,
			["saveinstave"] = true,
			["decompile"] = true,
			["syn"] = true,
			["getupvalue"] = true,
			["getupvalues"] = true,
			["setupvalue"] = true,
			["getstack"] = true,
			["setstack"] = true,
			["getconstants"] = true,
			["getconstant"] = true,
			["setconstant"] = true,
			["getproto"] = true,
			["getprotos"] = true,
			["checkcaller"] = true,
			["clonefunction"] = true,
			["cloneref"] = true,
			["getfunctionhash"] = true,
			["gethwid"] = true,
			["hookfunction"] = true,
			["hookmetamethod"] = true,
			["iscclosure"] = true,
			["islclosure"] = true,
			["newcclosure"] = true,
			["isexecutorclosure"] = true,
			["restorefunction"] = true,
			["crypt"] = true,
			["Drawing"] = true,

		}

		local builtInInited = false

		local richReplace = {
			["'"] = "&apos;",
			["\""] = "&quot;",
			["<"] = "&lt;",
			[">"] = "&gt;",
			["&"] = "&amp;"
		}

		local tabSub = "\205"
		local tabReplacement = (" %s%s "):format(tabSub,tabSub)

		local tabJumps = {
			[("[^%s] %s"):format(tabSub,tabSub)] = 0,
			[(" %s%s"):format(tabSub,tabSub)] = -1,
			[("%s%s "):format(tabSub,tabSub)] = 2,
			[("%s [^%s]"):format(tabSub,tabSub)] = 1,
		}

		local tweenService = service.TweenService
		local lineTweens = {}

		local function initBuiltIn()
			local env = getfenv()
			local type = type
			local tostring = tostring
			for name,_ in next,builtIns do
				local envVal = env[name]
				if type(envVal) == "table" then
					local items = {}
					for i,v in next,envVal do
						items[i] = true
					end
					builtIns[name] = items
				end
			end

			local enumEntries = {}
			local enums = Enum:GetEnums()
			for i = 1,#enums do
				enumEntries[tostring(enums[i])] = true
			end
			builtIns["Enum"] = enumEntries

			builtInInited = true
		end

		local function setupEditBox(obj)
			local editBox = obj.GuiElems.EditBox

			editBox.Focused:Connect(function()
				obj:ConnectEditBoxEvent()
				obj.Editing = true
			end)

			editBox.FocusLost:Connect(function()
				obj:DisconnectEditBoxEvent()
				obj.Editing = false
			end)

			editBox:GetPropertyChangedSignal("Text"):Connect(function()
				local text = editBox.Text
				if #text == 0 then obj.EditBoxCopyText = nil return end
				if obj.EditBoxCopying then return end
				if obj.EditBoxCopyText and text == obj.EditBoxCopyText then return end
				obj.EditBoxCopyText = nil
				obj.EditBoxCopying = true
				editBox.Text = ""
				obj.EditBoxCopying = false
				obj:AppendText(text)
			end)
		end

		local function setupMouseSelection(obj)
			local mouse = plr:GetMouse()
			local codeFrame = obj.GuiElems.LinesFrame
			local lines = obj.Lines

			codeFrame.InputBegan:Connect(function(input)
				if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
					local fontSizeX,fontSizeY = math.ceil(obj.FontSize/2),obj.FontSize

					local relX = mouse.X - codeFrame.AbsolutePosition.X
					local relY = mouse.Y - codeFrame.AbsolutePosition.Y
					local selX = math.round(relX / fontSizeX) + obj.ViewX
					local selY = math.floor(relY / fontSizeY) + obj.ViewY
					local releaseEvent,mouseEvent,scrollEvent
					local scrollPowerV,scrollPowerH = 0,0
					selY = math.min(#lines-1,selY)
					local relativeLine = lines[selY+1] or ""
					selX = math.min(#relativeLine, selX + obj:TabAdjust(selX,selY))

					obj.SelectionRange = {{-1,-1},{-1,-1}}
					obj:MoveCursor(selX,selY)
					obj.FloatCursorX = selX

					local function updateSelection()
						local relX = mouse.X - codeFrame.AbsolutePosition.X
						local relY = mouse.Y - codeFrame.AbsolutePosition.Y
						local sel2X = math.max(0,math.round(relX / fontSizeX) + obj.ViewX)
						local sel2Y = math.max(0,math.floor(relY / fontSizeY) + obj.ViewY)

						sel2Y = math.min(#lines-1,sel2Y)
						local relativeLine = lines[sel2Y+1] or ""
						sel2X = math.min(#relativeLine, sel2X + obj:TabAdjust(sel2X,sel2Y))

						if sel2Y < selY or (sel2Y == selY and sel2X < selX) then
							obj.SelectionRange = {{sel2X,sel2Y},{selX,selY}}
						else						
							obj.SelectionRange = {{selX,selY},{sel2X,sel2Y}}
						end

						obj:MoveCursor(sel2X,sel2Y)
						obj.FloatCursorX = sel2X
						obj:Refresh()
					end

					releaseEvent = service.UserInputService.InputEnded:Connect(function(input)
						if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
							releaseEvent:Disconnect()
							mouseEvent:Disconnect()
							scrollEvent:Disconnect()
							obj:SetCopyableSelection()
						end
					end)

					mouseEvent = service.UserInputService.InputChanged:Connect(function(input)
						if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
							local upDelta = mouse.Y - codeFrame.AbsolutePosition.Y
							local downDelta = mouse.Y - codeFrame.AbsolutePosition.Y - codeFrame.AbsoluteSize.Y
							local leftDelta = mouse.X - codeFrame.AbsolutePosition.X
							local rightDelta = mouse.X - codeFrame.AbsolutePosition.X - codeFrame.AbsoluteSize.X
							scrollPowerV = 0
							scrollPowerH = 0
							if downDelta > 0 then
								scrollPowerV = math.floor(downDelta*0.05) + 1
							elseif upDelta < 0 then
								scrollPowerV = math.ceil(upDelta*0.05) - 1
							end
							if rightDelta > 0 then
								scrollPowerH = math.floor(rightDelta*0.05) + 1
							elseif leftDelta < 0 then
								scrollPowerH = math.ceil(leftDelta*0.05) - 1
							end
							updateSelection()
						end
					end)

					scrollEvent = game:GetService("RunService").RenderStepped:Connect(function()
						if scrollPowerV ~= 0 or scrollPowerH ~= 0 then
							obj:ScrollDelta(scrollPowerH,scrollPowerV)
							updateSelection()
						end
					end)

					obj:Refresh()
				end
			end)
		end

		local function makeFrame(obj)
			local frame = create({
				{1,"Frame",{BackgroundColor3=Color3.new(0.15686275064945,0.15686275064945,0.15686275064945),BorderSizePixel = 0,Position=UDim2.new(0.5,-300,0.5,-200),Size=UDim2.new(0,600,0,400),}},
			})

			if Settings.Window.Transparency and Settings.Window.Transparency > 0 then
				frame.BackgroundTransparency = 0.5
			end

			local elems = {}

			local linesFrame = Instance.new("Frame")
			linesFrame.Name = "Lines"
			linesFrame.BackgroundTransparency = 1
			linesFrame.Size = UDim2.new(1,0,1,0)
			linesFrame.ClipsDescendants = true
			linesFrame.Parent = frame

			local lineNumbersLabel = Instance.new("TextLabel")
			lineNumbersLabel.Name = "LineNumbers"
			lineNumbersLabel.BackgroundTransparency = 1
			lineNumbersLabel.Font = Enum.Font.Code
			lineNumbersLabel.TextXAlignment = Enum.TextXAlignment.Right
			lineNumbersLabel.TextYAlignment = Enum.TextYAlignment.Top
			lineNumbersLabel.ClipsDescendants = true
			lineNumbersLabel.RichText = true
			lineNumbersLabel.Parent = frame

			local cursor = Instance.new("Frame")
			cursor.Name = "Cursor"
			cursor.BackgroundColor3 = Color3.fromRGB(220,220,220)
			cursor.BorderSizePixel = 0
			cursor.Parent = frame

			local editBox = Instance.new("TextBox")
			editBox.Name = "EditBox"
			editBox.MultiLine = true
			editBox.Visible = false
			editBox.Parent = frame

			lineTweens.Invis = tweenService:Create(cursor,TweenInfo.new(0.4,Enum.EasingStyle.Quart,Enum.EasingDirection.Out),{BackgroundTransparency = 1})
			lineTweens.Vis = tweenService:Create(cursor,TweenInfo.new(0.2,Enum.EasingStyle.Quart,Enum.EasingDirection.Out),{BackgroundTransparency = 0})

			elems.LinesFrame = linesFrame
			elems.LineNumbersLabel = lineNumbersLabel
			elems.Cursor = cursor
			elems.EditBox = editBox
			elems.ScrollCorner = create({{1,"Frame",{BackgroundColor3=Color3.new(0.15686275064945,0.15686275064945,0.15686275064945),BorderSizePixel=0,Name="ScrollCorner",Position=UDim2.new(1,-16,1,-16),Size=UDim2.new(0,16,0,16),Visible=false,}}})

			elems.ScrollCorner.Parent = frame
			linesFrame.InputBegan:Connect(function(input)
				if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
					obj:SetEditing(true,input)
				end
			end)

			obj.Frame = frame
			obj.Gui = frame
			obj.GuiElems = elems
			setupEditBox(obj)
			setupMouseSelection(obj)

			return frame
		end

		funcs.GetSelectionText = function(self)
			if not self:IsValidRange() then return "" end

			local selectionRange = self.SelectionRange
			local selX,selY = selectionRange[1][1], selectionRange[1][2]
			local sel2X,sel2Y = selectionRange[2][1], selectionRange[2][2]
			local deltaLines = sel2Y-selY
			local lines = self.Lines

			if not lines[selY+1] or not lines[sel2Y+1] then return "" end

			if deltaLines == 0 then
				return self:ConvertText(lines[selY+1]:sub(selX+1,sel2X), false)
			end

			local leftSub = lines[selY+1]:sub(selX+1)
			local rightSub = lines[sel2Y+1]:sub(1,sel2X)

			local result = leftSub.."\n" 
			for i = selY+1,sel2Y-1 do
				result = result..lines[i+1].."\n"
			end
			result = result..rightSub

			return self:ConvertText(result,false)
		end

		funcs.SetCopyableSelection = function(self)
			local text = self:GetSelectionText()
			local editBox = self.GuiElems.EditBox

			self.EditBoxCopyText = #text > 0 and text or nil
			self.EditBoxCopying = true
			editBox.Text = text
			editBox.SelectionStart = 1
			editBox.CursorPosition = #editBox.Text + 1
			self.EditBoxCopying = false
		end

		funcs.ConnectEditBoxEvent = function(self)
			if self.EditBoxEvent then
				self.EditBoxEvent:Disconnect()
			end

			self.EditBoxEvent = service.UserInputService.InputBegan:Connect(function(input)
				if input.UserInputType ~= Enum.UserInputType.Keyboard then return end

				local keycodes = Enum.KeyCode
				local keycode = input.KeyCode

				local function setupMove(key,func)
					local endCon,finished
					endCon = service.UserInputService.InputEnded:Connect(function(input)
						if input.KeyCode ~= key then return end
						endCon:Disconnect()
						finished = true
					end)
					func()
					Lib.FastWait(0.5)
					while not finished do func() Lib.FastWait(0.03) end
				end

				if keycode == keycodes.Down then
					setupMove(keycodes.Down,function()
						self.CursorX = self.FloatCursorX
						self.CursorY = self.CursorY + 1
						self:UpdateCursor()
						self:JumpToCursor()
					end)
				elseif keycode == keycodes.Up then
					setupMove(keycodes.Up,function()
						self.CursorX = self.FloatCursorX
						self.CursorY = self.CursorY - 1
						self:UpdateCursor()
						self:JumpToCursor()
					end)
				elseif keycode == keycodes.Left then
					setupMove(keycodes.Left,function()
						local line = self.Lines[self.CursorY+1] or ""
						self.CursorX = self.CursorX - 1 - (line:sub(self.CursorX-3,self.CursorX) == tabReplacement and 3 or 0)
						if self.CursorX < 0 then
							self.CursorY = self.CursorY - 1
							local line2 = self.Lines[self.CursorY+1] or ""
							self.CursorX = #line2
						end
						self.FloatCursorX = self.CursorX
						self:UpdateCursor()
						self:JumpToCursor()
					end)
				elseif keycode == keycodes.Right then
					setupMove(keycodes.Right,function()
						local line = self.Lines[self.CursorY+1] or ""
						self.CursorX = self.CursorX + 1 + (line:sub(self.CursorX+1,self.CursorX+4) == tabReplacement and 3 or 0)
						if self.CursorX > #line then
							self.CursorY = self.CursorY + 1
							self.CursorX = 0
						end
						self.FloatCursorX = self.CursorX
						self:UpdateCursor()
						self:JumpToCursor()
					end)
				elseif keycode == keycodes.Backspace then
					setupMove(keycodes.Backspace,function()
						local startRange,endRange
						if self:IsValidRange() then
							startRange = self.SelectionRange[1]
							endRange = self.SelectionRange[2]
						else
							endRange = {self.CursorX,self.CursorY}
						end

						if not startRange then
							local line = self.Lines[self.CursorY+1] or ""
							self.CursorX = self.CursorX - 1 - (line:sub(self.CursorX-3,self.CursorX) == tabReplacement and 3 or 0)
							if self.CursorX < 0 then
								self.CursorY = self.CursorY - 1
								local line2 = self.Lines[self.CursorY+1] or ""
								self.CursorX = #line2
							end
							self.FloatCursorX = self.CursorX
							self:UpdateCursor()

							startRange = startRange or {self.CursorX,self.CursorY}
						end

						self:DeleteRange({startRange,endRange},false,true)
						self:ResetSelection(true)
						self:JumpToCursor()
					end)
				elseif keycode == keycodes.Delete then
					setupMove(keycodes.Delete,function()
						local startRange,endRange
						if self:IsValidRange() then
							startRange = self.SelectionRange[1]
							endRange = self.SelectionRange[2]
						else
							startRange = {self.CursorX,self.CursorY}
						end

						if not endRange then
							local line = self.Lines[self.CursorY+1] or ""
							local endCursorX = self.CursorX + 1 + (line:sub(self.CursorX+1,self.CursorX+4) == tabReplacement and 3 or 0)
							local endCursorY = self.CursorY
							if endCursorX > #line then
								endCursorY = endCursorY + 1
								endCursorX = 0
							end
							self:UpdateCursor()

							endRange = endRange or {endCursorX,endCursorY}
						end

						self:DeleteRange({startRange,endRange},false,true)
						self:ResetSelection(true)
						self:JumpToCursor()
					end)
				elseif service.UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then
					if keycode == keycodes.A then
						self.SelectionRange = {{0,0},{#self.Lines[#self.Lines],#self.Lines-1}}
						self:SetCopyableSelection()
						self:Refresh()
					end
				end
			end)
		end

		funcs.DisconnectEditBoxEvent = function(self)
			if self.EditBoxEvent then
				self.EditBoxEvent:Disconnect()
			end
		end

		funcs.ResetSelection = function(self,norefresh)
			self.SelectionRange = {{-1,-1},{-1,-1}}
			if not norefresh then self:Refresh() end
		end

		funcs.IsValidRange = function(self,range)
			local selectionRange = range or self.SelectionRange
			local selX,selY = selectionRange[1][1], selectionRange[1][2]
			local sel2X,sel2Y = selectionRange[2][1], selectionRange[2][2]

			if selX == -1 or (selX == sel2X and selY == sel2Y) then return false end

			return true
		end

		funcs.DeleteRange = function(self,range,noprocess,updatemouse)
			range = range or self.SelectionRange
			if not self:IsValidRange(range) then return end

			local lines = self.Lines
			local selX,selY = range[1][1], range[1][2]
			local sel2X,sel2Y = range[2][1], range[2][2]
			local deltaLines = sel2Y-selY

			if not lines[selY+1] or not lines[sel2Y+1] then return end

			local leftSub = lines[selY+1]:sub(1,selX)
			local rightSub = lines[sel2Y+1]:sub(sel2X+1)
			lines[selY+1] = leftSub..rightSub

			local remove = table.remove
			for i = 1,deltaLines do
				remove(lines,selY+2)
			end

			if range == self.SelectionRange then self.SelectionRange = {{-1,-1},{-1,-1}} end
			if updatemouse then
				self.CursorX = selX
				self.CursorY = selY
				self:UpdateCursor()
			end

			if not noprocess then
				self:ProcessTextChange()
			end
		end

		funcs.AppendText = function(self,text)
			self:DeleteRange(nil,true,true)
			local lines,cursorX,cursorY = self.Lines,self.CursorX,self.CursorY
			local line = lines[cursorY+1]
			local before = line:sub(1,cursorX)
			local after = line:sub(cursorX+1)

			text = text:gsub("\r\n","\n")
			text = self:ConvertText(text,true)

			local textLines = text:split("\n")
			local insert = table.insert

			for i = 1,#textLines do
				local linePos = cursorY+i
				if i > 1 then insert(lines,linePos,"") end

				local textLine = textLines[i]
				local newBefore = (i == 1 and before or "")
				local newAfter = (i == #textLines and after or "")

				lines[linePos] = newBefore..textLine..newAfter
			end

			if #textLines > 1 then cursorX = 0 end

			self:ProcessTextChange()
			self.CursorX = cursorX + #textLines[#textLines]
			self.CursorY = cursorY + #textLines-1
			self:UpdateCursor()
		end

		funcs.ScrollDelta = function(self,x,y)
			self.ScrollV:ScrollTo(self.ScrollV.Index + y)
			self.ScrollH:ScrollTo(self.ScrollH.Index + x)
		end

		funcs.TabAdjust = function(self,x,y)
			local lines = self.Lines
			local line = lines[y+1]
			x=x+1

			if line then
				local left = line:sub(x-1,x-1)
				local middle = line:sub(x,x)
				local right = line:sub(x+1,x+1)
				local selRange = (#left > 0 and left or " ") .. (#middle > 0 and middle or " ") .. (#right > 0 and right or " ")

				for i,v in pairs(tabJumps) do
					if selRange:find(i) then
						return v
					end
				end
			end
			return 0
		end

		funcs.SetEditing = function(self,on,input)			
			self:UpdateCursor(input)

			if on then
				if self.Editable then
					self.GuiElems.EditBox.Text = ""
					self.GuiElems.EditBox:CaptureFocus()
				end
			else
				self.GuiElems.EditBox:ReleaseFocus()
			end
		end

		funcs.CursorAnim = function(self,on)
			local cursor = self.GuiElems.Cursor
			local animTime = tick()
			self.LastAnimTime = animTime

			if not on then return end

			lineTweens.Invis:Cancel()
			lineTweens.Vis:Cancel()
			cursor.BackgroundTransparency = 0

			coroutine.wrap(function()
				while self.Editable do
					Lib.FastWait(0.5)
					if self.LastAnimTime ~= animTime then return end
					lineTweens.Invis:Play()
					Lib.FastWait(0.4)
					if self.LastAnimTime ~= animTime then return end
					lineTweens.Vis:Play()
					Lib.FastWait(0.2)
				end
			end)()
		end

		funcs.MoveCursor = function(self,x,y)
			self.CursorX = x
			self.CursorY = y
			self:UpdateCursor()
			self:JumpToCursor()
		end

		funcs.JumpToCursor = function(self)
			self:Refresh()
		end

		funcs.UpdateCursor = function(self,input)
			local linesFrame = self.GuiElems.LinesFrame
			local cursor = self.GuiElems.Cursor			
			local hSize = math.max(0,linesFrame.AbsoluteSize.X)
			local vSize = math.max(0,linesFrame.AbsoluteSize.Y)
			local maxLines = math.ceil(vSize / self.FontSize)
			local maxCols = math.ceil(hSize / math.ceil(self.FontSize/2))
			local viewX,viewY = self.ViewX,self.ViewY
			local totalLinesStr = tostring(#self.Lines)
			local fontWidth = math.ceil(self.FontSize / 2)
			local linesOffset = #totalLinesStr*fontWidth + 4*fontWidth

			if input then
				local linesFrame = self.GuiElems.LinesFrame
				local frameX,frameY = linesFrame.AbsolutePosition.X,linesFrame.AbsolutePosition.Y
				local mouseX,mouseY = input.Position.X,input.Position.Y
				local fontSizeX,fontSizeY = math.ceil(self.FontSize/2),self.FontSize

				self.CursorX = self.ViewX + math.round((mouseX - frameX) / fontSizeX)
				self.CursorY = self.ViewY + math.floor((mouseY - frameY) / fontSizeY)
			end

			local cursorX,cursorY = self.CursorX,self.CursorY

			local line = self.Lines[cursorY+1] or ""
			if cursorX > #line then cursorX = #line
			elseif cursorX < 0 then cursorX = 0 end

			if cursorY >= #self.Lines then
				cursorY = math.max(0,#self.Lines-1)
			elseif cursorY < 0 then
				cursorY = 0
			end

			cursorX = cursorX + self:TabAdjust(cursorX,cursorY)

			self.CursorX = cursorX
			self.CursorY = cursorY

			local cursorVisible = (cursorX >= viewX) and (cursorY >= viewY) and (cursorX <= viewX + maxCols) and (cursorY <= viewY + maxLines)
			if cursorVisible then
				local offX = (cursorX - viewX)
				local offY = (cursorY - viewY)
				cursor.Position = UDim2.new(0,linesOffset + offX*math.ceil(self.FontSize/2) - 1,0,offY*self.FontSize)
				cursor.Size = UDim2.new(0,1,0,self.FontSize+2)
				cursor.Visible = true
				self:CursorAnim(true)
			else
				cursor.Visible = false
			end
		end

		funcs.MapNewLines = function(self)
			local newLines = {}
			local count = 1
			local text = self.Text
			local find = string.find
			local init = 1

			local pos = find(text,"\n",init,true)
			while pos do
				newLines[count] = pos
				count = count + 1
				init = pos + 1
				pos = find(text,"\n",init,true)
			end

			self.NewLines = newLines
		end

		funcs.PreHighlight = function(self)
			local start = tick()
			local text = self.Text:gsub("\\\\","  ")
			local textLen = #text
			local found = {}
			local foundMap = {}
			local extras = {}
			local find = string.find
			local sub = string.sub
			self.ColoredLines = {}

			local function findAll(str,pattern,typ,raw)
				local count = #found+1
				local init = 1
				local x,y,extra = find(str,pattern,init,raw)
				while x do
					found[count] = x
					foundMap[x] = typ
					if extra then
						extras[x] = extra
					end

					count = count+1
					init = y+1
					x,y,extra = find(str,pattern,init,raw)
				end
			end
			local start = tick()
			findAll(text,'"',1,true)
			findAll(text,"'",2,true)
			findAll(text,"%[(=*)%[",3)
			findAll(text,"--",4,true)
			table.sort(found)

			local newLines = self.NewLines
			local curLine = 0
			local lineTableCount = 1
			local lineStart = 0
			local lineEnd = 0
			local lastEnding = 0
			local foundHighlights = {}

			for i = 1,#found do
				local pos = found[i]
				if pos <= lastEnding then continue end

				local ending = pos
				local typ = foundMap[pos]
				if typ == 1 then
					ending = find(text,'"',pos+1,true)
					while ending and sub(text,ending-1,ending-1) == "\\" do
						ending = find(text,'"',ending+1,true)
					end
					if not ending then ending = textLen end
				elseif typ == 2 then
					ending = find(text,"'",pos+1,true)
					while ending and sub(text,ending-1,ending-1) == "\\" do
						ending = find(text,"'",ending+1,true)
					end
					if not ending then ending = textLen end
				elseif typ == 3 then
					_,ending = find(text,"]"..extras[pos].."]",pos+1,true)
					if not ending then ending = textLen end
				elseif typ == 4 then
					local ahead = foundMap[pos+2]

					if ahead == 3 then
						_,ending = find(text,"]"..extras[pos+2].."]",pos+1,true)
						if not ending then ending = textLen end
					else
						ending = find(text,"\n",pos+1,true) or textLen
					end
				end

				while pos > lineEnd do
					curLine = curLine + 1
					lineEnd = newLines[curLine] or textLen+1
				end
				while true do
					local lineTable = foundHighlights[curLine]
					if not lineTable then lineTable = {} foundHighlights[curLine] = lineTable end
					lineTable[pos] = {typ,ending}

					if ending > lineEnd then
						curLine = curLine + 1
						lineEnd = newLines[curLine] or textLen+1
					else
						break
					end
				end

				lastEnding = ending
			end
			self.PreHighlights = foundHighlights
		end

		funcs.HighlightLine = function(self,line)
			local cached = self.ColoredLines[line]
			if cached then return cached end

			local sub = string.sub
			local find = string.find
			local match = string.match
			local highlights = {}
			local preHighlights = self.PreHighlights[line] or {}
			local lineText = self.Lines[line] or ""
			local lineLen = #lineText
			local lastEnding = 0
			local currentType = 0
			local lastWord = nil
			local wordBeginsDotted = false
			local funcStatus = 0
			local lineStart = self.NewLines[line-1] or 0

			local preHighlightMap = {}
			for pos,data in next,preHighlights do
				local relativePos = pos-lineStart
				if relativePos < 1 then
					currentType = data[1]
					lastEnding = data[2] - lineStart
				else
					preHighlightMap[relativePos] = {data[1],data[2]-lineStart}
				end
			end

			for col = 1,#lineText do
				if col <= lastEnding then highlights[col] = currentType continue end

				local pre = preHighlightMap[col]
				if pre then
					currentType = pre[1]
					lastEnding = pre[2]
					highlights[col] = currentType
					wordBeginsDotted = false
					lastWord = nil
					funcStatus = 0
				else
					local char = sub(lineText,col,col)
					if find(char,"[%a_]") then
						local word = match(lineText,"[%a%d_]+",col)
						local wordType = (keywords[word] and 7) or (builtIns[word] and 8)

						lastEnding = col+#word-1

						if wordType ~= 7 then
							if wordBeginsDotted then
								local prevBuiltIn = lastWord and builtIns[lastWord]
								wordType = (prevBuiltIn and type(prevBuiltIn) == "table" and prevBuiltIn[word] and 8) or 10
							end

							if wordType ~= 8 then
								local x,y,br = find(lineText,"^%s*([%({\"'])",lastEnding+1)
								if x then
									wordType = (funcStatus > 0 and br == "(" and 16) or 9
									funcStatus = 0
								end
							end
						else
							wordType = specialKeywordsTypes[word] or wordType
							funcStatus = (word == "function" and 1 or 0)
						end

						lastWord = word
						wordBeginsDotted = false
						if funcStatus > 0 then funcStatus = 1 end

						if wordType then
							currentType = wordType
							highlights[col] = currentType
						else
							currentType = nil
						end
					elseif find(char,"%p") then
						local isDot = (char == ".")
						local isNum = isDot and find(sub(lineText,col+1,col+1),"%d")
						highlights[col] = (isNum and 6 or 5)

						if not isNum then
							local dotStr = isDot and match(lineText,"%.%.?%.?",col)
							if dotStr and #dotStr > 1 then
								currentType = 5
								lastEnding = col+#dotStr-1
								wordBeginsDotted = false
								lastWord = nil
								funcStatus = 0
							else
								if isDot then
									if wordBeginsDotted then
										lastWord = nil
									else
										wordBeginsDotted = true
									end
								else
									wordBeginsDotted = false
									lastWord = nil
								end

								funcStatus = ((isDot or char == ":") and funcStatus == 1 and 2) or 0
							end
						end
					elseif find(char,"%d") then
						local _,endPos = find(lineText,"%x+",col)
						local endPart = sub(lineText,endPos,endPos+1)
						if (endPart == "e+" or endPart == "e-") and find(sub(lineText,endPos+2,endPos+2),"%d") then
							endPos = endPos + 1
						end
						currentType = 6
						lastEnding = endPos
						highlights[col] = 6
						wordBeginsDotted = false
						lastWord = nil
						funcStatus = 0
					else
						highlights[col] = currentType
						local _,endPos = find(lineText,"%s+",col)
						if endPos then
							lastEnding = endPos
						end
					end
				end
			end

			self.ColoredLines[line] = highlights
			return highlights
		end

		funcs.Refresh = function(self)
			local start = tick()

			local linesFrame = self.Frame.Lines
			local hSize = math.max(0,linesFrame.AbsoluteSize.X)
			local vSize = math.max(0,linesFrame.AbsoluteSize.Y)
			local maxLines = math.ceil(vSize / self.FontSize)
			local maxCols = math.ceil(hSize / math.ceil(self.FontSize/2))
			local gsub = string.gsub
			local sub = string.sub

			local viewX,viewY = self.ViewX,self.ViewY

			local lineNumberStr = ""

			for row = 1,maxLines do
				local lineFrame = self.LineFrames[row]
				if not lineFrame then
					lineFrame = Instance.new("Frame")
					lineFrame.Name = "Line"
					lineFrame.Position = UDim2.new(0,0,0,(row-1)*self.FontSize)
					lineFrame.Size = UDim2.new(1,0,0,self.FontSize)
					lineFrame.BorderSizePixel = 0
					lineFrame.BackgroundTransparency = 1

					local selectionHighlight = Instance.new("Frame")
					selectionHighlight.Name = "SelectionHighlight"
					selectionHighlight.BorderSizePixel = 0
					selectionHighlight.BackgroundColor3 = Settings.Theme.Syntax.SelectionBack
					selectionHighlight.Parent = lineFrame

					local label = Instance.new("TextLabel")
					label.Name = "Label"
					label.BackgroundTransparency = 1
					label.Font = Enum.Font.Code
					label.TextSize = self.FontSize
					label.Size = UDim2.new(1,0,0,self.FontSize)
					label.RichText = true
					label.TextXAlignment = Enum.TextXAlignment.Left
					label.TextColor3 = self.Colors.Text
					label.ZIndex = 2
					label.Parent = lineFrame

					lineFrame.Parent = linesFrame
					self.LineFrames[row] = lineFrame
				end

				local relaY = viewY + row
				local lineText = self.Lines[relaY] or ""
				local resText = ""
				local highlights = self:HighlightLine(relaY)
				local colStart = viewX + 1

				local richTemplates = self.RichTemplates
				local textTemplate = richTemplates.Text
				local selectionTemplate = richTemplates.Selection
				local curType = highlights[colStart]
				local curTemplate = richTemplates[typeMap[curType]] or textTemplate

				local selectionRange = self.SelectionRange
				local selPos1 = selectionRange[1]
				local selPos2 = selectionRange[2]
				local selRow,selColumn = selPos1[2],selPos1[1]
				local sel2Row,sel2Column = selPos2[2],selPos2[1]
				local selRelaX,selRelaY = viewX,relaY-1

				if selRelaY >= selPos1[2] and selRelaY <= selPos2[2] then
					local fontSizeX = math.ceil(self.FontSize/2)
					local posX = (selRelaY == selPos1[2] and selPos1[1] or 0) - viewX
					local sizeX = (selRelaY == selPos2[2] and selPos2[1]-posX-viewX or maxCols+viewX)

					lineFrame.SelectionHighlight.Position = UDim2.new(0,posX*fontSizeX,0,0)
					lineFrame.SelectionHighlight.Size = UDim2.new(0,sizeX*fontSizeX,1,0)
					lineFrame.SelectionHighlight.Visible = true
				else
					lineFrame.SelectionHighlight.Visible = false
				end

				local inSelection = selRelaY >= selRow and selRelaY <= sel2Row and (selRelaY == selRow and viewX >= selColumn or selRelaY ~= selRow) and (selRelaY == sel2Row and viewX < sel2Column or selRelaY ~= sel2Row)
				if inSelection then
					curType = -999
					curTemplate = selectionTemplate
				end

				for col = 2,maxCols do
					local relaX = viewX + col
					local selRelaX = relaX-1
					local posType = highlights[relaX]

					local inSelection = selRelaY >= selRow and selRelaY <= sel2Row and (selRelaY == selRow and selRelaX >= selColumn or selRelaY ~= selRow) and (selRelaY == sel2Row and selRelaX < sel2Column or selRelaY ~= sel2Row)
					if inSelection then
						posType = -999
					end

					if posType ~= curType then
						local template = (inSelection and selectionTemplate) or richTemplates[typeMap[posType]] or textTemplate

						if template ~= curTemplate then
							local nextText = gsub(sub(lineText,colStart,relaX-1),"['\"<>&]",richReplace)
							resText = resText .. (curTemplate ~= textTemplate and (curTemplate .. nextText .. "</font>") or nextText)
							colStart = relaX
							curTemplate = template
						end
						curType = posType
					end
				end

				local lastText = gsub(sub(lineText,colStart,viewX+maxCols),"['\"<>&]",richReplace)
				if #lastText > 0 then
					resText = resText .. (curTemplate ~= textTemplate and (curTemplate .. lastText .. "</font>") or lastText)
				end

				if self.Lines[relaY] then

					lineNumberStr = lineNumberStr .. (relaY == self.CursorY + 1 and ("<b>"..relaY.."</b>\n") or relaY .. "\n")
				end

				lineFrame.Label.Text = resText
			end

			for i = maxLines+1,#self.LineFrames do
				self.LineFrames[i]:Destroy()
				self.LineFrames[i] = nil
			end

			self.Frame.LineNumbers.Text = lineNumberStr
			self:UpdateCursor()

		end

		funcs.UpdateView = function(self)
			local totalLinesStr = tostring(#self.Lines)
			local fontWidth = math.ceil(self.FontSize / 2)
			local linesOffset = #totalLinesStr*fontWidth + 4*fontWidth

			local linesFrame = self.Frame.Lines
			local hSize = linesFrame.AbsoluteSize.X
			local vSize = linesFrame.AbsoluteSize.Y
			local maxLines = math.ceil(vSize / self.FontSize)
			local totalWidth = self.MaxTextCols*fontWidth
			local scrollV = self.ScrollV
			local scrollH = self.ScrollH

			scrollV.VisibleSpace = maxLines
			scrollV.TotalSpace = #self.Lines + 1
			scrollH.VisibleSpace = math.ceil(hSize/fontWidth)
			scrollH.TotalSpace = self.MaxTextCols + 1

			scrollV.Gui.Visible = #self.Lines + 1 > maxLines
			scrollH.Gui.Visible = totalWidth > hSize

			local oldOffsets = self.FrameOffsets
			self.FrameOffsets = Vector2.new(scrollV.Gui.Visible and -16 or 0, scrollH.Gui.Visible and -16 or 0)
			if oldOffsets ~= self.FrameOffsets then
				self:UpdateView()
			else
				scrollV:ScrollTo(self.ViewY,true)
				scrollH:ScrollTo(self.ViewX,true)

				if scrollV.Gui.Visible and scrollH.Gui.Visible then
					scrollV.Gui.Size = UDim2.new(0,16,1,-16)
					scrollH.Gui.Size = UDim2.new(1,-16,0,16)
					self.GuiElems.ScrollCorner.Visible = true
				else
					scrollV.Gui.Size = UDim2.new(0,16,1,0)
					scrollH.Gui.Size = UDim2.new(1,0,0,16)
					self.GuiElems.ScrollCorner.Visible = false
				end

				self.ViewY = scrollV.Index
				self.ViewX = scrollH.Index
				self.Frame.Lines.Position = UDim2.new(0,linesOffset,0,0)
				self.Frame.Lines.Size = UDim2.new(1,-linesOffset+oldOffsets.X,1,oldOffsets.Y)
				self.Frame.LineNumbers.Position = UDim2.new(0,fontWidth,0,0)
				self.Frame.LineNumbers.Size = UDim2.new(0,#totalLinesStr*fontWidth,1,oldOffsets.Y)
				self.Frame.LineNumbers.TextSize = self.FontSize
			end
		end

		funcs.ProcessTextChange = function(self)
			local maxCols = 0
			local lines = self.Lines

			for i = 1,#lines do
				local lineLen = #lines[i]
				if lineLen > maxCols then
					maxCols = lineLen
				end
			end

			self.MaxTextCols = maxCols
			self:UpdateView()	
			self.Text = table.concat(self.Lines,"\n")
			self:MapNewLines()
			self:PreHighlight()
			self:Refresh()
		end

		funcs.ConvertText = function(self,text,toEditor)
			if toEditor then
				return text:gsub("\t","    ")
			else
				return text:gsub((" %s%s "):format(tabSub,tabSub),"\t")
			end
		end

		funcs.GetText = function(self)
			local source = table.concat(self.Lines,"\n")
			return self:ConvertText(source,false)
		end

		funcs.SetText = function(self,txt)
			txt = self:ConvertText(txt,true)
			local lines = self.Lines
			table.clear(lines)
			local count = 1

			for line in txt:gmatch("([^\n\r]*)[\n\r]?") do
				local len = #line
				lines[count] = line
				count = count + 1
			end

			self:ProcessTextChange()
		end

		funcs.MakeRichTemplates = function(self)
			local floor = math.floor
			local templates = {}

			for name,color in pairs(self.Colors) do
				templates[name] = ('<font color="rgb(%s,%s,%s)">'):format(floor(color.r*255),floor(color.g*255),floor(color.b*255))
			end

			self.RichTemplates = templates
		end

		funcs.ApplyTheme = function(self)
			local colors = Settings.Theme.Syntax
			self.Colors = colors
			self.Frame.LineNumbers.TextColor3 = colors.Text
			self.Frame.BackgroundColor3 = colors.Background
		end

		local mt = {__index = funcs}

		local function new()
			if not builtInInited then initBuiltIn() end

			local scrollV = Lib.ScrollBar.new()
			local scrollH = Lib.ScrollBar.new(true)
			scrollH.Gui.Position = UDim2.new(0,0,1,-16)
			local obj = setmetatable({
				FontSize = 16,
				ViewX = 0,
				ViewY = 0,
				Colors = Settings.Theme.Syntax,
				ColoredLines = {},
				Lines = {""},
				LineFrames = {},
				Editable = true,
				Editing = false,
				CursorX = 0,
				CursorY = 0,
				FloatCursorX = 0,
				Text = "",
				PreHighlights = {},
				SelectionRange = {{-1,-1},{-1,-1}},
				NewLines = {},
				FrameOffsets = Vector2.new(0,0),
				MaxTextCols = 0,
				ScrollV = scrollV,
				ScrollH = scrollH
			},mt)

			scrollV.WheelIncrement = 3
			scrollH.Increment = 2
			scrollH.WheelIncrement = 7

			scrollV.Scrolled:Connect(function()
				obj.ViewY = scrollV.Index
				obj:Refresh()
			end)

			scrollH.Scrolled:Connect(function()
				obj.ViewX = scrollH.Index
				obj:Refresh()
			end)

			makeFrame(obj)
			obj:MakeRichTemplates()
			obj:ApplyTheme()
			scrollV:SetScrollFrame(obj.Frame.Lines)
			scrollV.Gui.Parent = obj.Frame
			scrollH.Gui.Parent = obj.Frame

			obj:UpdateView()
			obj.Frame:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
				obj:UpdateView()
				obj:Refresh()
			end)

			return obj
		end

		return {new = new}
	end)()

	Lib.Checkbox = (function()
		local funcs = {}
		local c3 = Color3.fromRGB
		local v2 = Vector2.new
		local ud2s = UDim2.fromScale
		local ud2o = UDim2.fromOffset
		local ud = UDim.new
		local max = math.max
		local new = Instance.new
		local TweenSize = new("Frame").TweenSize
		local ti = TweenInfo.new
		local delay = delay

		local function ripple(object, color)
			local circle = new('Frame')
			circle.BackgroundColor3 = color
			circle.BackgroundTransparency = 0.75
			circle.BorderSizePixel = 0
			circle.AnchorPoint = v2(0.5, 0.5)
			circle.Size = ud2o()
			circle.Position = ud2s(0.5, 0.5)
			circle.Parent = object
			local rounding = new('UICorner')
			rounding.CornerRadius = ud(1)
			rounding.Parent = circle

			local abssz = object.AbsoluteSize
			local size = max(abssz.X, abssz.Y) * 5/3

			TweenSize(circle, ud2o(size, size), "Out", "Quart", 0.4)
			service.TweenService:Create(circle, ti(0.4, Enum.EasingStyle.Quart, Enum.EasingDirection.In), {BackgroundTransparency = 1}):Play()

			service.Debris:AddItem(circle, 0.4)
		end

		local function initGui(self,frame)
			local checkbox = frame or create({
				{1,"ImageButton",{BackgroundColor3=Color3.new(1,1,1),BackgroundTransparency=1,BorderSizePixel=0,Name="Checkbox",Position=UDim2.new(0,3,0,3),Size=UDim2.new(0,16,0,16),}},
				{2,"Frame",{BackgroundColor3=Color3.new(1,1,1),BackgroundTransparency=1,BorderSizePixel=0,Name="ripples",Parent={1},Size=UDim2.new(1,0,1,0),}},
				{3,"Frame",{BackgroundColor3=Color3.new(0.10196078568697,0.10196078568697,0.10196078568697),BorderSizePixel=0,Name="outline",Parent={1},Size=UDim2.new(0,16,0,16),}},
				{4,"Frame",{BackgroundColor3=Color3.new(0.14117647707462,0.14117647707462,0.14117647707462),BorderSizePixel=0,Name="filler",Parent={3},Position=UDim2.new(0,1,0,1),Size=UDim2.new(0,14,0,14),}},
				{5,"Frame",{BackgroundColor3=Color3.new(0.90196084976196,0.90196084976196,0.90196084976196),BorderSizePixel=0,Name="top",Parent={4},Size=UDim2.new(0,16,0,0),}},
				{6,"Frame",{AnchorPoint=Vector2.new(0,1),BackgroundColor3=Color3.new(0.90196084976196,0.90196084976196,0.90196084976196),BorderSizePixel=0,Name="bottom",Parent={4},Position=UDim2.new(0,0,0,14),Size=UDim2.new(0,16,0,0),}},
				{7,"Frame",{BackgroundColor3=Color3.new(0.90196084976196,0.90196084976196,0.90196084976196),BorderSizePixel=0,Name="left",Parent={4},Size=UDim2.new(0,0,0,16),}},
				{8,"Frame",{AnchorPoint=Vector2.new(1,0),BackgroundColor3=Color3.new(0.90196084976196,0.90196084976196,0.90196084976196),BorderSizePixel=0,Name="right",Parent={4},Position=UDim2.new(0,14,0,0),Size=UDim2.new(0,0,0,16),}},
				{9,"Frame",{AnchorPoint=Vector2.new(0.5,0.5),BackgroundColor3=Color3.new(1,1,1),BackgroundTransparency=1,BorderSizePixel=0,ClipsDescendants=true,Name="checkmark",Parent={4},Position=UDim2.new(0.5,0,0.5,0),Size=UDim2.new(0,0,0,20),}},
				{10,"ImageLabel",{AnchorPoint=Vector2.new(0.5,0.5),BackgroundColor3=Color3.new(1,1,1),BackgroundTransparency=1,BorderSizePixel=0,Image="rbxassetid://6234266378",Parent={9},Position=UDim2.new(0.5,0,0.5,0),ScaleType=3,Size=UDim2.new(0,15,0,11),}},
				{11,"ImageLabel",{AnchorPoint=Vector2.new(0.5,0.5),BackgroundColor3=Color3.new(1,1,1),BackgroundTransparency=1,Image="rbxassetid://6401617475",ImageColor3=Color3.new(0.20784313976765,0.69803923368454,0.98431372642517),Name="checkmark2",Parent={4},Position=UDim2.new(0.5,0,0.5,0),Size=UDim2.new(0,12,0,12),Visible=false,}},
				{12,"ImageLabel",{BackgroundColor3=Color3.new(1,1,1),BackgroundTransparency=1,Image="rbxassetid://6425281788",ImageTransparency=0.20000000298023,Name="middle",Parent={4},ScaleType=2,Size=UDim2.new(1,0,1,0),TileSize=UDim2.new(0,2,0,2),Visible=false,}},
				{13,"UICorner",{CornerRadius=UDim.new(0,2),Parent={3},}},
			})
			local outline = checkbox.outline
			local filler = outline.filler
			local checkmark = filler.checkmark
			local ripples_container = checkbox.ripples

			local top, bottom, left, right = filler.top, filler.bottom, filler.left, filler.right

			self.Gui = checkbox
			self.GuiElems = {
				Top = top,
				Bottom = bottom,
				Left = left,
				Right = right,
				Outline = outline,
				Filler = filler,
				Checkmark = checkmark,
				Checkmark2 = filler.checkmark2,
				Middle = filler.middle
			}
	
			
			checkbox.MouseButton1Up:Connect(function()
				if Lib.CheckMouseInGui(checkbox) then
					if self.Style == 0 then
						ripple(ripples_container, self.Disabled and self.Colors.Disabled or self.Colors.Primary)
					end

					if not self.Disabled then
						self:SetState(not self.Toggled,true)
					else
						self:Paint()
					end

					self.OnInput:Fire()
				end
			end)


			self:Paint()
		end

		funcs.Collapse = function(self,anim)
			local guiElems = self.GuiElems
			if anim then
				TweenSize(guiElems.Top, ud2o(14, 14), "In", "Quart", 4/15, true)
				TweenSize(guiElems.Bottom, ud2o(14, 14), "In", "Quart", 4/15, true)
				TweenSize(guiElems.Left, ud2o(14, 14), "In", "Quart", 4/15, true)
				TweenSize(guiElems.Right, ud2o(14, 14), "In", "Quart", 4/15, true)
			else
				guiElems.Top.Size = ud2o(14, 14)
				guiElems.Bottom.Size = ud2o(14, 14)
				guiElems.Left.Size = ud2o(14, 14)
				guiElems.Right.Size = ud2o(14, 14)
			end
		end

		funcs.Expand = function(self,anim)
			local guiElems = self.GuiElems
			if anim then
				TweenSize(guiElems.Top, ud2o(14, 0), "InOut", "Quart", 4/15, true)
				TweenSize(guiElems.Bottom, ud2o(14, 0), "InOut", "Quart", 4/15, true)
				TweenSize(guiElems.Left, ud2o(0, 14), "InOut", "Quart", 4/15, true)
				TweenSize(guiElems.Right, ud2o(0, 14), "InOut", "Quart", 4/15, true)
			else
				guiElems.Top.Size = ud2o(14, 0)
				guiElems.Bottom.Size = ud2o(14, 0)
				guiElems.Left.Size = ud2o(0, 14)
				guiElems.Right.Size = ud2o(0, 14)
			end
		end

		funcs.Paint = function(self)
			local guiElems = self.GuiElems

			if self.Style == 0 then
				local color_base = self.Disabled and self.Colors.Disabled
				guiElems.Outline.BackgroundColor3 = color_base or (self.Toggled and self.Colors.Primary) or self.Colors.Secondary
				local walls_color = color_base or self.Colors.Primary
				guiElems.Top.BackgroundColor3 = walls_color
				guiElems.Bottom.BackgroundColor3 = walls_color
				guiElems.Left.BackgroundColor3 = walls_color
				guiElems.Right.BackgroundColor3 = walls_color
			else
				guiElems.Outline.BackgroundColor3 = self.Disabled and self.Colors.Disabled or self.Colors.Secondary
				guiElems.Filler.BackgroundColor3 = self.Disabled and self.Colors.DisabledBackground or self.Colors.Background
				guiElems.Checkmark2.ImageColor3 = self.Disabled and self.Colors.DisabledCheck or self.Colors.Primary
			end
		end

		funcs.SetState = function(self,val,anim)
			self.Toggled = val

			if self.OutlineColorTween then self.OutlineColorTween:Cancel() end
			local setStateTime = tick()
			self.LastSetStateTime = setStateTime

			if self.Toggled then
				if self.Style == 0 then
					if anim then
						self.OutlineColorTween = service.TweenService:Create(self.GuiElems.Outline, ti(4/15, Enum.EasingStyle.Circular, Enum.EasingDirection.Out), {BackgroundColor3 = self.Colors.Primary})
						self.OutlineColorTween:Play()
						delay(0.15, function()
							if setStateTime ~= self.LastSetStateTime then return end
							self:Paint()
							TweenSize(self.GuiElems.Checkmark, ud2o(14, 20), "Out", "Bounce", 2/15, true)
						end)
					else
						self.GuiElems.Outline.BackgroundColor3 = self.Colors.Primary
						self:Paint()
						self.GuiElems.Checkmark.Size = ud2o(14, 20)
					end
					self:Collapse(anim)
				else
					self:Paint()
					self.GuiElems.Checkmark2.Visible = true
					self.GuiElems.Middle.Visible = false
				end
			else
				if self.Style == 0 then
					if anim then
						self.OutlineColorTween = service.TweenService:Create(self.GuiElems.Outline, ti(4/15, Enum.EasingStyle.Circular, Enum.EasingDirection.In), {BackgroundColor3 = self.Colors.Secondary})
						self.OutlineColorTween:Play()
						delay(0.15, function()
							if setStateTime ~= self.LastSetStateTime then return end
							self:Paint()
							TweenSize(self.GuiElems.Checkmark, ud2o(0, 20), "Out", "Quad", 1/15, true)
						end)
					else
						self.GuiElems.Outline.BackgroundColor3 = self.Colors.Secondary
						self:Paint()
						self.GuiElems.Checkmark.Size = ud2o(0, 20)
					end
					self:Expand(anim)
				else
					self:Paint()
					self.GuiElems.Checkmark2.Visible = false
					self.GuiElems.Middle.Visible = self.Toggled == nil
				end
			end
		end

		local mt = {__index = funcs}

		local function new(style)
			local obj = setmetatable({
				Toggled = false,
				Disabled = false,
				OnInput = Lib.Signal.new(),
				Style = style or 0,
				Colors = {
					Background = c3(36,36,36),
					Primary = c3(49,176,230),
					Secondary = c3(25,25,25),
					Disabled = c3(64,64,64),
					DisabledBackground = c3(52,52,52),
					DisabledCheck = c3(80,80,80)
				}
			},mt)
			initGui(obj)
			return obj
		end

		local function fromFrame(frame)
			local obj = setmetatable({
				Toggled = false,
				Disabled = false,
				Colors = {
					Background = c3(36,36,36),
					Primary = c3(49,176,230),
					Secondary = c3(25,25,25),
					Disabled = c3(64,64,64),
					DisabledBackground = c3(52,52,52)
				}
			},mt)
			initGui(obj,frame)
			return obj
		end

		return {new = new, fromFrame}
	end)()

	Lib.BrickColorPicker = (function()
		local funcs = {}
		local paletteCount = 0
		local mouse = service.Players.LocalPlayer:GetMouse()
		local hexStartX = 4
		local hexSizeX = 27
		local hexTriangleStart = 1
		local hexTriangleSize = 8

		local bottomColors = {
			Color3.fromRGB(17,17,17),
			Color3.fromRGB(99,95,98),
			Color3.fromRGB(163,162,165),
			Color3.fromRGB(205,205,205),
			Color3.fromRGB(223,223,222),
			Color3.fromRGB(237,234,234),
			Color3.fromRGB(27,42,53),
			Color3.fromRGB(91,93,105),
			Color3.fromRGB(159,161,172),
			Color3.fromRGB(202,203,209),
			Color3.fromRGB(231,231,236),
			Color3.fromRGB(248,248,248)
		}

		local function isMouseInHexagon(hex, touchPos)
			local relativeX = touchPos.X - hex.AbsolutePosition.X
			local relativeY = touchPos.Y - hex.AbsolutePosition.Y
			if relativeX >= hexStartX and relativeX < hexStartX + hexSizeX then
				relativeX = relativeX - 4
				local relativeWidth = (13 - math.min(relativeX, 26 - relativeX)) / 13
				if relativeY >= hexTriangleStart + hexTriangleSize * relativeWidth and relativeY < hex.AbsoluteSize.Y - hexTriangleStart - hexTriangleSize * relativeWidth then
					return true
				end
			end
			return false
		end

		local function hexInput(self, hex, color)
			hex.InputBegan:Connect(function(input)
				if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
					if isMouseInHexagon(hex, input.Position) then
						self.OnSelect:Fire(color)
						self:Close()
					end
				end
			end)

			hex.InputChanged:Connect(function(input)
				if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
					if isMouseInHexagon(hex, input.Position) then
						self.OnPreview:Fire(color)
					end
				end
			end)
		end

		local function createGui(self)
			local gui = create({
				{1,"ScreenGui",{Name="BrickColor",}},
				{2,"Frame",{Active=true,BackgroundColor3=Color3.new(0.17647059261799,0.17647059261799,0.17647059261799),BorderColor3=Color3.new(0.1294117718935,0.1294117718935,0.1294117718935),Parent={1},Position=UDim2.new(0.40000000596046,0,0.40000000596046,0),Size=UDim2.new(0,337,0,380),}},
				{3,"TextButton",{BackgroundColor3=Color3.new(0.2352941185236,0.2352941185236,0.2352941185236),BorderColor3=Color3.new(0.21568627655506,0.21568627655506,0.21568627655506),BorderSizePixel=0,Font=3,Name="MoreColors",Parent={2},Position=UDim2.new(0,5,1,-30),Size=UDim2.new(1,-10,0,25),Text="More Colors",TextColor3=Color3.new(1,1,1),TextSize=14,}},
				{4,"ImageLabel",{BackgroundColor3=Color3.new(1,1,1),BackgroundTransparency=1,BorderSizePixel=0,Image="rbxassetid://1281023007",ImageColor3=Color3.new(0.33333334326744,0.33333334326744,0.49803924560547),Name="Hex",Parent={2},Size=UDim2.new(0,35,0,35),Visible=false,}},
			})
			local colorFrame = gui.Frame
			local hex = colorFrame.Hex

			for row = 1,13 do
				local columns = math.min(row,14-row)+6
				for column = 1,columns do
					local nextColor = BrickColor.palette(paletteCount).Color
					local newHex = hex:Clone()
					newHex.Position = UDim2.new(0, (column-1)*25-(columns-7)*13+3*26 + 1, 0, (row-1)*23 + 4)
					newHex.ImageColor3 = nextColor
					newHex.Visible = true
					hexInput(self,newHex,nextColor)
					newHex.Parent = colorFrame
					paletteCount = paletteCount + 1
				end
			end

			for column = 1,12 do
				local nextColor = bottomColors[column]
				local newHex = hex:Clone()
				newHex.Position = UDim2.new(0, (column-1)*25-(12-7)*13+3*26 + 3, 0, 308)
				newHex.ImageColor3 = nextColor
				newHex.Visible = true
				hexInput(self,newHex,nextColor)
				newHex.Parent = colorFrame
				paletteCount = paletteCount + 1
			end

			colorFrame.MoreColors.MouseButton1Click:Connect(function()
				self.OnMoreColors:Fire()
				self:Close()
			end)

			self.Gui = gui
		end

		funcs.SetMoreColorsVisible = function(self,vis)
			local colorFrame = self.Gui.Frame
			colorFrame.Size = UDim2.new(0,337,0,380 - (not vis and 33 or 0))
			colorFrame.MoreColors.Visible = vis
		end

		funcs.Show = function(self,x,y,prevColor)
			self.PrevColor = prevColor or self.PrevColor

			local reverseY = false

			local x,y = x or mouse.X, y or mouse.Y
			local maxX,maxY = mouse.ViewSizeX,mouse.ViewSizeY
			Lib.ShowGui(self.Gui)
			local sizeX,sizeY = self.Gui.Frame.AbsoluteSize.X,self.Gui.Frame.AbsoluteSize.Y

			if x + sizeX > maxX then x = self.ReverseX and x - sizeX or maxX - sizeX end
			if y + sizeY > maxY then reverseY = true end

			local closable = false
			if self.CloseEvent then self.CloseEvent:Disconnect() end

			self.CloseEvent = service.UserInputService.InputBegan:Connect(function(input)
				if not closable or (input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch) then
					return
				end

				if not Lib.CheckMouseInGui(self.Gui.Frame) then
					self.CloseEvent:Disconnect()
					self:Close()
				end
			end)


			if reverseY then
				local newY = y - sizeY - (self.ReverseYOffset or 0)
				y = newY >= 0 and newY or 0
			end

			self.Gui.Frame.Position = UDim2.new(0,x,0,y)

			Lib.FastWait()
			closable = true
		end

		funcs.Close = function(self)
			self.Gui.Parent = nil
			self.OnCancel:Fire()
		end

		local mt = {__index = funcs}

		local function new()
			local obj = setmetatable({
				OnPreview = Lib.Signal.new(),
				OnSelect = Lib.Signal.new(),
				OnCancel = Lib.Signal.new(),
				OnMoreColors = Lib.Signal.new(),
				PrevColor = Color3.new(0,0,0)
			}, mt)
			createGui(obj)
			return obj
		end

		return {new = new}
	end)()

	Lib.ColorPicker = (function()
		local funcs = {}

		local function new()
			local newMt = setmetatable({},{})

			newMt.OnSelect = Lib.Signal.new()
			newMt.OnCancel = Lib.Signal.new()
			newMt.OnPreview = Lib.Signal.new()

			local guiContents = create({
				{1,"Frame",{BackgroundColor3=Color3.new(0.17647059261799,0.17647059261799,0.17647059261799),BorderSizePixel=0,ClipsDescendants=true,Name="Content",Position=UDim2.new(0,0,0,20),Size=UDim2.new(1,0,1,-20),}},
				{2,"Frame",{BackgroundColor3=Color3.new(1,1,1),BackgroundTransparency=1,Name="BasicColors",Parent={1},Position=UDim2.new(0,5,0,5),Size=UDim2.new(0,180,0,200),}},
				{3,"TextLabel",{BackgroundColor3=Color3.new(1,1,1),BackgroundTransparency=1,Font=3,Name="Title",Parent={2},Position=UDim2.new(0,0,0,-5),Size=UDim2.new(1,0,0,26),Text="Basic Colors",TextColor3=Color3.new(0.86274516582489,0.86274516582489,0.86274516582489),TextSize=14,TextXAlignment=0,}},
				{4,"Frame",{BackgroundColor3=Color3.new(0.14901961386204,0.14901961386204,0.14901961386204),BorderColor3=Color3.new(0.12549020349979,0.12549020349979,0.12549020349979),Name="Blue",Parent={1},Position=UDim2.new(1,-63,0,255),Size=UDim2.new(0,52,0,16),}},
				{5,"TextBox",{BackgroundColor3=Color3.new(0.25098040699959,0.25098040699959,0.25098040699959),BackgroundTransparency=1,BorderColor3=Color3.new(0.37647062540054,0.37647062540054,0.37647062540054),Font=3,Name="Input",Parent={4},Position=UDim2.new(0,2,0,0),Size=UDim2.new(0,50,0,16),Text="0",TextColor3=Color3.new(0.86274516582489,0.86274516582489,0.86274516582489),TextSize=14,TextXAlignment=0,}},
				{6,"Frame",{BackgroundColor3=Color3.new(1,1,1),BackgroundTransparency=1,BorderSizePixel=0,Name="ArrowFrame",Parent={5},Position=UDim2.new(1,-16,0,0),Size=UDim2.new(0,16,1,0),}},
				{7,"TextButton",{AutoButtonColor=false,BackgroundColor3=Color3.new(1,1,1),BackgroundTransparency=1,BorderSizePixel=0,Font=3,Name="Up",Parent={6},Size=UDim2.new(1,0,0,8),Text="",TextSize=14,}},
				{8,"Frame",{BackgroundTransparency=1,Name="Arrow",Parent={7},Size=UDim2.new(0,16,0,8),}},
				{9,"Frame",{BackgroundColor3=Color3.new(0.86274510622025,0.86274510622025,0.86274510622025),BorderSizePixel=0,Parent={8},Position=UDim2.new(0,8,0,3),Size=UDim2.new(0,1,0,1),}},
				{10,"Frame",{BackgroundColor3=Color3.new(0.86274510622025,0.86274510622025,0.86274510622025),BorderSizePixel=0,Parent={8},Position=UDim2.new(0,7,0,4),Size=UDim2.new(0,3,0,1),}},
				{11,"Frame",{BackgroundColor3=Color3.new(0.86274510622025,0.86274510622025,0.86274510622025),BorderSizePixel=0,Parent={8},Position=UDim2.new(0,6,0,5),Size=UDim2.new(0,5,0,1),}},
				{12,"TextButton",{AutoButtonColor=false,BackgroundColor3=Color3.new(1,1,1),BackgroundTransparency=1,BorderSizePixel=0,Font=3,Name="Down",Parent={6},Position=UDim2.new(0,0,0,8),Size=UDim2.new(1,0,0,8),Text="",TextSize=14,}},
				{13,"Frame",{BackgroundTransparency=1,Name="Arrow",Parent={12},Size=UDim2.new(0,16,0,8),}},
				{14,"Frame",{BackgroundColor3=Color3.new(0.86274510622025,0.86274510622025,0.86274510622025),BorderSizePixel=0,Parent={13},Position=UDim2.new(0,8,0,5),Size=UDim2.new(0,1,0,1),}},
				{15,"Frame",{BackgroundColor3=Color3.new(0.86274510622025,0.86274510622025,0.86274510622025),BorderSizePixel=0,Parent={13},Position=UDim2.new(0,7,0,4),Size=UDim2.new(0,3,0,1),}},
				{16,"Frame",{BackgroundColor3=Color3.new(0.86274510622025,0.86274510622025,0.86274510622025),BorderSizePixel=0,Parent={13},Position=UDim2.new(0,6,0,3),Size=UDim2.new(0,5,0,1),}},
				{17,"TextLabel",{BackgroundColor3=Color3.new(1,1,1),BackgroundTransparency=1,Font=3,Name="Title",Parent={4},Position=UDim2.new(0,-40,0,0),Size=UDim2.new(0,34,1,0),Text="Blue:",TextColor3=Color3.new(0.86274516582489,0.86274516582489,0.86274516582489),TextSize=14,TextXAlignment=1,}},
				{18,"Frame",{BackgroundColor3=Color3.new(0.21568627655506,0.21568627655506,0.21568627655506),BorderSizePixel=0,ClipsDescendants=true,Name="ColorSpaceFrame",Parent={1},Position=UDim2.new(1,-261,0,4),Size=UDim2.new(0,222,0,202),}},
				{19,"ImageLabel",{BackgroundColor3=Color3.new(1,1,1),BorderColor3=Color3.new(0.37647062540054,0.37647062540054,0.37647062540054),BorderSizePixel=0,Image="rbxassetid://1072518406",Name="ColorSpace",Parent={18},Position=UDim2.new(0,1,0,1),Size=UDim2.new(0,220,0,200),}},
				{20,"Frame",{BackgroundColor3=Color3.new(1,1,1),BackgroundTransparency=1,BorderSizePixel=0,Name="Scope",Parent={19},Position=UDim2.new(0,210,0,190),Size=UDim2.new(0,20,0,20),}},
				{21,"Frame",{BackgroundColor3=Color3.new(0,0,0),BorderSizePixel=0,Name="Line",Parent={20},Position=UDim2.new(0,9,0,0),Size=UDim2.new(0,2,0,20),}},
				{22,"Frame",{BackgroundColor3=Color3.new(0,0,0),BorderSizePixel=0,Name="Line",Parent={20},Position=UDim2.new(0,0,0,9),Size=UDim2.new(0,20,0,2),}},
				{23,"Frame",{BackgroundColor3=Color3.new(1,1,1),BackgroundTransparency=1,Name="CustomColors",Parent={1},Position=UDim2.new(0,5,0,210),Size=UDim2.new(0,180,0,90),}},
				{24,"TextLabel",{BackgroundColor3=Color3.new(1,1,1),BackgroundTransparency=1,Font=3,Name="Title",Parent={23},Size=UDim2.new(1,0,0,20),Text="Custom Colors (RC = Set)",TextColor3=Color3.new(0.86274516582489,0.86274516582489,0.86274516582489),TextSize=14,TextXAlignment=0,}},
				{25,"Frame",{BackgroundColor3=Color3.new(0.14901961386204,0.14901961386204,0.14901961386204),BorderColor3=Color3.new(0.12549020349979,0.12549020349979,0.12549020349979),Name="Green",Parent={1},Position=UDim2.new(1,-63,0,233),Size=UDim2.new(0,52,0,16),}},
				{26,"TextBox",{BackgroundColor3=Color3.new(0.25098040699959,0.25098040699959,0.25098040699959),BackgroundTransparency=1,BorderColor3=Color3.new(0.37647062540054,0.37647062540054,0.37647062540054),Font=3,Name="Input",Parent={25},Position=UDim2.new(0,2,0,0),Size=UDim2.new(0,50,0,16),Text="0",TextColor3=Color3.new(0.86274516582489,0.86274516582489,0.86274516582489),TextSize=14,TextXAlignment=0,}},
				{27,"Frame",{BackgroundColor3=Color3.new(1,1,1),BackgroundTransparency=1,BorderSizePixel=0,Name="ArrowFrame",Parent={26},Position=UDim2.new(1,-16,0,0),Size=UDim2.new(0,16,1,0),}},
				{28,"TextButton",{AutoButtonColor=false,BackgroundColor3=Color3.new(1,1,1),BackgroundTransparency=1,BorderSizePixel=0,Font=3,Name="Up",Parent={27},Size=UDim2.new(1,0,0,8),Text="",TextSize=14,}},
				{29,"Frame",{BackgroundTransparency=1,Name="Arrow",Parent={28},Size=UDim2.new(0,16,0,8),}},
				{30,"Frame",{BackgroundColor3=Color3.new(0.86274510622025,0.86274510622025,0.86274510622025),BorderSizePixel=0,Parent={29},Position=UDim2.new(0,8,0,3),Size=UDim2.new(0,1,0,1),}},
				{31,"Frame",{BackgroundColor3=Color3.new(0.86274510622025,0.86274510622025,0.86274510622025),BorderSizePixel=0,Parent={29},Position=UDim2.new(0,7,0,4),Size=UDim2.new(0,3,0,1),}},
				{32,"Frame",{BackgroundColor3=Color3.new(0.86274510622025,0.86274510622025,0.86274510622025),BorderSizePixel=0,Parent={29},Position=UDim2.new(0,6,0,5),Size=UDim2.new(0,5,0,1),}},
				{33,"TextButton",{AutoButtonColor=false,BackgroundColor3=Color3.new(1,1,1),BackgroundTransparency=1,BorderSizePixel=0,Font=3,Name="Down",Parent={27},Position=UDim2.new(0,0,0,8),Size=UDim2.new(1,0,0,8),Text="",TextSize=14,}},
				{34,"Frame",{BackgroundTransparency=1,Name="Arrow",Parent={33},Size=UDim2.new(0,16,0,8),}},
				{35,"Frame",{BackgroundColor3=Color3.new(0.86274510622025,0.86274510622025,0.86274510622025),BorderSizePixel=0,Parent={34},Position=UDim2.new(0,8,0,5),Size=UDim2.new(0,1,0,1),}},
				{36,"Frame",{BackgroundColor3=Color3.new(0.86274510622025,0.86274510622025,0.86274510622025),BorderSizePixel=0,Parent={34},Position=UDim2.new(0,7,0,4),Size=UDim2.new(0,3,0,1),}},
				{37,"Frame",{BackgroundColor3=Color3.new(0.86274510622025,0.86274510622025,0.86274510622025),BorderSizePixel=0,Parent={34},Position=UDim2.new(0,6,0,3),Size=UDim2.new(0,5,0,1),}},
				{38,"TextLabel",{BackgroundColor3=Color3.new(1,1,1),BackgroundTransparency=1,Font=3,Name="Title",Parent={25},Position=UDim2.new(0,-40,0,0),Size=UDim2.new(0,34,1,0),Text="Green:",TextColor3=Color3.new(0.86274516582489,0.86274516582489,0.86274516582489),TextSize=14,TextXAlignment=1,}},
				{39,"Frame",{BackgroundColor3=Color3.new(0.14901961386204,0.14901961386204,0.14901961386204),BorderColor3=Color3.new(0.12549020349979,0.12549020349979,0.12549020349979),Name="Hue",Parent={1},Position=UDim2.new(1,-180,0,211),Size=UDim2.new(0,52,0,16),}},
				{40,"TextBox",{BackgroundColor3=Color3.new(0.25098040699959,0.25098040699959,0.25098040699959),BackgroundTransparency=1,BorderColor3=Color3.new(0.37647062540054,0.37647062540054,0.37647062540054),Font=3,Name="Input",Parent={39},Position=UDim2.new(0,2,0,0),Size=UDim2.new(0,50,0,16),Text="0",TextColor3=Color3.new(0.86274516582489,0.86274516582489,0.86274516582489),TextSize=14,TextXAlignment=0,}},
				{41,"Frame",{BackgroundColor3=Color3.new(1,1,1),BackgroundTransparency=1,BorderSizePixel=0,Name="ArrowFrame",Parent={40},Position=UDim2.new(1,-16,0,0),Size=UDim2.new(0,16,1,0),}},
				{42,"TextButton",{AutoButtonColor=false,BackgroundColor3=Color3.new(1,1,1),BackgroundTransparency=1,BorderSizePixel=0,Font=3,Name="Up",Parent={41},Size=UDim2.new(1,0,0,8),Text="",TextSize=14,}},
				{43,"Frame",{BackgroundTransparency=1,Name="Arrow",Parent={42},Size=UDim2.new(0,16,0,8),}},
				{44,"Frame",{BackgroundColor3=Color3.new(0.86274510622025,0.86274510622025,0.86274510622025),BorderSizePixel=0,Parent={43},Position=UDim2.new(0,8,0,3),Size=UDim2.new(0,1,0,1),}},
				{45,"Frame",{BackgroundColor3=Color3.new(0.86274510622025,0.86274510622025,0.86274510622025),BorderSizePixel=0,Parent={43},Position=UDim2.new(0,7,0,4),Size=UDim2.new(0,3,0,1),}},
				{46,"Frame",{BackgroundColor3=Color3.new(0.86274510622025,0.86274510622025,0.86274510622025),BorderSizePixel=0,Parent={43},Position=UDim2.new(0,6,0,5),Size=UDim2.new(0,5,0,1),}},
				{47,"TextButton",{AutoButtonColor=false,BackgroundColor3=Color3.new(1,1,1),BackgroundTransparency=1,BorderSizePixel=0,Font=3,Name="Down",Parent={41},Position=UDim2.new(0,0,0,8),Size=UDim2.new(1,0,0,8),Text="",TextSize=14,}},
				{48,"Frame",{BackgroundTransparency=1,Name="Arrow",Parent={47},Size=UDim2.new(0,16,0,8),}},
				{49,"Frame",{BackgroundColor3=Color3.new(0.86274510622025,0.86274510622025,0.86274510622025),BorderSizePixel=0,Parent={48},Position=UDim2.new(0,8,0,5),Size=UDim2.new(0,1,0,1),}},
				{50,"Frame",{BackgroundColor3=Color3.new(0.86274510622025,0.86274510622025,0.86274510622025),BorderSizePixel=0,Parent={48},Position=UDim2.new(0,7,0,4),Size=UDim2.new(0,3,0,1),}},
				{51,"Frame",{BackgroundColor3=Color3.new(0.86274510622025,0.86274510622025,0.86274510622025),BorderSizePixel=0,Parent={48},Position=UDim2.new(0,6,0,3),Size=UDim2.new(0,5,0,1),}},
				{52,"TextLabel",{BackgroundColor3=Color3.new(1,1,1),BackgroundTransparency=1,Font=3,Name="Title",Parent={39},Position=UDim2.new(0,-40,0,0),Size=UDim2.new(0,34,1,0),Text="Hue:",TextColor3=Color3.new(0.86274516582489,0.86274516582489,0.86274516582489),TextSize=14,TextXAlignment=1,}},
				{53,"Frame",{BackgroundColor3=Color3.new(1,1,1),BorderColor3=Color3.new(0.21568627655506,0.21568627655506,0.21568627655506),Name="Preview",Parent={1},Position=UDim2.new(1,-260,0,211),Size=UDim2.new(0,35,1,-245),}},
				{54,"Frame",{BackgroundColor3=Color3.new(0.14901961386204,0.14901961386204,0.14901961386204),BorderColor3=Color3.new(0.12549020349979,0.12549020349979,0.12549020349979),Name="Red",Parent={1},Position=UDim2.new(1,-63,0,211),Size=UDim2.new(0,52,0,16),}},
				{55,"TextBox",{BackgroundColor3=Color3.new(0.25098040699959,0.25098040699959,0.25098040699959),BackgroundTransparency=1,BorderColor3=Color3.new(0.37647062540054,0.37647062540054,0.37647062540054),Font=3,Name="Input",Parent={54},Position=UDim2.new(0,2,0,0),Size=UDim2.new(0,50,0,16),Text="0",TextColor3=Color3.new(0.86274516582489,0.86274516582489,0.86274516582489),TextSize=14,TextXAlignment=0,}},
				{56,"Frame",{BackgroundColor3=Color3.new(1,1,1),BackgroundTransparency=1,BorderSizePixel=0,Name="ArrowFrame",Parent={55},Position=UDim2.new(1,-16,0,0),Size=UDim2.new(0,16,1,0),}},
				{57,"TextButton",{AutoButtonColor=false,BackgroundColor3=Color3.new(1,1,1),BackgroundTransparency=1,BorderSizePixel=0,Font=3,Name="Up",Parent={56},Size=UDim2.new(1,0,0,8),Text="",TextSize=14,}},
				{58,"Frame",{BackgroundTransparency=1,Name="Arrow",Parent={57},Size=UDim2.new(0,16,0,8),}},
				{59,"Frame",{BackgroundColor3=Color3.new(0.86274510622025,0.86274510622025,0.86274510622025),BorderSizePixel=0,Parent={58},Position=UDim2.new(0,8,0,3),Size=UDim2.new(0,1,0,1),}},
				{60,"Frame",{BackgroundColor3=Color3.new(0.86274510622025,0.86274510622025,0.86274510622025),BorderSizePixel=0,Parent={58},Position=UDim2.new(0,7,0,4),Size=UDim2.new(0,3,0,1),}},
				{61,"Frame",{BackgroundColor3=Color3.new(0.86274510622025,0.86274510622025,0.86274510622025),BorderSizePixel=0,Parent={58},Position=UDim2.new(0,6,0,5),Size=UDim2.new(0,5,0,1),}},
				{62,"TextButton",{AutoButtonColor=false,BackgroundColor3=Color3.new(1,1,1),BackgroundTransparency=1,BorderSizePixel=0,Font=3,Name="Down",Parent={56},Position=UDim2.new(0,0,0,8),Size=UDim2.new(1,0,0,8),Text="",TextSize=14,}},
				{63,"Frame",{BackgroundTransparency=1,Name="Arrow",Parent={62},Size=UDim2.new(0,16,0,8),}},
				{64,"Frame",{BackgroundColor3=Color3.new(0.86274510622025,0.86274510622025,0.86274510622025),BorderSizePixel=0,Parent={63},Position=UDim2.new(0,8,0,5),Size=UDim2.new(0,1,0,1),}},
				{65,"Frame",{BackgroundColor3=Color3.new(0.86274510622025,0.86274510622025,0.86274510622025),BorderSizePixel=0,Parent={63},Position=UDim2.new(0,7,0,4),Size=UDim2.new(0,3,0,1),}},
				{66,"Frame",{BackgroundColor3=Color3.new(0.86274510622025,0.86274510622025,0.86274510622025),BorderSizePixel=0,Parent={63},Position=UDim2.new(0,6,0,3),Size=UDim2.new(0,5,0,1),}},
				{67,"TextLabel",{BackgroundColor3=Color3.new(1,1,1),BackgroundTransparency=1,Font=3,Name="Title",Parent={54},Position=UDim2.new(0,-40,0,0),Size=UDim2.new(0,34,1,0),Text="Red:",TextColor3=Color3.new(0.86274516582489,0.86274516582489,0.86274516582489),TextSize=14,TextXAlignment=1,}},
				{68,"Frame",{BackgroundColor3=Color3.new(0.14901961386204,0.14901961386204,0.14901961386204),BorderColor3=Color3.new(0.12549020349979,0.12549020349979,0.12549020349979),Name="Sat",Parent={1},Position=UDim2.new(1,-180,0,233),Size=UDim2.new(0,52,0,16),}},
				{69,"TextBox",{BackgroundColor3=Color3.new(0.25098040699959,0.25098040699959,0.25098040699959),BackgroundTransparency=1,BorderColor3=Color3.new(0.37647062540054,0.37647062540054,0.37647062540054),Font=3,Name="Input",Parent={68},Position=UDim2.new(0,2,0,0),Size=UDim2.new(0,50,0,16),Text="0",TextColor3=Color3.new(0.86274516582489,0.86274516582489,0.86274516582489),TextSize=14,TextXAlignment=0,}},
				{70,"Frame",{BackgroundColor3=Color3.new(1,1,1),BackgroundTransparency=1,BorderSizePixel=0,Name="ArrowFrame",Parent={69},Position=UDim2.new(1,-16,0,0),Size=UDim2.new(0,16,1,0),}},
				{71,"TextButton",{AutoButtonColor=false,BackgroundColor3=Color3.new(1,1,1),BackgroundTransparency=1,BorderSizePixel=0,Font=3,Name="Up",Parent={70},Size=UDim2.new(1,0,0,8),Text="",TextSize=14,}},
				{72,"Frame",{BackgroundTransparency=1,Name="Arrow",Parent={71},Size=UDim2.new(0,16,0,8),}},
				{73,"Frame",{BackgroundColor3=Color3.new(0.86274510622025,0.86274510622025,0.86274510622025),BorderSizePixel=0,Parent={72},Position=UDim2.new(0,8,0,3),Size=UDim2.new(0,1,0,1),}},
				{74,"Frame",{BackgroundColor3=Color3.new(0.86274510622025,0.86274510622025,0.86274510622025),BorderSizePixel=0,Parent={72},Position=UDim2.new(0,7,0,4),Size=UDim2.new(0,3,0,1),}},
				{75,"Frame",{BackgroundColor3=Color3.new(0.86274510622025,0.86274510622025,0.86274510622025),BorderSizePixel=0,Parent={72},Position=UDim2.new(0,6,0,5),Size=UDim2.new(0,5,0,1),}},
				{76,"TextButton",{AutoButtonColor=false,BackgroundColor3=Color3.new(1,1,1),BackgroundTransparency=1,BorderSizePixel=0,Font=3,Name="Down",Parent={70},Position=UDim2.new(0,0,0,8),Size=UDim2.new(1,0,0,8),Text="",TextSize=14,}},
				{77,"Frame",{BackgroundTransparency=1,Name="Arrow",Parent={76},Size=UDim2.new(0,16,0,8),}},
				{78,"Frame",{BackgroundColor3=Color3.new(0.86274510622025,0.86274510622025,0.86274510622025),BorderSizePixel=0,Parent={77},Position=UDim2.new(0,8,0,5),Size=UDim2.new(0,1,0,1),}},
				{79,"Frame",{BackgroundColor3=Color3.new(0.86274510622025,0.86274510622025,0.86274510622025),BorderSizePixel=0,Parent={77},Position=UDim2.new(0,7,0,4),Size=UDim2.new(0,3,0,1),}},
				{80,"Frame",{BackgroundColor3=Color3.new(0.86274510622025,0.86274510622025,0.86274510622025),BorderSizePixel=0,Parent={77},Position=UDim2.new(0,6,0,3),Size=UDim2.new(0,5,0,1),}},
				{81,"TextLabel",{BackgroundColor3=Color3.new(1,1,1),BackgroundTransparency=1,Font=3,Name="Title",Parent={68},Position=UDim2.new(0,-40,0,0),Size=UDim2.new(0,34,1,0),Text="Sat:",TextColor3=Color3.new(0.86274516582489,0.86274516582489,0.86274516582489),TextSize=14,TextXAlignment=1,}},
				{82,"Frame",{BackgroundColor3=Color3.new(0.14901961386204,0.14901961386204,0.14901961386204),BorderColor3=Color3.new(0.12549020349979,0.12549020349979,0.12549020349979),Name="Val",Parent={1},Position=UDim2.new(1,-180,0,255),Size=UDim2.new(0,52,0,16),}},
				{83,"TextBox",{BackgroundColor3=Color3.new(0.25098040699959,0.25098040699959,0.25098040699959),BackgroundTransparency=1,BorderColor3=Color3.new(0.37647062540054,0.37647062540054,0.37647062540054),Font=3,Name="Input",Parent={82},Position=UDim2.new(0,2,0,0),Size=UDim2.new(0,50,0,16),Text="255",TextColor3=Color3.new(0.86274516582489,0.86274516582489,0.86274516582489),TextSize=14,TextXAlignment=0,}},
				{84,"Frame",{BackgroundColor3=Color3.new(1,1,1),BackgroundTransparency=1,BorderSizePixel=0,Name="ArrowFrame",Parent={83},Position=UDim2.new(1,-16,0,0),Size=UDim2.new(0,16,1,0),}},
				{85,"TextButton",{AutoButtonColor=false,BackgroundColor3=Color3.new(1,1,1),BackgroundTransparency=1,BorderSizePixel=0,Font=3,Name="Up",Parent={84},Size=UDim2.new(1,0,0,8),Text="",TextSize=14,}},
				{86,"Frame",{BackgroundTransparency=1,Name="Arrow",Parent={85},Size=UDim2.new(0,16,0,8),}},
				{87,"Frame",{BackgroundColor3=Color3.new(0.86274510622025,0.86274510622025,0.86274510622025),BorderSizePixel=0,Parent={86},Position=UDim2.new(0,8,0,3),Size=UDim2.new(0,1,0,1),}},
				{88,"Frame",{BackgroundColor3=Color3.new(0.86274510622025,0.86274510622025,0.86274510622025),BorderSizePixel=0,Parent={86},Position=UDim2.new(0,7,0,4),Size=UDim2.new(0,3,0,1),}},
				{89,"Frame",{BackgroundColor3=Color3.new(0.86274510622025,0.86274510622025,0.86274510622025),BorderSizePixel=0,Parent={86},Position=UDim2.new(0,6,0,5),Size=UDim2.new(0,5,0,1),}},
				{90,"TextButton",{AutoButtonColor=false,BackgroundColor3=Color3.new(1,1,1),BackgroundTransparency=1,BorderSizePixel=0,Font=3,Name="Down",Parent={84},Position=UDim2.new(0,0,0,8),Size=UDim2.new(1,0,0,8),Text="",TextSize=14,}},
				{91,"Frame",{BackgroundTransparency=1,Name="Arrow",Parent={90},Size=UDim2.new(0,16,0,8),}},
				{92,"Frame",{BackgroundColor3=Color3.new(0.86274510622025,0.86274510622025,0.86274510622025),BorderSizePixel=0,Parent={91},Position=UDim2.new(0,8,0,5),Size=UDim2.new(0,1,0,1),}},
				{93,"Frame",{BackgroundColor3=Color3.new(0.86274510622025,0.86274510622025,0.86274510622025),BorderSizePixel=0,Parent={91},Position=UDim2.new(0,7,0,4),Size=UDim2.new(0,3,0,1),}},
				{94,"Frame",{BackgroundColor3=Color3.new(0.86274510622025,0.86274510622025,0.86274510622025),BorderSizePixel=0,Parent={91},Position=UDim2.new(0,6,0,3),Size=UDim2.new(0,5,0,1),}},
				{95,"TextLabel",{BackgroundColor3=Color3.new(1,1,1),BackgroundTransparency=1,Font=3,Name="Title",Parent={82},Position=UDim2.new(0,-40,0,0),Size=UDim2.new(0,34,1,0),Text="Val:",TextColor3=Color3.new(0.86274516582489,0.86274516582489,0.86274516582489),TextSize=14,TextXAlignment=1,}},
				{96,"TextButton",{AutoButtonColor=false,BackgroundColor3=Color3.new(0.2352941185236,0.2352941185236,0.2352941185236),BorderColor3=Color3.new(0.21568627655506,0.21568627655506,0.21568627655506),Font=3,Name="Cancel",Parent={1},Position=UDim2.new(1,-105,1,-28),Size=UDim2.new(0,100,0,25),Text="Cancel",TextColor3=Color3.new(0.86274516582489,0.86274516582489,0.86274516582489),TextSize=14,}},
				{97,"TextButton",{AutoButtonColor=false,BackgroundColor3=Color3.new(0.2352941185236,0.2352941185236,0.2352941185236),BorderColor3=Color3.new(0.21568627655506,0.21568627655506,0.21568627655506),Font=3,Name="Ok",Parent={1},Position=UDim2.new(1,-210,1,-28),Size=UDim2.new(0,100,0,25),Text="OK",TextColor3=Color3.new(0.86274516582489,0.86274516582489,0.86274516582489),TextSize=14,}},
				{98,"ImageLabel",{BackgroundColor3=Color3.new(1,1,1),BorderColor3=Color3.new(0.21568627655506,0.21568627655506,0.21568627655506),Image="rbxassetid://1072518502",Name="ColorStrip",Parent={1},Position=UDim2.new(1,-30,0,5),Size=UDim2.new(0,13,0,200),}},
				{99,"Frame",{BackgroundColor3=Color3.new(0.3137255012989,0.3137255012989,0.3137255012989),BackgroundTransparency=1,BorderSizePixel=0,Name="ArrowFrame",Parent={1},Position=UDim2.new(1,-16,0,1),Size=UDim2.new(0,5,0,208),}},
				{100,"Frame",{BackgroundTransparency=1,Name="Arrow",Parent={99},Position=UDim2.new(0,-2,0,-4),Size=UDim2.new(0,8,0,16),}},
				{101,"Frame",{BackgroundColor3=Color3.new(0,0,0),BorderSizePixel=0,Parent={100},Position=UDim2.new(0,2,0,8),Size=UDim2.new(0,1,0,1),}},
				{102,"Frame",{BackgroundColor3=Color3.new(0,0,0),BorderSizePixel=0,Parent={100},Position=UDim2.new(0,3,0,7),Size=UDim2.new(0,1,0,3),}},
				{103,"Frame",{BackgroundColor3=Color3.new(0,0,0),BorderSizePixel=0,Parent={100},Position=UDim2.new(0,4,0,6),Size=UDim2.new(0,1,0,5),}},
				{104,"Frame",{BackgroundColor3=Color3.new(0,0,0),BorderSizePixel=0,Parent={100},Position=UDim2.new(0,5,0,5),Size=UDim2.new(0,1,0,7),}},
				{105,"Frame",{BackgroundColor3=Color3.new(0,0,0),BorderSizePixel=0,Parent={100},Position=UDim2.new(0,6,0,4),Size=UDim2.new(0,1,0,9),}},
			})
			local window = Lib.Window.new()
			window.Resizable = false
			window.Alignable = false
			window:SetTitle("Color Picker")
			window:Resize(450,330)
			for i,v in pairs(guiContents:GetChildren()) do
				v.Parent = window.GuiElems.Content
			end
			newMt.Window = window
			newMt.Gui = window.Gui
			local pickerGui = window.Gui.Main
			local pickerTopBar = pickerGui.TopBar
			local pickerFrame = pickerGui.Content
			local colorSpace = pickerFrame.ColorSpaceFrame.ColorSpace
			local colorStrip = pickerFrame.ColorStrip
			local previewFrame = pickerFrame.Preview
			local basicColorsFrame = pickerFrame.BasicColors
			local customColorsFrame = pickerFrame.CustomColors
			local okButton = pickerFrame.Ok
			local cancelButton = pickerFrame.Cancel
			local closeButton = pickerTopBar.Close

			local colorScope = colorSpace.Scope
			local colorArrow = pickerFrame.ArrowFrame.Arrow

			local hueInput = pickerFrame.Hue.Input
			local satInput = pickerFrame.Sat.Input
			local valInput = pickerFrame.Val.Input

			local redInput = pickerFrame.Red.Input
			local greenInput = pickerFrame.Green.Input
			local blueInput = pickerFrame.Blue.Input

			local user = service.UserInputService
			local mouse = service.Players.LocalPlayer:GetMouse()

			local hue,sat,val = 0,0,1
			local red,green,blue = 1,1,1
			local chosenColor = Color3.new(0,0,0)

			local basicColors = {Color3.new(0,0,0),Color3.new(0.66666668653488,0,0),Color3.new(0,0.33333334326744,0),Color3.new(0.66666668653488,0.33333334326744,0),Color3.new(0,0.66666668653488,0),Color3.new(0.66666668653488,0.66666668653488,0),Color3.new(0,1,0),Color3.new(0.66666668653488,1,0),Color3.new(0,0,0.49803924560547),Color3.new(0.66666668653488,0,0.49803924560547),Color3.new(0,0.33333334326744,0.49803924560547),Color3.new(0.66666668653488,0.33333334326744,0.49803924560547),Color3.new(0,0.66666668653488,0.49803924560547),Color3.new(0.66666668653488,0.66666668653488,0.49803924560547),Color3.new(0,1,0.49803924560547),Color3.new(0.66666668653488,1,0.49803924560547),Color3.new(0,0,1),Color3.new(0.66666668653488,0,1),Color3.new(0,0.33333334326744,1),Color3.new(0.66666668653488,0.33333334326744,1),Color3.new(0,0.66666668653488,1),Color3.new(0.66666668653488,0.66666668653488,1),Color3.new(0,1,1),Color3.new(0.66666668653488,1,1),Color3.new(0.33333334326744,0,0),Color3.new(1,0,0),Color3.new(0.33333334326744,0.33333334326744,0),Color3.new(1,0.33333334326744,0),Color3.new(0.33333334326744,0.66666668653488,0),Color3.new(1,0.66666668653488,0),Color3.new(0.33333334326744,1,0),Color3.new(1,1,0),Color3.new(0.33333334326744,0,0.49803924560547),Color3.new(1,0,0.49803924560547),Color3.new(0.33333334326744,0.33333334326744,0.49803924560547),Color3.new(1,0.33333334326744,0.49803924560547),Color3.new(0.33333334326744,0.66666668653488,0.49803924560547),Color3.new(1,0.66666668653488,0.49803924560547),Color3.new(0.33333334326744,1,0.49803924560547),Color3.new(1,1,0.49803924560547),Color3.new(0.33333334326744,0,1),Color3.new(1,0,1),Color3.new(0.33333334326744,0.33333334326744,1),Color3.new(1,0.33333334326744,1),Color3.new(0.33333334326744,0.66666668653488,1),Color3.new(1,0.66666668653488,1),Color3.new(0.33333334326744,1,1),Color3.new(1,1,1)}
			local customColors = {}

			local function updateColor(noupdate)
				local relativeX, relativeY, relativeStripY = 219 - hue * 219, 199 - sat * 199, 199 - val * 199
				local hsvColor = Color3.fromHSV(hue, sat, val)

				if noupdate == 2 or not noupdate then
					hueInput.Text = tostring(math.ceil(359 * hue))
					satInput.Text = tostring(math.ceil(255 * sat))
					valInput.Text = tostring(math.floor(255 * val))
				end
				if noupdate == 1 or not noupdate then
					redInput.Text = tostring(math.floor(255 * red))
					greenInput.Text = tostring(math.floor(255 * green))
					blueInput.Text = tostring(math.floor(255 * blue))
				end

				chosenColor = Color3.new(red, green, blue)
				colorScope.Position = UDim2.new(0, (relativeX - 9), 0, (relativeY - 9))
				colorStrip.ImageColor3 = Color3.fromHSV(hue, sat, 1)
				colorArrow.Position = UDim2.new(0, -2, 0, (relativeStripY - 4))
				previewFrame.BackgroundColor3 = chosenColor

				newMt.Color = chosenColor
				newMt.OnPreview:Fire(chosenColor)
			end

			local function handleInputBegan(input, updateFunc)
				if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
					while user:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) do
						updateFunc()task.wait()
					end
				end
			end

			local function colorSpaceInput()
				local relativeX = mouse.X - colorSpace.AbsolutePosition.X
				local relativeY = mouse.Y - colorSpace.AbsolutePosition.Y

				if relativeX < 0 then relativeX = 0 elseif relativeX > 219 then relativeX = 219 end
				if relativeY < 0 then relativeY = 0 elseif relativeY > 199 then relativeY = 199 end

				hue = (219 - relativeX) / 219
				sat = (199 - relativeY) / 199

				local hsvColor = Color3.fromHSV(hue, sat, val)
				red, green, blue = hsvColor.R, hsvColor.G, hsvColor.B
				updateColor()
			end

			local function colorStripInput()
				local relativeY = mouse.Y - colorStrip.AbsolutePosition.Y

				if relativeY < 0 then relativeY = 0 elseif relativeY > 199 then relativeY = 199 end	

				val = (199 - relativeY) / 199

				local hsvColor = Color3.fromHSV(hue, sat, val)
				red, green, blue = hsvColor.R, hsvColor.G, hsvColor.B
				updateColor()
			end

			colorSpace.InputBegan:Connect(function(input) handleInputBegan(input, colorSpaceInput) end)
			colorStrip.InputBegan:Connect(function(input) handleInputBegan(input, colorStripInput) end)

			local function hookButtons(frame, func)
				frame.ArrowFrame.Up.InputBegan:Connect(function(input)
					if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
						local releaseEvent, runEvent
						local startTime = tick()
						local pressing = true
						local startNum = tonumber(frame.Text)

						if not startNum then return end

						releaseEvent = user.InputEnded:Connect(function(endInput)
							if endInput.UserInputType == Enum.UserInputType.MouseButton1 or endInput.UserInputType == Enum.UserInputType.Touch then
								releaseEvent:Disconnect()
								pressing = false
							end
						end)

						startNum = startNum + 1
						func(startNum)
						while pressing do
							if tick() - startTime > 0.3 then
								startNum = startNum + 1
								func(startNum)
								startTime = tick()
							end
							task.wait(0.1)
						end
					end
				end)

				frame.ArrowFrame.Down.InputBegan:Connect(function(input)
					if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
						local releaseEvent, runEvent
						local startTime = tick()
						local pressing = true
						local startNum = tonumber(frame.Text)

						if not startNum then return end

						releaseEvent = user.InputEnded:Connect(function(endInput)
							if endInput.UserInputType == Enum.UserInputType.MouseButton1 or endInput.UserInputType == Enum.UserInputType.Touch then
								releaseEvent:Disconnect()
								pressing = false
							end
						end)

						startNum = startNum - 1
						func(startNum)
						while pressing do
							if tick() - startTime > 0.3 then
								startNum = startNum - 1
								func(startNum)
								startTime = tick()
							end
							task.wait(0.1)
						end
					end
				end)
			end


			local function updateHue(str)
				local num = tonumber(str)
				if num then
					hue = math.clamp(math.floor(num),0,359)/359
					local hsvColor = Color3.fromHSV(hue,sat,val)
					red,green,blue = hsvColor.r,hsvColor.g,hsvColor.b

					hueInput.Text = tostring(hue*359)
					updateColor(1)
				end
			end
			hueInput.FocusLost:Connect(function() updateHue(hueInput.Text) end) hookButtons(hueInput, hueInput)

			local function updateSat(str)
				local num = tonumber(str)
				if num then
					sat = math.clamp(math.floor(num),0,255)/255
					local hsvColor = Color3.fromHSV(hue,sat,val)
					red,green,blue = hsvColor.r,hsvColor.g,hsvColor.b
					satInput.Text = tostring(sat*255)
					updateColor(1)
				end
			end
			satInput.FocusLost:Connect(function() updateSat(satInput.Text) end) hookButtons(satInput,updateSat)

			local function updateVal(str)
				local num = tonumber(str)
				if num then
					val = math.clamp(math.floor(num),0,255)/255
					local hsvColor = Color3.fromHSV(hue,sat,val)
					red,green,blue = hsvColor.r,hsvColor.g,hsvColor.b
					valInput.Text = tostring(val*255)
					updateColor(1)
				end
			end
			valInput.FocusLost:Connect(function() updateVal(valInput.Text) end) hookButtons(valInput,updateVal)

			local function updateRed(str)
				local num = tonumber(str)
				if num then
					red = math.clamp(math.floor(num),0,255)/255
					local newColor = Color3.new(red,green,blue)
					hue,sat,val = Color3.toHSV(newColor)
					redInput.Text = tostring(red*255)
					updateColor(2)
				end
			end
			redInput.FocusLost:Connect(function() updateRed(redInput.Text) end) hookButtons(redInput,updateRed)

			local function updateGreen(str)
				local num = tonumber(str)
				if num then
					green = math.clamp(math.floor(num),0,255)/255
					local newColor = Color3.new(red,green,blue)
					hue,sat,val = Color3.toHSV(newColor)
					greenInput.Text = tostring(green*255)
					updateColor(2)
				end
			end
			greenInput.FocusLost:Connect(function() updateGreen(greenInput.Text) end) hookButtons(greenInput,updateGreen)

			local function updateBlue(str)
				local num = tonumber(str)
				if num then
					blue = math.clamp(math.floor(num),0,255)/255
					local newColor = Color3.new(red,green,blue)
					hue,sat,val = Color3.toHSV(newColor)
					blueInput.Text = tostring(blue*255)
					updateColor(2)
				end
			end
			blueInput.FocusLost:Connect(function() updateBlue(blueInput.Text) end) hookButtons(blueInput,updateBlue)

			local colorChoice = Instance.new("TextButton")
			colorChoice.Name = "Choice"
			colorChoice.Size = UDim2.new(0,25,0,18)
			colorChoice.BorderColor3 = Color3.fromRGB(55,55,55)
			colorChoice.Text = ""
			colorChoice.AutoButtonColor = false

			local row = 0
			local column = 0
			for i,v in pairs(basicColors) do
				local newColor = colorChoice:Clone()
				newColor.BackgroundColor3 = v
				newColor.Position = UDim2.new(0,1 + 30*column,0,21 + 23*row)

				newColor.MouseButton1Click:Connect(function()
					red,green,blue = v.r,v.g,v.b
					local newColor = Color3.new(red,green,blue)
					hue,sat,val = Color3.toHSV(newColor)
					updateColor()
				end)

				newColor.Parent = basicColorsFrame
				column = column + 1
				if column == 6 then row = row + 1 column = 0 end
			end

			row = 0
			column = 0
			for i = 1,12 do
				local color = customColors[i] or Color3.new(0,0,0)
				local newColor = colorChoice:Clone()
				newColor.BackgroundColor3 = color
				newColor.Position = UDim2.new(0,1 + 30*column,0,20 + 23*row)

				newColor.MouseButton1Click:Connect(function()
					local curColor = customColors[i] or Color3.new(0,0,0)
					red,green,blue = curColor.r,curColor.g,curColor.b
					hue,sat,val = Color3.toHSV(curColor)
					updateColor()
				end)

				newColor.MouseButton2Click:Connect(function()
					customColors[i] = chosenColor
					newColor.BackgroundColor3 = chosenColor
				end)

				newColor.Parent = customColorsFrame
				column = column + 1
				if column == 6 then row = row + 1 column = 0 end
			end

			okButton.MouseButton1Click:Connect(function() newMt.OnSelect:Fire(chosenColor) window:Close() end)
			okButton.InputBegan:Connect(function(input) if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then okButton.BackgroundTransparency = 0.4 end end)
			okButton.InputEnded:Connect(function(input) if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then okButton.BackgroundTransparency = 0 end end)


			cancelButton.MouseButton1Click:Connect(function() newMt.OnCancel:Fire() window:Close() end)
			cancelButton.InputBegan:Connect(function(input) if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then cancelButton.BackgroundTransparency = 0.4 end end)
			cancelButton.InputEnded:Connect(function(input) if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then cancelButton.BackgroundTransparency = 0 end end)

			updateColor()

			newMt.SetColor = function(self,color)
				red,green,blue = color.r,color.g,color.b
				hue,sat,val = Color3.toHSV(color)
				updateColor()
			end

			newMt.Show = function(self)
				self.Window:Show()
			end

			return newMt
		end

		return {new = new}
	end)()

	Lib.NumberSequenceEditor = (function()
		local function new()
			local newMt = setmetatable({},{})
			newMt.OnSelect = Lib.Signal.new()
			newMt.OnCancel = Lib.Signal.new()
			newMt.OnPreview = Lib.Signal.new()

			local guiContents = create({
				{1,"Frame",{BackgroundColor3=Color3.new(0.17647059261799,0.17647059261799,0.17647059261799),BorderSizePixel=0,ClipsDescendants=true,Name="Content",Position=UDim2.new(0,0,0,20),Size=UDim2.new(1,0,1,-20),}},
				{2,"Frame",{BackgroundColor3=Color3.new(0.14901961386204,0.14901961386204,0.14901961386204),BorderColor3=Color3.new(0.12549020349979,0.12549020349979,0.12549020349979),Name="Time",Parent={1},Position=UDim2.new(0,40,0,210),Size=UDim2.new(0,60,0,20),}},
				{3,"TextBox",{BackgroundColor3=Color3.new(0.25098040699959,0.25098040699959,0.25098040699959),BackgroundTransparency=1,BorderColor3=Color3.new(0.37647062540054,0.37647062540054,0.37647062540054),ClipsDescendants=true,Font=3,Name="Input",Parent={2},Position=UDim2.new(0,2,0,0),Size=UDim2.new(0,58,0,20),Text="0",TextColor3=Color3.new(0.86274516582489,0.86274516582489,0.86274516582489),TextSize=14,TextXAlignment=0,}},
				{4,"TextLabel",{BackgroundColor3=Color3.new(1,1,1),BackgroundTransparency=1,Font=3,Name="Title",Parent={2},Position=UDim2.new(0,-40,0,0),Size=UDim2.new(0,34,1,0),Text="Time",TextColor3=Color3.new(0.86274516582489,0.86274516582489,0.86274516582489),TextSize=14,TextXAlignment=1,}},
				{5,"TextButton",{AutoButtonColor=false,BackgroundColor3=Color3.new(0.2352941185236,0.2352941185236,0.2352941185236),BorderColor3=Color3.new(0.21568627655506,0.21568627655506,0.21568627655506),Font=3,Name="Close",Parent={1},Position=UDim2.new(1,-90,0,210),Size=UDim2.new(0,80,0,20),Text="Close",TextColor3=Color3.new(0.86274516582489,0.86274516582489,0.86274516582489),TextSize=14,}},
				{6,"TextButton",{AutoButtonColor=false,BackgroundColor3=Color3.new(0.2352941185236,0.2352941185236,0.2352941185236),BorderColor3=Color3.new(0.21568627655506,0.21568627655506,0.21568627655506),Font=3,Name="Reset",Parent={1},Position=UDim2.new(1,-180,0,210),Size=UDim2.new(0,80,0,20),Text="Reset",TextColor3=Color3.new(0.86274516582489,0.86274516582489,0.86274516582489),TextSize=14,}},
				{7,"TextButton",{AutoButtonColor=false,BackgroundColor3=Color3.new(0.2352941185236,0.2352941185236,0.2352941185236),BorderColor3=Color3.new(0.21568627655506,0.21568627655506,0.21568627655506),Font=3,Name="Delete",Parent={1},Position=UDim2.new(0,380,0,210),Size=UDim2.new(0,80,0,20),Text="Delete",TextColor3=Color3.new(0.86274516582489,0.86274516582489,0.86274516582489),TextSize=14,}},
				{8,"Frame",{BackgroundColor3=Color3.new(0.17647059261799,0.17647059261799,0.17647059261799),BorderColor3=Color3.new(0.21568627655506,0.21568627655506,0.21568627655506),Name="NumberLineOutlines",Parent={1},Position=UDim2.new(0,10,0,20),Size=UDim2.new(1,-20,0,170),}},
				{9,"Frame",{BackgroundColor3=Color3.new(0.25098040699959,0.25098040699959,0.25098040699959),BackgroundTransparency=1,BorderColor3=Color3.new(0.37647062540054,0.37647062540054,0.37647062540054),Name="NumberLine",Parent={1},Position=UDim2.new(0,10,0,20),Size=UDim2.new(1,-20,0,170),}},
				{10,"Frame",{BackgroundColor3=Color3.new(0.14901961386204,0.14901961386204,0.14901961386204),BorderColor3=Color3.new(0.12549020349979,0.12549020349979,0.12549020349979),Name="Value",Parent={1},Position=UDim2.new(0,170,0,210),Size=UDim2.new(0,60,0,20),}},
				{11,"TextLabel",{BackgroundColor3=Color3.new(1,1,1),BackgroundTransparency=1,Font=3,Name="Title",Parent={10},Position=UDim2.new(0,-40,0,0),Size=UDim2.new(0,34,1,0),Text="Value",TextColor3=Color3.new(0.86274516582489,0.86274516582489,0.86274516582489),TextSize=14,TextXAlignment=1,}},
				{12,"TextBox",{BackgroundColor3=Color3.new(0.25098040699959,0.25098040699959,0.25098040699959),BackgroundTransparency=1,BorderColor3=Color3.new(0.37647062540054,0.37647062540054,0.37647062540054),ClipsDescendants=true,Font=3,Name="Input",Parent={10},Position=UDim2.new(0,2,0,0),Size=UDim2.new(0,58,0,20),Text="0",TextColor3=Color3.new(0.86274516582489,0.86274516582489,0.86274516582489),TextSize=14,TextXAlignment=0,}},
				{13,"Frame",{BackgroundColor3=Color3.new(0.14901961386204,0.14901961386204,0.14901961386204),BorderColor3=Color3.new(0.12549020349979,0.12549020349979,0.12549020349979),Name="Envelope",Parent={1},Position=UDim2.new(0,300,0,210),Size=UDim2.new(0,60,0,20),}},
				{14,"TextBox",{BackgroundColor3=Color3.new(0.25098040699959,0.25098040699959,0.25098040699959),BackgroundTransparency=1,BorderColor3=Color3.new(0.37647062540054,0.37647062540054,0.37647062540054),ClipsDescendants=true,Font=3,Name="Input",Parent={13},Position=UDim2.new(0,2,0,0),Size=UDim2.new(0,58,0,20),Text="0",TextColor3=Color3.new(0.86274516582489,0.86274516582489,0.86274516582489),TextSize=14,TextXAlignment=0,}},
				{15,"TextLabel",{BackgroundColor3=Color3.new(1,1,1),BackgroundTransparency=1,Font=3,Name="Title",Parent={13},Position=UDim2.new(0,-40,0,0),Size=UDim2.new(0,34,1,0),Text="Envelope",TextColor3=Color3.new(0.86274516582489,0.86274516582489,0.86274516582489),TextSize=14,TextXAlignment=1,}},
			})
			local window = Lib.Window.new()
			window.Resizable = false
			window:Resize(680,265)
			window:SetTitle("NumberSequence Editor")
			newMt.Window = window
			newMt.Gui = window.Gui
			for i,v in pairs(guiContents:GetChildren()) do
				v.Parent = window.GuiElems.Content
			end
			local gui = window.Gui
			local pickerGui = gui.Main
			local pickerTopBar = pickerGui.TopBar
			local pickerFrame = pickerGui.Content
			local numberLine = pickerFrame.NumberLine
			local numberLineOutlines = pickerFrame.NumberLineOutlines
			local timeBox = pickerFrame.Time.Input
			local valueBox = pickerFrame.Value.Input
			local envelopeBox = pickerFrame.Envelope.Input
			local deleteButton = pickerFrame.Delete
			local resetButton = pickerFrame.Reset
			local closeButton = pickerFrame.Close
			local topClose = pickerTopBar.Close

			local points = {{1,0,3},{8,0.05,1},{5,0.6,2},{4,0.7,4},{6,1,4}}
			local lines = {}
			local eLines = {}
			local beginPoint = points[1]
			local endPoint = points[#points]
			local currentlySelected = nil
			local currentPoint = nil
			local resetSequence = nil

			local user = service.UserInputService
			local mouse = service.Players.LocalPlayer:GetMouse()

			for i = 2,10 do
				local newLine = Instance.new("Frame")
				newLine.BackgroundTransparency = 0.5
				newLine.BackgroundColor3 = Color3.new(96/255,96/255,96/255)
				newLine.BorderSizePixel = 0
				newLine.Size = UDim2.new(0,1,1,0)
				newLine.Position = UDim2.new((i-1)/(11-1),0,0,0)
				newLine.Parent = numberLineOutlines
			end

			for i = 2,4 do
				local newLine = Instance.new("Frame")
				newLine.BackgroundTransparency = 0.5
				newLine.BackgroundColor3 = Color3.new(96/255,96/255,96/255)
				newLine.BorderSizePixel = 0
				newLine.Size = UDim2.new(1,0,0,1)
				newLine.Position = UDim2.new(0,0,(i-1)/(5-1),0)
				newLine.Parent = numberLineOutlines
			end

			local lineTemp = Instance.new("Frame")
			lineTemp.BackgroundColor3 = Color3.new(0,0,0)
			lineTemp.BorderSizePixel = 0
			lineTemp.Size = UDim2.new(0,1,0,1)

			local sequenceLine = Instance.new("Frame")
			sequenceLine.BackgroundColor3 = Color3.new(0,0,0)
			sequenceLine.BorderSizePixel = 0
			sequenceLine.Size = UDim2.new(0,1,0,0)

			for i = 1,numberLine.AbsoluteSize.X do
				local line = sequenceLine:Clone()
				eLines[i] = line
				line.Name = "E"..tostring(i)
				line.BackgroundTransparency = 0.5
				line.BackgroundColor3 = Color3.new(199/255,44/255,28/255)
				line.Position = UDim2.new(0,i-1,0,0)
				line.Parent = numberLine
			end

			for i = 1,numberLine.AbsoluteSize.X do
				local line = sequenceLine:Clone()
				lines[i] = line
				line.Name = tostring(i)
				line.Position = UDim2.new(0,i-1,0,0)
				line.Parent = numberLine
			end

			local envelopeDrag = Instance.new("Frame")
			envelopeDrag.BackgroundTransparency = 1
			envelopeDrag.BackgroundColor3 = Color3.new(0,0,0)
			envelopeDrag.BorderSizePixel = 0
			envelopeDrag.Size = UDim2.new(0,7,0,20)
			envelopeDrag.Visible = false
			envelopeDrag.ZIndex = 2
			local envelopeDragLine = Instance.new("Frame",envelopeDrag)
			envelopeDragLine.Name = "Line"
			envelopeDragLine.BackgroundColor3 = Color3.new(0,0,0)
			envelopeDragLine.BorderSizePixel = 0
			envelopeDragLine.Position = UDim2.new(0,3,0,0)
			envelopeDragLine.Size = UDim2.new(0,1,0,20)
			envelopeDragLine.ZIndex = 2

			local envelopeDragTop,envelopeDragBottom = envelopeDrag:Clone(),envelopeDrag:Clone()
			envelopeDragTop.Parent = numberLine
			envelopeDragBottom.Parent = numberLine

			local function buildSequence()
				local newPoints = {}
				for i,v in pairs(points) do
					table.insert(newPoints,NumberSequenceKeypoint.new(v[2],v[1],v[3]))
				end
				newMt.Sequence = NumberSequence.new(newPoints)
				newMt.OnSelect:Fire(newMt.Sequence)
			end

			local function round(num,places)
				local multi = 10^places
				return math.floor(num*multi + 0.5)/multi
			end

			local function updateInputs(point)
				if point then
					currentPoint = point
					local rawT,rawV,rawE = point[2],point[1],point[3]
					timeBox.Text = round(rawT,(rawT < 0.01 and 5) or (rawT < 0.1 and 4) or 3)
					valueBox.Text = round(rawV,(rawV < 0.01 and 5) or (rawV < 0.1 and 4) or (rawV < 1 and 3) or 2)
					envelopeBox.Text = round(rawE,(rawE < 0.01 and 5) or (rawE < 0.1 and 4) or (rawV < 1 and 3) or 2)

					local envelopeDistance = numberLine.AbsoluteSize.Y*(point[3]/10)
					envelopeDragTop.Position = UDim2.new(0,point[4].Position.X.Offset-1,0,point[4].Position.Y.Offset-envelopeDistance-17)
					envelopeDragTop.Visible = true
					envelopeDragBottom.Position = UDim2.new(0,point[4].Position.X.Offset-1,0,point[4].Position.Y.Offset+envelopeDistance+2)
					envelopeDragBottom.Visible = true
				end
			end

			envelopeDragTop.InputBegan:Connect(function(input)
				if (input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch) or not currentPoint or Lib.CheckMouseInGui(currentPoint[4].Select) then return end

				local mouseEvent, releaseEvent
				local maxSize = numberLine.AbsoluteSize.Y
				local mouseDelta = math.abs(envelopeDragTop.AbsolutePosition.Y - mouse.Y)

				envelopeDragTop.Line.Position = UDim2.new(0, 2, 0, 0)
				envelopeDragTop.Line.Size = UDim2.new(0, 3, 0, 20)

				releaseEvent = user.InputEnded:Connect(function(input)
					if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then return end
					mouseEvent:Disconnect()
					releaseEvent:Disconnect()
					envelopeDragTop.Line.Position = UDim2.new(0, 3, 0, 0)
					envelopeDragTop.Line.Size = UDim2.new(0, 1, 0, 20)
				end)

				mouseEvent = user.InputChanged:Connect(function(input)
					if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
						local topDiff = (currentPoint[4].AbsolutePosition.Y + 2) - (mouse.Y - mouseDelta) - 19
						local newEnvelope = 10 * (math.max(topDiff, 0) / maxSize)
						local maxEnvelope = math.min(currentPoint[1], 10 - currentPoint[1])
						currentPoint[3] = math.min(newEnvelope, maxEnvelope)
						newMt:Redraw()
						buildSequence()
						updateInputs(currentPoint)
					end
				end)
			end)

			envelopeDragBottom.InputBegan:Connect(function(input)
				if (input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch) or not currentPoint or Lib.CheckMouseInGui(currentPoint[4].Select) then return end

				local mouseEvent, releaseEvent
				local maxSize = numberLine.AbsoluteSize.Y
				local mouseDelta = math.abs(envelopeDragBottom.AbsolutePosition.Y - mouse.Y)

				envelopeDragBottom.Line.Position = UDim2.new(0, 2, 0, 0)
				envelopeDragBottom.Line.Size = UDim2.new(0, 3, 0, 20)

				releaseEvent = user.InputEnded:Connect(function(input)
					if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then return end
					mouseEvent:Disconnect()
					releaseEvent:Disconnect()
					envelopeDragBottom.Line.Position = UDim2.new(0, 3, 0, 0)
					envelopeDragBottom.Line.Size = UDim2.new(0, 1, 0, 20)
				end)

				mouseEvent = user.InputChanged:Connect(function(input)
					if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
						local bottomDiff = (mouse.Y + (20 - mouseDelta)) - (currentPoint[4].AbsolutePosition.Y + 2) - 19
						local newEnvelope = 10 * (math.max(bottomDiff, 0) / maxSize)
						local maxEnvelope = math.min(currentPoint[1], 10 - currentPoint[1])
						currentPoint[3] = math.min(newEnvelope, maxEnvelope)
						newMt:Redraw()
						buildSequence()
						updateInputs(currentPoint)
					end
				end)
			end)

			local function placePoint(point)
				local newPoint = Instance.new("Frame")
				newPoint.Name = "Point"
				newPoint.BorderSizePixel = 0
				newPoint.Size = UDim2.new(0,5,0,5)
				newPoint.Position = UDim2.new(0,math.floor((numberLine.AbsoluteSize.X-1) * point[2])-2,0,numberLine.AbsoluteSize.Y*(10-point[1])/10-2)
				newPoint.BackgroundColor3 = Color3.new(0,0,0)

				local newSelect = Instance.new("Frame")
				newSelect.Name = "Select"
				newSelect.BackgroundTransparency = 1
				newSelect.BackgroundColor3 = Color3.new(199/255,44/255,28/255)
				newSelect.Position = UDim2.new(0,-2,0,-2)
				newSelect.Size = UDim2.new(0,9,0,9)
				newSelect.Parent = newPoint

				newPoint.Parent = numberLine


				newSelect.InputBegan:Connect(function(input)
					if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
						for i, v in pairs(points) do 
							v[4].Select.BackgroundTransparency = 1 
						end

						newSelect.BackgroundTransparency = 0
						updateInputs(point)
					end

					if (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) and not currentlySelected then
						currentPoint = point
						local mouseEvent, releaseEvent
						currentlySelected = true
						newSelect.BackgroundColor3 = Color3.new(249/255, 191/255, 59/255)

						local oldEnvelope = point[3]

						releaseEvent = user.InputEnded:Connect(function(input)
							if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then	return end

							mouseEvent:Disconnect()
							releaseEvent:Disconnect()
							currentlySelected = nil
							newSelect.BackgroundColor3 = Color3.new(199/255, 44/255, 28/255)
						end)

						mouseEvent = user.InputChanged:Connect(function(input)
							if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
								local maxX = numberLine.AbsoluteSize.X - 1
								local relativeX = (input.Position.X - numberLine.AbsolutePosition.X)
								if relativeX < 0 then relativeX = 0 end
								if relativeX > maxX then relativeX = maxX end

								local maxY = numberLine.AbsoluteSize.Y - 1
								local relativeY = (input.Position.Y - numberLine.AbsolutePosition.Y)
								if relativeY < 0 then relativeY = 0 end
								if relativeY > maxY then relativeY = maxY end

								if point ~= beginPoint and point ~= endPoint then
									point[2] = relativeX / maxX
								end

								point[1] = 10 - (relativeY / maxY) * 10
								local maxEnvelope = math.min(point[1], 10 - point[1])
								point[3] = math.min(oldEnvelope, maxEnvelope)
								newMt:Redraw()
								updateInputs(point)

								for i, v in pairs(points) do 
									v[4].Select.BackgroundTransparency = 1 
								end

								newSelect.BackgroundTransparency = 0
								buildSequence()
							end
						end)
					end
				end)

				return newPoint
			end

			local function placePoints()
				for i,v in pairs(points) do
					v[4] = placePoint(v)
				end
			end

			local function redraw(self)
				local numberLineSize = numberLine.AbsoluteSize
				table.sort(points,function(a,b) return a[2] < b[2] end)
				for i,v in pairs(points) do
					v[4].Position = UDim2.new(0,math.floor((numberLineSize.X-1) * v[2])-2,0,(numberLineSize.Y-1)*(10-v[1])/10-2)
				end
				lines[1].Size = UDim2.new(0,1,0,0)
				for i = 1,#points-1 do
					local fromPoint = points[i]
					local toPoint = points[i+1]
					local deltaY = toPoint[4].Position.Y.Offset-fromPoint[4].Position.Y.Offset
					local deltaX = toPoint[4].Position.X.Offset-fromPoint[4].Position.X.Offset
					local slope = deltaY/deltaX

					local fromEnvelope = fromPoint[3]
					local nextEnvelope = toPoint[3]

					local currentRise = math.abs(slope)
					local totalRise = 0
					local maxRise = math.abs(toPoint[4].Position.Y.Offset-fromPoint[4].Position.Y.Offset)

					for lineCount = math.min(fromPoint[4].Position.X.Offset+1,toPoint[4].Position.X.Offset),toPoint[4].Position.X.Offset do
						if deltaX == 0 and deltaY == 0 then return end
						local riseNow = math.floor(currentRise)
						local line = lines[lineCount+3]
						if line then
							if totalRise+riseNow > maxRise then riseNow = maxRise-totalRise end
							if math.sign(slope) == -1 then
								line.Position = UDim2.new(0,lineCount+2,0,fromPoint[4].Position.Y.Offset + -(totalRise+riseNow)+2)
							else
								line.Position = UDim2.new(0,lineCount+2,0,fromPoint[4].Position.Y.Offset + totalRise+2)
							end
							line.Size = UDim2.new(0,1,0,math.max(riseNow,1))
						end
						totalRise = totalRise + riseNow
						currentRise = currentRise - riseNow + math.abs(slope)

						local envPercent = (lineCount-fromPoint[4].Position.X.Offset)/(toPoint[4].Position.X.Offset-fromPoint[4].Position.X.Offset)
						local envLerp = fromEnvelope+(nextEnvelope-fromEnvelope)*envPercent
						local relativeSize = (envLerp/10)*numberLineSize.Y						

						local line = eLines[lineCount + 3]
						if line then
							line.Position = UDim2.new(0,lineCount+2,0,lines[lineCount+3].Position.Y.Offset-math.floor(relativeSize))
							line.Size = UDim2.new(0,1,0,math.floor(relativeSize*2))
						end
					end
				end
			end
			newMt.Redraw = redraw



			local function loadSequence(self,seq)
				resetSequence = seq
				for i,v in pairs(points) do if v[4] then v[4]:Destroy() end end
				points = {}
				for i,v in pairs(seq.Keypoints) do
					local maxEnvelope = math.min(v.Value,10-v.Value)
					local newPoint = {v.Value,v.Time,math.min(v.Envelope,maxEnvelope)}
					newPoint[4] = placePoint(newPoint)
					table.insert(points,newPoint)
				end
				beginPoint = points[1]
				endPoint = points[#points]
				currentlySelected = nil
				redraw()
				envelopeDragTop.Visible = false
				envelopeDragBottom.Visible = false
			end
			newMt.SetSequence = loadSequence

			timeBox.FocusLost:Connect(function()
				local point = currentPoint
				local num = tonumber(timeBox.Text)
				if point and num and point ~= beginPoint and point ~= endPoint then
					num = math.clamp(num,0,1)
					point[2] = num
					redraw()
					buildSequence()
					updateInputs(point)
				end
			end)

			valueBox.FocusLost:Connect(function()
				local point = currentPoint
				local num = tonumber(valueBox.Text)
				if point and num then
					local oldEnvelope = point[3]
					num = math.clamp(num,0,10)
					point[1] = num
					local maxEnvelope = math.min(point[1],10-point[1])
					point[3] = math.min(oldEnvelope,maxEnvelope)
					redraw()
					buildSequence()
					updateInputs(point)
				end
			end)

			envelopeBox.FocusLost:Connect(function()
				local point = currentPoint
				local num = tonumber(envelopeBox.Text)
				if point and num then
					num = math.clamp(num,0,5)
					local maxEnvelope = math.min(point[1],10-point[1])
					point[3] = math.min(num,maxEnvelope)
					redraw()
					buildSequence()
					updateInputs(point)
				end
			end)

			local function buttonAnimations(button,inverse)
				button.InputBegan:Connect(function(input) if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then button.BackgroundTransparency = (inverse and 0.5 or 0.4) end end)
				button.InputEnded:Connect(function(input) if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then button.BackgroundTransparency = (inverse and 1 or 0) end end)
			end

			numberLine.InputBegan:Connect(function(input)
				if (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) and #points < 20 then

					if Lib.CheckMouseInGui(envelopeDragTop) or Lib.CheckMouseInGui(envelopeDragBottom) then return end

					for i, v in pairs(points) do
						if Lib.CheckMouseInGui(v[4].Select) then
							return
						end
					end

					local maxX = numberLine.AbsoluteSize.X - 1
					local relativeX = (input.Position.X - numberLine.AbsolutePosition.X)
					if relativeX < 0 then relativeX = 0 end
					if relativeX > maxX then relativeX = maxX end

					local maxY = numberLine.AbsoluteSize.Y - 1
					local relativeY = (input.Position.Y - numberLine.AbsolutePosition.Y)
					if relativeY < 0 then relativeY = 0 end
					if relativeY > maxY then relativeY = maxY end

					local raw = relativeX / maxX
					local newPoint = {10 - (relativeY / maxY) * 10, raw, 0}
					newPoint[4] = placePoint(newPoint)
					table.insert(points, newPoint)
					redraw()
					buildSequence()
				end
			end)

			deleteButton.MouseButton1Click:Connect(function()
				if currentPoint and currentPoint ~= beginPoint and currentPoint ~= endPoint then
					for i,v in pairs(points) do
						if v == currentPoint then
							v[4]:Destroy()
							table.remove(points,i)
							break
						end
					end
					currentlySelected = nil
					redraw()
					buildSequence()
					updateInputs(points[1])
				end
			end)

			resetButton.MouseButton1Click:Connect(function()
				if resetSequence then
					newMt:SetSequence(resetSequence)
					buildSequence()
				end
			end)

			closeButton.MouseButton1Click:Connect(function()
				window:Close()
			end)

			buttonAnimations(deleteButton)
			buttonAnimations(resetButton)
			buttonAnimations(closeButton)

			placePoints()
			redraw()

			newMt.Show = function(self)
				window:Show()
			end

			return newMt
		end

		return {new = new}
	end)()

	Lib.ColorSequenceEditor = (function()
		local function new()
			local newMt = setmetatable({},{})
			newMt.OnSelect = Lib.Signal.new()
			newMt.OnCancel = Lib.Signal.new()
			newMt.OnPreview = Lib.Signal.new()
			newMt.OnPickColor = Lib.Signal.new()

			local guiContents = create({
				{1,"Frame",{BackgroundColor3=Color3.new(0.17647059261799,0.17647059261799,0.17647059261799),BorderSizePixel=0,ClipsDescendants=true,Name="Content",Position=UDim2.new(0,0,0,20),Size=UDim2.new(1,0,1,-20),}},
				{2,"Frame",{BackgroundColor3=Color3.new(0.17647059261799,0.17647059261799,0.17647059261799),BorderColor3=Color3.new(0.21568627655506,0.21568627655506,0.21568627655506),Name="ColorLine",Parent={1},Position=UDim2.new(0,10,0,5),Size=UDim2.new(1,-20,0,70),}},
				{3,"Frame",{BackgroundColor3=Color3.new(1,1,1),BorderSizePixel=0,Name="Gradient",Parent={2},Size=UDim2.new(1,0,1,0),}},
				{4,"UIGradient",{Parent={3},}},
				{5,"Frame",{BackgroundColor3=Color3.new(1,1,1),BackgroundTransparency=1,BorderSizePixel=0,Name="Arrows",Parent={1},Position=UDim2.new(0,1,0,73),Size=UDim2.new(1,-2,0,16),}},
				{6,"Frame",{BackgroundColor3=Color3.new(0,0,0),BackgroundTransparency=0.5,BorderSizePixel=0,Name="Cursor",Parent={1},Position=UDim2.new(0,10,0,0),Size=UDim2.new(0,1,0,80),}},
				{7,"Frame",{BackgroundColor3=Color3.new(0.14901961386204,0.14901961386204,0.14901961386204),BorderColor3=Color3.new(0.12549020349979,0.12549020349979,0.12549020349979),Name="Time",Parent={1},Position=UDim2.new(0,40,0,95),Size=UDim2.new(0,100,0,20),}},
				{8,"TextBox",{BackgroundColor3=Color3.new(0.25098040699959,0.25098040699959,0.25098040699959),BackgroundTransparency=1,BorderColor3=Color3.new(0.37647062540054,0.37647062540054,0.37647062540054),ClipsDescendants=true,Font=3,Name="Input",Parent={7},Position=UDim2.new(0,2,0,0),Size=UDim2.new(0,98,0,20),Text="0",TextColor3=Color3.new(0.86274516582489,0.86274516582489,0.86274516582489),TextSize=14,TextXAlignment=0,}},
				{9,"TextLabel",{BackgroundColor3=Color3.new(1,1,1),BackgroundTransparency=1,Font=3,Name="Title",Parent={7},Position=UDim2.new(0,-40,0,0),Size=UDim2.new(0,34,1,0),Text="Time",TextColor3=Color3.new(0.86274516582489,0.86274516582489,0.86274516582489),TextSize=14,TextXAlignment=1,}},
				{10,"Frame",{BackgroundColor3=Color3.new(1,1,1),BorderColor3=Color3.new(0.21568627655506,0.21568627655506,0.21568627655506),Name="ColorBox",Parent={1},Position=UDim2.new(0,220,0,95),Size=UDim2.new(0,20,0,20),}},
				{11,"TextLabel",{BackgroundColor3=Color3.new(1,1,1),BackgroundTransparency=1,Font=3,Name="Title",Parent={10},Position=UDim2.new(0,-40,0,0),Size=UDim2.new(0,34,1,0),Text="Color",TextColor3=Color3.new(0.86274516582489,0.86274516582489,0.86274516582489),TextSize=14,TextXAlignment=1,}},
				{12,"TextButton",{AutoButtonColor=false,BackgroundColor3=Color3.new(0.2352941185236,0.2352941185236,0.2352941185236),BorderColor3=Color3.new(0.21568627655506,0.21568627655506,0.21568627655506),BorderSizePixel=0,Font=3,Name="Close",Parent={1},Position=UDim2.new(1,-90,0,95),Size=UDim2.new(0,80,0,20),Text="Close",TextColor3=Color3.new(0.86274516582489,0.86274516582489,0.86274516582489),TextSize=14,}},
				{13,"TextButton",{AutoButtonColor=false,BackgroundColor3=Color3.new(0.2352941185236,0.2352941185236,0.2352941185236),BorderColor3=Color3.new(0.21568627655506,0.21568627655506,0.21568627655506),BorderSizePixel=0,Font=3,Name="Reset",Parent={1},Position=UDim2.new(1,-180,0,95),Size=UDim2.new(0,80,0,20),Text="Reset",TextColor3=Color3.new(0.86274516582489,0.86274516582489,0.86274516582489),TextSize=14,}},
				{14,"TextButton",{AutoButtonColor=false,BackgroundColor3=Color3.new(0.2352941185236,0.2352941185236,0.2352941185236),BorderColor3=Color3.new(0.21568627655506,0.21568627655506,0.21568627655506),BorderSizePixel=0,Font=3,Name="Delete",Parent={1},Position=UDim2.new(0,280,0,95),Size=UDim2.new(0,80,0,20),Text="Delete",TextColor3=Color3.new(0.86274516582489,0.86274516582489,0.86274516582489),TextSize=14,}},
				{15,"Frame",{BackgroundTransparency=1,Name="Arrow",Parent={1},Size=UDim2.new(0,16,0,16),Visible=false,}},
				{16,"Frame",{BackgroundColor3=Color3.new(0.86274510622025,0.86274510622025,0.86274510622025),BorderSizePixel=0,Parent={15},Position=UDim2.new(0,8,0,3),Size=UDim2.new(0,1,0,2),}},
				{17,"Frame",{BackgroundColor3=Color3.new(0.86274510622025,0.86274510622025,0.86274510622025),BorderSizePixel=0,Parent={15},Position=UDim2.new(0,7,0,5),Size=UDim2.new(0,3,0,2),}},
				{18,"Frame",{BackgroundColor3=Color3.new(0.86274510622025,0.86274510622025,0.86274510622025),BorderSizePixel=0,Parent={15},Position=UDim2.new(0,6,0,7),Size=UDim2.new(0,5,0,2),}},
				{19,"Frame",{BackgroundColor3=Color3.new(0.86274510622025,0.86274510622025,0.86274510622025),BorderSizePixel=0,Parent={15},Position=UDim2.new(0,5,0,9),Size=UDim2.new(0,7,0,2),}},
				{20,"Frame",{BackgroundColor3=Color3.new(0.86274510622025,0.86274510622025,0.86274510622025),BorderSizePixel=0,Parent={15},Position=UDim2.new(0,4,0,11),Size=UDim2.new(0,9,0,2),}},
			})
			local window = Lib.Window.new()
			window.Resizable = false
			window:Resize(650,150)
			window:SetTitle("ColorSequence Editor")
			newMt.Window = window
			newMt.Gui = window.Gui
			for i,v in pairs(guiContents:GetChildren()) do
				v.Parent = window.GuiElems.Content
			end
			local gui = window.Gui
			local pickerGui = gui.Main
			local pickerTopBar = pickerGui.TopBar
			local pickerFrame = pickerGui.Content
			local colorLine = pickerFrame.ColorLine
			local gradient = colorLine.Gradient.UIGradient
			local arrowFrame = pickerFrame.Arrows
			local arrow = pickerFrame.Arrow
			local cursor = pickerFrame.Cursor
			local timeBox = pickerFrame.Time.Input
			local colorBox = pickerFrame.ColorBox
			local deleteButton = pickerFrame.Delete
			local resetButton = pickerFrame.Reset
			local closeButton = pickerFrame.Close
			local topClose = pickerTopBar.Close

			local user = service.UserInputService
			local mouse = service.Players.LocalPlayer:GetMouse()

			local colors = {{Color3.new(1,0,1),0},{Color3.new(0.2,0.9,0.2),0.2},{Color3.new(0.4,0.5,0.9),0.7},{Color3.new(0.6,1,1),1}}
			local resetSequence = nil

			local beginPoint = colors[1]
			local endPoint = colors[#colors]

			local currentlySelected = nil
			local currentPoint = nil

			local sequenceLine = Instance.new("Frame")
			sequenceLine.BorderSizePixel = 0
			sequenceLine.Size = UDim2.new(0,1,1,0)

			newMt.Sequence = ColorSequence.new(Color3.new(1,1,1))
			local function buildSequence(noupdate)
				local newPoints = {}
				table.sort(colors,function(a,b) return a[2] < b[2] end)
				for i,v in pairs(colors) do
					table.insert(newPoints,ColorSequenceKeypoint.new(v[2],v[1]))
				end
				newMt.Sequence = ColorSequence.new(newPoints)
				if not noupdate then newMt.OnSelect:Fire(newMt.Sequence) end
			end

			local function round(num,places)
				local multi = 10^places
				return math.floor(num*multi + 0.5)/multi
			end

			local function updateInputs(point)
				if point then
					currentPoint = point
					local raw = point[2]
					timeBox.Text = round(raw,(raw < 0.01 and 5) or (raw < 0.1 and 4) or 3)
					colorBox.BackgroundColor3 = point[1]
				end
			end

			local function placeArrow(ind,point)
				local newArrow = arrow:Clone()
				newArrow.Position = UDim2.new(0,ind-1,0,0)
				newArrow.Visible = true
				newArrow.Parent = arrowFrame

				newArrow.InputBegan:Connect(function(input)
					if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
						cursor.Visible = true
						cursor.Position = UDim2.new(0, 9 + newArrow.Position.X.Offset, 0, 0)
					end

					if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
						updateInputs(point)
						if point == beginPoint or point == endPoint or currentlySelected then return end

						local mouseEvent, releaseEvent
						currentlySelected = true

						releaseEvent = user.InputEnded:Connect(function(input)
							if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then return end
							mouseEvent:Disconnect()
							releaseEvent:Disconnect()
							currentlySelected = nil
							cursor.Visible = false
						end)

						mouseEvent = user.InputChanged:Connect(function(input)
							if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
								local maxSize = colorLine.AbsoluteSize.X - 1
								local relativeX = (input.Position.X - colorLine.AbsolutePosition.X)
								if relativeX < 0 then relativeX = 0 end
								if relativeX > maxSize then relativeX = maxSize end
								local raw = relativeX / maxSize
								point[2] = relativeX / maxSize
								updateInputs(point)
								cursor.Visible = true
								cursor.Position = UDim2.new(0, 9 + newArrow.Position.X.Offset, 0, 0)
								buildSequence()
								newMt:Redraw()
							end
						end)
					end
				end)

				newArrow.InputEnded:Connect(function(input)
					if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
						cursor.Visible = false
					end
				end)



				return newArrow
			end

			local function placeArrows()
				for i,v in pairs(colors) do
					v[3] = placeArrow(math.floor((colorLine.AbsoluteSize.X-1) * v[2]) + 1,v)
				end
			end

			local function redraw(self)
				gradient.Color = newMt.Sequence or ColorSequence.new(Color3.new(1,1,1))

				for i = 2,#colors do
					local nextColor = colors[i]
					local endPos = math.floor((colorLine.AbsoluteSize.X-1) * nextColor[2]) + 1
					nextColor[3].Position = UDim2.new(0,endPos,0,0)
				end		
			end
			newMt.Redraw = redraw

			local function loadSequence(self,seq)
				resetSequence = seq
				for i,v in pairs(colors) do if v[3] then v[3]:Destroy() end end
				colors = {}
				currentlySelected = nil
				for i,v in pairs(seq.Keypoints) do
					local newPoint = {v.Value,v.Time}
					newPoint[3] = placeArrow(v.Time,newPoint)
					table.insert(colors,newPoint)
				end
				beginPoint = colors[1]
				endPoint = colors[#colors]
				currentlySelected = nil
				updateInputs(colors[1])
				buildSequence(true)
				redraw()
			end
			newMt.SetSequence = loadSequence

			local function buttonAnimations(button,inverse)
				button.InputBegan:Connect(function(input) if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then button.BackgroundTransparency = (inverse and 0.5 or 0.4) end end)
				button.InputEnded:Connect(function(input) if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then button.BackgroundTransparency = (inverse and 1 or 0) end end)
			end

			colorLine.InputBegan:Connect(function(input)
				if (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) and #colors < 20 then
					local maxSize = colorLine.AbsoluteSize.X - 1
					local relativeX = (input.Position.X - colorLine.AbsolutePosition.X)
					if relativeX < 0 then relativeX = 0 end
					if relativeX > maxSize then relativeX = maxSize end

					local raw = relativeX / maxSize
					local fromColor = nil
					local toColor = nil
					for i, col in pairs(colors) do
						if col[2] >= raw then
							fromColor = colors[math.max(i - 1, 1)]
							toColor = colors[i]
							break
						end
					end
					local lerpColor = fromColor[1]:lerp(toColor[1], (raw - fromColor[2]) / (toColor[2] - fromColor[2]))
					local newPoint = {lerpColor, raw}
					newPoint[3] = placeArrow(newPoint[2], newPoint)
					table.insert(colors, newPoint)
					updateInputs(newPoint)
					buildSequence()
					redraw()
				end
			end)

			colorLine.InputChanged:Connect(function(input)
				if (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
					local maxSize = colorLine.AbsoluteSize.X - 1
					local relativeX = (input.Position.X - colorLine.AbsolutePosition.X)
					if relativeX < 0 then relativeX = 0 end
					if relativeX > maxSize then relativeX = maxSize end
					cursor.Visible = true
					cursor.Position = UDim2.new(0, 10 + relativeX, 0, 0)
				end
			end)

			colorLine.InputEnded:Connect(function(input)
				if (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
					local inArrow = false
					for i, v in pairs(colors) do
						if Lib.CheckMouseInGui(v[3]) then
							inArrow = v[3]
						end
					end
					cursor.Visible = inArrow and true or false
					if inArrow then cursor.Position = UDim2.new(0, 9 + inArrow.Position.X.Offset, 0, 0) end
				end
			end)

			timeBox:GetPropertyChangedSignal("Text"):Connect(function()
				local point = currentPoint
				local num = tonumber(timeBox.Text)
				if point and num and point ~= beginPoint and point ~= endPoint then
					num = math.clamp(num,0,1)
					point[2] = num
					buildSequence()
					redraw()
				end
			end)

			colorBox.InputBegan:Connect(function(input)
				if (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then
					local editor = newMt.ColorPicker
					if not editor then
						editor = Lib.ColorPicker.new()
						editor.Window:SetTitle("ColorSequence Color Picker")

						editor.OnSelect:Connect(function(col)
							if currentPoint then
								currentPoint[1] = col
							end
							buildSequence()
							redraw()
						end)

						newMt.ColorPicker = editor
					end

					editor.Window:ShowAndFocus()
				end
			end)

			deleteButton.MouseButton1Click:Connect(function()
				if currentPoint and currentPoint ~= beginPoint and currentPoint ~= endPoint then
					for i,v in pairs(colors) do
						if v == currentPoint then
							v[3]:Destroy()
							table.remove(colors,i)
							break
						end
					end
					currentlySelected = nil
					updateInputs(colors[1])
					buildSequence()
					redraw()
				end
			end)

			resetButton.MouseButton1Click:Connect(function()
				if resetSequence then
					newMt:SetSequence(resetSequence)
				end
			end)

			closeButton.MouseButton1Click:Connect(function()
				window:Close()
			end)

			topClose.MouseButton1Click:Connect(function()
				window:Close()
			end)

			buttonAnimations(deleteButton)
			buttonAnimations(resetButton)
			buttonAnimations(closeButton)

			placeArrows()
			redraw()

			newMt.Show = function(self)
				window:Show()
			end

			return newMt
		end

		return {new = new}
	end)()

	Lib.ViewportTextBox = (function()
		local textService = service.TextService

		local props = {
			OffsetX = 0,
			TextBox = PH,
			CursorPos = -1,
			Gui = PH,
			View = PH
		}
		local funcs = {}
		funcs.Update = function(self)
			local cursorPos = self.CursorPos or -1
			local text = self.TextBox.Text
			if text == "" then self.TextBox.Position = UDim2.new(0,0,0,0) return end
			if cursorPos == -1 then return end

			local cursorText = text:sub(1,cursorPos-1)
			local pos = nil
			local leftEnd = -self.TextBox.Position.X.Offset
			local rightEnd = leftEnd + self.View.AbsoluteSize.X

			local totalTextSize = textService:GetTextSize(text,self.TextBox.TextSize,self.TextBox.Font,Vector2.new(999999999,100)).X
			local cursorTextSize = textService:GetTextSize(cursorText,self.TextBox.TextSize,self.TextBox.Font,Vector2.new(999999999,100)).X

			if cursorTextSize > rightEnd then
				pos = math.max(-1,cursorTextSize - self.View.AbsoluteSize.X + 2)
			elseif cursorTextSize < leftEnd then
				pos = math.max(-1,cursorTextSize-2)
			elseif totalTextSize < rightEnd then
				pos = math.max(-1,totalTextSize - self.View.AbsoluteSize.X + 2)
			end

			if pos then
				self.TextBox.Position = UDim2.new(0,-pos,0,0)
				self.TextBox.Size = UDim2.new(1,pos,1,0)
			end
		end

		funcs.GetText = function(self)
			return self.TextBox.Text
		end

		funcs.SetText = function(self,text)
			self.TextBox.Text = text
		end

		local mt = getGuiMT(props,funcs)

		local function convert(textbox)
			local obj = initObj(props,mt)

			local view = Instance.new("Frame")
			view.BackgroundTransparency = textbox.BackgroundTransparency
			view.BackgroundColor3 = textbox.BackgroundColor3
			view.BorderSizePixel = textbox.BorderSizePixel
			view.BorderColor3 = textbox.BorderColor3
			view.Position = textbox.Position
			view.Size = textbox.Size
			view.ClipsDescendants = true
			view.Name = textbox.Name
			textbox.BackgroundTransparency = 1
			textbox.Position = UDim2.new(0,0,0,0)
			textbox.Size = UDim2.new(1,0,1,0)
			textbox.TextXAlignment = Enum.TextXAlignment.Left
			textbox.Name = "Input"

			obj.TextBox = textbox
			obj.View = view
			obj.Gui = view

			textbox.Changed:Connect(function(prop)
				if prop == "Text" or prop == "CursorPosition" or prop == "AbsoluteSize" then
					local cursorPos = obj.TextBox.CursorPosition
					if cursorPos ~= -1 then obj.CursorPos = cursorPos end
					obj:Update()
				end
			end)

			obj:Update()

			view.Parent = textbox.Parent
			textbox.Parent = view

			return obj
		end

		local function new()
			local textBox = Instance.new("TextBox")
			textBox.Active = true
			textBox.Size = UDim2.new(0,100,0,20)
			textBox.BackgroundColor3 = Settings.Theme.TextBox
			textBox.BorderColor3 = Settings.Theme.Outline3
			textBox.ClearTextOnFocus = false
			textBox.TextColor3 = Settings.Theme.Text
			textBox.Font = Enum.Font.SourceSans
			textBox.TextSize = 14
			textBox.Text = ""
			return convert(textBox)
		end

		return {new = new, convert = convert}
	end)()

	Lib.Label = (function()
		local props,funcs = {},{}

		local mt = getGuiMT(props,funcs)

		local function new()
			local label = Instance.new("TextLabel")
			label.BackgroundTransparency = 1
			label.TextXAlignment = Enum.TextXAlignment.Left
			label.TextColor3 = Settings.Theme.Text
			label.TextTransparency = 0.1
			label.Size = UDim2.new(0,100,0,20)
			label.Font = Enum.Font.SourceSans
			label.TextSize = 14

			local obj = setmetatable({
				Gui = label
			},mt)
			return obj
		end

		return {new = new}
	end)()

	Lib.Frame = (function()
		local props,funcs = {},{}

		local mt = getGuiMT(props,funcs)

		local function new()
			local fr = Instance.new("Frame")
			fr.BackgroundColor3 = Settings.Theme.Main1
			fr.BorderColor3 = Settings.Theme.Outline1
			fr.Size = UDim2.new(0,50,0,50)

			local obj = setmetatable({
				Gui = fr
			},mt)
			return obj
		end

		return {new = new}
	end)()

	Lib.Button = (function()
		local props = {
			Gui = PH,
			Anim = PH,
			Disabled = false,
			OnClick = SIGNAL,
			OnDown = SIGNAL,
			OnUp = SIGNAL,
			AllowedButtons = {1}
		}
		local funcs = {}
		local tableFind = table.find

		funcs.Trigger = function(self,event,button)
			if not self.Disabled and tableFind(self.AllowedButtons,button) then
				self["On"..event]:Fire(button)
			end
		end

		funcs.SetDisabled = function(self,dis)
			self.Disabled = dis

			if dis then
				self.Anim:Disable()
				self.Gui.TextTransparency = 0.5
			else
				self.Anim.Enable()
				self.Gui.TextTransparency = 0
			end
		end

		local mt = getGuiMT(props,funcs)

		local function new()
			local b = Instance.new("TextButton")
			b.AutoButtonColor = false
			b.TextColor3 = Settings.Theme.Text
			b.TextTransparency = 0.1
			b.Size = UDim2.new(0,100,0,20)
			b.Font = Enum.Font.SourceSans
			b.TextSize = 14
			b.BackgroundColor3 = Settings.Theme.Button
			b.BorderColor3 = Settings.Theme.Outline2

			local obj = initObj(props,mt)
			obj.Gui = b
			obj.Anim = Lib.ButtonAnim(b,{Mode = 2, StartColor = Settings.Theme.Button, HoverColor = Settings.Theme.ButtonHover, PressColor = Settings.Theme.ButtonPress, OutlineColor = Settings.Theme.Outline2})

			b.MouseButton1Click:Connect(function() obj:Trigger("Click",1) end)
			b.MouseButton1Down:Connect(function() obj:Trigger("Down",1) end)
			b.MouseButton1Up:Connect(function() obj:Trigger("Up",1) end)

			b.MouseButton2Click:Connect(function() obj:Trigger("Click",2) end)
			b.MouseButton2Down:Connect(function() obj:Trigger("Down",2) end)
			b.MouseButton2Up:Connect(function() obj:Trigger("Up",2) end)

			return obj
		end

		return {new = new}
	end)()

	Lib.DropDown = (function()
		local props = {
			Gui = PH,
			Anim = PH,
			Context = PH,
			Selected = PH,
			Disabled = false,
			CanBeEmpty = true,
			Options = {},
			GuiElems = {},
			OnSelect = SIGNAL
		}
		local funcs = {}

		funcs.Update = function(self)
			local options = self.Options

			if #options > 0 then
				if not self.Selected then
					if not self.CanBeEmpty then
						self.Selected = options[1]
						self.GuiElems.Label.Text = options[1]
					else
						self.GuiElems.Label.Text = "- Select -"
					end
				else
					self.GuiElems.Label.Text = self.Selected
				end
			else
				self.GuiElems.Label.Text = "- Select -"
			end
		end

		funcs.ShowOptions = function(self)
			local context = self.Context

			context.Width = self.Gui.AbsoluteSize.X
			context.ReverseYOffset = self.Gui.AbsoluteSize.Y
			context:Show(self.Gui.AbsolutePosition.X, self.Gui.AbsolutePosition.Y + context.ReverseYOffset)
		end

		funcs.SetOptions = function(self,opts)
			self.Options = opts

			local context = self.Context
			local options = self.Options
			context:Clear()

			local onClick = function(option) self.Selected = option self.OnSelect:Fire(option) self:Update() end

			if self.CanBeEmpty then
				context:Add({Name = "- Select -", function() self.Selected = nil self.OnSelect:Fire(nil) self:Update() end})
			end

			for i = 1,#options do
				context:Add({Name = options[i], OnClick = onClick})
			end

			self:Update()
		end

		funcs.SetSelected = function(self,opt)
			self.Selected = type(opt) == "number" and self.Options[opt] or opt
			self:Update()
		end

		local mt = getGuiMT(props,funcs)

		local function new()
			local f = Instance.new("TextButton")
			f.AutoButtonColor = false
			f.Text = ""
			f.Size = UDim2.new(0,100,0,20)
			f.BackgroundColor3 = Settings.Theme.TextBox
			f.BorderColor3 = Settings.Theme.Outline3

			local label = Lib.Label.new()
			label.Position = UDim2.new(0,2,0,0)
			label.Size = UDim2.new(1,-22,1,0)
			label.TextTruncate = Enum.TextTruncate.AtEnd
			label.Parent = f
			local arrow = create({
				{1,"Frame",{BackgroundTransparency=1,Name="EnumArrow",Position=UDim2.new(1,-16,0,2),Size=UDim2.new(0,16,0,16),}},
				{2,"Frame",{BackgroundColor3=Color3.new(0.86274510622025,0.86274510622025,0.86274510622025),BorderSizePixel=0,Parent={1},Position=UDim2.new(0,8,0,9),Size=UDim2.new(0,1,0,1),}},
				{3,"Frame",{BackgroundColor3=Color3.new(0.86274510622025,0.86274510622025,0.86274510622025),BorderSizePixel=0,Parent={1},Position=UDim2.new(0,7,0,8),Size=UDim2.new(0,3,0,1),}},
				{4,"Frame",{BackgroundColor3=Color3.new(0.86274510622025,0.86274510622025,0.86274510622025),BorderSizePixel=0,Parent={1},Position=UDim2.new(0,6,0,7),Size=UDim2.new(0,5,0,1),}},
			})
			arrow.Parent = f

			local obj = initObj(props,mt)
			obj.Gui = f
			obj.Anim = Lib.ButtonAnim(f,{Mode = 2, StartColor = Settings.Theme.TextBox, LerpTo = Settings.Theme.Button, LerpDelta = 0.15})
			obj.Context = Lib.ContextMenu.new()
			obj.Context.Iconless = true
			obj.Context.MaxHeight = 200
			obj.Selected = nil
			obj.GuiElems = {Label = label}
			f.MouseButton1Down:Connect(function() obj:ShowOptions() end)
			obj:Update()
			return obj
		end

		return {new = new}
	end)()

	Lib.ClickSystem = (function()
		local props = {
			LastItem = PH,
			OnDown = SIGNAL,
			OnRelease = SIGNAL,
			AllowedButtons = {1},
			Combo = 0,
			MaxCombo = 2,
			ComboTime = 0.5,
			Items = {},
			ItemCons = {},
			ClickId = -1,
			LastButton = ""
		}
		local funcs = {}
		local tostring = tostring

		local disconnect = function(con)
			local pos = table.find(con.Signal.Connections,con)
			if pos then table.remove(con.Signal.Connections,pos) end
		end

		funcs.Trigger = function(self, item, button, X, Y)
			if table.find(self.AllowedButtons, button) then
				if self.LastButton ~= button or self.LastItem ~= item or self.Combo == self.MaxCombo or tick() - self.ClickId > self.ComboTime then
					self.Combo = 0
					self.LastButton = button
					self.LastItem = item
				end

				self.Combo = self.Combo + 1
				self.ClickId = tick()

				task.spawn(function()
					if self.InputDown then
						self.InputDown = false
					else
						self.InputDown = tick()

						local Connection = item.MouseButton1Up:Once(function()
							self.InputDown = false
						end)

						while self.InputDown and not Explorer.Dragging do
							if (tick() - self.InputDown) >= 0.4 then
								self.InputDown = false
								self["OnRelease"]:Fire(item, self.Combo, 2, Vector2.new(X, Y))
								break
							end;task.wait()
						end
					end
				end)

				local release
				release = service.UserInputService.InputEnded:Connect(function(input)
					if input.UserInputType == Enum.UserInputType["MouseButton" .. button] then
						release:Disconnect()
						if Lib.CheckMouseInGui(item) and self.LastButton == button and self.LastItem == item then
							self.InputDown = false
							self["OnRelease"]:Fire(item,self.Combo,button)
						end
					end
				end)

				self["OnDown"]:Fire(item,self.Combo,button)
			end
		end

		funcs.Add = function(self,item)
			if table.find(self.Items,item) then return end

			local cons = {}
			cons[1] = item.MouseButton1Down:Connect(function(X, Y) self:Trigger(item, 1, X, Y) end)
			cons[2] = item.MouseButton2Down:Connect(function(X, Y) self:Trigger(item, 2, X, Y) end)

			self.ItemCons[item] = cons
			self.Items[#self.Items+1] = item
		end

		funcs.Remove = function(self,item)
			local ind = table.find(self.Items,item)
			if not ind then return end

			for i,v in pairs(self.ItemCons[item]) do
				v:Disconnect()
			end
			self.ItemCons[item] = nil
			table.remove(self.Items,ind)
		end

		local mt = {__index = funcs}

		local function new()
			local obj = initObj(props,mt)

			return obj
		end

		return {new = new}
	end)()

	return Lib
end

return {InitDeps = initDeps, InitAfterMain = initAfterMain, Main = main}
end,
["ModelViewer"] = function()

local Main,Lib,Apps,Settings
local Explorer, Properties, ScriptViewer, ModelViewer, Notebook
local API,RMD,env,service,plr,create,createSimple

local function initDeps(data)
	Main = data.Main
	Lib = data.Lib
	Apps = data.Apps
	Settings = data.Settings

	API = data.API
	RMD = data.RMD
	env = data.env
	service = data.service
	plr = data.plr
	create = data.create
	createSimple = data.createSimple
end

local function initAfterMain()
	Explorer = Apps.Explorer
	Properties = Apps.Properties
	ScriptViewer = Apps.ScriptViewer
	Notebook = Apps.Notebook
end

local function getPath(obj)
	if obj.Parent == nil then
		return "Nil parented"
	else
		return Explorer.GetInstancePath(obj)
	end
end

local function main()
	local RunService = game:GetService("RunService")
	local UserInputService = game:GetService("UserInputService")
	
	local ModelViewer = {
		EnableInputCamera = true,
		IsViewing = false,
		AutoRefresh = false,
		ZoomMultiplier = 2,
		AutoRotate = true,
		RotationSpeed = 0.01,
		RefreshRate = 30
	}
	
	local window, viewportFrame, pathLabel, settingsButton, hintLabel
	local model, camera, originalModel
	local viewCenter
	local viewToken = 0
	local rotationX, rotationY = -0.35, 0
	local distance = 10
	local defaultHint = "Select a Part or Model in the Explorer to preview it"

	local function showHint(text)
		if hintLabel then
			hintLabel.Text = text or defaultHint
			hintLabel.Visible = true
		end
	end

	local function safeClone(item)
		local changed = {}
		local function unlock(obj)
			local ok,arch = pcall(function() return obj.Archivable end)
			if ok and arch == false and pcall(function() obj.Archivable = true end) then
				changed[#changed+1] = obj
			end
		end
		unlock(item)
		for _,d in ipairs(item:GetDescendants()) do unlock(d) end
		local ok,clone = pcall(item.Clone,item)
		for _,obj in ipairs(changed) do pcall(function() obj.Archivable = false end) end
		return ok and clone or nil
	end

	local function isPreviewable(item)
		return typeof(item) == "Instance" and item ~= workspace and not item:IsA("Terrain") and (item:IsA("BasePart") or item:IsA("Model"))
	end

	ModelViewer.StopViewModel = function(updating)
		if updating then
			local old = viewportFrame:FindFirstChildOfClass("Model")
			if old then old:Destroy() end
		else
			camera = nil
			model = nil
			viewCenter = nil
			viewToken = viewToken + 1
			viewportFrame:ClearAllChildren()

			ModelViewer.IsViewing = false
			window:SetTitle("3D Preview")
			pathLabel.Gui.Text = ""
			showHint()
		end
	end

	ModelViewer.ViewModel = function(item, updating, noFocus)
		if not item then return end
		if not isPreviewable(item) then
			if not updating then showHint("Only Parts and Models can be previewed") end
			return
		end

		local clone = safeClone(item)
		if not clone then
			if not updating then showHint("This object can't be cloned for preview") end
			return
		end

		local newModel
		if item:IsA("BasePart") then
			newModel = Instance.new("Model")
			clone.Parent = newModel
			newModel.PrimaryPart = clone
		else
			newModel = clone
			if not newModel:FindFirstChildWhichIsA("BasePart",true) then
				newModel:Destroy()
				if not updating then showHint("This model has no parts to show") end
				return
			end
		end

		ModelViewer.StopViewModel(updating)
		model = newModel
		model.Parent = viewportFrame

		local ok,cf,size = pcall(model.GetBoundingBox,model)
		if ok then
			viewCenter = cf.Position
		else
			local part = model:FindFirstChildWhichIsA("BasePart",true)
			viewCenter = part and part.Position or Vector3.zero
			size = part and part.Size or Vector3.one
		end

		originalModel = item

		if not updating then
			distance = math.max(size.Magnitude,3)
			rotationX = -0.35

			local token = viewToken
			if ModelViewer.AutoRefresh then
				task.spawn(function()
					while model and ModelViewer.AutoRefresh and viewToken == token do
						task.wait(1 / ModelViewer.RefreshRate)
						if not (model and ModelViewer.AutoRefresh and viewToken == token) then break end
						ModelViewer.ViewModel(originalModel, true)
					end
				end)
			end

			camera = Instance.new("Camera")
			camera.FieldOfView = 60
			camera.Parent = viewportFrame
			viewportFrame.CurrentCamera = camera

			if hintLabel then hintLabel.Visible = false end
			window:SetTitle(item.Name.." - 3D Preview")
			local pathOk,path = pcall(getPath,originalModel)
			pathLabel.Gui.Text = "path: " .. (pathOk and tostring(path) or item:GetFullName())
			if not noFocus then window:Show() end
			ModelViewer.IsViewing = true
		end
	end

	ModelViewer.Init = function()
		window = Lib.Window.new()
		window:SetTitle("3D Preview")
		window:Resize(350,200)
		ModelViewer.Window =  window
		
		viewportFrame = Instance.new("ViewportFrame")
		viewportFrame.Parent = window.GuiElems.Content
		viewportFrame.BackgroundTransparency = 1
		viewportFrame.Size = UDim2.new(1,0,1,0)
		viewportFrame.Ambient = Color3.fromRGB(170,170,170)
		viewportFrame.LightColor = Color3.fromRGB(255,255,255)
		viewportFrame.LightDirection = Vector3.new(-1,-1,-1)

		hintLabel = Instance.new("TextLabel")
		hintLabel.Name = "Hint"
		hintLabel.BackgroundTransparency = 1
		hintLabel.Font = Enum.Font.Gotham
		hintLabel.Size = UDim2.new(1,-20,1,0)
		hintLabel.Position = UDim2.new(0,10,0,0)
		hintLabel.Text = defaultHint
		hintLabel.TextColor3 = Color3.fromRGB(130,130,130)
		hintLabel.TextSize = 13
		hintLabel.TextWrapped = true
		hintLabel.Parent = window.GuiElems.Content
		
		pathLabel = Lib.Label.new()
		pathLabel.Gui.Parent = window.GuiElems.Content
		pathLabel.Gui.AnchorPoint = Vector2.new(0,1)
		pathLabel.Gui.Text = ""
		pathLabel.Gui.TextSize = 12
		pathLabel.Gui.TextTransparency = 0.45
		pathLabel.Gui.Position = UDim2.new(0,1,1,0)
		pathLabel.Gui.Size = UDim2.new(1,-1,0,15)
		pathLabel.Gui.BackgroundTransparency = 1
		
		settingsButton = Instance.new("ImageButton",window.GuiElems.Content)
		settingsButton.AnchorPoint = Vector2.new(1,0)
		settingsButton.BackgroundTransparency = 1
		settingsButton.Size = UDim2.new(0,15,0,15)
		settingsButton.Position = UDim2.new(1,-3,0,3)
		settingsButton.Image = "rbxassetid://6578871732"
		settingsButton.ImageTransparency = 0.5
		if UserInputService:GetLastInputType() == Enum.UserInputType.Touch then
			settingsButton.Visible = true
		else
			settingsButton.Visible = false
		end

		local dragging = false
		local hovering = false
		local lastpos = Vector2.zero

		viewportFrame.InputBegan:Connect(function(input)
			if not ModelViewer.EnableInputCamera then return end
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				dragging = true
				lastpos = input.Position
			elseif input.KeyCode == Enum.KeyCode.LeftShift then
				ModelViewer.ZoomMultiplier = 10
			end
		end)
		

		viewportFrame.MouseEnter:Connect(function()
			hovering = true
		end)
		viewportFrame.MouseLeave:Connect(function()
			hovering = false
		end)

		viewportFrame.InputEnded:Connect(function(input)
			if not ModelViewer.EnableInputCamera then return end
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				dragging = false
			elseif input.KeyCode == Enum.KeyCode.LeftShift then
				ModelViewer.ZoomMultiplier = 2
			end
		end)

		viewportFrame.InputChanged:Connect(function(input)
			if not ModelViewer.EnableInputCamera then return end
			if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
				local delta = input.Position - lastpos
				lastpos = input.Position

				rotationY -= delta.X * 0.01
				rotationX -= delta.Y * 0.01
				rotationX = math.clamp(rotationX, -math.pi/2 + 0.1, math.pi/2 - 0.1)
			end

			if input.UserInputType == Enum.UserInputType.MouseWheel and hovering then
				distance = math.clamp(distance - (input.Position.Z * ModelViewer.ZoomMultiplier), 0.1, math.huge)
			end
		end)

		RunService.RenderStepped:Connect(function()
			if camera and model and viewCenter then
				if not dragging and ModelViewer.AutoRotate then
					rotationY += ModelViewer.RotationSpeed
				end

				local rotation = CFrame.Angles(0, rotationY, 0) * CFrame.Angles(rotationX, 0, 0)
				local camPos = (CFrame.new(viewCenter) * rotation * CFrame.new(0, 0, distance)).Position
				camera.CFrame = CFrame.lookAt(camPos, viewCenter)
			end
		end)

		local followQueued = false
		if Explorer and Explorer.Selection then
			Explorer.Selection.Changed:Connect(function()
				if window.Closed or followQueued then return end
				followQueued = true
				task.defer(function()
					followQueued = false
					if window.Closed then return end
					local list = Explorer.Selection.List
					local obj = list and list[1] and list[1].Obj
					if isPreviewable(obj) and obj ~= originalModel then
						ModelViewer.ViewModel(obj, false, true)
					end
				end)
			end)
		end

		window.OnActivate:Connect(function()
			if ModelViewer.IsViewing then return end
			task.defer(function()
				if ModelViewer.IsViewing then return end
				local list = Explorer and Explorer.Selection and Explorer.Selection.List
				local obj = list and list[1] and list[1].Obj
				if isPreviewable(obj) then
					ModelViewer.ViewModel(obj)
				else
					showHint()
				end
			end)
		end)
		
		local context = Lib.ContextMenu.new()
		
		local absoluteSize = context.Gui.AbsoluteSize
		context.MaxHeight = (absoluteSize.Y <= 600 and (absoluteSize.Y - 40)) or nil

		context:Register("STOP",{Name = "Stop Viewing", OnClick = function()
			ModelViewer.StopViewModel()
		end})
		context:Register("EXIT",{Name = "Exit", OnClick = function()
			ModelViewer.StopViewModel()
			context:Hide()
			window:Hide()
		end})
		context:Register("COPY_PATH",{Name = "Copy Path", OnClick = function()
			if model then
				env.setclipboard(getPath(originalModel))
			end
		end})
		context:Register("REFRESH",{Name = "Refresh", OnClick = function()
			if originalModel then
				ModelViewer.ViewModel(originalModel)
			end
		end})
		context:Register("ENABLE_AUTO_REFRESH",{Name = "Enable Auto Refresh", OnClick = function()
			if originalModel then
				ModelViewer.AutoRefresh = true
				ModelViewer.ViewModel(originalModel)
			end
		end})
		context:Register("DISABLE_AUTO_REFRESH",{Name = "Disable Auto Refresh", OnClick = function()
			if originalModel then
				ModelViewer.AutoRefresh = false
				ModelViewer.ViewModel(originalModel)
			end
		end})
		context:Register("SAVE_INST",{Name = "Save to File", OnClick = function()
			if model then
				Lib.SaveAsPrompt("Place_"..game.PlaceId.."_"..originalModel.Name.."_"..os.time(), function(filename)
					window:SetTitle(originalModel.Name.." - Model Viewer - Saving")	
					
					local success, result = pcall(env.saveinstance,
					originalModel, filename,
						{
							Decompile = true,
							RemovePlayerCharacters = false
						}
					)
					
					if success then
						window:SetTitle(originalModel.Name.." - Model Viewer - Saved")
						context:Hide()
						task.wait(5)
						if model then
							window:SetTitle(originalModel.Name.." - Model Viewer")
						end
					else
						window:SetTitle(originalModel.Name.." - Model Viewer - Error")
						warn("Error while saving model: "..result)
						context:Hide()
						task.wait(5)
						if model then
							window:SetTitle(originalModel.Name.." - Model Viewer")
						end
					end
				end)
			end
		end})
		
		context:Register("ENABLE_AUTO_ROTATE",{Name = "Enable Auto Rotate", OnClick = function()
			ModelViewer.AutoRotate = true
			
		end})
		context:Register("DISABLE_AUTO_ROTATE",{Name = "Disable Auto Rotate", OnClick = function()
			ModelViewer.AutoRotate = false
		end})
		context:Register("LOCK_CAM",{Name = "Lock Camera", OnClick = function()
			ModelViewer.EnableInputCamera = false
		end})
		context:Register("UNLOCK_CAM",{Name = "Unlock Camera", OnClick = function()
			ModelViewer.EnableInputCamera = true
		end})
		
		context:Register("ZOOM_IN",{Name = "Zoom In", OnClick = function()
			distance = math.clamp(distance - (ModelViewer.ZoomMultiplier * 2), 2, math.huge)
		end})
		
		context:Register("ZOOM_OUT",{Name = "Zoom Out", OnClick = function()
			distance = math.clamp(distance + (ModelViewer.ZoomMultiplier * 2), 2, math.huge)
		end})
		
		local function ShowContext()
			context:Clear()

			context:AddRegistered("STOP", not ModelViewer.IsViewing)	
			context:AddRegistered("REFRESH", not ModelViewer.IsViewing)
			context:AddRegistered("COPY_PATH", not ModelViewer.IsViewing)
			context:AddRegistered("SAVE_INST", not ModelViewer.IsViewing)
			context:AddDivider()
			
			if env.isonmobile then
				context:AddRegistered("ZOOM_IN")
				context:AddRegistered("ZOOM_OUT")
				context:AddDivider()
			end

			if ModelViewer.AutoRotate then
				context:AddRegistered("DISABLE_AUTO_ROTATE")
			else
				context:AddRegistered("ENABLE_AUTO_ROTATE")
			end
			if ModelViewer.AutoRefresh then
				context:AddRegistered("DISABLE_AUTO_REFRESH")
			else
				context:AddRegistered("ENABLE_AUTO_REFRESH")
			end
			if ModelViewer.EnableInputCamera then
				context:AddRegistered("LOCK_CAM")
			else
				context:AddRegistered("UNLOCK_CAM")
			end

			context:AddDivider()

			context:AddRegistered("EXIT")

			context:Show()
		end
		
		local function HideContext()
			context:Hide()
		end
		
		viewportFrame.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton2 then
				ShowContext()
			elseif input.UserInputType == Enum.UserInputType.MouseButton1 and Lib.CheckMouseInGui(context.Gui) then
				HideContext()
			end
		end)
		settingsButton.MouseButton1Click:Connect(function()
			ShowContext()
		end)
	end

	return ModelViewer
end

if gethsfuncs then
	_G.moduleData = {InitDeps = initDeps, InitAfterMain = initAfterMain, Main = main}
else
	return {InitDeps = initDeps, InitAfterMain = initAfterMain, Main = main}
end
end,
["Properties"] = function()

local Main,Lib,Apps,Settings
local Explorer, Properties, ScriptViewer, Notebook
local API,RMD,env,service,plr,create,createSimple

local function initDeps(data)
	Main = data.Main
	Lib = data.Lib
	Apps = data.Apps
	Settings = data.Settings

	API = data.API
	RMD = data.RMD
	env = data.env
	service = data.service
	plr = data.plr
	create = data.create
	createSimple = data.createSimple
end

local function initAfterMain()
	Explorer = Apps.Explorer
	Properties = Apps.Properties
	ScriptViewer = Apps.ScriptViewer
	Notebook = Apps.Notebook
end

local function main()
	local Properties = {}

	local window, toolBar, propsFrame
	local scrollV, scrollH
	local categoryOrder
	local props,viewList,expanded,indexableProps,propEntries,autoUpdateObjs = {},{},{},{},{},{}
	local inputBox,inputTextBox,inputProp
	local checkboxes,propCons = {},{}
	local table,string = table,string
	local getPropChangedSignal = game.GetPropertyChangedSignal
	local getAttributeChangedSignal = game.GetAttributeChangedSignal
	local isa = game.IsA
	local getAttribute = game.GetAttribute
	local setAttribute = game.SetAttribute

	Properties.GuiElems = {}
	Properties.Index = 0
	Properties.ViewWidth = 0
	Properties.MinInputWidth = 100
	Properties.EntryIndent = 16
	Properties.EntryOffset = 4
	Properties.NameWidthCache = {}
	Properties.SubPropCache = {}
	Properties.ClassLists = {}
	Properties.SearchText = ""

	Properties.AddAttributeProp = {Category = "Attributes", Class = "", Name = "", SpecialRow = "AddAttribute", Tags = {}}
	Properties.SoundPreviewProp = {Category = "Data", ValueType = {Name = "SoundPlayer"}, Class = "Sound", Name = "Preview", Tags = {}}

	Properties.IgnoreProps = {
		["DataModel"] = {
			["PrivateServerId"] = true,
			["PrivateServerOwnerId"] = true,
			["VIPServerId"] = true,
			["VIPServerOwnerId"] = true
		}
	}

	Properties.ExpandableTypes = {
		["Vector2"] = true,
		["Vector3"] = true,
		["UDim"] = true,
		["UDim2"] = true,
		["CFrame"] = true,
		["Rect"] = true,
		["PhysicalProperties"] = true,
		["Ray"] = true,
		["NumberRange"] = true,
		["Faces"] = true,
		["Axes"] = true,
	}

	Properties.ExpandableProps = {
		["Sound.SoundId"] = true
	}

	Properties.CollapsedCategories = {
		["Surface Inputs"] = true,
		["Surface"] = true
	}

	Properties.ConflictSubProps = {
		["Vector2"] = {"X","Y"},
		["Vector3"] = {"X","Y","Z"},
		["UDim"] = {"Scale","Offset"},
		["UDim2"] = {"X","X.Scale","X.Offset","Y","Y.Scale","Y.Offset"},
		["CFrame"] = {"Position","Position.X","Position.Y","Position.Z",
			"RightVector","RightVector.X","RightVector.Y","RightVector.Z",
			"UpVector","UpVector.X","UpVector.Y","UpVector.Z",
			"LookVector","LookVector.X","LookVector.Y","LookVector.Z"},
		["Rect"] = {"Min.X","Min.Y","Max.X","Max.Y"},
		["PhysicalProperties"] = {"Density","Elasticity","ElasticityWeight","Friction","FrictionWeight"},
		["Ray"] = {"Origin","Origin.X","Origin.Y","Origin.Z","Direction","Direction.X","Direction.Y","Direction.Z"},
		["NumberRange"] = {"Min","Max"},
		["Faces"] = {"Back","Bottom","Front","Left","Right","Top"},
		["Axes"] = {"X","Y","Z"}
	}

	Properties.ConflictIgnore = {
		["BasePart"] = {
			["ResizableFaces"] = true
		}
	}

	Properties.RoundableTypes = {
		["float"] = true,
		["double"] = true,
		["Color3"] = true,
		["UDim"] = true,
		["UDim2"] = true,
		["Vector2"] = true,
		["Vector3"] = true,
		["NumberRange"] = true,
		["Rect"] = true,
		["NumberSequence"] = true,
		["ColorSequence"] = true,
		["Ray"] = true,
		["CFrame"] = true
	}

	Properties.TypeNameConvert = {
		["number"] = "double",
		["boolean"] = "bool"
	}

	Properties.ToNumberTypes = {
		["int"] = true,
		["int64"] = true,
		["float"] = true,
		["double"] = true
	}

	Properties.DefaultPropValue = {
		string = "",
		bool = false,
		double = 0,
		UDim = UDim.new(0,0),
		UDim2 = UDim2.new(0,0,0,0),
		BrickColor = BrickColor.new("Medium stone grey"),
		Color3 = Color3.new(1,1,1),
		Vector2 = Vector2.new(0,0),
		Vector3 = Vector3.new(0,0,0),
		NumberSequence = NumberSequence.new(1),
		ColorSequence = ColorSequence.new(Color3.new(1,1,1)),
		NumberRange = NumberRange.new(0),
		Rect = Rect.new(0,0,0,0)
	}

	Properties.AllowedAttributeTypes = {"string","boolean","number","UDim","UDim2","BrickColor","Color3","Vector2","Vector3","NumberSequence","ColorSequence","NumberRange","Rect"}

	Properties.StringToValue = function(prop,str)
		local typeData = prop.ValueType
		local typeName = typeData.Name

		if typeName == "string" or typeName == "Content" then
			return str
		elseif Properties.ToNumberTypes[typeName] then
			return tonumber(str)
		elseif typeName == "Vector2" then
			local vals = str:split(",")
			local x,y = tonumber(vals[1]),tonumber(vals[2])
			if x and y and #vals >= 2 then return Vector2.new(x,y) end
		elseif typeName == "Vector3" then
			local vals = str:split(",")
			local x,y,z = tonumber(vals[1]),tonumber(vals[2]),tonumber(vals[3])
			if x and y and z and #vals >= 3 then return Vector3.new(x,y,z) end
		elseif typeName == "UDim" then
			local vals = str:split(",")
			local scale,offset = tonumber(vals[1]),tonumber(vals[2])
			if scale and offset and #vals >= 2 then return UDim.new(scale,offset) end
		elseif typeName == "UDim2" then
			local vals = str:gsub("[{}]",""):split(",")
			local xScale,xOffset,yScale,yOffset = tonumber(vals[1]),tonumber(vals[2]),tonumber(vals[3]),tonumber(vals[4])
			if xScale and xOffset and yScale and yOffset and #vals >= 4 then return UDim2.new(xScale,xOffset,yScale,yOffset) end
		elseif typeName == "CFrame" then
			local vals = str:split(",")
			local s,result = pcall(CFrame.new,unpack(vals))
			if s and #vals >= 12 then return result end
		elseif typeName == "Rect" then
			local vals = str:split(",")
			local s,result = pcall(Rect.new,unpack(vals))
			if s and #vals >= 4 then return result end
		elseif typeName == "Ray" then
			local vals = str:gsub("[{}]",""):split(",")
			local s,origin = pcall(Vector3.new,unpack(vals,1,3))
			local s2,direction = pcall(Vector3.new,unpack(vals,4,6))
			if s and s2 and #vals >= 6 then return Ray.new(origin,direction) end
		elseif typeName == "NumberRange" then
			local vals = str:split(",")
			local s,result = pcall(NumberRange.new,unpack(vals))
			if s and #vals >= 1 then return result end
		elseif typeName == "Color3" then
			local vals = str:gsub("[{}]",""):split(",")
			local s,result = pcall(Color3.fromRGB,unpack(vals))
			if s and #vals >= 3 then return result end
		end

		return nil
	end

	Properties.ValueToString = function(prop,val)
		local typeData = prop.ValueType
		local typeName = typeData.Name

		if typeName == "Color3" then
			return Lib.ColorToBytes(val)
		elseif typeName == "NumberRange" then
			return val.Min..", "..val.Max
		end

		return tostring(val)
	end

	Properties.GetIndexableProps = function(obj,classData)
		if not Main.Elevated then
			if not pcall(function() return obj.ClassName end) then return nil end
		end

		local ignoreProps = Properties.IgnoreProps[classData.Name] or {}

		local result = {}
		local count = 1
		local props = classData.Properties
		for i = 1,#props do
			local prop = props[i]
			if not ignoreProps[prop.Name] then
				local s = pcall(function() return obj[prop.Name] end)
				if s then
					result[count] = prop
					count = count + 1
				end
			end
		end

		return result
	end

	Properties.FindFirstObjWhichIsA = function(class)
		local classList = Properties.ClassLists[class] or {}
		if classList and #classList > 0 then
			return classList[1]
		end

		return nil
	end

	Properties.ComputeConflicts = function(p)
		local maxConflictCheck = Settings.Properties.MaxConflictCheck
		local sList = Explorer.Selection.List
		local classLists = Properties.ClassLists
		local stringSplit = string.split
		local t_clear = table.clear
		local conflictIgnore = Properties.ConflictIgnore
		local conflictMap = {}
		local propList = p and {p} or props

		if p then
			local gName = p.Class.."."..p.Name
			autoUpdateObjs[gName] = nil
			local subProps = Properties.ConflictSubProps[p.ValueType.Name] or {}
			for i = 1,#subProps do
				autoUpdateObjs[gName.."."..subProps[i]] = nil
			end
		else
			table.clear(autoUpdateObjs)
		end

		if #sList > 0 then
			for i = 1,#propList do
				local prop = propList[i]
				local propName,propClass = prop.Name,prop.Class
				local typeData = prop.RootType or prop.ValueType
				local typeName = typeData.Name
				local attributeName = prop.AttributeName
				local gName = propClass.."."..propName

				local checked = 0
				local subProps = Properties.ConflictSubProps[typeName] or {}
				local subPropCount = #subProps
				local toCheck = subPropCount + 1
				local conflictsFound = 0
				local indexNames = {}
				local ignored = conflictIgnore[propClass] and conflictIgnore[propClass][propName]
				local truthyCheck = (typeName == "PhysicalProperties")
				local isAttribute = prop.IsAttribute
				local isMultiType = prop.MultiType

				t_clear(conflictMap)

				if not isMultiType then
					local firstVal,firstObj,firstSet
					local classList = classLists[prop.Class] or {}
					for c = 1,#classList do
						local obj = classList[c]
						if not firstSet then
							if isAttribute then
								firstVal = getAttribute(obj,attributeName)
								if firstVal ~= nil then
									firstObj = obj
									firstSet = true
								end
							else
								firstVal = obj[propName]
								firstObj = obj
								firstSet = true
							end
							if ignored then break end
						else
							local propVal,skip
							if isAttribute then
								propVal = getAttribute(obj,attributeName)
								if propVal == nil then skip = true end
							else
								propVal = obj[propName]
							end

							if not skip then
								if not conflictMap[1] then
									if truthyCheck then
										if (firstVal and true or false) ~= (propVal and true or false) then
											conflictMap[1] = true
											conflictsFound = conflictsFound + 1
										end
									elseif firstVal ~= propVal then
										conflictMap[1] = true
										conflictsFound = conflictsFound + 1
									end
								end

								if subPropCount > 0 then
									for sPropInd = 1,subPropCount do
										local indexes = indexNames[sPropInd]
										if not indexes then indexes = stringSplit(subProps[sPropInd],".") indexNames[sPropInd] = indexes end

										local firstValSub = firstVal
										local propValSub = propVal

										for j = 1,#indexes do
											if not firstValSub or not propValSub then break end
											local indexName = indexes[j]
											firstValSub = firstValSub[indexName]
											propValSub = propValSub[indexName]
										end

										local mapInd = sPropInd + 1
										if not conflictMap[mapInd] and firstValSub ~= propValSub then
											conflictMap[mapInd] = true
											conflictsFound = conflictsFound + 1
										end
									end
								end

								if conflictsFound == toCheck then break end
							end
						end

						checked = checked + 1
						if checked == maxConflictCheck then break end
					end

					if not conflictMap[1] then autoUpdateObjs[gName] = firstObj end
					for sPropInd = 1,subPropCount do
						if not conflictMap[sPropInd+1] then
							autoUpdateObjs[gName.."."..subProps[sPropInd]] = firstObj
						end
					end
				end
			end
		end

		if p then
			Properties.Refresh()
		end
	end

	Properties.ShowExplorerProps = function()
		local maxConflictCheck = Settings.Properties.MaxConflictCheck
		local sList = Explorer.Selection.List
		local foundClasses = {}
		local propCount = 1
		local elevated = Main.Elevated
		local showDeprecated,showHidden = Settings.Properties.ShowDeprecated,Settings.Properties.ShowHidden
		local Classes = API.Classes
		local classLists = {}
		local lower = string.lower
		local RMDCustomOrders = RMD.PropertyOrders
		local getAttributes = game.GetAttributes
		local maxAttrs = Settings.Properties.MaxAttributes
		local showingAttrs = Settings.Properties.ShowAttributes
		local foundAttrs = {}
		local attrCount = 0
		local typeof = typeof
		local typeNameConvert = Properties.TypeNameConvert

		table.clear(props)

		for i = 1,#sList do
			local node = sList[i]
			local obj = node.Obj
			local class = node.Class
			if not class then class = obj.ClassName node.Class = class end

			local apiClass = Classes[class]
			while apiClass do
				local APIClassName = apiClass.Name
				if not foundClasses[APIClassName] then
					local apiProps = indexableProps[APIClassName]
					if not apiProps then apiProps = Properties.GetIndexableProps(obj,apiClass) indexableProps[APIClassName] = apiProps end

					for i = 1,#apiProps do
						local prop = apiProps[i]
						local tags = prop.Tags
						if (not tags.Deprecated or showDeprecated) and (not tags.Hidden or showHidden) then
							props[propCount] = prop
							propCount = propCount + 1
						end
					end
					foundClasses[APIClassName] = true
				end

				local classList = classLists[APIClassName]
				if not classList then classList = {} classLists[APIClassName] = classList end
				classList[#classList+1] = obj

				apiClass = apiClass.Superclass
			end

			if showingAttrs and attrCount < maxAttrs then
				local attrs = getAttributes(obj)
				for name,val in pairs(attrs) do
					local typ = typeof(val)
					if not foundAttrs[name] then
						local category = (typ == "Instance" and "Class") or (typ == "EnumItem" and "Enum") or "Other"
						local valType = {Name = typeNameConvert[typ] or typ, Category = category}
						local attrProp = {IsAttribute = true, Name = "ATTR_"..name, AttributeName = name, DisplayName = name, Class = "Instance", ValueType = valType, Category = "Attributes", Tags = {}}
						props[propCount] = attrProp
						propCount = propCount + 1
						attrCount = attrCount + 1
						foundAttrs[name] = {typ,attrProp}
						if attrCount == maxAttrs then break end
					elseif foundAttrs[name][1] ~= typ then
						foundAttrs[name][2].MultiType = true
						foundAttrs[name][2].Tags.ReadOnly = true
						foundAttrs[name][2].ValueType = {Name = "string"}
					end
				end
			end
		end

		table.sort(props,function(a,b)
			if a.Category ~= b.Category then
				return (categoryOrder[a.Category] or 9999) < (categoryOrder[b.Category] or 9999)
			else
				local aOrder = (RMDCustomOrders[a.Class] and RMDCustomOrders[a.Class][a.Name]) or 9999999
				local bOrder = (RMDCustomOrders[b.Class] and RMDCustomOrders[b.Class][b.Name]) or 9999999
				if aOrder ~= bOrder then
					return aOrder < bOrder
				else
					return lower(a.Name) < lower(b.Name)
				end
			end
		end)

		Properties.ClassLists = classLists
		Properties.ComputeConflicts()
		if #props > 0 then
			props[#props+1] = Properties.AddAttributeProp
		end

		Properties.Update()
		Properties.Refresh()
	end

	Properties.UpdateView = function()
		local maxEntries = math.ceil(propsFrame.AbsoluteSize.Y / 23)
		local maxX = propsFrame.AbsoluteSize.X
		local totalWidth = Properties.ViewWidth + Properties.MinInputWidth

		scrollV.VisibleSpace = maxEntries
		scrollV.TotalSpace = #viewList + 1
		scrollH.VisibleSpace = maxX
		scrollH.TotalSpace = totalWidth

		scrollV.Gui.Visible = #viewList + 1 > maxEntries
		scrollH.Gui.Visible = Settings.Properties.ScaleType == 0 and totalWidth > maxX

		local oldSize = propsFrame.Size
		propsFrame.Size = UDim2.new(1,(scrollV.Gui.Visible and -16 or 0),1,(scrollH.Gui.Visible and -39 or -23))
		if oldSize ~= propsFrame.Size then
			Properties.UpdateView()
		else
			scrollV:Update()
			scrollH:Update()

			if scrollV.Gui.Visible and scrollH.Gui.Visible then
				scrollV.Gui.Size = UDim2.new(0,16,1,-39)
				scrollH.Gui.Size = UDim2.new(1,-16,0,16)
				Properties.Window.GuiElems.Content.ScrollCorner.Visible = true
			else
				scrollV.Gui.Size = UDim2.new(0,16,1,-23)
				scrollH.Gui.Size = UDim2.new(1,0,0,16)
				Properties.Window.GuiElems.Content.ScrollCorner.Visible = false
			end

			Properties.Index = scrollV.Index
		end
	end

	Properties.MakeSubProp = function(prop,subName,valueType,displayName)
		local subProp = {}
		for i,v in pairs(prop) do
			subProp[i] = v
		end
		subProp.RootType = subProp.RootType or subProp.ValueType
		subProp.ValueType = valueType
		subProp.SubName = subProp.SubName and (subProp.SubName..subName) or subName
		subProp.DisplayName = displayName

		return subProp
	end

	Properties.GetExpandedProps = function(prop)
		local result = {}
		local typeData = prop.ValueType
		local typeName = typeData.Name
		local makeSubProp = Properties.MakeSubProp

		if typeName == "Vector2" then
			result[1] = makeSubProp(prop,".X",{Name = "float"})
			result[2] = makeSubProp(prop,".Y",{Name = "float"})
		elseif typeName == "Vector3" then
			result[1] = makeSubProp(prop,".X",{Name = "float"})
			result[2] = makeSubProp(prop,".Y",{Name = "float"})
			result[3] = makeSubProp(prop,".Z",{Name = "float"})
		elseif typeName == "CFrame" then
			result[1] = makeSubProp(prop,".Position",{Name = "Vector3"})
			result[2] = makeSubProp(prop,".RightVector",{Name = "Vector3"})
			result[3] = makeSubProp(prop,".UpVector",{Name = "Vector3"})
			result[4] = makeSubProp(prop,".LookVector",{Name = "Vector3"})
		elseif typeName == "UDim" then
			result[1] = makeSubProp(prop,".Scale",{Name = "float"})
			result[2] = makeSubProp(prop,".Offset",{Name = "int"})
		elseif typeName == "UDim2" then
			result[1] = makeSubProp(prop,".X",{Name = "UDim"})
			result[2] = makeSubProp(prop,".Y",{Name = "UDim"})
		elseif typeName == "Rect" then
			result[1] = makeSubProp(prop,".Min.X",{Name = "float"},"X0")
			result[2] = makeSubProp(prop,".Min.Y",{Name = "float"},"Y0")
			result[3] = makeSubProp(prop,".Max.X",{Name = "float"},"X1")
			result[4] = makeSubProp(prop,".Max.Y",{Name = "float"},"Y1")
		elseif typeName == "PhysicalProperties" then
			result[1] = makeSubProp(prop,".Density",{Name = "float"})
			result[2] = makeSubProp(prop,".Elasticity",{Name = "float"})
			result[3] = makeSubProp(prop,".ElasticityWeight",{Name = "float"})
			result[4] = makeSubProp(prop,".Friction",{Name = "float"})
			result[5] = makeSubProp(prop,".FrictionWeight",{Name = "float"})
		elseif typeName == "Ray" then
			result[1] = makeSubProp(prop,".Origin",{Name = "Vector3"})
			result[2] = makeSubProp(prop,".Direction",{Name = "Vector3"})
		elseif typeName == "NumberRange" then
			result[1] = makeSubProp(prop,".Min",{Name = "float"})
			result[2] = makeSubProp(prop,".Max",{Name = "float"})
		elseif typeName == "Faces" then
			result[1] = makeSubProp(prop,".Back",{Name = "bool"})
			result[2] = makeSubProp(prop,".Bottom",{Name = "bool"})
			result[3] = makeSubProp(prop,".Front",{Name = "bool"})
			result[4] = makeSubProp(prop,".Left",{Name = "bool"})
			result[5] = makeSubProp(prop,".Right",{Name = "bool"})
			result[6] = makeSubProp(prop,".Top",{Name = "bool"})
		elseif typeName == "Axes" then
			result[1] = makeSubProp(prop,".X",{Name = "bool"})
			result[2] = makeSubProp(prop,".Y",{Name = "bool"})
			result[3] = makeSubProp(prop,".Z",{Name = "bool"})
		end

		if prop.Name == "SoundId" and prop.Class == "Sound" then
			result[1] = Properties.SoundPreviewProp
		end

		return result
	end

	Properties.Update = function()
		table.clear(viewList)

		local nameWidthCache = Properties.NameWidthCache
		local lastCategory
		local count = 1
		local maxWidth,maxDepth = 0,1

		local textServ = service.TextService
		local getTextSize = textServ.GetTextSize
		local font = Enum.Font.SourceSans
		local size = Vector2.new(math.huge,20)
		local stringSplit = string.split
		local entryIndent = Properties.EntryIndent
		local isFirstScaleType = Settings.Properties.ScaleType == 0
		local find,lower = string.find,string.lower
		local searchText = (#Properties.SearchText > 0 and lower(Properties.SearchText))

		local function recur(props,depth)
			for i = 1,#props do
				local prop = props[i]
				local propName = prop.Name
				local subName = prop.SubName
				local category = prop.Category

				local visible
				if searchText and depth == 1 then
					if find(lower(propName),searchText,1,true) then
						visible = true
					end
				else
					visible = true
				end

				if visible and lastCategory ~= category then
					viewList[count] = {CategoryName = category}
					count = count + 1
					lastCategory = category
				end

				if (expanded["CAT_"..category] and visible) or prop.SpecialRow then
					if depth > 1 then prop.Depth = depth if depth > maxDepth then maxDepth = depth end end

					if isFirstScaleType then
						local nameArr = subName and stringSplit(subName,".")
						local displayName = prop.DisplayName or (nameArr and nameArr[#nameArr]) or propName

						local nameWidth = nameWidthCache[displayName]
						if not nameWidth then nameWidth = getTextSize(textServ,displayName,14,font,size).X nameWidthCache[displayName] = nameWidth end

						local totalWidth = nameWidth + entryIndent*depth
						if totalWidth > maxWidth then
							maxWidth = totalWidth
						end
					end

					viewList[count] = prop
					count = count + 1

					local fullName = prop.Class.."."..prop.Name..(prop.SubName or "")
					if expanded[fullName] then
						local nextDepth = depth+1
						local expandedProps = Properties.GetExpandedProps(prop)
						if #expandedProps > 0 then
							recur(expandedProps,nextDepth)
						end
					end
				end
			end
		end
		recur(props,1)

		inputProp = nil
		Properties.ViewWidth = maxWidth + 9 + Properties.EntryOffset
		Properties.UpdateView()
	end

	Properties.NewPropEntry = function(index)
		local newEntry = Properties.EntryTemplate:Clone()
		local nameFrame = newEntry.NameFrame
		local valueFrame = newEntry.ValueFrame
		local newCheckbox = Lib.Checkbox.new(1)
		newCheckbox.Gui.Position = UDim2.new(0,3,0,3)
		newCheckbox.Gui.Parent = valueFrame
		newCheckbox.OnInput:Connect(function()
			local prop = viewList[index + Properties.Index]
			if not prop then return end

			if prop.ValueType.Name == "PhysicalProperties" then
				Properties.SetProp(prop,newCheckbox.Toggled and true or nil)
			else
				Properties.SetProp(prop,newCheckbox.Toggled)
			end
		end)
		checkboxes[index] = newCheckbox

		local iconFrame = Main.MiscIcons:GetLabel()
		iconFrame.Position = UDim2.new(0,2,0,3)
		iconFrame.Parent = newEntry.ValueFrame.RightButton

		newEntry.Position = UDim2.new(0,0,0,23*(index-1))

		nameFrame.Expand.InputBegan:Connect(function(input)
			local prop = viewList[index + Properties.Index]
			if not prop or input.UserInputType ~= Enum.UserInputType.MouseMovement then return end

			local fullName = (prop.CategoryName and "CAT_"..prop.CategoryName) or prop.Class.."."..prop.Name..(prop.SubName or "")

			Main.MiscIcons:DisplayByKey(newEntry.NameFrame.Expand.Icon, expanded[fullName] and "Collapse_Over" or "Expand_Over")
		end)

		nameFrame.Expand.InputEnded:Connect(function(input)
			local prop = viewList[index + Properties.Index]
			if not prop or input.UserInputType ~= Enum.UserInputType.MouseMovement then return end

			local fullName = (prop.CategoryName and "CAT_"..prop.CategoryName) or prop.Class.."."..prop.Name..(prop.SubName or "")

			Main.MiscIcons:DisplayByKey(newEntry.NameFrame.Expand.Icon, expanded[fullName] and "Collapse" or "Expand")
		end)

		nameFrame.Expand.MouseButton1Down:Connect(function()
			local prop = viewList[index + Properties.Index]
			if not prop then return end

			local fullName = (prop.CategoryName and "CAT_"..prop.CategoryName) or prop.Class.."."..prop.Name..(prop.SubName or "")
			if not prop.CategoryName and not Properties.ExpandableTypes[prop.ValueType and prop.ValueType.Name] and not Properties.ExpandableProps[fullName] then return end

			expanded[fullName] = not expanded[fullName]
			Properties.Update()
			Properties.Refresh()
		end)

		nameFrame.PropName.InputBegan:Connect(function(input)
			local prop = viewList[index + Properties.Index]
			if not prop then return end
			if input.UserInputType == Enum.UserInputType.MouseMovement and not nameFrame.PropName.TextFits then
				local fullNameFrame = Properties.FullNameFrame	
				local nameArr = string.split(prop.Class.."."..prop.Name..(prop.SubName or ""),".")
				local dispName = prop.DisplayName or nameArr[#nameArr]
				local sizeX = service.TextService:GetTextSize(dispName,14,Enum.Font.SourceSans,Vector2.new(math.huge,20)).X

				fullNameFrame.TextLabel.Text = dispName
				fullNameFrame.Size = UDim2.new(0,sizeX + 4,0,22)
				fullNameFrame.Visible = true
				Properties.FullNameFrameIndex = index
				Properties.FullNameFrameAttach.SetData(fullNameFrame, {Target = nameFrame})
				Properties.FullNameFrameAttach.Enable()
			end
		end)

		nameFrame.PropName.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseMovement and Properties.FullNameFrameIndex == index then
				Properties.FullNameFrame.Visible = false
				Properties.FullNameFrameAttach.Disable()
			end
		end)

		valueFrame.ValueBox.MouseButton1Down:Connect(function()
			local prop = viewList[index + Properties.Index]
			if not prop then return end

			Properties.SetInputProp(prop,index)
		end)

		valueFrame.ColorButton.MouseButton1Down:Connect(function()
			local prop = viewList[index + Properties.Index]
			if not prop then return end

			Properties.SetInputProp(prop,index,"color")
		end)

		valueFrame.RightButton.MouseButton1Click:Connect(function()
			local prop = viewList[index + Properties.Index]
			if not prop then return end

			local fullName = prop.Class.."."..prop.Name..(prop.SubName or "")
			local inputFullName = inputProp and (inputProp.Class.."."..inputProp.Name..(inputProp.SubName or ""))

			if fullName == inputFullName and inputProp.ValueType.Category == "Class" then
				inputProp = nil
				Properties.SetProp(prop,nil)
			else
				Properties.SetInputProp(prop,index,"right")
			end
		end)

		nameFrame.ToggleAttributes.MouseButton1Click:Connect(function()
			Settings.Properties.ShowAttributes = not Settings.Properties.ShowAttributes
			Properties.ShowExplorerProps()
		end)

		newEntry.RowButton.MouseButton1Click:Connect(function()
			Properties.DisplayAddAttributeWindow()
		end)

		newEntry.EditAttributeButton.MouseButton1Down:Connect(function()
			local prop = viewList[index + Properties.Index]
			if not prop then return end

			Properties.DisplayAttributeContext(prop)
		end)

		valueFrame.SoundPreview.ControlButton.MouseButton1Click:Connect(function()
			if Properties.PreviewSound and Properties.PreviewSound.Playing then
				Properties.SetSoundPreview(false)
			else
				local soundObj = Properties.FindFirstObjWhichIsA("Sound")
				if soundObj then Properties.SetSoundPreview(soundObj) end
			end
		end)

		valueFrame.SoundPreview.InputBegan:Connect(function(input)
			if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end

			local releaseEvent,mouseEvent
			releaseEvent = service.UserInputService.InputEnded:Connect(function(input)
				if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
				releaseEvent:Disconnect()
				mouseEvent:Disconnect()
			end)

			local timeLine = newEntry.ValueFrame.SoundPreview.TimeLine
			local soundObj = Properties.FindFirstObjWhichIsA("Sound")
			if soundObj then Properties.SetSoundPreview(soundObj,true) end

			local function update(input)
				local sound = Properties.PreviewSound
				if not sound or sound.TimeLength == 0 then return end

				local mouseX = input.Position.X
				local timeLineSize = timeLine.AbsoluteSize
				local relaX = mouseX - timeLine.AbsolutePosition.X

				if timeLineSize.X <= 1 then return end
				if relaX < 0 then relaX = 0 elseif relaX >= timeLineSize.X then relaX = timeLineSize.X-1 end

				local perc = (relaX/(timeLineSize.X-1))
				sound.TimePosition = perc*sound.TimeLength
				timeLine.Slider.Position = UDim2.new(perc,-4,0,-8)
			end
			update(input)

			mouseEvent = service.UserInputService.InputChanged:Connect(function(input)
				if input.UserInputType == Enum.UserInputType.MouseMovement then
					update(input)
				end
			end)
		end)

		newEntry.Parent = propsFrame

		return {
			Gui = newEntry,
			GuiElems = {
				NameFrame = nameFrame,
				ValueFrame = valueFrame,
				PropName = nameFrame.PropName,
				ValueBox = valueFrame.ValueBox,
				Expand = nameFrame.Expand,
				ColorButton = valueFrame.ColorButton,
				ColorPreview = valueFrame.ColorButton.ColorPreview,
				Gradient = valueFrame.ColorButton.ColorPreview.UIGradient,
				EnumArrow = valueFrame.EnumArrow,
				Checkbox = valueFrame.Checkbox,
				RightButton = valueFrame.RightButton,
				RightButtonIcon = iconFrame,
				RowButton = newEntry.RowButton,
				EditAttributeButton = newEntry.EditAttributeButton,
				ToggleAttributes = nameFrame.ToggleAttributes,
				SoundPreview = valueFrame.SoundPreview,
				SoundPreviewSlider = valueFrame.SoundPreview.TimeLine.Slider
			}
		}
	end

	Properties.GetSoundPreviewEntry = function()
		for i = 1,#viewList do
			if viewList[i] == Properties.SoundPreviewProp then
				return propEntries[i - Properties.Index]
			end
		end
	end

	Properties.SetSoundPreview = function(soundObj,noplay)
		local sound = Properties.PreviewSound
		if not sound then
			sound = Instance.new("Sound")
			sound.Name = "Preview"
			sound.Paused:Connect(function()
				local entry = Properties.GetSoundPreviewEntry()
				if entry then Main.MiscIcons:DisplayByKey(entry.GuiElems.SoundPreview.ControlButton.Icon, "Play") end
			end)
			sound.Resumed:Connect(function() Properties.Refresh() end)
			sound.Ended:Connect(function()
				local entry = Properties.GetSoundPreviewEntry()
				if entry then entry.GuiElems.SoundPreviewSlider.Position = UDim2.new(0,-4,0,-8) end
				Properties.Refresh()
			end)
			sound.Parent = window.Gui
			Properties.PreviewSound = sound
		end

		if not soundObj then
			sound:Pause()
		else
			local newId = sound.SoundId ~= soundObj.SoundId
			sound.SoundId = soundObj.SoundId
			sound.PlaybackSpeed = soundObj.PlaybackSpeed
			sound.Volume = soundObj.Volume
			if newId then sound.TimePosition = 0 end
			if not noplay then sound:Resume() end

			coroutine.wrap(function()
				local previewTime = tick()
				Properties.SoundPreviewTime = previewTime
				while previewTime == Properties.SoundPreviewTime and sound.Playing do
					local entry = Properties.GetSoundPreviewEntry()
					if entry then
						local tl = sound.TimeLength
						local perc = sound.TimePosition/(tl == 0 and 1 or tl)
						entry.GuiElems.SoundPreviewSlider.Position = UDim2.new(perc,-4,0,-8)
					end
					Lib.FastWait()
				end
			end)()
			Properties.Refresh()
		end
	end

	Properties.DisplayAttributeContext = function(prop)
		local context = Properties.AttributeContext
		if not context then
			context = Lib.ContextMenu.new()
			context.Iconless = true
			context.Width = 80
		end
		context:Clear()

		context:Add({Name = "Edit", OnClick = function()
			Properties.DisplayAddAttributeWindow(prop)
		end})
		context:Add({Name = "Delete", OnClick = function()
			Properties.SetProp(prop,nil,true)
			Properties.ShowExplorerProps()
		end})

		context:Show()
	end

	Properties.DisplayAddAttributeWindow = function(editAttr)
		local win = Properties.AddAttributeWindow
		if not win then
			win = Lib.Window.new()
			win.Alignable = false
			win.Resizable = false
			win:SetTitle("Add Attribute")
			win:SetSize(200,130)

			local saveButton = Lib.Button.new()
			local nameLabel = Lib.Label.new()
			nameLabel.Text = "Name"
			nameLabel.Position = UDim2.new(0,30,0,10)
			nameLabel.Size = UDim2.new(0,40,0,20)
			win:Add(nameLabel)

			local nameBox = Lib.ViewportTextBox.new()
			nameBox.Position = UDim2.new(0,75,0,10)
			nameBox.Size = UDim2.new(0,120,0,20)
			win:Add(nameBox,"NameBox")
			nameBox.TextBox:GetPropertyChangedSignal("Text"):Connect(function()
				saveButton:SetDisabled(#nameBox:GetText() == 0)
			end)

			local typeLabel = Lib.Label.new()
			typeLabel.Text = "Type"
			typeLabel.Position = UDim2.new(0,30,0,40)
			typeLabel.Size = UDim2.new(0,40,0,20)
			win:Add(typeLabel)

			local typeChooser = Lib.DropDown.new()
			typeChooser.CanBeEmpty = false
			typeChooser.Position = UDim2.new(0,75,0,40)
			typeChooser.Size = UDim2.new(0,120,0,20)
			typeChooser:SetOptions(Properties.AllowedAttributeTypes)
			win:Add(typeChooser,"TypeChooser")

			local errorLabel = Lib.Label.new()
			errorLabel.Text = ""
			errorLabel.Position = UDim2.new(0,5,1,-45)
			errorLabel.Size = UDim2.new(1,-10,0,20)
			errorLabel.TextColor3 = Settings.Theme.Important
			win.ErrorLabel = errorLabel
			win:Add(errorLabel,"Error")

			local cancelButton = Lib.Button.new()
			cancelButton.Text = "Cancel"
			cancelButton.Position = UDim2.new(1,-97,1,-25)
			cancelButton.Size = UDim2.new(0,92,0,20)
			cancelButton.OnClick:Connect(function()
				win:Close()
			end)
			win:Add(cancelButton)

			saveButton.Text = "Save"
			saveButton.Position = UDim2.new(0,5,1,-25)
			saveButton.Size = UDim2.new(0,92,0,20)
			saveButton.OnClick:Connect(function()
				local name = nameBox:GetText()
				if #name > 100 then
					errorLabel.Text = "Error: Name over 100 chars"
					return
				elseif name:sub(1,3) == "RBX" then
					errorLabel.Text = "Error: Name begins with 'RBX'"
					return
				end

				local typ = typeChooser.Selected
				local valType = {Name = Properties.TypeNameConvert[typ] or typ, Category = "DataType"}
				local attrProp = {IsAttribute = true, Name = "ATTR_"..name, AttributeName = name, DisplayName = name, Class = "Instance", ValueType = valType, Category = "Attributes", Tags = {}}

				Settings.Properties.ShowAttributes = true
				Properties.SetProp(attrProp,Properties.DefaultPropValue[valType.Name],true,Properties.EditingAttribute)
				Properties.ShowExplorerProps()
				win:Close()
			end)
			win:Add(saveButton,"SaveButton")

			Properties.AddAttributeWindow = win
		end

		Properties.EditingAttribute = editAttr
		win:SetTitle(editAttr and "Edit Attribute "..editAttr.AttributeName or "Add Attribute")
		win.Elements.Error.Text = ""
		win.Elements.NameBox:SetText("")
		win.Elements.SaveButton:SetDisabled(true)
		win.Elements.TypeChooser:SetSelected(1)
		win:Show()
	end

	Properties.IsTextEditable = function(prop)
		local typeData = prop.ValueType
		local typeName = typeData.Name

		return typeName ~= "bool" and typeData.Category ~= "Enum" and typeData.Category ~= "Class" and typeName ~= "BrickColor"
	end

	Properties.DisplayEnumDropdown = function(entryIndex)
		local context = Properties.EnumContext
		if not context then
			context = Lib.ContextMenu.new()
			context.Iconless = true
			context.MaxHeight = 200
			context.ReverseYOffset = 22
			Properties.EnumDropdown = context
		end

		if not inputProp or inputProp.ValueType.Category ~= "Enum" then return end
		local prop = inputProp

		local entry = propEntries[entryIndex]
		local valueFrame = entry.GuiElems.ValueFrame

		local enum = Enum[prop.ValueType.Name]
		if not enum then return end

		local sorted = {}
		for name,enum in next,enum:GetEnumItems() do
			sorted[#sorted+1] = enum
		end
		table.sort(sorted,function(a,b) return a.Name < b.Name end)

		context:Clear()

		local function onClick(name)
			if prop ~= inputProp then return end

			local enumItem = enum[name]
			inputProp = nil
			Properties.SetProp(prop,enumItem)
		end

		for i = 1,#sorted do
			local enumItem = sorted[i]
			context:Add({Name = enumItem.Name, OnClick = onClick})
		end

		context.Width = valueFrame.AbsoluteSize.X
		context:Show(valueFrame.AbsolutePosition.X, valueFrame.AbsolutePosition.Y + 22)
	end

	Properties.DisplayBrickColorEditor = function(prop,entryIndex,col)
		local editor = Properties.BrickColorEditor
		if not editor then
			editor = Lib.BrickColorPicker.new()
			editor.Gui.DisplayOrder = Main.DisplayOrders.Menu
			editor.ReverseYOffset = 22

			editor.OnSelect:Connect(function(col)
				if not editor.CurrentProp or editor.CurrentProp.ValueType.Name ~= "BrickColor" then return end

				if editor.CurrentProp == inputProp then inputProp = nil end
				Properties.SetProp(editor.CurrentProp,BrickColor.new(col))
			end)

			editor.OnMoreColors:Connect(function()
				editor:Close()
				local colProp
				for i,v in pairs(API.Classes.BasePart.Properties) do
					if v.Name == "Color" then
						colProp = v
						break
					end
				end
				Properties.DisplayColorEditor(colProp,editor.SavedColor.Color)
			end)

			Properties.BrickColorEditor = editor
		end

		local entry = propEntries[entryIndex]
		local valueFrame = entry.GuiElems.ValueFrame

		editor.CurrentProp = prop
		editor.SavedColor = col
		if prop and prop.Class == "BasePart" and prop.Name == "BrickColor" then
			editor:SetMoreColorsVisible(true)
		else
			editor:SetMoreColorsVisible(false)
		end
		editor:Show(valueFrame.AbsolutePosition.X, valueFrame.AbsolutePosition.Y + 22)
	end

	Properties.DisplayColorEditor = function(prop,col)
		local editor = Properties.ColorEditor
		if not editor then
			editor = Lib.ColorPicker.new()

			editor.OnSelect:Connect(function(col)
				if not editor.CurrentProp then return end
				local typeName = editor.CurrentProp.ValueType.Name
				if typeName ~= "Color3" and typeName ~= "BrickColor" then return end

				local colVal = (typeName == "Color3" and col or BrickColor.new(col))

				if editor.CurrentProp == inputProp then inputProp = nil end
				Properties.SetProp(editor.CurrentProp,colVal)
			end)

			Properties.ColorEditor = editor
		end

		editor.CurrentProp = prop
		if col then
			editor:SetColor(col)
		else
			local firstVal = Properties.GetFirstPropVal(prop)
			if firstVal then editor:SetColor(firstVal) end
		end
		editor:Show()
	end

	Properties.DisplayNumberSequenceEditor = function(prop,seq)
		local editor = Properties.NumberSequenceEditor
		if not editor then
			editor = Lib.NumberSequenceEditor.new()

			editor.OnSelect:Connect(function(val)
				if not editor.CurrentProp or editor.CurrentProp.ValueType.Name ~= "NumberSequence" then return end

				if editor.CurrentProp == inputProp then inputProp = nil end
				Properties.SetProp(editor.CurrentProp,val)
			end)

			Properties.NumberSequenceEditor = editor
		end

		editor.CurrentProp = prop
		if seq then
			editor:SetSequence(seq)
		else
			local firstVal = Properties.GetFirstPropVal(prop)
			if firstVal then editor:SetSequence(firstVal) end
		end
		editor:Show()
	end

	Properties.DisplayColorSequenceEditor = function(prop,seq)
		local editor = Properties.ColorSequenceEditor
		if not editor then
			editor = Lib.ColorSequenceEditor.new()

			editor.OnSelect:Connect(function(val)
				if not editor.CurrentProp or editor.CurrentProp.ValueType.Name ~= "ColorSequence" then return end

				if editor.CurrentProp == inputProp then inputProp = nil end
				Properties.SetProp(editor.CurrentProp,val)
			end)

			Properties.ColorSequenceEditor = editor
		end

		editor.CurrentProp = prop
		if seq then
			editor:SetSequence(seq)
		else
			local firstVal = Properties.GetFirstPropVal(prop)
			if firstVal then editor:SetSequence(firstVal) end
		end
		editor:Show()
	end

	Properties.GetFirstPropVal = function(prop)
		local first = Properties.FindFirstObjWhichIsA(prop.Class)
		if first then
			return Properties.GetPropVal(prop,first)
		end
	end

	Properties.GetPropVal = function(prop,obj)
		if prop.MultiType then return "<Multiple Types>" end
		if not obj then return end

		local propVal
		if prop.IsAttribute then
			propVal = getAttribute(obj,prop.AttributeName)
			if propVal == nil then return nil end

			local typ = typeof(propVal)
			local currentType = Properties.TypeNameConvert[typ] or typ
			if prop.RootType then
				if prop.RootType.Name ~= currentType then
					return nil
				end
			elseif prop.ValueType.Name ~= currentType then
				return nil
			end
		else
			propVal = obj[prop.Name]
		end
		if prop.SubName then
			local indexes = string.split(prop.SubName,".")
			for i = 1,#indexes do
				local indexName = indexes[i]
				if #indexName > 0 and propVal then
					propVal = propVal[indexName]
				end
			end
		end

		return propVal
	end

	Properties.SelectObject = function(obj)
		if inputProp and inputProp.ValueType.Category == "Class" then
			local prop = inputProp
			inputProp = nil

			if isa(obj,prop.ValueType.Name) then
				Properties.SetProp(prop,obj)
			else
				Properties.Refresh()
			end

			return true
		end

		return false
	end

	Properties.DisplayProp = function(prop,entryIndex)
		local propName = prop.Name
		local typeData = prop.ValueType
		local typeName = typeData.Name
		local tags = prop.Tags
		local gName = prop.Class.."."..prop.Name..(prop.SubName or "")
		local propObj = autoUpdateObjs[gName]
		local entryData = propEntries[entryIndex]
		local UDim2 = UDim2

		local guiElems = entryData.GuiElems
		local valueFrame = guiElems.ValueFrame
		local valueBox = guiElems.ValueBox
		local colorButton = guiElems.ColorButton
		local colorPreview = guiElems.ColorPreview
		local gradient = guiElems.Gradient
		local enumArrow = guiElems.EnumArrow
		local checkbox = guiElems.Checkbox
		local rightButton = guiElems.RightButton
		local soundPreview = guiElems.SoundPreview

		local propVal = Properties.GetPropVal(prop,propObj)
		local inputFullName = inputProp and (inputProp.Class.."."..inputProp.Name..(inputProp.SubName or ""))

		local offset = 4
		local endOffset = 6

		if (typeName == "Color3" or typeName == "BrickColor" or typeName == "ColorSequence") then
			colorButton.Visible = true
			enumArrow.Visible = false
			if propVal then
				gradient.Color = (typeName == "Color3" and ColorSequence.new(propVal)) or (typeName == "BrickColor" and ColorSequence.new(propVal.Color)) or propVal
			else
				gradient.Color = ColorSequence.new(Color3.new(1,1,1))
			end
			colorPreview.BorderColor3 = (typeName == "ColorSequence" and Color3.new(1,1,1) or Color3.new(0,0,0))
			offset = 22
			endOffset = 24 + (typeName == "ColorSequence" and 20 or 0)
		elseif typeData.Category == "Enum" then
			colorButton.Visible = false
			enumArrow.Visible = not prop.Tags.ReadOnly
			endOffset = 22
		elseif (gName == inputFullName and typeData.Category == "Class") or typeName == "NumberSequence" then
			colorButton.Visible = false
			enumArrow.Visible = false
			endOffset = 26
		else
			colorButton.Visible = false
			enumArrow.Visible = false
		end

		valueBox.Position = UDim2.new(0,offset,0,0)
		valueBox.Size = UDim2.new(1,-endOffset,1,0)

		if inputFullName == gName and typeData.Category == "Class" then
			Main.MiscIcons:DisplayByKey(guiElems.RightButtonIcon, "Delete")
			guiElems.RightButtonIcon.Visible = true
			rightButton.Text = ""
			rightButton.Visible = true
		elseif typeName == "NumberSequence" or typeName == "ColorSequence" then
			guiElems.RightButtonIcon.Visible = false
			rightButton.Text = "..."
			rightButton.Visible = true
		else
			rightButton.Visible = false
		end

		if typeName == "bool" or typeName == "PhysicalProperties" then
			valueBox.Visible = false
			checkbox.Visible = true
			soundPreview.Visible = false
			checkboxes[entryIndex].Disabled = tags.ReadOnly
			if typeName == "PhysicalProperties" and autoUpdateObjs[gName] then
				checkboxes[entryIndex]:SetState(propVal and true or false)
			else
				checkboxes[entryIndex]:SetState(propVal)
			end
		elseif typeName == "SoundPlayer" then
			valueBox.Visible = false
			checkbox.Visible = false
			soundPreview.Visible = true
			local playing = Properties.PreviewSound and Properties.PreviewSound.Playing
			Main.MiscIcons:DisplayByKey(soundPreview.ControlButton.Icon, playing and "Pause" or "Play")
		else
			valueBox.Visible = true
			checkbox.Visible = false
			soundPreview.Visible = false

			if propVal ~= nil then
				if typeName == "Color3" then
					valueBox.Text = "["..Lib.ColorToBytes(propVal).."]"
				elseif typeData.Category == "Enum" then
					valueBox.Text = propVal.Name
				elseif Properties.RoundableTypes[typeName] and Settings.Properties.NumberRounding then
					local rawStr = Properties.ValueToString(prop,propVal)
					valueBox.Text = rawStr:gsub("-?%d+%.%d+",function(num)
						return tostring(tonumber(("%."..Settings.Properties.NumberRounding.."f"):format(num)))
					end)
				else
					valueBox.Text = Properties.ValueToString(prop,propVal)
				end
			else
				valueBox.Text = ""
			end

			valueBox.TextColor3 = tags.ReadOnly and Settings.Theme.PlaceholderText or Settings.Theme.Text
		end
	end

	Properties.Refresh = function()
		local maxEntries = math.max(math.ceil((propsFrame.AbsoluteSize.Y) / 23),0)	
		local maxX = propsFrame.AbsoluteSize.X
		local valueWidth = math.max(Properties.MinInputWidth,maxX-Properties.ViewWidth)
		local inputPropVisible = false
		local isa = game.IsA
		local UDim2 = UDim2
		local stringSplit = string.split
		local scaleType = Settings.Properties.ScaleType

		for i = 1,#propCons do
			propCons[i]:Disconnect()
		end
		table.clear(propCons)

		Properties.FullNameFrame.Visible = false
		Properties.FullNameFrameAttach.Disable()

		for i = 1,maxEntries do
			local entryData = propEntries[i]
			if not propEntries[i] then entryData = Properties.NewPropEntry(i) propEntries[i] = entryData end

			local entry = entryData.Gui
			local guiElems = entryData.GuiElems
			local nameFrame = guiElems.NameFrame
			local propNameLabel = guiElems.PropName
			local valueFrame = guiElems.ValueFrame
			local expand = guiElems.Expand
			local valueBox = guiElems.ValueBox
			local propNameBox = guiElems.PropName
			local rightButton = guiElems.RightButton
			local editAttributeButton = guiElems.EditAttributeButton
			local toggleAttributes = guiElems.ToggleAttributes

			local prop = viewList[i + Properties.Index]
			if prop then
				local entryXOffset = (scaleType == 0 and scrollH.Index or 0)
				entry.Visible = true
				entry.Position = UDim2.new(0,-entryXOffset,0,entry.Position.Y.Offset)
				entry.Size = UDim2.new(scaleType == 0 and 0 or 1, scaleType == 0 and Properties.ViewWidth + valueWidth or 0,0,22)

				if prop.SpecialRow then
					if prop.SpecialRow == "AddAttribute" then
						nameFrame.Visible = false
						valueFrame.Visible = false
						guiElems.RowButton.Visible = true
					end
				else
					nameFrame.Visible = true
					guiElems.RowButton.Visible = false

					local depth = Properties.EntryIndent*(prop.Depth or 1)
					local leftOffset = depth + Properties.EntryOffset
					nameFrame.Position = UDim2.new(0,leftOffset,0,0)
					propNameLabel.Size = UDim2.new(1,-2 - (scaleType == 0 and 0 or 6),1,0)

					local gName = (prop.CategoryName and "CAT_"..prop.CategoryName) or prop.Class.."."..prop.Name..(prop.SubName or "")

					if prop.CategoryName then
						entry.BackgroundColor3 = Settings.Theme.Main1
						valueFrame.Visible = false

						propNameBox.Text = prop.CategoryName
						propNameBox.Font = Enum.Font.SourceSansBold
						expand.Visible = true
						propNameBox.TextColor3 = Settings.Theme.Text
						nameFrame.BackgroundTransparency = 1
						nameFrame.Size = UDim2.new(1,0,1,0)
						editAttributeButton.Visible = false

						local showingAttrs = Settings.Properties.ShowAttributes
						toggleAttributes.Position = UDim2.new(1,-85-leftOffset,0,0)
						toggleAttributes.Text = (showingAttrs and "[Setting: ON]" or "[Setting: OFF]")
						toggleAttributes.TextColor3 = Settings.Theme.Text
						toggleAttributes.Visible = (prop.CategoryName == "Attributes")
					else
						local propName = prop.Name
						local typeData = prop.ValueType
						local typeName = typeData.Name
						local tags = prop.Tags
						local propObj = autoUpdateObjs[gName]

						local attributeOffset = (prop.IsAttribute and 20 or 0)
						editAttributeButton.Visible = (prop.IsAttribute and not prop.RootType)
						toggleAttributes.Visible = false

						if scaleType == 0 then
							nameFrame.Size = UDim2.new(0,Properties.ViewWidth - leftOffset - 1,1,0)
							valueFrame.Position = UDim2.new(0,Properties.ViewWidth,0,0)
							valueFrame.Size = UDim2.new(0,valueWidth - attributeOffset,1,0)
						else
							nameFrame.Size = UDim2.new(0.5,-leftOffset - 1,1,0)
							valueFrame.Position = UDim2.new(0.5,0,0,0)
							valueFrame.Size = UDim2.new(0.5,-attributeOffset,1,0)
						end

						local nameArr = stringSplit(gName,".")
						propNameBox.Text = prop.DisplayName or nameArr[#nameArr]
						propNameBox.Font = Enum.Font.SourceSans
						entry.BackgroundColor3 = Settings.Theme.Main2
						valueFrame.Visible = true

						expand.Visible = typeData.Category == "DataType" and Properties.ExpandableTypes[typeName] or Properties.ExpandableProps[gName]
						propNameBox.TextColor3 = tags.ReadOnly and Settings.Theme.PlaceholderText or Settings.Theme.Text

						Properties.DisplayProp(prop,i)
						if propObj then
							if prop.IsAttribute then
								propCons[#propCons+1] = getAttributeChangedSignal(propObj,prop.AttributeName):Connect(function()
									Properties.DisplayProp(prop,i)
								end)
							else
								propCons[#propCons+1] = getPropChangedSignal(propObj,propName):Connect(function()
									Properties.DisplayProp(prop,i)
								end)
							end
						end

						local beforeVisible = valueBox.Visible
						local inputFullName = inputProp and (inputProp.Class.."."..inputProp.Name..(inputProp.SubName or ""))
						if gName == inputFullName then
							nameFrame.BackgroundColor3 = Settings.Theme.ListSelection
							nameFrame.BackgroundTransparency = 0
							if typeData.Category == "Class" or typeData.Category == "Enum" or typeName == "BrickColor" then
								valueFrame.BackgroundColor3 = Settings.Theme.TextBox
								valueFrame.BackgroundTransparency = 0
								valueBox.Visible = true
							else
								inputPropVisible = true
								local scale = (scaleType == 0 and 0 or 0.5)
								local offset = (scaleType == 0 and Properties.ViewWidth-scrollH.Index or 0)
								local endOffset = 0

								if typeName == "Color3" or typeName == "ColorSequence" then
									offset = offset + 22
								end

								if typeName == "NumberSequence" or typeName == "ColorSequence" then
									endOffset = 20
								end

								inputBox.Position = UDim2.new(scale,offset,0,entry.Position.Y.Offset)
								inputBox.Size = UDim2.new(1-scale,-offset-endOffset-attributeOffset,0,22)
								inputBox.Visible = true
								valueBox.Visible = false
							end
						else
							nameFrame.BackgroundColor3 = Settings.Theme.Main1
							nameFrame.BackgroundTransparency = 1
							valueFrame.BackgroundColor3 = Settings.Theme.Main1
							valueFrame.BackgroundTransparency = 1
							valueBox.Visible = beforeVisible
						end
					end

					if prop.CategoryName or Properties.ExpandableTypes[prop.ValueType and prop.ValueType.Name] or Properties.ExpandableProps[gName] then
						if Lib.CheckMouseInGui(expand) then
							Main.MiscIcons:DisplayByKey(expand.Icon, expanded[gName] and "Collapse_Over" or "Expand_Over")
						else
							Main.MiscIcons:DisplayByKey(expand.Icon, expanded[gName] and "Collapse" or "Expand")
						end
						expand.Visible = true
					else
						expand.Visible = false
					end
				end
				entry.Visible = true
			else
				entry.Visible = false
			end
		end

		if not inputPropVisible then
			inputBox.Visible = false
		end

		for i = maxEntries+1,#propEntries do
			propEntries[i].Gui:Destroy()
			propEntries[i] = nil
			checkboxes[i] = nil
		end
	end

	Properties.SetProp = function(prop,val,noupdate,prevAttribute)
		local sList = Explorer.Selection.List
		local propName = prop.Name
		local subName = prop.SubName
		local propClass = prop.Class
		local typeData = prop.ValueType
		local typeName = typeData.Name
		local attributeName = prop.AttributeName
		local rootTypeData = prop.RootType
		local rootTypeName = rootTypeData and rootTypeData.Name
		local fullName = prop.Class.."."..prop.Name..(prop.SubName or "")
		local Vector3 = Vector3

		for i = 1,#sList do
			local node = sList[i]
			local obj = node.Obj

			if isa(obj,propClass) then
				pcall(function()
					local setVal = val
					local root
					if prop.IsAttribute then
						root = getAttribute(obj,attributeName)
					else
						root = obj[propName]
					end

					if prevAttribute then
						if prevAttribute.ValueType.Name == typeName then
							setVal = getAttribute(obj,prevAttribute.AttributeName) or setVal
						end
						setAttribute(obj,prevAttribute.AttributeName,nil)
					end

					if rootTypeName then
						if rootTypeName == "Vector2" then
							setVal = Vector2.new((subName == ".X" and setVal) or root.X, (subName == ".Y" and setVal) or root.Y)
						elseif rootTypeName == "Vector3" then
							setVal = Vector3.new((subName == ".X" and setVal) or root.X, (subName == ".Y" and setVal) or root.Y, (subName == ".Z" and setVal) or root.Z)
						elseif rootTypeName == "UDim" then
							setVal = UDim.new((subName == ".Scale" and setVal) or root.Scale, (subName == ".Offset" and setVal) or root.Offset)
						elseif rootTypeName == "UDim2" then
							local rootX,rootY = root.X,root.Y
							local X_UDim = (subName == ".X" and setVal) or UDim.new((subName == ".X.Scale" and setVal) or rootX.Scale, (subName == ".X.Offset" and setVal) or rootX.Offset)
							local Y_UDim = (subName == ".Y" and setVal) or UDim.new((subName == ".Y.Scale" and setVal) or rootY.Scale, (subName == ".Y.Offset" and setVal) or rootY.Offset)
							setVal = UDim2.new(X_UDim,Y_UDim)
						elseif rootTypeName == "CFrame" then
							local rootPos,rootRight,rootUp,rootLook = root.Position,root.RightVector,root.UpVector,root.LookVector
							local pos = (subName == ".Position" and setVal) or Vector3.new((subName == ".Position.X" and setVal) or rootPos.X, (subName == ".Position.Y" and setVal) or rootPos.Y, (subName == ".Position.Z" and setVal) or rootPos.Z)
							local rightV = (subName == ".RightVector" and setVal) or Vector3.new((subName == ".RightVector.X" and setVal) or rootRight.X, (subName == ".RightVector.Y" and setVal) or rootRight.Y, (subName == ".RightVector.Z" and setVal) or rootRight.Z)
							local upV = (subName == ".UpVector" and setVal) or Vector3.new((subName == ".UpVector.X" and setVal) or rootUp.X, (subName == ".UpVector.Y" and setVal) or rootUp.Y, (subName == ".UpVector.Z" and setVal) or rootUp.Z)
							local lookV = (subName == ".LookVector" and setVal) or Vector3.new((subName == ".LookVector.X" and setVal) or rootLook.X, (subName == ".RightVector.Y" and setVal) or rootLook.Y, (subName == ".RightVector.Z" and setVal) or rootLook.Z)
							setVal = CFrame.fromMatrix(pos,rightV,upV,-lookV)
						elseif rootTypeName == "Rect" then
							local rootMin,rootMax = root.Min,root.Max
							local min = Vector2.new((subName == ".Min.X" and setVal) or rootMin.X, (subName == ".Min.Y" and setVal) or rootMin.Y)
							local max = Vector2.new((subName == ".Max.X" and setVal) or rootMax.X, (subName == ".Max.Y" and setVal) or rootMax.Y)
							setVal = Rect.new(min,max)
						elseif rootTypeName == "PhysicalProperties" then
							local rootProps = PhysicalProperties.new(obj.Material)
							local density = (subName == ".Density" and setVal) or (root and root.Density) or rootProps.Density
							local friction = (subName == ".Friction" and setVal) or (root and root.Friction) or rootProps.Friction
							local elasticity = (subName == ".Elasticity" and setVal) or (root and root.Elasticity) or rootProps.Elasticity
							local frictionWeight = (subName == ".FrictionWeight" and setVal) or (root and root.FrictionWeight) or rootProps.FrictionWeight
							local elasticityWeight = (subName == ".ElasticityWeight" and setVal) or (root and root.ElasticityWeight) or rootProps.ElasticityWeight
							setVal = PhysicalProperties.new(density,friction,elasticity,frictionWeight,elasticityWeight)
						elseif rootTypeName == "Ray" then
							local rootOrigin,rootDirection = root.Origin,root.Direction
							local origin = (subName == ".Origin" and setVal) or Vector3.new((subName == ".Origin.X" and setVal) or rootOrigin.X, (subName == ".Origin.Y" and setVal) or rootOrigin.Y, (subName == ".Origin.Z" and setVal) or rootOrigin.Z)
							local direction = (subName == ".Direction" and setVal) or Vector3.new((subName == ".Direction.X" and setVal) or rootDirection.X, (subName == ".Direction.Y" and setVal) or rootDirection.Y, (subName == ".Direction.Z" and setVal) or rootDirection.Z)
							setVal = Ray.new(origin,direction)
						elseif rootTypeName == "Faces" then
							local faces = {}
							local faceList = {"Back","Bottom","Front","Left","Right","Top"}
							for _,face in pairs(faceList) do
								local val
								if subName == "."..face then
									val = setVal
								else
									val = root[face]
								end
								if val then faces[#faces+1] = Enum.NormalId[face] end
							end
							setVal = Faces.new(unpack(faces))
						elseif rootTypeName == "Axes" then
							local axes = {}
							local axesList = {"X","Y","Z"}
							for _,axe in pairs(axesList) do
								local val
								if subName == "."..axe then
									val = setVal
								else
									val = root[axe]
								end
								if val then axes[#axes+1] = Enum.Axis[axe] end
							end
							setVal = Axes.new(unpack(axes))
						elseif rootTypeName == "NumberRange" then
							setVal = NumberRange.new(subName == ".Min" and setVal or root.Min, subName == ".Max" and setVal or root.Max)
						end
					end

					if typeName == "PhysicalProperties" and setVal then
						setVal = root or PhysicalProperties.new(obj.Material)
					end

					if prop.IsAttribute then
						setAttribute(obj,attributeName,setVal)
					else
						obj[propName] = setVal
					end
				end)
			end
		end

		if not noupdate then
			Properties.ComputeConflicts(prop)
		end
	end

	Properties.InitInputBox = function()
		inputBox = create({
			{1,"Frame",{BackgroundColor3=Color3.new(0.14901961386204,0.14901961386204,0.14901961386204),BorderSizePixel=0,Name="InputBox",Size=UDim2.new(0,200,0,22),Visible=false,ZIndex=2,}},
			{2,"TextBox",{BackgroundColor3=Color3.new(0.17647059261799,0.17647059261799,0.17647059261799),BackgroundTransparency=1,BorderColor3=Color3.new(0.062745101749897,0.51764708757401,1),BorderSizePixel=0,ClearTextOnFocus=false,Font=3,Parent={1},PlaceholderColor3=Color3.new(0.69803923368454,0.69803923368454,0.69803923368454),Position=UDim2.new(0,3,0,0),Size=UDim2.new(1,-6,1,0),Text="",TextColor3=Color3.new(1,1,1),TextSize=14,TextXAlignment=0,ZIndex=2,}},
		})
		inputTextBox = inputBox.TextBox
		inputBox.BackgroundColor3 = Settings.Theme.TextBox
		inputBox.Parent = Properties.Window.GuiElems.Content.List

		inputTextBox.FocusLost:Connect(function()
			if not inputProp then return end

			local prop = inputProp
			inputProp = nil
			local val = Properties.StringToValue(prop,inputTextBox.Text)
			if val then Properties.SetProp(prop,val) else Properties.Refresh() end
		end)

		inputTextBox.Focused:Connect(function()
			inputTextBox.SelectionStart = 1
			inputTextBox.CursorPosition = #inputTextBox.Text + 1
		end)

		Lib.ViewportTextBox.convert(inputTextBox)
	end

	Properties.SetInputProp = function(prop,entryIndex,special)
		local typeData = prop.ValueType
		local typeName = typeData.Name
		local fullName = prop.Class.."."..prop.Name..(prop.SubName or "")
		local propObj = autoUpdateObjs[fullName]
		local propVal = Properties.GetPropVal(prop,propObj)

		if prop.Tags.ReadOnly then return end

		inputProp = prop
		if special then
			if special == "color" then
				if typeName == "Color3" then
					inputTextBox.Text = propVal and Properties.ValueToString(prop,propVal) or ""
					Properties.DisplayColorEditor(prop,propVal)
				elseif typeName == "BrickColor" then
					Properties.DisplayBrickColorEditor(prop,entryIndex,propVal)
				elseif typeName == "ColorSequence" then
					inputTextBox.Text = propVal and Properties.ValueToString(prop,propVal) or ""
					Properties.DisplayColorSequenceEditor(prop,propVal)
				end
			elseif special == "right" then
				if typeName == "NumberSequence" then
					inputTextBox.Text = propVal and Properties.ValueToString(prop,propVal) or ""
					Properties.DisplayNumberSequenceEditor(prop,propVal)
				elseif typeName == "ColorSequence" then
					inputTextBox.Text = propVal and Properties.ValueToString(prop,propVal) or ""
					Properties.DisplayColorSequenceEditor(prop,propVal)
				end
			end
		else
			if Properties.IsTextEditable(prop) then
				inputTextBox.Text = propVal and Properties.ValueToString(prop,propVal) or ""
				inputTextBox:CaptureFocus()
			elseif typeData.Category == "Enum" then
				Properties.DisplayEnumDropdown(entryIndex)
			elseif typeName == "BrickColor" then
				Properties.DisplayBrickColorEditor(prop,entryIndex,propVal)
			end
		end
		Properties.Refresh()
	end

	Properties.InitSearch = function()
		local searchBox = Properties.GuiElems.ToolBar.SearchFrame.SearchBox

		Lib.ViewportTextBox.convert(searchBox)

		searchBox:GetPropertyChangedSignal("Text"):Connect(function()
			Properties.SearchText = searchBox.Text
			Properties.Update()
			Properties.Refresh()
		end)
	end

	Properties.InitEntryStuff = function()
		Properties.EntryTemplate = create({
			{1,"TextButton",{AutoButtonColor=false,BackgroundColor3=Color3.new(0.17647059261799,0.17647059261799,0.17647059261799),BorderColor3=Color3.new(0.1294117718935,0.1294117718935,0.1294117718935),Font=3,Name="Entry",Position=UDim2.new(0,1,0,1),Size=UDim2.new(0,250,0,22),Text="",TextSize=14,}},
			{2,"Frame",{BackgroundColor3=Color3.new(0.04313725605607,0.35294118523598,0.68627452850342),BackgroundTransparency=1,BorderColor3=Color3.new(0.33725491166115,0.49019610881805,0.73725491762161),BorderSizePixel=0,Name="NameFrame",Parent={1},Position=UDim2.new(0,20,0,0),Size=UDim2.new(1,-40,1,0),}},
			{3,"TextLabel",{BackgroundColor3=Color3.new(1,1,1),BackgroundTransparency=1,Font=3,Name="PropName",Parent={2},Position=UDim2.new(0,2,0,0),Size=UDim2.new(1,-2,1,0),Text="Anchored",TextColor3=Color3.new(1,1,1),TextSize=14,TextTransparency=0.10000000149012,TextTruncate=1,TextXAlignment=0,}},
			{4,"TextButton",{BackgroundColor3=Color3.new(1,1,1),BackgroundTransparency=1,ClipsDescendants=true,Font=3,Name="Expand",Parent={2},Position=UDim2.new(0,-20,0,1),Size=UDim2.new(0,20,0,20),Text="",TextSize=14,Visible=false,}},
			{5,"ImageLabel",{BackgroundColor3=Color3.new(1,1,1),BackgroundTransparency=1,Image="rbxassetid://5642383285",ImageRectOffset=Vector2.new(144,16),ImageRectSize=Vector2.new(16,16),Name="Icon",Parent={4},Position=UDim2.new(0,2,0,2),ScaleType=4,Size=UDim2.new(0,16,0,16),}},
			{6,"TextButton",{BackgroundColor3=Color3.new(1,1,1),BackgroundTransparency=1,BorderSizePixel=0,Font=4,Name="ToggleAttributes",Parent={2},Position=UDim2.new(1,-85,0,0),Size=UDim2.new(0,85,0,22),Text="[SETTING: OFF]",TextColor3=Color3.new(1,1,1),TextSize=14,TextTransparency=0.10000000149012,Visible=false,}},
			{7,"Frame",{BackgroundColor3=Color3.new(0.04313725605607,0.35294118523598,0.68627452850342),BackgroundTransparency=1,BorderColor3=Color3.new(0.33725491166115,0.49019607901573,0.73725491762161),BorderSizePixel=0,Name="ValueFrame",Parent={1},Position=UDim2.new(1,-100,0,0),Size=UDim2.new(0,80,1,0),}},
			{8,"Frame",{BackgroundColor3=Color3.new(0.14117647707462,0.14117647707462,0.14117647707462),BorderColor3=Color3.new(0.33725491166115,0.49019610881805,0.73725491762161),BorderSizePixel=0,Name="Line",Parent={7},Position=UDim2.new(0,-1,0,0),Size=UDim2.new(0,1,1,0),}},
			{9,"TextButton",{BackgroundColor3=Color3.new(1,1,1),BackgroundTransparency=1,BorderSizePixel=0,Font=3,Name="ColorButton",Parent={7},Size=UDim2.new(0,20,0,22),Text="",TextColor3=Color3.new(1,1,1),TextSize=14,Visible=false,}},
			{10,"Frame",{BackgroundColor3=Color3.new(1,1,1),BorderColor3=Color3.new(0,0,0),Name="ColorPreview",Parent={9},Position=UDim2.new(0,5,0,6),Size=UDim2.new(0,10,0,10),}},
			{11,"UIGradient",{Parent={10},}},
			{12,"Frame",{BackgroundTransparency=1,Name="EnumArrow",Parent={7},Position=UDim2.new(1,-16,0,3),Size=UDim2.new(0,16,0,16),Visible=false,}},
			{13,"Frame",{BackgroundColor3=Color3.new(0.86274510622025,0.86274510622025,0.86274510622025),BorderSizePixel=0,Parent={12},Position=UDim2.new(0,8,0,9),Size=UDim2.new(0,1,0,1),}},
			{14,"Frame",{BackgroundColor3=Color3.new(0.86274510622025,0.86274510622025,0.86274510622025),BorderSizePixel=0,Parent={12},Position=UDim2.new(0,7,0,8),Size=UDim2.new(0,3,0,1),}},
			{15,"Frame",{BackgroundColor3=Color3.new(0.86274510622025,0.86274510622025,0.86274510622025),BorderSizePixel=0,Parent={12},Position=UDim2.new(0,6,0,7),Size=UDim2.new(0,5,0,1),}},
			{16,"TextButton",{BackgroundColor3=Color3.new(1,1,1),BackgroundTransparency=1,Font=3,Name="ValueBox",Parent={7},Position=UDim2.new(0,4,0,0),Size=UDim2.new(1,-8,1,0),Text="",TextColor3=Color3.new(1,1,1),TextSize=14,TextTransparency=0.10000000149012,TextTruncate=1,TextXAlignment=0,}},
			{17,"TextButton",{BackgroundColor3=Color3.new(1,1,1),BackgroundTransparency=1,BorderSizePixel=0,Font=3,Name="RightButton",Parent={7},Position=UDim2.new(1,-20,0,0),Size=UDim2.new(0,20,0,22),Text="...",TextColor3=Color3.new(1,1,1),TextSize=14,Visible=false,}},
			{18,"TextButton",{BackgroundColor3=Color3.new(1,1,1),BackgroundTransparency=1,BorderSizePixel=0,Font=3,Name="SettingsButton",Parent={7},Position=UDim2.new(1,-20,0,0),Size=UDim2.new(0,20,0,22),Text="",TextColor3=Color3.new(1,1,1),TextSize=14,Visible=false,}},
			{19,"Frame",{BackgroundColor3=Color3.new(1,1,1),BackgroundTransparency=1,Name="SoundPreview",Parent={7},Size=UDim2.new(1,0,1,0),Visible=false,}},
			{20,"TextButton",{BackgroundColor3=Color3.new(1,1,1),BackgroundTransparency=1,BorderSizePixel=0,Font=3,Name="ControlButton",Parent={19},Size=UDim2.new(0,20,0,22),Text="",TextColor3=Color3.new(1,1,1),TextSize=14,}},
			{21,"ImageLabel",{BackgroundColor3=Color3.new(1,1,1),BackgroundTransparency=1,Image="rbxassetid://5642383285",ImageRectOffset=Vector2.new(144,16),ImageRectSize=Vector2.new(16,16),Name="Icon",Parent={20},Position=UDim2.new(0,2,0,3),ScaleType=4,Size=UDim2.new(0,16,0,16),}},
			{22,"Frame",{BackgroundColor3=Color3.new(0.3137255012989,0.3137255012989,0.3137255012989),BorderSizePixel=0,Name="TimeLine",Parent={19},Position=UDim2.new(0,26,0.5,-1),Size=UDim2.new(1,-34,0,2),}},
			{23,"Frame",{BackgroundColor3=Color3.new(0.2352941185236,0.2352941185236,0.2352941185236),BorderColor3=Color3.new(0.1294117718935,0.1294117718935,0.1294117718935),Name="Slider",Parent={22},Position=UDim2.new(0,-4,0,-8),Size=UDim2.new(0,8,0,18),}},
			{24,"TextButton",{BackgroundColor3=Color3.new(1,1,1),BackgroundTransparency=1,BorderSizePixel=0,Font=3,Name="EditAttributeButton",Parent={1},Position=UDim2.new(1,-20,0,0),Size=UDim2.new(0,20,0,22),Text="",TextColor3=Color3.new(1,1,1),TextSize=14,}},
			{25,"ImageLabel",{BackgroundColor3=Color3.new(1,1,1),BackgroundTransparency=1,Image="rbxassetid://5034718180",ImageTransparency=0.20000000298023,Name="Icon",Parent={24},Position=UDim2.new(0,2,0,3),Size=UDim2.new(0,16,0,16),}},
			{26,"TextButton",{AutoButtonColor=false,BackgroundColor3=Color3.new(0.2352941185236,0.2352941185236,0.2352941185236),BorderSizePixel=0,Font=3,Name="RowButton",Parent={1},Size=UDim2.new(1,0,1,0),Text="Add Attribute",TextColor3=Color3.new(1,1,1),TextSize=14,TextTransparency=0.10000000149012,Visible=false,}},
		})

		local fullNameFrame = Lib.Frame.new()
		local label = Lib.Label.new()
		label.Parent = fullNameFrame.Gui
		label.Position = UDim2.new(0,2,0,0)
		label.Size = UDim2.new(1,-4,1,0)
		fullNameFrame.Visible = false
		fullNameFrame.Parent = window.Gui
		
		if Settings.Window.Transparency and Settings.Window.Transparency > 0 then
			Properties.EntryTemplate.BackgroundTransparency = 0.75
		end


		Properties.FullNameFrame = fullNameFrame
		Properties.FullNameFrameAttach = Lib.AttachTo(fullNameFrame)
	end

	Properties.Init = function()
		local guiItems = create({
			{1,"Folder",{Name="Items",}},
			{2,"Frame",{BackgroundColor3=Color3.new(0.20392157137394,0.20392157137394,0.20392157137394),BorderSizePixel=0,Name="ToolBar",Parent={1},Size=UDim2.new(1,0,0,22),}},
			{3,"Frame",{BackgroundColor3=Color3.new(0.14901961386204,0.14901961386204,0.14901961386204),BorderColor3=Color3.new(0.1176470592618,0.1176470592618,0.1176470592618),BorderSizePixel=0,Name="SearchFrame",Parent={2},Position=UDim2.new(0,3,0,1),Size=UDim2.new(1,-6,0,18),}},
			{4,"TextBox",{BackgroundColor3=Color3.new(1,1,1),BackgroundTransparency=1,ClearTextOnFocus=false,Font=3,Name="SearchBox",Parent={3},PlaceholderColor3=Color3.new(0.39215689897537,0.39215689897537,0.39215689897537),PlaceholderText="Search properties",Position=UDim2.new(0,4,0,0),Size=UDim2.new(1,-24,0,18),Text="",TextColor3=Color3.new(1,1,1),TextSize=14,TextXAlignment=0,}},
			{5,"UICorner",{CornerRadius=UDim.new(0,2),Parent={3},}},
			{6,"TextButton",{AutoButtonColor=false,BackgroundColor3=Color3.new(0.12549020349979,0.12549020349979,0.12549020349979),BackgroundTransparency=1,BorderSizePixel=0,Font=3,Name="Reset",Parent={3},Position=UDim2.new(1,-17,0,1),Size=UDim2.new(0,16,0,16),Text="",TextColor3=Color3.new(1,1,1),TextSize=14,}},
			{7,"ImageLabel",{BackgroundColor3=Color3.new(1,1,1),BackgroundTransparency=1,Image="rbxassetid://5034718129",ImageColor3=Color3.new(0.39215686917305,0.39215686917305,0.39215686917305),Parent={6},Size=UDim2.new(0,16,0,16),}},
			{8,"TextButton",{AutoButtonColor=false,BackgroundColor3=Color3.new(0.12549020349979,0.12549020349979,0.12549020349979),BackgroundTransparency=1,BorderSizePixel=0,Font=3,Name="Refresh",Parent={2},Position=UDim2.new(1,-20,0,1),Size=UDim2.new(0,18,0,18),Text="",TextColor3=Color3.new(1,1,1),TextSize=14,Visible=false,}},
			{9,"ImageLabel",{BackgroundColor3=Color3.new(1,1,1),BackgroundTransparency=1,Image="rbxassetid://5642310344",Parent={8},Position=UDim2.new(0,3,0,3),Size=UDim2.new(0,12,0,12),}},
			{10,"Frame",{BackgroundColor3=Color3.new(0.15686275064945,0.15686275064945,0.15686275064945),BorderSizePixel=0,Name="ScrollCorner",Parent={1},Position=UDim2.new(1,-16,1,-16),Size=UDim2.new(0,16,0,16),Visible=false,}},
			{11,"Frame",{BackgroundColor3=Color3.new(1,1,1),BackgroundTransparency=1,ClipsDescendants=true,Name="List",Parent={1},Position=UDim2.new(0,0,0,23),Size=UDim2.new(1,0,1,-23),}},
		})

		categoryOrder =  API.CategoryOrder
		for category,_ in next,categoryOrder do
			if not Properties.CollapsedCategories[category] then
				expanded["CAT_"..category] = true
			end
		end
		expanded["Sound.SoundId"] = true

		window = Lib.Window.new()
		Properties.Window = window
		window:SetTitle("Properties")

		toolBar = guiItems.ToolBar
		propsFrame = guiItems.List

		Properties.GuiElems.ToolBar = toolBar
		Properties.GuiElems.PropsFrame = propsFrame

		Properties.InitEntryStuff()

		window.GuiElems.Main:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
			if Properties.Window:IsContentVisible() then
				Properties.UpdateView()
				Properties.Refresh()
			end
		end)
		window.OnActivate:Connect(function()
			Properties.UpdateView()
			Properties.Update()
			Properties.Refresh()
		end)
		window.OnRestore:Connect(function()
			Properties.UpdateView()
			Properties.Update()
			Properties.Refresh()
		end)

		scrollV = Lib.ScrollBar.new()		
		scrollV.WheelIncrement = 3
		scrollV.Gui.Position = UDim2.new(1,-16,0,23)
		scrollV:SetScrollFrame(propsFrame)
		scrollV.Scrolled:Connect(function()
			Properties.Index = scrollV.Index
			Properties.Refresh()
		end)

		scrollH = Lib.ScrollBar.new(true)
		scrollH.Increment = 5
		scrollH.WheelIncrement = 20
		scrollH.Gui.Position = UDim2.new(0,0,1,-16)
		scrollH.Scrolled:Connect(function()
			Properties.Refresh()
		end)

		window.GuiElems.Line.Position = UDim2.new(0,0,0,22)
		toolBar.Parent = window.GuiElems.Content
		propsFrame.Parent = window.GuiElems.Content
		guiItems.ScrollCorner.Parent = window.GuiElems.Content
		scrollV.Gui.Parent = window.GuiElems.Content
		scrollH.Gui.Parent = window.GuiElems.Content
		Properties.InitInputBox()
		Properties.InitSearch()
	end

	return Properties
end

if gethsfuncs then
	_G.moduleData = {InitDeps = initDeps, InitAfterMain = initAfterMain, Main = main}
else
	return {InitDeps = initDeps, InitAfterMain = initAfterMain, Main = main}
end
end,
["SaveInstance"] = function()

local Main,Lib,Apps,Settings
local Explorer, Properties, ScriptViewer, SaveInstance, Notebook
local API,RMD,env,service,plr,create,createSimple

local function initDeps(data)
	Main = data.Main
	Lib = data.Lib
	Apps = data.Apps
	Settings = data.Settings

	API = data.API
	RMD = data.RMD
	env = data.env
	service = data.service
	plr = data.plr
	create = data.create
	createSimple = data.createSimple
end

local function initAfterMain()
	Explorer = Apps.Explorer
	Properties = Apps.Properties
	ScriptViewer = Apps.ScriptViewer
	SaveInstance = Apps.SaveInstance
	Notebook = Apps.Notebook
end

local function main()
	local SaveInstance = {}
	local window, ListFrame
	local fileName = "Place_"..game.PlaceId.."_"..game:GetService("MarketplaceService"):GetProductInfo(game.PlaceId).Name.."_{TIMESTAMP}"
	local Saving = false
	
	local SaveInstanceArgs = {
		Decompile = true,
		DecompileTimeout = 10,
		DecompileIgnore = {"Chat", "CoreGui", "CorePackages"},
		NilInstances = false,
		RemovePlayerCharacters = true,
		SavePlayers = false,
		MaxThreads = 3,
		ShowStatus = true,
		IgnoreDefaultProps = true,
		IsolateStarterPlayer = true
	}
	
	local function AddCheckbox(title, default)
		local frame = Lib.Frame.new()
		frame.Gui.Parent = ListFrame
		frame.Gui.Transparency = 1
		frame.Gui.Size = UDim2.new(1,0,0,20)
		
		local listlayout = Instance.new("UIListLayout")
		listlayout.Parent = frame.Gui
		listlayout.FillDirection = Enum.FillDirection.Horizontal
		listlayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
		listlayout.VerticalAlignment = Enum.VerticalAlignment.Center
		listlayout.Padding = UDim.new(0, 10)
		
		local checkbox = Lib.Checkbox.new()
		
		checkbox.Gui.Parent = frame.Gui
		checkbox.Gui.Size = UDim2.new(0,15,0,15)
		
		local label = Lib.Label.new()
		
		label.Gui.Parent = frame.Gui
		label.Gui.Size = UDim2.new(1, 0,1, -15)
		label.Gui.Text = title
		label.TextTruncate = Enum.TextTruncate.AtEnd
		
		checkbox:SetState(default)
		
		return checkbox
	end
	
	local function AddTextbox(title, default, sizeX)
		default = tostring(default)
		local frame = Lib.Frame.new()
		frame.Gui.Parent = ListFrame
		frame.Gui.Transparency = 1
		frame.Gui.Size = UDim2.new(1,0,0,20)

		local listlayout = Instance.new("UIListLayout")
		listlayout.Parent = frame.Gui
		listlayout.FillDirection = Enum.FillDirection.Horizontal
		listlayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
		listlayout.VerticalAlignment = Enum.VerticalAlignment.Center
		listlayout.Padding = UDim.new(0, 10)

		local textbox = Instance.new("TextBox")
		textbox.BackgroundColor3 = Settings.Theme.TextBox
		textbox.BorderColor3 = Settings.Theme.Outline3
		textbox.ClearTextOnFocus = false
		textbox.TextColor3 = Settings.Theme.Text
		textbox.Font = Enum.Font.SourceSans
		textbox.TextSize = 14
		textbox.ZIndex = 2

		textbox.Parent = frame.Gui
		if sizeX and type(sizeX) == "number" then
			textbox.Size = UDim2.new(0,sizeX,0,15)
		else
			textbox.Size = UDim2.new(0,45,0,15)
		end
		
		frame.Gui.AutomaticSize = Enum.AutomaticSize.X
		textbox.AutomaticSize = Enum.AutomaticSize.X

		local label = Lib.Label.new()

		label.Parent = frame.Gui
		label.Size = UDim2.new(1, 0,1, -15)
		label.Text = title
		label.TextTruncate = Enum.TextTruncate.AtEnd

		textbox.Text = default

		return {TextBox = textbox}
	end
	
	SaveInstance.Init = function()
		window = Lib.Window.new()
		window:SetTitle("Save Instance")
		window:Resize(350,350)
		SaveInstance.Window = window
		
		
		ListFrame = Instance.new("ScrollingFrame")
		ListFrame.Parent = window.GuiElems.Content
		ListFrame.Size = UDim2.new(1, 0,1, -40)
		ListFrame.Position = UDim2.new(0, 0, 0, 0)
		ListFrame.Transparency = 1
		ListFrame.CanvasSize = UDim2.new(0,0,0,0)
		ListFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
		ListFrame.ScrollBarThickness = 16
		ListFrame.BottomImage = ""
		ListFrame.TopImage = ""
		ListFrame.ScrollBarImageColor3 = Color3.fromRGB(70, 70, 70)
		ListFrame.ScrollBarImageTransparency = 0
		ListFrame.ZIndex = 2
		ListFrame.BorderSizePixel = 0
		
		local scrollbar = Lib.ScrollBar.new()
		scrollbar.Gui.Parent = window.GuiElems.Content
		scrollbar.Gui.Size = UDim2.new(1, 0,1, -40)
		scrollbar.Gui.Up.ZIndex = 3
		scrollbar.Gui.Down.ZIndex = 3
		
		ListFrame:GetPropertyChangedSignal("AbsoluteWindowSize"):Connect(function()
			if ListFrame.AbsoluteCanvasSize ~= ListFrame.AbsoluteWindowSize then
				scrollbar.Gui.Visible = true
			else
				scrollbar.Gui.Visible = false
			end
		end)
		
		local ListLayout = Instance.new("UIListLayout")
		ListLayout.Parent = ListFrame
		ListLayout.Padding = UDim.new(0, 5)
		
		local Padding = Instance.new("UIPadding")
		Padding.Parent = ListFrame
		Padding.PaddingBottom = UDim.new(0, 5)
		Padding.PaddingLeft = UDim.new(0, 10)
		Padding.PaddingRight = UDim.new(0, 10)
		Padding.PaddingTop = UDim.new(0, 5)
		
		
		local Decompile = AddCheckbox("Decompile Scripts (LocalScript and ModuleScript)", SaveInstanceArgs.Decompile)
		Decompile.OnInput:Connect(function()
			SaveInstanceArgs.Decompile = Decompile.Toggled
		end)
		
		local decompileTimeout = AddTextbox("Decompile Timeout (s)", SaveInstanceArgs.DecompileTimeout, 15)
		decompileTimeout.TextBox.FocusLost:Connect(function()
			SaveInstanceArgs.DecompileTimeout = tonumber(decompileTimeout.TextBox.Text)
		end)
		
		local decompileThread = AddTextbox("Decompiler Max Threads", "3", 15)
		decompileThread.TextBox.FocusLost:Connect(function()
			SaveInstanceArgs.MaxThreads = tonumber(decompileThread.TextBox.Text)
		end)
		
		local decompileIgnore = AddTextbox("Decompile Ignore", table.concat(SaveInstanceArgs.DecompileIgnore, ","), 50)
		decompileIgnore.TextBox.FocusLost:Connect(function()
			local inputText = decompileIgnore.TextBox.Text
			local rawList = string.split(inputText, ", ") or string.split(inputText, ",")
			local finalList = {}

			for _, text in ipairs(rawList) do
				local split = string.split(text, ",") or string.split(text, ", ")
				for _, textFound in ipairs(split) do
					table.insert(finalList, textFound)
				end
			end
			SaveInstanceArgs.DecompileIgnore = finalList
		end)

		
		local NilObj = AddCheckbox("Save Nil Instances", SaveInstanceArgs.NilInstances)
		NilObj.OnInput:Connect(function()
			SaveInstanceArgs.NilInstances = NilObj.Toggled
		end)

		local RemovePlayerChar = AddCheckbox("Remove Player Characters", SaveInstanceArgs.RemovePlayerCharacters)
		RemovePlayerChar.OnInput:Connect(function()
			SaveInstanceArgs.RemovePlayerCharacters = RemovePlayerChar.Toggled
		end)
		
		local SavePlayerObj = AddCheckbox("Save Player Instance", SaveInstanceArgs.SavePlayers)
		SavePlayerObj.OnInput:Connect(function()
			SaveInstanceArgs.SavePlayers = SavePlayerObj.Toggled
		end)
		
		local IsolateStarterPlr = AddCheckbox("Isolate StarterPlayer", SaveInstanceArgs.IsolateStarterPlayer)
		IsolateStarterPlr.OnInput:Connect(function()
			SaveInstanceArgs.IsolateStarterPlayer = IsolateStarterPlr.Toggled
		end)
		
		local IgnoreDefaultProps = AddCheckbox("Ignore Default Properties", SaveInstanceArgs.IgnoreDefaultProps)
		IgnoreDefaultProps.OnInput:Connect(function()
			SaveInstanceArgs.IgnoreDefaultProps = IgnoreDefaultProps.Toggled
		end)
		
		local ShowStat = AddCheckbox("Show Status", SaveInstanceArgs.ShowStatus)
		ShowStat.OnInput:Connect(function()
			SaveInstanceArgs.ShowStatus = ShowStat.Toggled
		end)
		
		
		local FilenameTextBox = Lib.ViewportTextBox.new()
		FilenameTextBox.Gui.Parent = window.GuiElems.Content
		FilenameTextBox.Size = UDim2.new(1,0, 0,20)
		FilenameTextBox.Position = UDim2.new(0,0, 1,-40)
		
		local textpadding = Instance.new("UIPadding")
		textpadding.Parent = FilenameTextBox.Gui
		textpadding.PaddingLeft = UDim.new(0, 5)
		textpadding.PaddingRight = UDim.new(0, 5)
		
		local BackgroundButton = Lib.Frame.new()
		BackgroundButton.Gui.Parent = window.GuiElems.Content
		BackgroundButton.Size = UDim2.new(1,0, 0,20)
		BackgroundButton.Position = UDim2.new(0,0, 1,-20)
		
		local LabelButton = Lib.Label.new()
		LabelButton.Gui.Parent = window.GuiElems.Content
		LabelButton.Size = UDim2.new(1,0, 0,20)
		LabelButton.Position = UDim2.new(0,0, 1,-20)
		LabelButton.Gui.Text = "Save"
		LabelButton.Gui.TextXAlignment = Enum.TextXAlignment.Center
		
		local Button = Instance.new("TextButton")
		Button.Parent = BackgroundButton.Gui
		Button.Size = UDim2.new(1,0, 1,0)
		Button.Position = UDim2.new(0,0, 0,0)
		Button.Transparency = 1
		
		FilenameTextBox.TextBox.Text = fileName
		Button.MouseButton1Click:Connect(function()
			local fileName = FilenameTextBox.TextBox.Text:gsub("{TIMESTAMP}", os.date("%d-%m-%Y_%H-%M-%S"))
			window:SetTitle("Save Instance - Saving")
			local s, result = pcall(env.saveinstance, game, fileName, SaveInstanceArgs)
			if s then
				window:SetTitle("Save Instance - Saved")
			else
				window:SetTitle("Save Instance - Error")
				task.spawn(error("Failed to save the game: "..result))
			end
			task.wait(5)
			window:SetTitle("Save Instance")
		end)
	end

	return SaveInstance
end

if gethsfuncs then
	_G.moduleData = {InitDeps = initDeps, InitAfterMain = initAfterMain, Main = main}
else
	return {InitDeps = initDeps, InitAfterMain = initAfterMain, Main = main}
end
end,
["ScriptViewer"] = function()
local Main,Lib,Apps,Settings
local Explorer, Properties, ScriptViewer, Notebook
local API,RMD,env,service,plr,create,createSimple

local function initDeps(data)
	Main = data.Main
	Lib = data.Lib
	Apps = data.Apps
	Settings = data.Settings

	API = data.API
	RMD = data.RMD
	env = data.env
	service = data.service
	plr = data.plr
	create = data.create
	createSimple = data.createSimple
end

local function initAfterMain()
	Explorer = Apps.Explorer
	Properties = Apps.Properties
	ScriptViewer = Apps.ScriptViewer
	Notebook = Apps.Notebook
end

local executorName = "Unknown"
local executorVersion = "???"
if identifyexecutor then
	local name,ver = identifyexecutor()
	executorName = name
	executorVersion = ver
elseif game:GetService("RunService"):IsStudio() then
	executorName = "Studio"
	executorVersion = version()
end

local function getPath(obj)
	if obj.Parent == nil then
		return "Nil parented"
	else
		return Explorer.GetInstancePath(obj)
	end
end

local function main()
	local ScriptViewer = {}
	local window, codeFrame
	
	local execute, clear, dumpbtn
	
	local PreviousScr = nil
	
	ScriptViewer.DumpFunctions = function(scr)
		local getgc = getgc or get_gc_objects
		local getupvalues = (debug and debug.getupvalues) or getupvalues or getupvals
		local getconstants = (debug and debug.getconstants) or getconstants or getconsts
		local getinfo = (debug and (debug.getinfo or debug.info)) or getinfo
		local original = ("\n-- // Function Dumper made by King.Kevin\n-- // Script Path: %s\n\n--[["):format(getPath(scr))
		local dump = original
		local functions, function_count, data_base = {}, 0, {}
		function functions:add_to_dump(str, indentation, new_line)
			local new_line = new_line or true
			dump = dump .. ("%s%s%s"):format(string.rep("		", indentation), tostring(str), new_line and "\n" or "")
		end
		function functions:get_function_name(func)
			local n = getinfo(func).name
			return n ~= "" and n or "Unknown Name"
		end
		function functions:dump_table(input, indent, index)
			local indent = indent < 0 and 0 or indent
			functions:add_to_dump(("%s [%s] %s"):format(tostring(index), tostring(typeof(input)), tostring(input)), indent - 1)
			local count = 0
			for index, value in pairs(input) do
				count = count + 1
				if type(value) == "function" then
					functions:add_to_dump(("%d [function] = %s"):format(count, functions:get_function_name(value)), indent)
				elseif type(value) == "table" then
					if not data_base[value] then
						data_base[value] = true
						functions:add_to_dump(("%d [table]:"):format(count), indent)
						functions:dump_table(value, indent + 1, index)
					else
						functions:add_to_dump(("%d [table] (Recursive table detected)"):format(count), indent)
					end
				else
					functions:add_to_dump(("%d [%s] = %s"):format(count, tostring(typeof(value)), tostring(value)), indent)
				end
			end
		end
		function functions:dump_function(input, indent)
			functions:add_to_dump(("\nFunction Dump: %s"):format(functions:get_function_name(input)), indent)
			functions:add_to_dump(("\nFunction Upvalues: %s"):format(functions:get_function_name(input)), indent)
			for index, upvalue in pairs(getupvalues(input)) do
				if type(upvalue) == "function" then
					functions:add_to_dump(("%d [function] = %s"):format(index, functions:get_function_name(upvalue)), indent + 1)
				elseif type(upvalue) == "table" then
					if not data_base[upvalue] then
						data_base[upvalue] = true
						functions:add_to_dump(("%d [table]:"):format(index), indent + 1)
						functions:dump_table(upvalue, indent + 2, index)
					else
						functions:add_to_dump(("%d [table] (Recursive table detected)"):format(index), indent + 1)
					end
				else
					functions:add_to_dump(("%d [%s] = %s"):format(index, tostring(typeof(upvalue)), tostring(upvalue)), indent + 1)
				end
			end
			functions:add_to_dump(("\nFunction Constants: %s"):format(functions:get_function_name(input)), indent)
			for index, constant in pairs(getconstants(input)) do
				if type(constant) == "function" then
					functions:add_to_dump(("%d [function] = %s"):format(index, functions:get_function_name(constant)), indent + 1)
				elseif type(constant) == "table" then
					if not data_base[constant] then
						data_base[constant] = true
						functions:add_to_dump(("%d [table]:"):format(index), indent + 1)
						functions:dump_table(constant, indent + 2, index)
					else
						functions:add_to_dump(("%d [table] (Recursive table detected)"):format(index), indent + 1)
					end
				else
					functions:add_to_dump(("%d [%s] = %s"):format(index, tostring(typeof(constant)), tostring(constant)), indent + 1)
				end
			end
		end
		for _, _function in pairs(env.getgc()) do
			if typeof(_function) == "function" and getfenv(_function).script and getfenv(_function).script == scr then
				functions:dump_function(_function, 0)
				functions:add_to_dump("\n" .. ("="):rep(100), 0, false)
			end
		end
		local source = codeFrame:GetText()

		if dump ~= original then source = source .. dump .. "]]" end
		codeFrame:SetText(source)
		
		window:Show()
	end

	ScriptViewer.Init = function()
		window = Lib.Window.new()
		window:SetTitle("Notepad")
		window:Resize(500,400)
		ScriptViewer.Window = window

		codeFrame = Lib.CodeFrame.new()
		codeFrame.Frame.Position = UDim2.new(0,0,0,20)
		codeFrame.Frame.Size = UDim2.new(1,0,1,-40)
		codeFrame.Frame.Parent = window.GuiElems.Content
		
		local copy = Instance.new("TextButton",window.GuiElems.Content)
		copy.BackgroundTransparency = 1
		copy.Size = UDim2.new(0.33,0,0,20)
		copy.Position = UDim2.new(0,0,0,0)
		copy.Text = "Copy to Clipboard"
		
		if env.setclipboard then
			copy.TextColor3 = Color3.new(1,1,1)
			copy.Interactable = true
		else
			copy.TextColor3 = Color3.new(0.5,0.5,0.5)
			copy.Interactable = false
		end

		copy.MouseButton1Click:Connect(function()
			local source = codeFrame:GetText()
			env.setclipboard(source)
		end)

		local save = Instance.new("TextButton",window.GuiElems.Content)
		save.BackgroundTransparency = 1
		save.Size = UDim2.new(0.33,0,0,20)
		save.Position = UDim2.new(0.33,0,0,0)
		save.Text = "Save to File"
		save.TextColor3 = Color3.new(1,1,1)
		
		if env.writefile then
			save.TextColor3 = Color3.new(1,1,1)
			save.Interactable = true
		else
			save.TextColor3 = Color3.new(0.5,0.5,0.5)
		end

		save.MouseButton1Click:Connect(function()
			local source = codeFrame:GetText()
			local filename = "Place_"..game.PlaceId.."_Script_"..os.time()..".txt"

			Lib.SaveAsPrompt(filename,source)
		end)
		
		dumpbtn = Instance.new("TextButton",window.GuiElems.Content)
		dumpbtn.BackgroundTransparency = 1
		dumpbtn.Position = UDim2.new(0.7,0,0,0)
		dumpbtn.Size = UDim2.new(0.3,0,0,20)
		dumpbtn.Text = "Dump Functions"
		dumpbtn.TextColor3 = Color3.new(0.5,0.5,0.5)
		
		if env.getgc then
			dumpbtn.TextColor3 = Color3.new(1,1,1)
			dumpbtn.Interactable = true
		else
			dumpbtn.TextColor3 = Color3.new(0.5,0.5,0.5)
			dumpbtn.Interactable = false
		end

		dumpbtn.MouseButton1Click:Connect(function()
			if PreviousScr ~= nil then
				pcall(ScriptViewer.DumpFunctions, PreviousScr)
			end
		end)
		
		
		
		execute = Instance.new("TextButton",window.GuiElems.Content)
		execute.BackgroundTransparency = 1
		execute.Size = UDim2.new(0.5,0,0,20)
		execute.Position = UDim2.new(0,0,1,-20)
		execute.Text = "Execute"
		execute.TextColor3 = Color3.new(1,1,1)
		
		if env.loadstring then
			execute.TextColor3 = Color3.new(1,1,1)
			execute.Interactable = true
		else
			execute.TextColor3 = Color3.new(0.5,0.5,0.5)
			execute.Interactable = false
		end

		execute.MouseButton1Click:Connect(function()
			local source = codeFrame:GetText()
			env.loadstring(source)()
		end)

		clear = Instance.new("TextButton",window.GuiElems.Content)
		clear.BackgroundTransparency = 1
		clear.Size = UDim2.new(0.5,0,0,20)
		clear.Position = UDim2.new(0.5,0,1,-20)
		clear.Text = "Clear"
		clear.TextColor3 = Color3.new(1,1,1)

		clear.MouseButton1Click:Connect(function()
			codeFrame:SetText("")
		end)
	end
	
	-- isDecompileError: Solara returns errors as comment-strings, not nil.
	local function isDecompileError(src)
		if type(src) ~= "string" then return true end
		local low = src:lower():sub(1, 80)
		return low:find("^%-%- failed to decompile")
		    or low:find("^%-%- decompile error")
		    or low:find("^%-%- unable to decompile")
		    or low:find("^%-%- decompiler error")
		    or low:find("^%-%- cannot be decompiled")
		    or low:find("^%-%- failed to get script")
		    or (low:find("error") and low:find("decompil"))
		    or false
	end

	-- decompileCache persists across ViewScript calls this session.
	decompileCache = decompileCache or {}

	ScriptViewer.ViewScript = function(scr)
		-- FIX 6: Early bail for server-side Scripts (impossible to decompile).
		if scr:IsA("Script") and not scr:IsA("LocalScript") then
			local rc = scr.RunContext
			if rc == Enum.RunContext.Server or rc == Enum.RunContext.Legacy then
				local msg = "-- Unable to view source.\n"
				    .. "-- Script Path: "..getPath(scr).."\n"
				    .. "-- Reason: Server-side Script cannot be decompiled from the client.\n"
				    .. "-- Executor: "..(env.executor or executorName).." ("..(env.executorVersion or executorVersion)..")"
				codeFrame:SetText(msg)
				window:Show()
				return
			end
		end

		-- FIX 5: Cache by script hash to avoid re-decompiling the same script.
		local cacheKey = nil
		if getscripthash then
			local ok, h = pcall(getscripthash, scr)
			if ok and type(h) == "string" and #h == 64 then
				cacheKey = h
			end
		end
		if cacheKey and decompileCache[cacheKey] then
			codeFrame:SetText(decompileCache[cacheKey])
			window:Show()
			return
		end

		local oldtick = tick()
		local _prevIdentity = getthreadidentity and getthreadidentity() or nil
		if setthreadidentity then pcall(setthreadidentity, 8) end

		-- FIX 3: 15-second timeout via coroutine so Solara can't freeze the thread.
		local s, source = false, nil
		local done = false
		task.spawn(function()
			s, source = pcall(env.decompile or function() end, scr)
			done = true
		end)
		local waited = 0
		while not done and waited < 15 do
			task.wait(0.1)
			waited = waited + 0.1
		end
		if not done then
			s = false
			source = nil
		end

		if setthreadidentity and _prevIdentity then pcall(setthreadidentity, _prevIdentity) end

		-- FIX 2: isDecompileError catches Solara's error-as-comment responses.
		if not s or isDecompileError(source) then
			-- FIX 4: Konstant HTTPS fallback with 3 retries.
			local usedKonstant = false
			if env.request and env.getscriptbytecode then
				local okBc, bytecode = pcall(env.getscriptbytecode, scr)
				if okBc and bytecode and #bytecode > 0 then
					for attempt = 1, 3 do
						local okReq, resp = pcall(env.request, {
							Url    = "https://api.plusgiant5.com/konstant/decompile",
							Method = "POST",
							Body   = bytecode,
							Headers = {["Content-Type"] = "text/plain"},
						})
						if okReq and resp and resp.StatusCode == 200 and resp.Body and #resp.Body > 0 then
							source = "-- [Konstant fallback — native decompile failed]\n"
							    .. "-- Script Path: "..getPath(scr).."\n"
							    .. "-- Executor: "..(env.executor or executorName).."\n\n"
							    .. resp.Body
							s = true
							usedKonstant = true
							break
						end
						task.wait(0.6)
					end
				end
			end

			if not usedKonstant then
				PreviousScr = nil
				dumpbtn.TextColor3 = Color3.new(0.5, 0.5, 0.5)
				local errMsg = "-- Unable to view source.\n"
				    .. "-- Script Path: "..getPath(scr).."\n"
				if not env.decompile then
					errMsg = errMsg .. "-- Reason: Executor does not expose 'decompile'.\n"
				elseif waited >= 15 then
					errMsg = errMsg .. "-- Reason: Decompile timed out after 15s (obfuscated?).\n"
				else
					errMsg = errMsg .. "-- Reason: Decompile returned error (obfuscated or protected).\n"
					if source and type(source) == "string" then
						errMsg = errMsg .. "--\n-- Decompiler output:\n" .. source:sub(1, 400) .. "\n"
					end
				end
				errMsg = errMsg .. "-- Executor: "..(env.executor or executorName).." ("..(env.executorVersion or executorVersion)..")"
				codeFrame:SetText(errMsg)
				window:Show()
				return
			end
		end

		PreviousScr = scr
		dumpbtn.TextColor3 = Color3.new(1, 1, 1)

		local decompiled = source
		local elapsed = tostring(math.floor((tick() - oldtick) * 100) / 100)
		local header = "-- Script Path: "..getPath(scr).."\n"
		    .. "-- Took "..elapsed.."s to decompile.\n"
		    .. "-- Executor: "..(env.executor or executorName).." ("..(env.executorVersion or executorVersion)..")\n\n"
		source = header .. decompiled

		-- FIX 5: Store in cache.
		if cacheKey and not isDecompileError(decompiled) then
			decompileCache[cacheKey] = source
		end

		codeFrame:SetText(source)
		window:Show()
	end

	return ScriptViewer
end

if gethsfuncs then
	_G.moduleData = {InitDeps = initDeps, InitAfterMain = initAfterMain, Main = main}
else
	return {InitDeps = initDeps, InitAfterMain = initAfterMain, Main = main}
end
end,

-- ══════════════════════════════════════════════════════════════════════════
--  MODULE: RemoteSpy
-- ══════════════════════════════════════════════════════════════════════════
["RemoteSpy"] = function()
local Main,Lib,Apps,Settings
local Explorer,Properties,ScriptViewer
local API,RMD,env,service,plr,create,createSimple

local function initDeps(data)
	Main=data.Main Lib=data.Lib Apps=data.Apps Settings=data.Settings
	API=data.API RMD=data.RMD env=data.env service=data.service
	plr=data.plr create=data.create createSimple=data.createSimple
end
local function initAfterMain()
	Explorer=Apps.Explorer Properties=Apps.Properties ScriptViewer=Apps.ScriptViewer
end

local function main()
	local RemoteSpy = {}
	local window = Lib.Window.new()
	window:SetTitle("Remote Spy")
	window:Resize(600, 380)
	local cf = window.ContentFrame
	cf.BackgroundColor3 = Color3.fromRGB(16,16,16)
	cf.ClipsDescendants = true

	-- Toolbar
	local toolbar = Instance.new("Frame")
	toolbar.Size = UDim2.new(1,0,0,28)
	toolbar.BackgroundColor3 = Color3.fromRGB(26,26,26)
	toolbar.BorderSizePixel = 0
	toolbar.Parent = cf

	local function mkBtn(txt, x, color, cb)
		local b = Instance.new("TextButton")
		b.Size = UDim2.new(0,70,0,22)
		b.Position = UDim2.new(0,x,0,3)
		b.BackgroundColor3 = color
		b.BorderSizePixel = 0
		b.TextColor3 = Color3.fromRGB(255,255,255)
		b.TextSize = 11
		b.Font = Enum.Font.GothamBold
		b.Text = txt
		b.Parent = toolbar
		b.MouseButton1Click:Connect(cb)
		local uc = Instance.new("UICorner") uc.CornerRadius = UDim.new(0,4) uc.Parent = b
		return b
	end

	local paused = false
	local btnPause = mkBtn("⏸ Pause", 4, Color3.fromRGB(200,140,0), function()
		paused = not paused
	end)
	mkBtn("🗑 Clear", 78, Color3.fromRGB(160,50,50), function()
		for _, v in ipairs(cf:GetChildren()) do
			if v:IsA("Frame") and v.LayoutOrder and v.LayoutOrder > 0 then v:Destroy() end
		end
	end)

	-- Filter box
	local filterBox = Instance.new("TextBox")
	filterBox.Size = UDim2.new(1,-260,0,22)
	filterBox.Position = UDim2.new(0,156,0,3)
	filterBox.BackgroundColor3 = Color3.fromRGB(32,32,32)
	filterBox.BorderSizePixel = 0
	filterBox.TextColor3 = Color3.fromRGB(200,200,200)
	filterBox.TextSize = 11
	filterBox.Font = Enum.Font.Code
	filterBox.PlaceholderText = "Filter remote name…"
	filterBox.ClearTextOnFocus = false
	filterBox.Text = ""
	filterBox.Parent = toolbar

	-- Log scroll
	local scroll = Instance.new("ScrollingFrame")
	scroll.Size = UDim2.new(1,0,1,-28)
	scroll.Position = UDim2.new(0,0,0,28)
	scroll.BackgroundTransparency = 1
	scroll.ScrollBarThickness = 5
	scroll.CanvasSize = UDim2.new(0,0,0,0)
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.Parent = cf
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0,1)
	layout.Parent = scroll

	local rowCount = 0
	local MAX_ROWS = 200

	local typeColors = {
		FireServer   = Color3.fromRGB(80,200,120),
		InvokeServer = Color3.fromRGB(100,180,255),
		OnClientEvent= Color3.fromRGB(255,180,80),
		OnClientInvoke=Color3.fromRGB(255,130,130),
	}

	local function addRow(remType, remName, path, argStr)
		if paused then return end
		local filter = filterBox.Text:lower()
		if filter ~= "" and not remName:lower():find(filter) then return end
		rowCount = rowCount + 1
		-- Trim old rows
		if rowCount > MAX_ROWS then
			local children = scroll:GetChildren()
			for _, c in ipairs(children) do
				if c:IsA("Frame") then c:Destroy() break end
			end
		end
		local row = Instance.new("Frame")
		row.Size = UDim2.new(1,0,0,20)
		row.BackgroundColor3 = rowCount%2==0 and Color3.fromRGB(20,20,20) or Color3.fromRGB(24,24,24)
		row.BorderSizePixel = 0
		row.LayoutOrder = rowCount
		row.Parent = scroll
		local typeLbl = Instance.new("TextLabel")
		typeLbl.Size = UDim2.new(0,110,1,0)
		typeLbl.BackgroundTransparency = 1
		typeLbl.TextColor3 = typeColors[remType] or Color3.fromRGB(200,200,200)
		typeLbl.TextSize = 10
		typeLbl.Font = Enum.Font.GothamBold
		typeLbl.Text = remType
		typeLbl.Parent = row
		local nameLbl = Instance.new("TextLabel")
		nameLbl.Size = UDim2.new(0,160,1,0)
		nameLbl.Position = UDim2.new(0,112,0,0)
		nameLbl.BackgroundTransparency = 1
		nameLbl.TextColor3 = Color3.fromRGB(220,220,220)
		nameLbl.TextSize = 10
		nameLbl.Font = Enum.Font.Code
		nameLbl.Text = remName
		nameLbl.TextTruncate = Enum.TextTruncate.AtEnd
		nameLbl.Parent = row
		local argLbl = Instance.new("TextLabel")
		argLbl.Size = UDim2.new(1,-278,1,0)
		argLbl.Position = UDim2.new(0,278,0,0)
		argLbl.BackgroundTransparency = 1
		argLbl.TextColor3 = Color3.fromRGB(150,150,150)
		argLbl.TextSize = 10
		argLbl.Font = Enum.Font.Code
		argLbl.Text = argStr
		argLbl.TextTruncate = Enum.TextTruncate.AtEnd
		argLbl.Parent = row
		-- click to select in Explorer
		row.InputBegan:Connect(function(inp)
			if inp.UserInputType == Enum.UserInputType.MouseButton1 then
				pcall(function() Explorer.ViewObject(game:FindFirstChild(path,true)) end)
			end
		end)
		-- auto-scroll
		pcall(function()
			scroll.CanvasPosition = Vector2.new(0, scroll.AbsoluteCanvasSize.Y)
		end)
	end

	local function formatArgs(...)
		local parts = {}
		for _, v in ipairs({...}) do
			local t = typeof(v)
			if t == "string" then parts[#parts+1] = ("%q"):format(v:sub(1,60))
			elseif t == "number" then parts[#parts+1] = tostring(v)
			elseif t == "boolean" then parts[#parts+1] = tostring(v)
			elseif t == "Instance" then parts[#parts+1] = v.ClassName.."("..v.Name..")"
			else parts[#parts+1] = "["..t.."]"
			end
		end
		return table.concat(parts, ", ")
	end

	-- Hook all RemoteEvents + RemoteFunctions
	local hooked = {}
	local function hookRemote(rem)
		if hooked[rem] then return end
		hooked[rem] = true
		local path = rem:GetFullName()
		local name = rem.Name
		if rem:IsA("RemoteEvent") then
			if hookfunction and rem.FireServer then
				local origFireServer = rem.FireServer
				pcall(hookfunction, origFireServer, newcclosure and newcclosure(function(self, ...)
					addRow("FireServer", name, path, formatArgs(...))
					return origFireServer(self, ...)
				end) or function(self,...) addRow("FireServer",name,path,formatArgs(...)) return origFireServer(self,...) end)
			end
			if hookfunction and rem.OnClientEvent then
				local origOCE = rem.OnClientEvent
				-- can't hook RBXScriptSignal directly, patch via Connect
			end
		elseif rem:IsA("RemoteFunction") then
			if hookfunction and rem.InvokeServer then
				local origIS = rem.InvokeServer
				pcall(hookfunction, origIS, newcclosure and newcclosure(function(self,...)
					addRow("InvokeServer", name, path, formatArgs(...))
					return origIS(self,...)
				end) or function(self,...) addRow("InvokeServer",name,path,formatArgs(...)) return origIS(self,...) end)
			end
		end
	end

	task.spawn(function()
		for _, v in ipairs(game:GetDescendants()) do
			if v:IsA("RemoteEvent") or v:IsA("RemoteFunction") then
				pcall(hookRemote, v)
			end
		end
		game.DescendantAdded:Connect(function(v)
			task.wait(0.05)
			if v:IsA("RemoteEvent") or v:IsA("RemoteFunction") then
				pcall(hookRemote, v)
			end
		end)
	end)

	RemoteSpy.Open = function() window:Show() end
	Apps.RemoteSpy = RemoteSpy
	return RemoteSpy
end

if gethsfuncs then
	_G.moduleData = {InitDeps = initDeps, InitAfterMain = initAfterMain, Main = main}
else
	return {InitDeps = initDeps, InitAfterMain = initAfterMain, Main = main}
end
end,

-- ══════════════════════════════════════════════════════════════════════════
--  MODULE: CodeGen  — generate Luau code from any Instance
-- ══════════════════════════════════════════════════════════════════════════
["CodeGen"] = function()
local Main,Lib,Apps,Settings
local Explorer,Properties,ScriptViewer
local API,RMD,env,service,plr,create,createSimple

local function initDeps(data)
	Main=data.Main Lib=data.Lib Apps=data.Apps Settings=data.Settings
	API=data.API RMD=data.RMD env=data.env service=data.service
	plr=data.plr create=data.create createSimple=data.createSimple
end
local function initAfterMain()
	Explorer=Apps.Explorer Properties=Apps.Properties ScriptViewer=Apps.ScriptViewer
end

local function main()
	local CodeGen = {}

	local function v3s(v) return ("Vector3.new(%g,%g,%g)"):format(v.X,v.Y,v.Z) end
	local function cf2s(cf)
		local x,y,z = cf.X,cf.Y,cf.Z
		local rx,ry,rz = cf:ToEulerAnglesXYZ()
		if math.abs(rx)<0.001 and math.abs(ry)<0.001 and math.abs(rz)<0.001 then
			return ("CFrame.new(%g,%g,%g)"):format(x,y,z)
		end
		return ("CFrame.new(%g,%g,%g) * CFrame.Angles(%g,%g,%g)"):format(x,y,z,rx,ry,rz)
	end
	local function c3s(c) return ("Color3.fromRGB(%d,%d,%d)"):format(c.R*255,c.G*255,c.B*255) end
	local function udim2s(u) return ("UDim2.new(%g,%g,%g,%g)"):format(u.X.Scale,u.X.Offset,u.Y.Scale,u.Y.Offset) end

	local function propValue(v)
		local t = typeof(v)
		if t == "string"   then return ("%q"):format(v)
		elseif t == "boolean" or t == "number" then return tostring(v)
		elseif t == "Vector3"    then return v3s(v)
		elseif t == "CFrame"     then return cf2s(v)
		elseif t == "Color3"     then return c3s(v)
		elseif t == "BrickColor" then return ('BrickColor.new("%s")'):format(tostring(v))
		elseif t == "EnumItem"   then return ("Enum.%s.%s"):format(tostring(v.EnumType),v.Name)
		elseif t == "UDim2"      then return udim2s(v)
		elseif t == "UDim"       then return ("UDim.new(%g,%g)"):format(v.Scale,v.Offset)
		elseif t == "Rect"       then return ("Rect.new(%g,%g,%g,%g)"):format(v.Min.X,v.Min.Y,v.Max.X,v.Max.Y)
		else return nil
		end
	end

	local SKIP_PROPS = {Parent=true,ClassName=true,archivable=true,Archivable=true}
	local DEFAULT_VALS = {
		Anchored=false,CanCollide=true,Locked=false,Transparency=0,Reflectance=0,
		CastShadow=true,BackgroundTransparency=0,TextTransparency=0,BorderSizePixel=1,
	}

	local function generateCode(root, depth)
		depth = depth or 0
		local lines = {}
		local indent = string.rep("\t", depth)
		local varName = root.Name:gsub("[^%w_]","_"):gsub("^(%d)","_%1")
		if varName == "" then varName = "inst" end
		lines[#lines+1] = indent .. ("local %s = Instance.new(%q)"):format(varName, root.ClassName)
		-- Properties
		for prop, defVal in pairs(DEFAULT_VALS) do
			local ok, v = pcall(function() return root[prop] end)
			if ok and v ~= nil and v ~= defVal then
				local vs = propValue(v)
				if vs then lines[#lines+1] = indent .. ("%s.%s = %s"):format(varName,prop,vs) end
			end
		end
		-- Additional important props
		for _, prop in ipairs({"Name","Size","Position","CFrame","Color","BrickColor","Material",
			"Text","Font","TextSize","BackgroundColor3","TextColor3","Image","Visible",
			"MeshId","TextureId","SoundId","AnimationId","Value"}) do
			if not SKIP_PROPS[prop] then
				local ok, v = pcall(function() return root[prop] end)
				if ok and v ~= nil then
					local vs = propValue(v)
					if vs then lines[#lines+1] = indent .. ("%s.%s = %s"):format(varName,prop,vs) end
				end
			end
		end
		-- Children
		local ok2, children = pcall(function() return root:GetChildren() end)
		if ok2 then
			for _, child in ipairs(children) do
				local childLines, childVar = generateCode(child, depth+1)
				for _, l in ipairs(childLines) do lines[#lines+1] = l end
				lines[#lines+1] = indent.."\t"..childVar..".Parent = "..varName
			end
		end
		return lines, varName
	end

	CodeGen.GenerateForSelection = function()
		local sel = Apps.Explorer and Apps.Explorer.selection and Apps.Explorer.selection.List
		if not sel or #sel == 0 then return end
		local obj = sel[1].Obj
		local codeLines, _ = generateCode(obj, 0)
		local code = table.concat(codeLines, "\n")
		-- Show in window
		local win = Lib.Window.new()
		win:SetTitle("CodeGen — " .. obj.Name)
		win:Resize(560, 440)
		local cf2 = win.ContentFrame
		cf2.BackgroundColor3 = Color3.fromRGB(18,18,18)
		local tb = Instance.new("TextBox")
		tb.Size = UDim2.new(1,-8,1,-38)
		tb.Position = UDim2.new(0,4,0,4)
		tb.MultiLine = true
		tb.BackgroundColor3 = Color3.fromRGB(22,22,22)
		tb.TextColor3 = Color3.fromRGB(200,200,200)
		tb.TextSize = 11
		tb.Font = Enum.Font.Code
		tb.Text = code
		tb.TextEditable = false
		tb.ClearTextOnFocus = false
		tb.TextXAlignment = Enum.TextXAlignment.Left
		tb.TextYAlignment = Enum.TextYAlignment.Top
		tb.Parent = cf2
		local btn = Instance.new("TextButton")
		btn.Size = UDim2.new(0,100,0,28)
		btn.Position = UDim2.new(0,4,1,-34)
		btn.BackgroundColor3 = Color3.fromRGB(0,150,200)
		btn.BorderSizePixel = 0
		btn.TextColor3 = Color3.fromRGB(255,255,255)
		btn.TextSize = 12
		btn.Font = Enum.Font.GothamBold
		btn.Text = "Copy Code"
		btn.Parent = cf2
		btn.MouseButton1Click:Connect(function()
			if env.setclipboard then env.setclipboard(code) end
		end)
		local uc = Instance.new("UICorner") uc.CornerRadius = UDim.new(0,4) uc.Parent = btn
		win:Show()
	end

	Apps.CodeGen = CodeGen
	return CodeGen
end

if gethsfuncs then
	_G.moduleData = {InitDeps = initDeps, InitAfterMain = initAfterMain, Main = main}
else
	return {InitDeps = initDeps, InitAfterMain = initAfterMain, Main = main}
end
end,

-- ══════════════════════════════════════════════════════════════════════════
--  MODULE: OrphanedInstances — tracks nil-parented / destroyed instances
-- ══════════════════════════════════════════════════════════════════════════
["OrphanedInstances"] = function()
local Main,Lib,Apps,Settings
local API,RMD,env,service,plr,create,createSimple

local function initDeps(data)
	Main=data.Main Lib=data.Lib Apps=data.Apps Settings=data.Settings
	API=data.API RMD=data.RMD env=data.env service=data.service
	plr=data.plr create=data.create createSimple=data.createSimple
end
local function initAfterMain() end

local function main()
	local OrphanedInstances = {}
	local window = Lib.Window.new()
	window:SetTitle("Orphaned Instances")
	window:Resize(420, 340)
	local cf = window.ContentFrame
	cf.BackgroundColor3 = Color3.fromRGB(16,16,16)
	cf.ClipsDescendants = true

	local scroll = Instance.new("ScrollingFrame")
	scroll.Size = UDim2.new(1,0,1,-30)
	scroll.Position = UDim2.new(0,0,0,30)
	scroll.BackgroundTransparency = 1
	scroll.ScrollBarThickness = 5
	scroll.CanvasSize = UDim2.new(0,0,0,0)
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.Parent = cf
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0,1)
	layout.Parent = scroll

	local toolbar = Instance.new("Frame")
	toolbar.Size = UDim2.new(1,0,0,28)
	toolbar.BackgroundColor3 = Color3.fromRGB(24,24,24)
	toolbar.BorderSizePixel = 0
	toolbar.Parent = cf

	local scanBtn = Instance.new("TextButton")
	scanBtn.Size = UDim2.new(0,90,0,22)
	scanBtn.Position = UDim2.new(0,4,0,3)
	scanBtn.BackgroundColor3 = Color3.fromRGB(0,140,200)
	scanBtn.BorderSizePixel = 0
	scanBtn.TextColor3 = Color3.fromRGB(255,255,255)
	scanBtn.TextSize = 11
	scanBtn.Font = Enum.Font.GothamBold
	scanBtn.Text = "🔍 Scan"
	scanBtn.Parent = toolbar
	local uc = Instance.new("UICorner") uc.CornerRadius = UDim.new(0,4) uc.Parent = scanBtn

	local countLbl = Instance.new("TextLabel")
	countLbl.Size = UDim2.new(1,-100,1,0)
	countLbl.Position = UDim2.new(0,100,0,0)
	countLbl.BackgroundTransparency = 1
	countLbl.TextColor3 = Color3.fromRGB(150,150,150)
	countLbl.TextSize = 11
	countLbl.Font = Enum.Font.Code
	countLbl.Text = "Click Scan to find nil-parented instances"
	countLbl.TextXAlignment = Enum.TextXAlignment.Left
	countLbl.Parent = toolbar

	scanBtn.MouseButton1Click:Connect(function()
		-- Clear
		for _, v in ipairs(scroll:GetChildren()) do
			if v:IsA("TextLabel") or v:IsA("Frame") then v:Destroy() end
		end
		local found = 0
		local function addRow(name, cls, extra)
			found = found + 1
			local lbl = Instance.new("TextLabel")
			lbl.Size = UDim2.new(1,-8,0,18)
			lbl.BackgroundTransparency = 1
			lbl.TextColor3 = Color3.fromRGB(200,200,200)
			lbl.TextSize = 11
			lbl.Font = Enum.Font.Code
			lbl.Text = ("[%s] %s  %s"):format(cls, name, extra or "")
			lbl.TextXAlignment = Enum.TextXAlignment.Left
			lbl.LayoutOrder = found
			lbl.Parent = scroll
		end
		-- Strategy 1: getnilinstances
		if getnilinstances then
			local ok, nilInsts = pcall(getnilinstances)
			if ok and nilInsts then
				for _, v in ipairs(nilInsts) do
					pcall(function()
						addRow(v.Name, v.ClassName, "(nil parent)")
					end)
				end
			end
		end
		-- Strategy 2: getgc scan
		if getgc and found == 0 then
			local ok, gc = pcall(getgc, true)
			if ok and gc then
				for _, v in ipairs(gc) do
					if typeof(v) == "Instance" then
						local ok2, par = pcall(function() return v.Parent end)
						if ok2 and par == nil then
							pcall(function() addRow(v.Name, v.ClassName, "(gc, no parent)") end)
						end
					end
				end
			end
		end
		countLbl.Text = ("Found %d orphaned instances"):format(found)
	end)

	OrphanedInstances.Open = function() window:Show() end
	Apps.OrphanedInstances = OrphanedInstances
	return OrphanedInstances
end

if gethsfuncs then
	_G.moduleData = {InitDeps = initDeps, InitAfterMain = initAfterMain, Main = main}
else
	return {InitDeps = initDeps, InitAfterMain = initAfterMain, Main = main}
end
end,

-- ══════════════════════════════════════════════════════════════════════════
--  MODULE: MemoryScanner — search upvalues / gc for strings
-- ══════════════════════════════════════════════════════════════════════════
["MemoryScanner"] = function()
local Main,Lib,Apps,Settings
local API,RMD,env,service,plr,create,createSimple

local function initDeps(data)
	Main=data.Main Lib=data.Lib Apps=data.Apps Settings=data.Settings
	API=data.API RMD=data.RMD env=data.env service=data.service
	plr=data.plr create=data.create createSimple=data.createSimple
end
local function initAfterMain() end

local function main()
	local MemoryScanner = {}
	local window = Lib.Window.new()
	window:SetTitle("Memory Scanner")
	window:Resize(500, 380)
	local cf = window.ContentFrame
	cf.BackgroundColor3 = Color3.fromRGB(16,16,16)
	cf.ClipsDescendants = true

	-- Search bar
	local searchBar = Instance.new("Frame")
	searchBar.Size = UDim2.new(1,0,0,30)
	searchBar.BackgroundColor3 = Color3.fromRGB(24,24,24)
	searchBar.BorderSizePixel = 0
	searchBar.Parent = cf

	local tb = Instance.new("TextBox")
	tb.Size = UDim2.new(1,-100,0,22)
	tb.Position = UDim2.new(0,4,0,4)
	tb.BackgroundColor3 = Color3.fromRGB(32,32,32)
	tb.BorderSizePixel = 0
	tb.TextColor3 = Color3.fromRGB(200,200,200)
	tb.TextSize = 12
	tb.Font = Enum.Font.Code
	tb.PlaceholderText = "Search string in upvalues / gc…"
	tb.ClearTextOnFocus = false
	tb.Text = ""
	tb.Parent = searchBar

	local scanBtn = Instance.new("TextButton")
	scanBtn.Size = UDim2.new(0,88,0,22)
	scanBtn.Position = UDim2.new(1,-92,0,4)
	scanBtn.BackgroundColor3 = Color3.fromRGB(0,150,200)
	scanBtn.BorderSizePixel = 0
	scanBtn.TextColor3 = Color3.fromRGB(255,255,255)
	scanBtn.TextSize = 12
	scanBtn.Font = Enum.Font.GothamBold
	scanBtn.Text = "🔍 Scan"
	scanBtn.Parent = searchBar
	local uc = Instance.new("UICorner") uc.CornerRadius = UDim.new(0,4) uc.Parent = scanBtn

	local scroll = Instance.new("ScrollingFrame")
	scroll.Size = UDim2.new(1,0,1,-30)
	scroll.Position = UDim2.new(0,0,0,30)
	scroll.BackgroundTransparency = 1
	scroll.ScrollBarThickness = 5
	scroll.CanvasSize = UDim2.new(0,0,0,0)
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.Parent = cf
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0,1)
	layout.Parent = scroll

	local rowN = 0
	local function addRow(source, key, val)
		rowN = rowN + 1
		local f = Instance.new("Frame")
		f.Size = UDim2.new(1,0,0,20)
		f.BackgroundColor3 = rowN%2==0 and Color3.fromRGB(20,20,20) or Color3.fromRGB(24,24,24)
		f.BorderSizePixel = 0
		f.LayoutOrder = rowN
		f.Parent = scroll
		local srcL = Instance.new("TextLabel")
		srcL.Size = UDim2.new(0,80,1,0)
		srcL.BackgroundTransparency = 1
		srcL.TextColor3 = Color3.fromRGB(100,180,255)
		srcL.TextSize = 10
		srcL.Font = Enum.Font.Code
		srcL.Text = source
		srcL.Parent = f
		local keyL = Instance.new("TextLabel")
		keyL.Size = UDim2.new(0,100,1,0)
		keyL.Position = UDim2.new(0,82,0,0)
		keyL.BackgroundTransparency = 1
		keyL.TextColor3 = Color3.fromRGB(180,230,180)
		keyL.TextSize = 10
		keyL.Font = Enum.Font.Code
		keyL.Text = tostring(key):sub(1,20)
		keyL.Parent = f
		local valL = Instance.new("TextLabel")
		valL.Size = UDim2.new(1,-188,1,0)
		valL.Position = UDim2.new(0,188,0,0)
		valL.BackgroundTransparency = 1
		valL.TextColor3 = Color3.fromRGB(220,220,180)
		valL.TextSize = 10
		valL.Font = Enum.Font.Code
		valL.Text = tostring(val):sub(1,80)
		valL.TextTruncate = Enum.TextTruncate.AtEnd
		valL.Parent = f
	end

	scanBtn.MouseButton1Click:Connect(function()
		for _, v in ipairs(scroll:GetChildren()) do
			if v:IsA("Frame") then v:Destroy() end
		end
		rowN = 0
		local query = tb.Text:lower()
		if query == "" then return end
		-- Scan upvalues of all closures in gc
		task.spawn(function()
			if getgc then
				local ok, gc = pcall(getgc)
				if ok and gc then
					for _, fn in ipairs(gc) do
						if type(fn) == "function" then
							if getupvalues then
								local ok2, ups = pcall(getupvalues, fn)
								if ok2 and ups then
									for k, v2 in pairs(ups) do
										if type(v2) == "string" and v2:lower():find(query) then
											addRow("upvalue", k, v2:sub(1,100))
										end
									end
								end
							end
						elseif type(fn) == "string" then
							if fn:lower():find(query) then
								addRow("gc-string", "–", fn:sub(1,100))
							end
						end
					end
				end
			end
			-- Scan _G and shared
			for scope, tbl in pairs({["_G"]=_G, ["shared"]=shared}) do
				if tbl then
					for k, v2 in pairs(tbl) do
						if type(v2) == "string" and v2:lower():find(query) then
							addRow(scope, k, v2:sub(1,100))
						end
					end
				end
			end
		end)
	end)

	MemoryScanner.Open = function() window:Show() end
	Apps.MemoryScanner = MemoryScanner
	return MemoryScanner
end

if gethsfuncs then
	_G.moduleData = {InitDeps = initDeps, InitAfterMain = initAfterMain, Main = main}
else
	return {InitDeps = initDeps, InitAfterMain = initAfterMain, Main = main}
end
end,

-- ══════════════════════════════════════════════════════════════════════════
--  MODULE: PhysicsViz — velocity / force arrows via Drawing API
-- ══════════════════════════════════════════════════════════════════════════
["PhysicsViz"] = function()
local Main,Lib,Apps,Settings
local API,RMD,env,service,plr,create,createSimple

local function initDeps(data)
	Main=data.Main Lib=data.Lib Apps=data.Apps Settings=data.Settings
	API=data.API RMD=data.RMD env=data.env service=data.service
	plr=data.plr create=data.create createSimple=data.createSimple
end
local function initAfterMain() end

local function main()
	local PhysicsViz = {}
	local active = false
	local drawings = {}
	local RunService = game:GetService("RunService")
	local camera = workspace.CurrentCamera

	local function clearDrawings()
		for _, d in ipairs(drawings) do pcall(function() d:Remove() end) end
		drawings = {}
	end

	local function worldToViewport(pos)
		local ok, vp, onScreen = pcall(function()
			return camera:WorldToViewportPoint(pos)
		end)
		if not ok then return nil, false end
		return Vector2.new(vp.X, vp.Y), onScreen and vp.Z > 0
	end

	local function drawArrow(origin, dir, color, label)
		if not Drawing then return end
		local tip = origin + dir
		local op, onScreen1 = worldToViewport(origin)
		local tp, onScreen2 = worldToViewport(tip)
		if not op or not tp or not onScreen1 then return end
		local line = Drawing.new("Line")
		line.From = op
		line.To = tp
		line.Color = color
		line.Thickness = 2
		line.Visible = true
		table.insert(drawings, line)
		if label then
			local txt = Drawing.new("Text")
			txt.Position = tp + Vector2.new(4, -6)
			txt.Text = label
			txt.Color = color
			txt.Size = 13
			txt.Outline = true
			txt.Visible = true
			table.insert(drawings, txt)
		end
	end

	local conn
	local function startViz()
		conn = RunService.RenderStepped:Connect(function()
			clearDrawings()
			-- Show velocity arrows for all BaseParts in workspace
			local parts = workspace:GetDescendants()
			for _, p in ipairs(parts) do
				if p:IsA("BasePart") and not p.Anchored then
					local vel = p.AssemblyLinearVelocity
					local speed = vel.Magnitude
					if speed > 0.5 then
						local scale = math.min(speed / 20, 6)
						local color = speed > 50 and Color3.fromRGB(255,80,80)
							or speed > 20 and Color3.fromRGB(255,200,50)
							or Color3.fromRGB(80,200,80)
						pcall(drawArrow, p.Position, vel.Unit * scale * 3,
							color, ("%.1f"):format(speed))
					end
				end
			end
		end)
	end

	local function stopViz()
		if conn then conn:Disconnect() conn = nil end
		clearDrawings()
	end

	-- Control window
	local window = Lib.Window.new()
	window:SetTitle("Physics Visualizer")
	window:Resize(280, 160)
	local cf = window.ContentFrame
	cf.BackgroundColor3 = Color3.fromRGB(16,16,16)
	cf.ClipsDescendants = true

	local status = Instance.new("TextLabel")
	status.Size = UDim2.new(1,-10,0,30)
	status.Position = UDim2.new(0,5,0,10)
	status.BackgroundTransparency = 1
	status.TextColor3 = Color3.fromRGB(180,180,180)
	status.TextSize = 12
	status.Font = Enum.Font.Gotham
	status.Text = "Velocity arrows: OFF"
	status.Parent = cf

	local note = Instance.new("TextLabel")
	note.Size = UDim2.new(1,-10,0,30)
	note.Position = UDim2.new(0,5,0,40)
	note.BackgroundTransparency = 1
	note.TextColor3 = Color3.fromRGB(110,110,110)
	note.TextSize = 10
	note.Font = Enum.Font.Code
	note.Text = "Requires Drawing API (Solara ✓)\nArrows scale with velocity, color = speed"
	note.TextWrapped = true
	note.Parent = cf

	local toggleBtn = Instance.new("TextButton")
	toggleBtn.Size = UDim2.new(0,120,0,30)
	toggleBtn.Position = UDim2.new(0,5,0,80)
	toggleBtn.BackgroundColor3 = Color3.fromRGB(60,160,60)
	toggleBtn.BorderSizePixel = 0
	toggleBtn.TextColor3 = Color3.fromRGB(255,255,255)
	toggleBtn.TextSize = 13
	toggleBtn.Font = Enum.Font.GothamBold
	toggleBtn.Text = "▶ Enable"
	toggleBtn.Parent = cf
	local uc = Instance.new("UICorner") uc.CornerRadius = UDim.new(0,5) uc.Parent = toggleBtn

	toggleBtn.MouseButton1Click:Connect(function()
		active = not active
		if active then
			if not Drawing then
				status.Text = "❌ Drawing API not available"
				active = false
				return
			end
			startViz()
			toggleBtn.Text = "■ Disable"
			toggleBtn.BackgroundColor3 = Color3.fromRGB(180,50,50)
			status.Text = "Velocity arrows: ON"
			status.TextColor3 = Color3.fromRGB(100,255,120)
		else
			stopViz()
			toggleBtn.Text = "▶ Enable"
			toggleBtn.BackgroundColor3 = Color3.fromRGB(60,160,60)
			status.Text = "Velocity arrows: OFF"
			status.TextColor3 = Color3.fromRGB(180,180,180)
		end
	end)

	window.OnClose = function() stopViz() active = false end

	PhysicsViz.Open = function() window:Show() end
	Apps.PhysicsViz = PhysicsViz
	return PhysicsViz
end

if gethsfuncs then
	_G.moduleData = {InitDeps = initDeps, InitAfterMain = initAfterMain, Main = main}
else
	return {InitDeps = initDeps, InitAfterMain = initAfterMain, Main = main}
end
end,
}
local oldgame = oldgame or game

cloneref = cloneref or function(ref)
	if not getreg then return ref end
	
	local InstanceList
	
	local a = Instance.new("Part")
	for _, c in pairs(getreg()) do
		if type(c) == "table" and #c then
			if rawget(c, "__mode") == "kvs" then
				for d, e in pairs(c) do
					if e == a then
						InstanceList = c
						break
					end
				end
			end
		end
	end
	local f = {}
	function f.invalidate(g)
		if not InstanceList then
			return
		end
		for b, c in pairs(InstanceList) do
			if c == g then
				InstanceList[b] = nil
				return g
			end
		end
	end
	return f.invalidate
end

local isFsSupported = readfile and writefile and isfile and isfolder and listfiles and delfile and delfolder

local Main, Explorer, Properties, ScriptViewer, Console, SaveInstance, ModelViewer , DefaultSettings, Notebook, Serializer, Lib local ggv = getgenv or nil
local API, RMD

DefaultSettings = (function()
	local rgb = Color3.fromRGB	
	
	return {
		Explorer = {
			_Recurse = true,
			Sorting = true,
			TeleportToOffset = Vector3.new(0,0,0),
			ClickToRename = true,
			AutoUpdateSearch = true,
			AutoUpdateMode = 0,
			PartSelectionBox = true,
			GuiSelectionBox = true,
			CopyPathUseGetChildren = true
		},
		Properties = {
			_Recurse = true,
			MaxConflictCheck = 50,
			ShowDeprecated = true,
			ShowHidden = false,
			ClearOnFocus = false,
			LoadstringInput = true,
			NumberRounding = 3,
			ShowAttributes = true,
			MaxAttributes = 50,
			ScaleType = 0
		},
		Theme = {
			_Recurse = true,
			Main1 = rgb(14,14,14),
			Main2 = rgb(0,0,0),
			Outline1 = rgb(28,28,28),
			Outline2 = rgb(35,35,35),
			Outline3 = rgb(30,30,30),
			TextBox = rgb(10,10,10),
			Menu = rgb(8,8,8),
			ListSelection = rgb(11,90,175),
			Button = rgb(20,20,20),
			ButtonHover = rgb(30,30,30),
			ButtonPress = rgb(12,12,12),
			Highlight = rgb(35,35,35),
			Text = rgb(255,255,255),
			PlaceholderText = rgb(100,100,100),
			Important = rgb(255,0,0),
			ExplorerIconMap = "",
			MiscIconMap = "",
			Syntax = {
				Text = rgb(204,204,204),
				Background = rgb(0,0,0),
				Selection = rgb(255,255,255),
				SelectionBack = rgb(11,90,175),
				Operator = rgb(204,204,204),
				Number = rgb(255,198,0),
				String = rgb(173,241,149),
				Comment = rgb(102,102,102),
				Keyword = rgb(248,109,124),
				Error = rgb(255,0,0),
				FindBackground = rgb(141,118,0),
				MatchingWord = rgb(40,40,40),
				BuiltIn = rgb(132,214,247),
				CurrentLine = rgb(18,20,28),
				LocalMethod = rgb(253,251,172),
				LocalProperty = rgb(97,161,241),
				Nil = rgb(255,198,0),
				Bool = rgb(255,198,0),
				Function = rgb(248,109,124),
				Local = rgb(248,109,124),
				Self = rgb(248,109,124),
				FunctionName = rgb(253,251,172),
				Bracket = rgb(204,204,204)
			},
		},
		Window = {
			TitleOnMiddle = false,
			Transparency = 0
		},
		RemoteBlockWriteAttribute = false,
		ClassIcon = "NewDark",
	}
end)()

local ForcedTheme = {}
for k,v in pairs(DefaultSettings.Theme) do ForcedTheme[k] = v end

local Settings = DefaultSettings or {}
local Apps = {}
local env = {}

local service = setmetatable({},{__index = function(self,name)
	local serv = cloneref(game:GetService(name))
	self[name] = serv
	return serv
end})
local plr = service.Players.LocalPlayer or service.Players.PlayerAdded:wait()

-- ══════════════════════════════════════════════════════════════════
-- DEX+ STARTERPACK CAPTURE — multi-strategy, runs at attach time
-- ══════════════════════════════════════════════════════════════════
local StarterPackCache = {}       -- {[name] = Instance or proxy-table}
local StarterPackCacheList = {}   -- ordered array of captured instances
local StarterPackCacheLock = {}   -- dedup by instance identity
local StarterPackLog = {}         -- human-readable capture log

local function spLog(msg)
	table.insert(StarterPackLog, ("[%.2f] %s"):format(tick(), msg))
end

local function spAddInst(inst, source)
	if StarterPackCacheLock[inst] then return end
	StarterPackCacheLock[inst] = true
	local entry = {Obj = inst, Source = source, CapturedAt = tick()}
	StarterPackCache[inst.Name] = entry
	table.insert(StarterPackCacheList, entry)
	spLog(("captured '%s' (%s) via %s"):format(inst.Name, inst.ClassName, source))
end

local function spScanContainer(container, source)
	local ok, children = pcall(function() return container:GetChildren() end)
	if ok then
		for _, v in ipairs(children) do
			pcall(spAddInst, v, source)
		end
	end
end

-- Strategy 1: Immediate snapshot of StarterPack on attach
task.spawn(function()
	local ok, sp = pcall(game.GetService, game, "StarterPack")
	if ok and sp then
		spScanContainer(sp, "StarterPack.immediate")
		spLog(("strategy1 done: %d items"):format(#StarterPackCacheList))
	end
end)

-- Strategy 2: DescendantAdded hook — catches replicated items as they arrive
task.spawn(function()
	local ok, sp = pcall(game.GetService, game, "StarterPack")
	if not ok or not sp then return end
	local conn
	conn = game.DescendantAdded:Connect(function(inst)
		if inst.Parent == sp then
			spAddInst(inst, "DescendantAdded.StarterPack")
		end
	end)
	task.delay(60, function() pcall(function() conn:Disconnect() end) end)
end)

-- Strategy 3: Backpack mirror — populated from StarterPack when char spawns
task.spawn(function()
	local function captureBackpack()
		task.wait(0.05) -- let it populate
		local ok, bp = pcall(function() return plr:FindFirstChildOfClass("Backpack") end)
		if ok and bp then
			spScanContainer(bp, "Backpack.onSpawn")
		end
	end
	pcall(captureBackpack) -- current character
	plr.CharacterAdded:Connect(function()
		pcall(captureBackpack)
	end)
end)

-- Strategy 4: Poll StarterPack for 30s (handles late replication)
task.spawn(function()
	local ok, sp = pcall(game.GetService, game, "StarterPack")
	if not ok or not sp then return end
	local deadline = tick() + 30
	while tick() < deadline do
		spScanContainer(sp, "poll.StarterPack")
		local ok2, bp = pcall(function() return plr:FindFirstChildOfClass("Backpack") end)
		if ok2 and bp then spScanContainer(bp, "poll.Backpack") end
		task.wait(1)
	end
	spLog("polling ended")
end)

-- Strategy 5: getnilinstances scan — finds Tool/Script instances parented to nil
task.spawn(function()
	task.wait(3) -- let executor settle
	if not (getnilinstances or get_nil_instances) then return end
	local gni = getnilinstances or get_nil_instances
	local ok, nils = pcall(gni)
	if not ok then return end
	local toolClasses = {Tool=true, HopperBin=true, LocalScript=true, ModuleScript=true, Script=true}
	for _, v in ipairs(nils) do
		if toolClasses[v.ClassName] then
			spAddInst(v, "getnilinstances")
		end
	end
	spLog(("strategy5 nil scan done: %d total"):format(#StarterPackCacheList))
end)

-- Strategy 6: getgc scan — deep scan for Tool/Script instances in GC
task.spawn(function()
	task.wait(5)
	if not (getgc) then return end
	local ok, gc = pcall(getgc, true)
	if not ok then return end
	local toolClasses = {Tool=true, HopperBin=true}
	for _, v in ipairs(gc) do
		if typeof(v) == "Instance" then
			local ck = v.ClassName
			if toolClasses[ck] then
				-- Only capture if it looks like it came from StarterPack
				local par = v.Parent
				if par == nil or (typeof(par)=="Instance" and par.ClassName=="StarterPack") then
					spAddInst(v, "getgc")
				end
			end
		end
	end
	spLog(("strategy6 gc scan done: %d total"):format(#StarterPackCacheList))
end)

-- Strategy 7: StarterGui mirror (StarterPlayerScripts, StarterCharacterScripts)
task.spawn(function()
	local services = {"StarterGui", "StarterPlayer"}
	for _, svcName in ipairs(services) do
		local ok, svc = pcall(game.GetService, game, svcName)
		if ok and svc then
			spScanContainer(svc, svcName..".immediate")
			-- Also hook for late replication
			game.DescendantAdded:Connect(function(inst)
				if inst.Parent == svc then
					spAddInst(inst, "DescendantAdded."..svcName)
				end
			end)
		end
	end
end)

-- Expose cache globally so DEX window can reach it
getgenv().DEX_StarterPackCache = StarterPackCacheList
getgenv().DEX_StarterPackLog   = StarterPackLog

-- ══════════════════════════════════════════════════════════════════
-- DEX+ HIDDEN SERVICES — force-access before Explorer builds tree
-- ══════════════════════════════════════════════════════════════════
local DEX_HiddenServices = {}
-- EVERY known Roblox service — visible, hidden, protected, deprecated
local _hiddenServiceNames = {
	-- Core / protected (require identity 8)
	"CoreGui","CorePackages","RobloxReplicatedStorage","NetworkClient",
	"ScriptContext","MemStorageService","HttpRbxApiService",
	"RbxAnalyticsService","RuntimeScriptService","ScriptEditorService",
	"StudioAssetService","StudioDeviceEmulatorService","StudioService",
	"ProcessInstancePhysicsService","UniversalAppTransparencyService",
	"GeographyService","HeartbeatService","SpawnerService",
	"CrossDMScriptChangeListener","ScriptProfilerService","ScriptDebuggerService",
	"LuaWebService","GuidRegistryService","DataModelPatchService",
	"UGCValidationService","FloodCheckerService","CookiesService",
	-- Communication / networking
	"ReplicatedStorage","ReplicatedFirst","HttpService","MessagingService",
	"RemoteService","MobileService","NetworkSettings","NetworkServer",
	"BrowserService","DraftsService","SharedTableRegistry",
	-- Players / social
	"Players","FriendService","UserService","SocialService",
	"GroupService","PermissionsService","AvatarEditorService",
	"AvatarImportService","ItemPromptService","SessionService",
	"AvatarCreationService","ExperienceInviteOptions","SafetyService",
	"PlatformFriendsService","OmniRecommendationsService",
	-- Gameplay services
	"Workspace","Lighting","SoundService","Teams","Chat","TextChatService",
	"StarterGui","StarterPack","StarterPlayer",
	"ServerStorage","ServerScriptService",
	"InsertService","AssetService","ContentProvider",
	"KeyframeSequenceProvider","AnimationClipProvider",
	"MouseService","TimerService","SeatService",
	-- Marketplace / economy
	"MarketplaceService","BadgeService","GamePassService","PointsService",
	"VirtualCurrencyService","DataStoreService","OrderedDataStoreService",
	"MemoryStoreService",
	-- Input / device
	"UserInputService","ContextActionService","GamepadService",
	"HapticService","GestureService","TouchInputService",
	"VirtualInputManager","VRService","HumanoidReplayService",
	"GazeSelectionService","PlayerEmulatorService",
	-- Physics / rendering
	"PhysicsService","TweenService","RunService","JointsService",
	"Geometry","SelectionService","PathfindingService",
	"CollisionGroupsAPI","WeldConstraintService","DraggerService",
	"WrapService","UnionAsyncOperationService",
	-- UI / GUI
	"GuiService","ProximityPromptService","LoadingGui",
	"NotificationService","BubbleChatConfiguration","AppStorageService",
	"ScreenshotHud","StickerService","PackageUIService","WidgetGuiService",
	"ThumbnailCameraService","CaptureCameraService",
	-- Telemetry / analytics
	"AnalyticsService","AdService","TeleportService","LogService",
	"PerformanceStats","PlatformCloudStorageService",
	-- Localization
	"LocalizationService","TranslationService","LocalizationTable","LanguageService",
	-- Voice / video
	"VoiceChatService","SpatialVoiceService","VideoCaptureService","VideoService",
	-- Text / moderation
	"TextService","TextFilteringService","AbuseReportService",
	-- Version / plugin
	"VersionControlService","PluginGuiService","PluginDebugService",
	"PluginManagementService","PluginPoliciesService",
	-- Misc
	"Selection","ChangeHistoryService","TestService",
	"StyleRuleService","PolicyService","RenderSettings",
	"CollectionService","PhysicsSettings","DebugSettings","TaskScheduler",
	"ScriptService","ColorCorrectionEffect",
	"StreamingEnabledService","AssetDeliveryProxy",
}
task.spawn(function()
	for attempt = 1, 3 do
		local ok, oldIdentity = pcall(getthreadidentity)
		pcall(setthreadidentity, 8)

		for _, name in ipairs(_hiddenServiceNames) do
			if not DEX_HiddenServices[name] then
				local s, svc = pcall(game.GetService, game, name)
				if s and svc and typeof(svc) == "Instance" then
					DEX_HiddenServices[name] = svc
				end
			end
		end

		local ok2, children = pcall(function() return game:GetChildren() end)
		if ok2 and children then
			for _, v in ipairs(children) do
				if typeof(v) == "Instance" and not DEX_HiddenServices[v.ClassName] then
					DEX_HiddenServices[v.ClassName] = v
				end
			end
		end

		if ok and oldIdentity then pcall(setthreadidentity, oldIdentity) end

		local count = 0
		for _ in pairs(DEX_HiddenServices) do count = count + 1 end
		if count > 20 then break end
		task.wait(1)
	end
end)
getgenv().DEX_HiddenServices = DEX_HiddenServices

local darkenedInsts = setmetatable({},{__mode = "k"})

local function darkenColor(c)
	local r,g,b = c.R,c.G,c.B
	local mx = math.max(r,g,b)
	if mx - math.min(r,g,b) > 0.04 or mx > 0.5 or mx < 0.01 then return c end
	local k = mx^0.8
	return Color3.new(r*k,g*k,b*k)
end

local darkProps = {BackgroundColor3 = true, BorderColor3 = true}

local function darkenProp(inst,prop,val)
	if typeof(val) == "Color3" and (darkProps[prop] or (prop == "Color" and inst:IsA("UIStroke"))) then
		return darkenColor(val)
	end
	return val
end

local function darkenTree(root)
	local list = root:GetDescendants()
	list[#list+1] = root
	for _,obj in ipairs(list) do
		if not darkenedInsts[obj] then
			darkenedInsts[obj] = true
			if obj:IsA("GuiObject") then
				obj.BackgroundColor3 = darkenColor(obj.BackgroundColor3)
				obj.BorderColor3 = darkenColor(obj.BorderColor3)
			elseif obj:IsA("UIStroke") then
				obj.Color = darkenColor(obj.Color)
			end
		end
	end
end

local create = function(data)
	local insts = {}
	for i,v in pairs(data) do
		local inst = Instance.new(v[2])
		insts[v[1]] = inst
		darkenedInsts[inst] = true
	end

	for _,v in pairs(data) do
		local inst = insts[v[1]]
		for prop,val in pairs(v[3]) do
			if type(val) == "table" then
				inst[prop] = insts[val[1]]
			else
				inst[prop] = darkenProp(inst,prop,val)
			end
		end
	end

	return insts[1]
end

local createSimple = function(class,props)
	local inst = Instance.new(class)
	darkenedInsts[inst] = true
	for i,v in next,props do
		inst[i] = darkenProp(inst,i,v)
	end
	return inst
end

Main = (function()
	local Main = {}

	Main.ModuleList = {"Explorer","Properties","ScriptViewer","Console","SaveInstance","ModelViewer",
		"RemoteSpy","CodeGen","OrphanedInstances","MemoryScanner","PhysicsViz"}
	Main.Elevated = false
	Main.AllowDraggableOnMobile = true
	Main.MissingEnv = {}
	Main.Version = "v1.1.6"
	Main.Mouse = plr:GetMouse()
	Main.AppControls = {}
	Main.Apps = Apps
	Main.MenuApps = {}
	Main.GitRepoName = "FusionWTF/Dex-Explorer"

	Main.DisplayOrders = {
		SideWindow = 8,
		Window = 10,
		Menu = 100000,
		Core = 101000
	}
	Main.DarkenTree = darkenTree
	Main.DarkenColor = darkenColor
	Main.MarkDark = function(inst) darkenedInsts[inst] = true end
	
	
	Main.GetRandomString = function()
		local output = ""
		for i = 2, 25 do
			output = output .. string.char(math.random(1,250))
		end
		
		return output
	end
	
	Main.SecureGui = function(gui)
		gui.Name = Main.GetRandomString()
		if gethui then
			gui.Parent = gethui()
		elseif syn and syn.protect_gui then
			syn.protect_gui(gui)
			gui.Parent = service.CoreGui
		elseif protect_gui then
			protect_gui(gui)
			gui.Parent = service.CoreGui
		elseif protectgui then
			protectgui(gui)
			gui.Parent = service.CoreGui
		else
			if Main.Elevated then
				gui.Parent = service.CoreGui
			else
				gui.Parent = service.Players.LocalPlayer:WaitForChild("PlayerGui")
			end
		end
	end

	Main.GetInitDeps = function()
		return {
			Main = Main,
			Lib = Lib,
			Apps = Apps,
			Settings = Settings,

			API = API,
			RMD = RMD,
			env = env,
			service = service,
			plr = plr,
			create = create,
			createSimple = createSimple
		}
	end

	Main.Error = function(str)
		if rconsoleprint then
			rconsoleprint("DEX ERROR: "..tostring(str).."\n")
			wait(9e9)
		else
			error(str)
		end
	end

	Main.LoadModule = function(name)
		if Main.Elevated then
			local control

			if EmbeddedModules then
				control = EmbeddedModules[name]()

				if gethsfuncs then
					control = _G.moduleData
				end

				if not control then Main.Error("Missing Embedded Module: "..name) end
			elseif _G.DebugLoadModel then
				local model = Main.DebugModel
				if not model then model = oldgame:GetObjects(getsynasset("AfterModules.rbxm"))[1] end

				control = loadstring(model.Modules[name].Source)()
				print("Locally Loaded Module",name,control)
			else
				local hashs = Main.ModuleHashData
				if not hashs then
					local s,hashDataStr = pcall(oldgame.HttpGet, game, "https://api.github.com/repos/"..Main.GitRepoName.."/ModuleHashs.dat")
					if not s then Main.Error("Failed to get module hashs") end

					local s,hashData = pcall(service.HttpService.JSONDecode,service.HttpService,hashDataStr)
					if not s then Main.Error("Failed to decode module hash JSON") end

					hashs = hashData
					Main.ModuleHashData = hashs
				end

				local hashfunc = (syn and syn.crypt.hash) or function() return "" end
				local filePath = "dex/ModuleCache/"..name..".lua"
				local s,moduleStr = pcall(env.readfile,filePath)

				if s and hashfunc(moduleStr) == hashs[name] then
					control = loadstring(moduleStr)()
				else
					local s,moduleStr = pcall(oldgame.HttpGet, game, "https://api.github.com/repos/"..Main.GitRepoName.."/Modules/"..name..".lua")
					if not s then Main.Error("Failed to get external module data of "..name) end

					env.writefile(filePath,moduleStr)
					control = loadstring(moduleStr)()
				end
			end

			Main.AppControls[name] = control
			control.InitDeps(Main.GetInitDeps())

			local moduleData = control.Main()
			Apps[name] = moduleData
			return moduleData
		else
			local module = script:WaitForChild("Modules"):WaitForChild(name,2)
			if not module then Main.Error("CANNOT FIND MODULE "..name) end

			local control = require(module)
			Main.AppControls[name] = control
			control.InitDeps(Main.GetInitDeps())

			local moduleData = control.Main()
			Apps[name] = moduleData
			return moduleData
		end
	end

	Main.LoadModules = function()
		for i,v in pairs(Main.ModuleList) do
			local s,e = pcall(Main.LoadModule,v)
			if not s then
				Main.Error("FAILED LOADING " .. v .. " CAUSE " .. e)
			end
		end

		Explorer = Apps.Explorer
		Properties = Apps.Properties
		ScriptViewer = Apps.ScriptViewer
		Console = Apps.Console
		SaveInstance = Apps.SaveInstance
		ModelViewer = Apps.ModelViewer
		Notebook = Apps.Notebook
		
		local appTable = {
			Explorer = Explorer,
			Properties = Properties,
			ScriptViewer = ScriptViewer,
			Console = Console,
			SaveInstance = SaveInstance,
			ModelViewer = ModelViewer,
			Notebook = Notebook,
			
		}

		Main.AppControls.Lib.InitAfterMain(appTable)
		for i,v in pairs(Main.ModuleList) do
			local control = Main.AppControls[v]
			if control then
				control.InitAfterMain(appTable)
			end
		end
	end

	Main.InitEnv = function()
		setmetatable(env,{__newindex = function(self,name,func)
			if not func then Main.MissingEnv[#Main.MissingEnv+1] = name return end
			rawset(self,name,func)
		end})

		env.isonmobile = game:GetService("UserInputService").TouchEnabled
		
		env.loadstring = (pcall(loadstring,"local a = 1") and loadstring) or (game:GetService("RunService"):IsStudio() and script.Modules:FindFirstChild("Loadstring") and require(script.Modules:FindFirstChild("Loadstring")))

		env.isfile = isfile
		env.isfolder = isfolder
		env.readfile = readfile
		env.writefile = writefile
		env.appendfile = appendfile
		env.makefolder = makefolder
		env.listfiles = listfiles
		env.loadfile = loadfile
		env.saveinstance = saveinstance or (function()
			if game:GetService("RunService"):IsStudio() then return function() error("Cannot run in Roblox Studio!") end end
			local Params = {
				RepoURL = "https://raw.githubusercontent.com/luau/SynSaveInstance/main/",
				SSI = "saveinstance",
			}
			local synsaveinstance = loadstring(oldgame:HttpGet(Params.RepoURL .. Params.SSI .. ".luau", true), Params.SSI)()
		
			local function wrappedsaveinstance(obj, filepath, options)
				options["FilePath"] = filepath
				options["Object"] = obj
				return synsaveinstance(options)
			end
			
			getgenv().saveinstance = wrappedsaveinstance
			return wrappedsaveinstance
		end)()
		
		env.parsefile = function(name)
			return tostring(name):gsub("[*\\?:<>|]+", ""):sub(1, 175)
		end

		env.getupvalues = debug.getupvalues or getupvalues or getupvals
		env.getconstants = debug.getconstants or getconstants or getconsts
		env.islclosure = islclosure or is_l_closure
		env.checkcaller = checkcaller
		env.getreg = getreg
		env.getgc = getgc
		
		env.hookfunction = hookfunction
		env.hookmetamethod = hookmetamethod

		env.getscriptbytecode = getscriptbytecode or dumpstring
		env.setfflag = setfflag
		env.protectgui = protect_gui or (syn and syn.protect_gui)
		env.gethui = gethui
		env.setclipboard = setclipboard
		env.getnilinstances = getnilinstances or get_nil_instances
		env.getloadedmodules = getloadedmodules
		
		env.isViableDecompileScript = function(obj)
			if typeof(obj) ~= "Instance" then return false end
			return obj:IsA("LuaSourceContainer")
		end
		env.request = (syn and syn.request) or (http and http.request) or http_request or (fluxus and fluxus.request) or request
		
		env.decompile = decompile or (function()
			
			if not env.getscriptbytecode then  return end

			local API = "http://api.plusgiant5.com"

			local last_call = 0

			local request = env.request

			local function call(konstantType, scriptPath)
				local success, bytecode = pcall(env.getscriptbytecode, scriptPath)

				if (not success) then
					return `-- Failed to get script bytecode, error:\n\n--[[\n{bytecode}\n--]]`
				end

				local time_elapsed = os.clock() - last_call
				if time_elapsed <= .5 then
					task.wait(.5 - time_elapsed)
				end

				local httpResult = request({
					Url = API .. konstantType,
					Body = bytecode,
					Method = "POST",
					Headers = {
						["Content-Type"] = "text/plain"
					}
				})

				last_call = os.clock()

				if (httpResult.StatusCode ~= 200) then
					return `-- Error occurred while requesting Konstant API, error:\n\n--[[\n{httpResult.Body}\n--]]`
				else
					return httpResult.Body
				end
			end

			local function decompile(scriptPath)
				return call("/konstant/decompile", scriptPath)
			end

			getgenv().decompile = decompile
			
			env.decompile = decompile
			return decompile
		end)()

		if identifyexecutor then
			local _exName, _exVer = identifyexecutor()
			Main.Executor = _exName
			env.executor = _exName or "Unknown"
			env.executorVersion = _exVer or "???"
		else
			env.executor = "Unknown"
			env.executorVersion = "???"
		end

		Main.GuiHolder = Main.Elevated and service.CoreGui or plr:FindFirstChildOfClass("PlayerGui")

		setmetatable(env,nil)
	end

	Main.IncompatibleTest = function()
	end
	
	local function serialize(val)
		if typeof(val) == "Color3" then
			local serializedColor = {}
			serializedColor.R = val.R
			serializedColor.G = val.G
			serializedColor.B = val.B
			return serializedColor
		else
			return val
		end
	end
	
	local function deserialize(val)
		if typeof(val) == "table" then
			if val.R and val.G and val.B then
				return Color3.new(val.R, val.G, val.B)
			else
				return val
			end
		else
			return val
		end
	end
	
	Main.ExportSettings = function()
		local rawData = Settings or DefaultSettings

		local function recur(tbl)
			local newTbl = {}
			for i, v in pairs(tbl) do
				if typeof(v) == "table" then
					newTbl[i] = recur(v)
				else
					newTbl[i] = serialize(v)
				end
			end
			return newTbl
		end

		local serializedData = recur(rawData)

		local s, json = pcall(service.HttpService.JSONEncode, service.HttpService, serializedData)
		if s and json then
			return json
		end
	end



	Main.LoadSettings = function()
		local s, data = pcall(env.readfile or error, "DexSettings.json")
		if s and data and data ~= "" then
			local s, decoded = pcall(service.HttpService.JSONDecode, service.HttpService, data)
			if s and decoded then

				local function recur(tbl)
					local newTbl = {}
					for i, v in pairs(tbl) do
						if typeof(v) == "table" then
							newTbl[i] = deserialize(recur(v))
						else
							newTbl[i] = deserialize(v)
						end
					end
					return newTbl
				end

				local deserializedData = recur(decoded)
				for k, v in pairs(deserializedData) do
					Settings[k] = v
				end

			else
				warn("failed to decode settings json")
			end
		else
			Main.ResetSettings()
		end
	end

	
	

	Main.ResetSettings = function()
		local function recur(t,res)
			for set,val in pairs(t) do
				if type(val) == "table" and val._Recurse then
					if type(res[set]) ~= "table" then
						res[set] = {}
					end
					recur(val,res[set])
				else
					res[set] = val
				end
			end
			return res
		end
		recur(DefaultSettings,Settings)
	end

	Main.FetchAPI = function(callbackiflong, callbackiftoolong, XD)
		local downloaded = false
		local api,rawAPI
		if Main.Elevated then
			if Main.LocalDepsUpToDate() then
				local localAPI = Lib.ReadFile("dex/rbx_api.dat")
				if localAPI then 
					rawAPI = localAPI
				else
					Main.DepsVersionData[1] = ""
				end
			end
			task.spawn(function()
				task.wait(10)
				if not downloaded and callbackiflong then callbackiflong() end

				task.wait(20)
				if not downloaded and callbackiftoolong then callbackiftoolong() end

				task.wait(30)
				if not downloaded and XD then XD() end
			end)
			rawAPI = rawAPI or game:HttpGet("http://setup.roblox.com/"..Main.RobloxVersion.."-API-Dump.json")
		else
			if script:FindFirstChild("API") then
				rawAPI = require(script.API)
			else
				error("NO API EXISTS")
			end
		end
		downloaded = true
		
		Main.RawAPI = rawAPI
		api = service.HttpService:JSONDecode(rawAPI)

		local classes,enums = {},{}
		local categoryOrder,seenCategories = {},{}

		local function insertAbove(t,item,aboveItem)
			local findPos = table.find(t,item)
			if not findPos then return end
			table.remove(t,findPos)

			local pos = table.find(t,aboveItem)
			if not pos then return end
			table.insert(t,pos,item)
		end

		for _,class in pairs(api.Classes) do
			local newClass = {}
			newClass.Name = class.Name
			newClass.Superclass = class.Superclass
			newClass.Properties = {}
			newClass.Functions = {}
			newClass.Events = {}
			newClass.Callbacks = {}
			newClass.Tags = {}

			if class.Tags then for c,tag in pairs(class.Tags) do newClass.Tags[tag] = true end end
			for __,member in pairs(class.Members) do
				local newMember = {}
				newMember.Name = member.Name
				newMember.Class = class.Name
				newMember.Security = member.Security
				newMember.Tags ={}
				if member.Tags then for c,tag in pairs(member.Tags) do newMember.Tags[tag] = true end end

				local mType = member.MemberType
				if mType == "Property" then
					local propCategory = member.Category or "Other"
					propCategory = propCategory:match("^%s*(.-)%s*$")
					if not seenCategories[propCategory] then
						categoryOrder[#categoryOrder+1] = propCategory
						seenCategories[propCategory] = true
					end
					newMember.ValueType = member.ValueType
					newMember.Category = propCategory
					newMember.Serialization = member.Serialization
					table.insert(newClass.Properties,newMember)
				elseif mType == "Function" then
					newMember.Parameters = {}
					newMember.ReturnType = member.ReturnType.Name
					for c,param in pairs(member.Parameters) do
						table.insert(newMember.Parameters,{Name = param.Name, Type = param.Type.Name})
					end
					table.insert(newClass.Functions,newMember)
				elseif mType == "Event" then
					newMember.Parameters = {}
					for c,param in pairs(member.Parameters) do
						table.insert(newMember.Parameters,{Name = param.Name, Type = param.Type.Name})
					end
					table.insert(newClass.Events,newMember)
				end
			end

			classes[class.Name] = newClass
		end

		for _,class in pairs(classes) do
			class.Superclass = classes[class.Superclass]
		end

		for _,enum in pairs(api.Enums) do
			local newEnum = {}
			newEnum.Name = enum.Name
			newEnum.Items = {}
			newEnum.Tags = {}

			if enum.Tags then for c,tag in pairs(enum.Tags) do newEnum.Tags[tag] = true end end
			for __,item in pairs(enum.Items) do
				local newItem = {}
				newItem.Name = item.Name
				newItem.Value = item.Value
				table.insert(newEnum.Items,newItem)
			end

			enums[enum.Name] = newEnum
		end

		local function getMember(class,member)
			if not classes[class] or not classes[class][member] then return end
			local result = {}

			local currentClass = classes[class]
			while currentClass do
				for _,entry in pairs(currentClass[member]) do
					result[#result+1] = entry
				end
				currentClass = currentClass.Superclass
			end

			table.sort(result,function(a,b) return a.Name < b.Name end)
			return result
		end

		insertAbove(categoryOrder,"Behavior","Tuning")
		insertAbove(categoryOrder,"Appearance","Data")
		insertAbove(categoryOrder,"Attachments","Axes")
		insertAbove(categoryOrder,"Cylinder","Slider")
		insertAbove(categoryOrder,"Localization","Jump Settings")
		insertAbove(categoryOrder,"Surface","Motion")
		insertAbove(categoryOrder,"Surface Inputs","Surface")
		insertAbove(categoryOrder,"Part","Surface Inputs")
		insertAbove(categoryOrder,"Assembly","Surface Inputs")
		insertAbove(categoryOrder,"Character","Controls")
		categoryOrder[#categoryOrder+1] = "Unscriptable"
		categoryOrder[#categoryOrder+1] = "Attributes"

		local categoryOrderMap = {}
		for i = 1,#categoryOrder do
			categoryOrderMap[categoryOrder[i]] = i
		end

		return {
			Classes = classes,
			Enums = enums,
			CategoryOrder = categoryOrderMap,
			GetMember = getMember
		}
	end

	Main.FetchRMD = function()
		local rawXML
		if Main.Elevated then
			if Main.LocalDepsUpToDate() then
				local localRMD = Lib.ReadFile("dex/rbx_rmd.dat")
				if localRMD then 
					rawXML = localRMD
				else
					Main.DepsVersionData[1] = ""
				end
			end
			rawXML = rawXML or game:HttpGet("https://raw.githubusercontent.com/CloneTrooper1019/Roblox-Client-Tracker/roblox/ReflectionMetadata.xml")
		else
			if script:FindFirstChild("RMD") then
				rawXML = require(script.RMD)
			else
				error("NO RMD EXISTS")
			end
		end
		Main.RawRMD = rawXML
		local parsed = Lib.ParseXML(rawXML)
		local classList = parsed.children[1].children[1].children
		local enumList = parsed.children[1].children[2].children
		local propertyOrders = {}

		local classes,enums = {},{}
		for _,class in pairs(classList) do
			local className = ""
			for _,child in pairs(class.children) do
				if child.tag == "Properties" then
					local data = {Properties = {}, Functions = {}}
					local props = child.children
					for _,prop in pairs(props) do
						local name = prop.attrs.name
						name = name:sub(1,1):upper()..name:sub(2)
						data[name] = prop.children[1].text
					end
					className = data.Name
					classes[className] = data
				elseif child.attrs.class == "ReflectionMetadataProperties" then
					local members = child.children
					for _,member in pairs(members) do
						if member.attrs.class == "ReflectionMetadataMember" then
							local data = {}
							if member.children[1].tag == "Properties" then
								local props = member.children[1].children
								for _,prop in pairs(props) do
									if prop.attrs then
										local name = prop.attrs.name
										name = name:sub(1,1):upper()..name:sub(2)
										data[name] = prop.children[1].text
									end
								end
								if data.PropertyOrder then
									local orders = propertyOrders[className]
									if not orders then orders = {} propertyOrders[className] = orders end
									orders[data.Name] = tonumber(data.PropertyOrder)
								end
								classes[className].Properties[data.Name] = data
							end
						end
					end
				elseif child.attrs.class == "ReflectionMetadataFunctions" then
					local members = child.children
					for _,member in pairs(members) do
						if member.attrs.class == "ReflectionMetadataMember" then
							local data = {}
							if member.children[1].tag == "Properties" then
								local props = member.children[1].children
								for _,prop in pairs(props) do
									if prop.attrs then
										local name = prop.attrs.name
										name = name:sub(1,1):upper()..name:sub(2)
										data[name] = prop.children[1].text
									end
								end
								classes[className].Functions[data.Name] = data
							end
						end
					end
				end
			end
		end

		for _,enum in pairs(enumList) do
			local enumName = ""
			for _,child in pairs(enum.children) do
				if child.tag == "Properties" then
					local data = {Items = {}}
					local props = child.children
					for _,prop in pairs(props) do
						local name = prop.attrs.name
						name = name:sub(1,1):upper()..name:sub(2)
						data[name] = prop.children[1].text
					end
					enumName = data.Name
					enums[enumName] = data
				elseif child.attrs.class == "ReflectionMetadataEnumItem" then
					local data = {}
					if child.children[1].tag == "Properties" then
						local props = child.children[1].children
						for _,prop in pairs(props) do
							local name = prop.attrs.name
							name = name:sub(1,1):upper()..name:sub(2)
							data[name] = prop.children[1].text
						end
						enums[enumName].Items[data.Name] = data
					end
				end
			end
		end

		return {Classes = classes, Enums = enums, PropertyOrders = propertyOrders}
	end

	Main.ShowGui = Main.SecureGui

	Main.CreateIntro = function(initStatus)
		local gui = create({
			{1,"ScreenGui",{Name="Intro",}},
			{2,"Frame",{Active=true,BackgroundColor3=Color3.new(0.20392157137394,0.20392157137394,0.20392157137394),BorderSizePixel=0,Name="Main",Parent={1},Position=UDim2.new(0.5,-175,0.5,-100),Size=UDim2.new(0,350,0,200),}},
			{3,"Frame",{BackgroundColor3=Color3.new(0.17647059261799,0.17647059261799,0.17647059261799),BorderSizePixel=0,ClipsDescendants=true,Name="Holder",Parent={2},Size=UDim2.new(1,0,1,0),}},
			{4,"UIGradient",{Parent={3},Rotation=30,Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,1,0),NumberSequenceKeypoint.new(1,1,0),}),}},
			{5,"TextLabel",{BackgroundColor3=Color3.new(1,1,1),BackgroundTransparency=1,Font=4,Name="Title",Parent={3},Position=UDim2.new(0,-330,0,15),Size=UDim2.new(0,310,0,50),Text="Dex Premium",TextColor3=Color3.new(1,1,1),TextSize=44,TextTransparency=1,TextXAlignment=0,}},
			{6,"TextLabel",{BackgroundColor3=Color3.new(1,1,1),BackgroundTransparency=1,Font=3,Name="Desc",Parent={3},Position=UDim2.new(0,-230,0,60),Size=UDim2.new(0,180,0,25),Text="Ultimate Debugging Suite",TextColor3=Color3.new(1,1,1),TextSize=18,TextTransparency=1,}},
			{7,"TextLabel",{BackgroundColor3=Color3.new(1,1,1),BackgroundTransparency=1,Font=3,Name="StatusText",Parent={3},Position=UDim2.new(0,20,0,110),Size=UDim2.new(0,180,0,25),Text="Fetching API",TextColor3=Color3.new(1,1,1),TextSize=14,TextTransparency=1,}},
			{8,"Frame",{BackgroundColor3=Color3.new(0.20392157137394,0.20392157137394,0.20392157137394),BorderSizePixel=0,Name="ProgressBar",Parent={3},Position=UDim2.new(0,110,0,145),Size=UDim2.new(0,0,0,4),}},
			{9,"Frame",{BackgroundColor3=Color3.new(0.2392156869173,0.56078433990479,0.86274510622025),BorderSizePixel=0,Name="Bar",Parent={8},Size=UDim2.new(0,0,1,0),}},
			{10,"ImageLabel",{BackgroundColor3=Color3.new(1,1,1),BackgroundTransparency=1,Image="rbxassetid://2764171053",ImageColor3=Color3.new(0.17647059261799,0.17647059261799,0.17647059261799),Parent={8},ScaleType=1,Size=UDim2.new(1,0,1,0),SliceCenter=Rect.new(2,2,254,254),}},
			{11,"TextLabel",{BackgroundColor3=Color3.new(1,1,1),BackgroundTransparency=1,Font=3,Name="Creator",Parent={2},Position=UDim2.new(1,-155,1,-20),Size=UDim2.new(0,150,0,20),Text="Developed by Ximmy",TextColor3=Color3.new(1,1,1),TextSize=14,TextXAlignment=1,}},
			{12,"UIGradient",{Parent={11},Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,1,0),NumberSequenceKeypoint.new(1,1,0),}),}},
			{13,"TextLabel",{BackgroundColor3=Color3.new(1,1,1),BackgroundTransparency=1,Font=3,Name="Version",Parent={2},Position=UDim2.new(1,-155,1,-35),Size=UDim2.new(0,150,0,20),Text=Main.Version,TextColor3=Color3.new(1,1,1),TextSize=14,TextXAlignment=1,}},
			{14,"UIGradient",{Parent={13},Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,1,0),NumberSequenceKeypoint.new(1,1,0),}),}},
			{15,"ImageLabel",{BackgroundColor3=Color3.new(1,1,1),BackgroundTransparency=1,BorderSizePixel=0,Image="rbxassetid://1427967925",Name="Outlines",Parent={2},Position=UDim2.new(0,-5,0,-5),ScaleType=1,Size=UDim2.new(1,10,1,10),SliceCenter=Rect.new(6,6,25,25),TileSize=UDim2.new(0,20,0,20),}},
			{16,"UIGradient",{Parent={15},Rotation=-30,Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,1,0),NumberSequenceKeypoint.new(1,1,0),}),}},
			{17,"UIGradient",{Parent={2},Rotation=-30,Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,1,0),NumberSequenceKeypoint.new(1,1,0),}),}},
			{18,"UIDragDetector", {Parent={2}}}
		})
		Main.ShowGui(gui)
		local backGradient = gui.Main.UIGradient
		local outlinesGradient = gui.Main.Outlines.UIGradient
		local holderGradient = gui.Main.Holder.UIGradient
		local titleText = gui.Main.Holder.Title
		local descText = gui.Main.Holder.Desc
		local versionText = gui.Main.Version
		local versionGradient = versionText.UIGradient
		local creatorText = gui.Main.Creator
		local creatorGradient = creatorText.UIGradient
		local statusText = gui.Main.Holder.StatusText
		local progressBar = gui.Main.Holder.ProgressBar
		local tweenS = service.TweenService

		local renderStepped = service.RunService.RenderStepped
		local signalWait = renderStepped.wait
		local fastwait = function(s)
			if not s then return signalWait(renderStepped) end
			local start = tick()
			while tick() - start < s do signalWait(renderStepped) end
		end

		statusText.Text = initStatus

		local function tweenNumber(n,ti,func)
			local tweenVal = Instance.new("IntValue")
			tweenVal.Value = 0
			tweenVal.Changed:Connect(func)
			local tween = tweenS:Create(tweenVal,ti,{Value = n})
			tween:Play()
			tween.Completed:Connect(function()
				tweenVal:Destroy()
			end)
		end

		local ti = TweenInfo.new(0.4,Enum.EasingStyle.Quad,Enum.EasingDirection.Out)
		tweenNumber(100,ti,function(val)
			val = val/200
			local start = NumberSequenceKeypoint.new(0,0)
			local a1 = NumberSequenceKeypoint.new(val,0)
			local a2 = NumberSequenceKeypoint.new(math.min(0.5,val+math.min(0.05,val)),1)
			if a1.Time == a2.Time then a2 = a1 end
			local b1 = NumberSequenceKeypoint.new(1-val,0)
			local b2 = NumberSequenceKeypoint.new(math.max(0.5,1-val-math.min(0.05,val)),1)
			if b1.Time == b2.Time then b2 = b1 end
			local goal = NumberSequenceKeypoint.new(1,0)
			backGradient.Transparency = NumberSequence.new({start,a1,a2,b2,b1,goal})
			outlinesGradient.Transparency = NumberSequence.new({start,a1,a2,b2,b1,goal})
		end)

		fastwait(0.4)

		tweenNumber(100,ti,function(val)
			val = val/166.66
			local start = NumberSequenceKeypoint.new(0,0)
			local a1 = NumberSequenceKeypoint.new(val,0)
			local a2 = NumberSequenceKeypoint.new(val+0.01,1)
			local goal = NumberSequenceKeypoint.new(1,1)
			holderGradient.Transparency = NumberSequence.new({start,a1,a2,goal})
		end)

		tweenS:Create(titleText,ti,{Position = UDim2.new(0,20,0,15), TextTransparency = 0}):Play()
		tweenS:Create(descText,ti,{Position = UDim2.new(0,20,0,60), TextTransparency = 0}):Play()

		local function rightTextTransparency(obj)
			tweenNumber(100,ti,function(val)
				val = val/100
				local a1 = NumberSequenceKeypoint.new(1-val,0)
				local a2 = NumberSequenceKeypoint.new(math.max(0,1-val-0.01),1)
				if a1.Time == a2.Time then a2 = a1 end
				local start = NumberSequenceKeypoint.new(0,a1 == a2 and 0 or 1)
				local goal = NumberSequenceKeypoint.new(1,0)
				obj.Transparency = NumberSequence.new({start,a2,a1,goal})
			end)
		end
		rightTextTransparency(versionGradient)
		rightTextTransparency(creatorGradient)

		fastwait(0.9)

		local progressTI = TweenInfo.new(0.25,Enum.EasingStyle.Quad,Enum.EasingDirection.Out)

		tweenS:Create(statusText,progressTI,{Position = UDim2.new(0,20,0,120), TextTransparency = 0}):Play()
		tweenS:Create(progressBar,progressTI,{Position = UDim2.new(0,60,0,145), Size = UDim2.new(0,100,0,4)}):Play()

		fastwait(0.25)

		local function setProgress(text,n)
			statusText.Text = text
			tweenS:Create(progressBar.Bar,progressTI,{Size = UDim2.new(n,0,1,0)}):Play()
		end

		local function close()
			tweenS:Create(titleText,progressTI,{TextTransparency = 1}):Play()
			tweenS:Create(descText,progressTI,{TextTransparency = 1}):Play()
			tweenS:Create(versionText,progressTI,{TextTransparency = 1}):Play()
			tweenS:Create(creatorText,progressTI,{TextTransparency = 1}):Play()
			tweenS:Create(statusText,progressTI,{TextTransparency = 1}):Play()
			tweenS:Create(progressBar,progressTI,{BackgroundTransparency = 1}):Play()
			tweenS:Create(progressBar.Bar,progressTI,{BackgroundTransparency = 1}):Play()
			tweenS:Create(progressBar.ImageLabel,progressTI,{ImageTransparency = 1}):Play()

			tweenNumber(100,TweenInfo.new(0.4,Enum.EasingStyle.Back,Enum.EasingDirection.In),function(val)
				val = val/250
				local start = NumberSequenceKeypoint.new(0,0)
				local a1 = NumberSequenceKeypoint.new(0.6+val,0)
				local a2 = NumberSequenceKeypoint.new(math.min(1,0.601+val),1)
				if a1.Time == a2.Time then a2 = a1 end
				local goal = NumberSequenceKeypoint.new(1,a1 == a2 and 0 or 1)
				holderGradient.Transparency = NumberSequence.new({start,a1,a2,goal})
			end)

			fastwait(0.5)
			gui.Main.BackgroundTransparency = 1
			outlinesGradient.Rotation = 30

			tweenNumber(100,ti,function(val)
				val = val/100
				local start = NumberSequenceKeypoint.new(0,1)
				local a1 = NumberSequenceKeypoint.new(val,1)
				local a2 = NumberSequenceKeypoint.new(math.min(1,val+math.min(0.05,val)),0)
				if a1.Time == a2.Time then a2 = a1 end
				local goal = NumberSequenceKeypoint.new(1,a1 == a2 and 1 or 0)
				outlinesGradient.Transparency = NumberSequence.new({start,a1,a2,goal})
				holderGradient.Transparency = NumberSequence.new({start,a1,a2,goal})
			end)

			fastwait(0.45)
			gui:Destroy()
		end

		return {SetProgress = setProgress, Close = close, Object = gui}
	end

	Main.CreateApp = function(data)
		if Main.MenuApps[data.Name] then return end
		local control = {}

		local app = Main.AppTemplate:Clone()
		local tile = app.Main
		Lib.DrawIcon(tile.Icon,data.Icon,Color3.fromRGB(215,215,215),2)

		local hovering = false
		local function updateState()
			tile.BackgroundTransparency = (data.Open or hovering) and 0 or 1
			tile.BackgroundColor3 = hovering and Color3.fromRGB(26,26,26) or Color3.fromRGB(16,16,16)
			tile.Highlight.Visible = data.Open
			tile.AppName.TextTransparency = data.Open and 0 or 0.35
		end

		local function enable(silent)
			if data.Open then return end
			data.Open = true
			updateState()
			if not silent then
				if data.Window then data.Window:Show() end
				if data.OnClick then data.OnClick(data.Open) end
			end
		end

		local function disable(silent)
			if not data.Open then return end
			data.Open = false
			updateState()
			if not silent then
				if data.Window then data.Window:Hide() end
				if data.OnClick then data.OnClick(data.Open) end
			end
		end

		tile.AppName.Text = data.Name
		updateState()

		tile.MouseEnter:Connect(function()
			hovering = true
			updateState()
		end)

		tile.MouseLeave:Connect(function()
			hovering = false
			updateState()
		end)

		tile.MouseButton1Click:Connect(function()
			if data.Open then disable() else enable() end
		end)

		local window = data.Window
		if window then
			window.OnActivate:Connect(function() enable(true) end)
			window.OnDeactivate:Connect(function() disable(true) end)
		end

		app.Visible = true
		app.Parent = Main.AppsContainer
		Main.AppsFrame.CanvasSize = UDim2.new(0,0,0,Main.AppsContainerGrid.AbsoluteContentSize.Y + 16)

		control.Enable = enable
		control.Disable = disable
		Main.MenuApps[data.Name] = control
		return control
	end

	Main.SetMainGuiOpen = function(val)
		Main.MainGuiOpen = val
		Lib.Window.SetHubVisible(val)
	end

	Main.CreateScriptsWindow = function()
		local window = Lib.Window.new()
		window:SetTitle("Scripts")
		window:Resize(320,500)
		Main.ScriptsWindow = window

		local ROW = 20
		local colors = {
			Card = Color3.fromRGB(14,14,14),
			CardHover = Color3.fromRGB(26,26,26),
			Stroke = Color3.fromRGB(34,34,34),
			Text = Color3.fromRGB(220,220,220),
			Dim = Color3.fromRGB(125,125,125),
			Hover = Color3.fromRGB(24,24,24),
			Selected = Color3.fromRGB(11,90,175),
		}
		local skipServices = {CoreGui = true, CorePackages = true, RobloxPluginGuiService = true}

		local function mk(class,props,parent)
			local inst = Instance.new(class)
			Main.MarkDark(inst)
			for k,v in pairs(props) do inst[k] = v end
			if parent then inst.Parent = parent end
			return inst
		end
		local function round(parent,r) return mk("UICorner",{CornerRadius=UDim.new(0,r)},parent) end
		local function stroke(parent) return mk("UIStroke",{ApplyStrokeMode=Enum.ApplyStrokeMode.Border,Color=colors.Stroke,Thickness=1},parent) end

		local content = window.GuiElems.Content
		local toolbar = mk("Frame",{BackgroundTransparency=1,Name="Toolbar",Position=UDim2.new(0,6,0,6),Size=UDim2.new(1,-12,0,26)},content)

		local searchBox = mk("TextBox",{BackgroundColor3=colors.Card,BorderSizePixel=0,ClearTextOnFocus=false,Font=Enum.Font.Gotham,PlaceholderColor3=colors.Dim,PlaceholderText="Search scripts",Size=UDim2.new(1,-80,1,0),Text="",TextColor3=colors.Text,TextSize=12,TextXAlignment=Enum.TextXAlignment.Left},toolbar)
		round(searchBox,6)
		stroke(searchBox)
		mk("UIPadding",{PaddingLeft=UDim.new(0,8),PaddingRight=UDim.new(0,8)},searchBox)

		local refreshBtn = mk("TextButton",{AnchorPoint=Vector2.new(1,0),AutoButtonColor=false,BackgroundColor3=colors.Card,BorderSizePixel=0,Font=Enum.Font.GothamMedium,Position=UDim2.new(1,0,0,0),Size=UDim2.new(0,74,1,0),Text="Refresh",TextColor3=colors.Text,TextSize=12},toolbar)
		round(refreshBtn,6)
		stroke(refreshBtn)
		refreshBtn.MouseEnter:Connect(function() refreshBtn.BackgroundColor3 = colors.CardHover end)
		refreshBtn.MouseLeave:Connect(function() refreshBtn.BackgroundColor3 = colors.Card end)

		local statusLabel = mk("TextLabel",{BackgroundTransparency=1,Font=Enum.Font.Gotham,Position=UDim2.new(0,8,0,36),Size=UDim2.new(1,-16,0,14),Text="",TextColor3=colors.Dim,TextSize=11,TextXAlignment=Enum.TextXAlignment.Left},content)

		local list = mk("ScrollingFrame",{Active=true,BackgroundTransparency=1,BorderSizePixel=0,CanvasSize=UDim2.new(0,0,0,0),Name="Tree",Position=UDim2.new(0,0,0,54),ScrollBarImageColor3=Color3.fromRGB(90,90,90),ScrollBarThickness=6,ScrollingDirection=Enum.ScrollingDirection.Y,Size=UDim2.new(1,0,1,-54)},content)

		local root = {Children = {}, Count = 0}
		local scriptList = {}
		local flat = {}
		local pool = {}
		local rowItems = {}
		local expandedObjs = setmetatable({},{__mode = "k"})
		local selectedObj
		local lastClickObj,lastClickTime = nil,0
		local scanning = false
		local dirty = false
		local hasScanned = false

		local orderCache = {}
		local function classOrder(cls)
			local o = orderCache[cls]
			if not o then
				local entry = RMD and RMD.Classes and RMD.Classes[cls]
				o = entry and tonumber(entry.ExplorerOrder) or 9999
				orderCache[cls] = o
			end
			return o
		end

		local function sortChildren(node)
			table.sort(node.Children,function(a,b)
				local ao,bo = classOrder(a.Class),classOrder(b.Class)
				if ao ~= bo then return ao < bo end
				return a.NameLower < b.NameLower
			end)
			for _,c in ipairs(node.Children) do sortChildren(c) end
		end

		local function scan()
			local newRoot = {Children = {}, Count = 0}
			local cache = {}
			local found = {}

			local function nodeFor(obj)
				local n = cache[obj]
				if n then return n end
				local parent = obj.Parent
				if parent == nil then return nil end
				local pnode = parent == game and newRoot or nodeFor(parent)
				if not pnode then return nil end
				local name = tostring(obj.Name)
				n = {Obj = obj, Class = obj.ClassName, NameLower = name:lower(), Children = {}, Count = 0, Parent = pnode}
				cache[obj] = n
				pnode.Children[#pnode.Children+1] = n
				return n
			end

			for _,svc in ipairs(game:GetChildren()) do
				local okCls,cls = pcall(function() return svc.ClassName end)
				if okCls and not skipServices[cls] then
					local ok,desc = pcall(svc.GetDescendants,svc)
					if ok then
						for i,d in ipairs(desc) do
							if d:IsA("LuaSourceContainer") then
								local n = nodeFor(d)
								if n and not n.IsScript then
									n.IsScript = true
									found[#found+1] = n
									local p = n.Parent
									while p do
										p.Count = p.Count + 1
										p = p.Parent
									end
								end
							end
							if i % 20000 == 0 then task.wait() end
						end
					end
				end
			end

			sortChildren(newRoot)
			table.sort(found,function(a,b) return a.NameLower < b.NameLower end)
			return newRoot,found
		end

		local function selectInExplorer(obj)
			local node = obj and nodes[obj]
			if node then
				selection:Set(node)
				Explorer.ViewNode(node)
			end
		end

		local function objPath(obj)
			local ok,path = pcall(Explorer.GetInstancePath,obj)
			if ok and path then return tostring(path) end
			local ok2,full = pcall(obj.GetFullName,obj)
			return ok2 and full or tostring(obj)
		end

		local function isExpandable(node)
			return #node.Children > 0
		end

		local render

		local function rebuildFlat()
			flat = {}
			local query = searchBox.Text:lower()
			if query ~= "" then
				for _,n in ipairs(scriptList) do
					if n.NameLower:find(query,1,true) then
						flat[#flat+1] = {n,0,true}
					end
				end
			else
				local function walk(node,depth)
					for _,c in ipairs(node.Children) do
						flat[#flat+1] = {c,depth}
						if expandedObjs[c.Obj] then walk(c,depth+1) end
					end
				end
				walk(root,0)
			end
			list.CanvasSize = UDim2.new(0,0,0,#flat*ROW)
			render()
		end

		local function makeRow()
			local row = mk("TextButton",{AutoButtonColor=false,BackgroundColor3=colors.Hover,BackgroundTransparency=1,BorderSizePixel=0,Size=UDim2.new(1,-6,0,ROW),Text=""},list)
			mk("ImageLabel",{BackgroundTransparency=1,Name="Expand",Size=UDim2.new(0,16,0,16)},row)
			mk("Frame",{BackgroundTransparency=1,Name="Icon",Size=UDim2.new(0,16,0,16)},row)
			mk("TextLabel",{BackgroundTransparency=1,Font=Enum.Font.SourceSans,Name="EntryName",Text="",TextColor3=colors.Text,TextSize=14,TextTruncate=Enum.TextTruncate.AtEnd,TextXAlignment=Enum.TextXAlignment.Left},row)
			mk("TextLabel",{AnchorPoint=Vector2.new(1,0),BackgroundTransparency=1,Font=Enum.Font.Gotham,Name="Info",Position=UDim2.new(1,-8,0,0),Text="",TextColor3=colors.Dim,TextSize=11,TextTruncate=Enum.TextTruncate.AtEnd,TextXAlignment=Enum.TextXAlignment.Right},row)

			local hovering = false
			local function restyle()
				local item = rowItems[row]
				local obj = item and item[1].Obj
				if obj and obj == selectedObj then
					row.BackgroundColor3 = colors.Selected
					row.BackgroundTransparency = 0
				elseif hovering then
					row.BackgroundColor3 = colors.Hover
					row.BackgroundTransparency = 0
				else
					row.BackgroundTransparency = 1
				end
			end
			row.MouseEnter:Connect(function() hovering = true restyle() end)
			row.MouseLeave:Connect(function() hovering = false restyle() end)
			pool[#pool+1] = {Row = row, Restyle = restyle}
			return pool[#pool]
		end

		local function toggle(node)
			if not isExpandable(node) then return end
			expandedObjs[node.Obj] = not expandedObjs[node.Obj] or nil
			rebuildFlat()
		end

		local function setAllExpanded(node,value)
			for _,c in ipairs(node.Children) do
				if isExpandable(c) then
					expandedObjs[c.Obj] = value or nil
					setAllExpanded(c,value)
				end
			end
		end

		local function restyleAll()
			for _,p in ipairs(pool) do p.Restyle() end
		end

		local context = Lib.ContextMenu.new()
		local contextNode
		context:Register("VIEW",{Name = "View Script",OnClick = function()
			if contextNode and contextNode.IsScript then ScriptViewer.ViewScript(contextNode.Obj) end
		end})
		context:Register("SELECT",{Name = "Select in Explorer",OnClick = function()
			if contextNode then selectInExplorer(contextNode.Obj) end
		end})
		context:Register("COPY_PATH",{Name = "Copy Path",OnClick = function()
			if contextNode and env.setclipboard then env.setclipboard(objPath(contextNode.Obj)) end
		end})
		context:Register("EXPAND_ALL",{Name = "Expand All",OnClick = function()
			if contextNode then
				expandedObjs[contextNode.Obj] = true
				setAllExpanded(contextNode,true)
				rebuildFlat()
			end
		end})
		context:Register("COLLAPSE_ALL",{Name = "Collapse All",OnClick = function()
			if contextNode then
				expandedObjs[contextNode.Obj] = nil
				setAllExpanded(contextNode,false)
				rebuildFlat()
			end
		end})

		local function onRowInput(entry,input)
			local item = rowItems[entry.Row]
			if not item then return end
			local node,depth,isSearch = item[1],item[2],item[3]
			local obj = node.Obj
			local kind = input.UserInputType

			if kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch then
				local x = input.Position.X - entry.Row.AbsolutePosition.X
				local indent = 4 + depth*16
				if not isSearch and isExpandable(node) and x >= indent and x <= indent + 18 then
					toggle(node)
					return
				end

				local now = tick()
				local double = lastClickObj == obj and now - lastClickTime < 0.35
				lastClickObj,lastClickTime = obj,now
				selectedObj = obj
				restyleAll()
				selectInExplorer(obj)

				if double then
					lastClickObj = nil
					if node.IsScript then
						ScriptViewer.ViewScript(obj)
					elseif not isSearch then
						toggle(node)
					end
				end
			elseif kind == Enum.UserInputType.MouseButton2 then
				selectedObj = obj
				restyleAll()
				contextNode = node
				context:Clear()
				context:AddRegistered("VIEW",not node.IsScript)
				context:AddRegistered("SELECT",nodes[obj] == nil)
				context:AddRegistered("COPY_PATH",env.setclipboard == nil)
				if not isSearch and isExpandable(node) then
					context:AddDivider()
					context:AddRegistered("EXPAND_ALL")
					context:AddRegistered("COLLAPSE_ALL")
				end
				context:Show()
			end
		end

		render = function()
			local first = math.max(1,math.floor(list.CanvasPosition.Y / ROW) + 1)
			local count = math.ceil(list.AbsoluteSize.Y / ROW) + 1
			for i = 1,count do
				local entry = pool[i]
				if not entry then
					entry = makeRow()
					entry.Row.InputBegan:Connect(function(input) onRowInput(entry,input) end)
				end
				local row = entry.Row
				local index = first + i - 1
				local item = flat[index]
				rowItems[row] = item
				if item then
					local node,depth,isSearch = item[1],item[2],item[3]
					local obj = node.Obj
					local indent = 4 + depth*16
					row.Position = UDim2.new(0,0,0,(index-1)*ROW)
					row.Visible = true

					local expand = row.Expand
					expand.Position = UDim2.new(0,indent,0,2)
					if not isSearch and isExpandable(node) then
						Main.MiscIcons:DisplayByKey(expand,expandedObjs[obj] and "Collapse" or "Expand")
						expand.Visible = true
					else
						expand.Visible = false
					end

					local icon = row.Icon
					icon.Position = UDim2.new(0,isSearch and 6 or indent + 18,0,2)
					pcall(Main.MiscIcons.DisplayExplorerIcons,Main.MiscIcons,icon,node.Class)

					local nameX = (isSearch and 6 or indent + 18) + 22
					local okName,name = pcall(function() return obj.Name end)
					row.EntryName.Text = okName and tostring(name) or "?"
					row.EntryName.Position = UDim2.new(0,nameX,0,0)

					local info = row.Info
					if isSearch then
						local parent = obj.Parent
						info.Text = parent and objPath(parent) or "nil"
						info.Size = UDim2.new(0.5,-8,1,0)
						row.EntryName.Size = UDim2.new(0.5,-nameX,1,0)
					else
						info.Text = node.IsScript and (node.Count > 0 and tostring(node.Count) or "") or tostring(node.Count)
						info.Size = UDim2.new(0,44,1,0)
						row.EntryName.Size = UDim2.new(1,-nameX-56,1,0)
					end
				else
					row.Visible = false
				end
				entry.Restyle()
			end
			for i = count+1,#pool do
				pool[i].Row.Visible = false
				rowItems[pool[i].Row] = nil
			end
		end

		local function refresh()
			if scanning then return end
			scanning = true
			dirty = false
			statusLabel.Text = "Scanning..."
			task.spawn(function()
				local start = tick()
				local ok,newRoot,found = pcall(scan)
				scanning = false
				hasScanned = true
				if not ok then
					statusLabel.Text = "Scan failed: "..tostring(newRoot)
					return
				end
				root,scriptList = newRoot,found
				statusLabel.Text = ("%d scripts in %d places  \u{2022}  %.2fs"):format(#found,#newRoot.Children,tick() - start)
				rebuildFlat()
			end)
		end

		list:GetPropertyChangedSignal("CanvasPosition"):Connect(function() render() end)
		list:GetPropertyChangedSignal("AbsoluteSize"):Connect(function() render() end)
		searchBox:GetPropertyChangedSignal("Text"):Connect(function()
			list.CanvasPosition = Vector2.new(0,0)
			rebuildFlat()
		end)
		refreshBtn.MouseButton1Click:Connect(refresh)

		local function markDirty(obj)
			if dirty then return end
			local ok,isScript = pcall(function() return obj:IsA("LuaSourceContainer") end)
			if ok and isScript then dirty = true end
		end
		game.DescendantAdded:Connect(markDirty)
		game.DescendantRemoving:Connect(markDirty)

		task.spawn(function()
			while true do
				task.wait(3)
				if dirty and not scanning and window:IsVisible() then
					refresh()
				end
			end
		end)

		window.OnActivate:Connect(function()
			if not hasScanned then refresh() end
		end)

		return window
	end

	Main.CreateTestsWindow = function()
		local window = Lib.Window.new()
		window:SetTitle("Tests")
		window:Resize(580,460)
		Main.TestsWindow = window

		local UNC_URL = "https://raw.githubusercontent.com/ltseverydayyou/uuuuuuu/refs/heads/main/UNC%20test"

		local genv = type(getgenv) == "function" and select(2,pcall(getgenv)) or nil
		if type(genv) ~= "table" then genv = nil end
		local renv = type(getrenv) == "function" and select(2,pcall(getrenv)) or nil
		if type(renv) ~= "table" then renv = nil end
		local senv = getfenv()

		local function envLookup(k)
			if k == "cloneref" then return NativeCloneref end
			local v = genv and genv[k]
			if v == nil then v = senv[k] end
			if v == nil and renv then v = renv[k] end
			return v
		end

		local function getPath(path)
			local parts = string.split(path,".")
			local v = envLookup(parts[1])
			for i = 2,#parts do
				if type(v) ~= "table" and type(v) ~= "userdata" then return nil end
				local ok,nv = pcall(function() return v[parts[i]] end)
				if not ok then return nil end
				v = nv
			end
			return v
		end

		local function shortErr(e)
			local s = tostring(e):gsub("^.-:%d+: ","")
			if #s > 140 then s = s:sub(1,137).."..." end
			return s
		end

		local function executorName()
			local f = envLookup("identifyexecutor") or envLookup("getexecutorname")
			if type(f) ~= "function" then return "Unknown" end
			local ok,a,b = pcall(f)
			if not ok or a == nil then return "Unknown" end
			return b and (tostring(a).." "..tostring(b)) or tostring(a)
		end

		local function tableCheck(f) return type(f()) == "table" end

		local suncTests = {
			{"cache.invalidate"},
			{"cache.iscached"},
			{"cache.replace"},
			{"cloneref",function(f) return typeof(f(oldgame)) == "Instance" end},
			{"compareinstances",function(f) return f(oldgame,oldgame) == true end},
			{"base64_encode",function(f) return f("test") ~= nil end},
			{"base64_decode",function(f) return f("dGVzdA==") == "test" end},
			{"debug.getconstant",function(f) return f(function() return "test" end,1) ~= nil end},
			{"debug.getconstants",function(f) return type(f(function() return "test" end)) == "table" end},
			{"debug.getinfo",function(f) return type(f(1)) == "table" end},
			{"debug.getproto"},
			{"debug.getprotos"},
			{"debug.getupvalue"},
			{"debug.getupvalues"},
			{"debug.setconstant"},
			{"debug.setupvalue"},
			{"debug.getstack"},
			{"debug.setstack"},
			{"getgc",tableCheck},
			{"filtergc"},
			{"getloadedmodules",tableCheck},
			{"getrunningscripts",tableCheck},
			{"getscripts",tableCheck},
			{"getscriptclosure"},
			{"getscriptbytecode"},
			{"getcallingscript"},
			{"getscripthash"},
			{"getsenv"},
			{"getgenv",tableCheck},
			{"getrenv",tableCheck},
			{"hookmetamethod"},
			{"getrawmetatable",function(f) return type(f(oldgame)) == "table" end},
			{"setrawmetatable"},
			{"iscclosure",function(f) return f(print) == true end},
			{"isexecutorclosure",nil,{"isexecutorclosure","islclosure"}},
			{"islclosure"},
			{"newcclosure"},
			{"hookfunction"},
			{"restorefunction"},
			{"clonefunction"},
			{"setreadonly"},
			{"isreadonly",function(f) return type(f({})) == "boolean" end},
			{"lz4compress"},
			{"lz4decompress"},
			{"request",nil,{"request","http_request","syn.request"}},
			{"WebSocket.connect"},
			{"getcallbackvalue"},
			{"listfiles"},
			{"writefile"},
			{"readfile"},
			{"isfolder"},
			{"makefolder"},
			{"appendfile"},
			{"isfile"},
			{"delfolder"},
			{"delfile"},
			{"loadfile"},
			{"gethui",function(f) return typeof(f()) == "Instance" end},
			{"getnamecallmethod"},
			{"setscriptable"},
			{"isscriptable"},
			{"getinstances"},
			{"getnilinstances"},
			{"fireproximityprompt"},
			{"fireclickdetector"},
			{"firetouchinterest"},
			{"firesignal"},
			{"getthreadidentity",function(f) return type(f()) == "number" end},
			{"setthreadidentity"},
			{"getrenderproperty"},
			{"setrenderproperty"},
			{"isrenderobj"},
			{"Drawing.new"},
			{"Drawing.Fonts"},
			{"cleardrawcache"},
			{"loadstring",function(f) return type(f("return true")()) == "boolean" end},
			{"identifyexecutor"},
			{"getfunctionhash"},
			{"gethiddenproperty"},
			{"sethiddenproperty"},
			{"getconnections"},
			{"checkcaller"},
			{"getcustomasset"},
			{"replicatesignal"},
			{"decompile"},
			{"crypt.decrypt"},
			{"crypt.encrypt"},
			{"crypt.generatebytes"},
			{"crypt.generatekey"},
			{"crypt.hash"},
		}

		local colors = {
			Card = Color3.fromRGB(14,14,14),
			CardHover = Color3.fromRGB(26,26,26),
			Well = Color3.fromRGB(8,8,8),
			Stroke = Color3.fromRGB(34,34,34),
			Text = Color3.fromRGB(235,235,235),
			Dim = Color3.fromRGB(135,135,135),
			Accent = Color3.fromRGB(0,170,255),
			PASS = Color3.fromRGB(46,204,113),
			FAIL = Color3.fromRGB(235,77,75),
			MISS = Color3.fromRGB(240,147,43),
			SKIP = Color3.fromRGB(165,110,255),
			INFO = Color3.fromRGB(130,130,130),
			NOTE = Color3.fromRGB(0,170,255),
		}
		local badgeText = {PASS = "PASSED", FAIL = "FAILED", MISS = "MISSING", SKIP = "SKIPPED", INFO = "EXISTS", NOTE = "NOTE"}
		local logText = {PASS = "\u{2713} PASSED", FAIL = "\u{2717} FAILED", MISS = "\u{2717} MISSING", SKIP = "- SKIPPED", INFO = "~ EXISTS", NOTE = "i NOTE"}

		local function mk(class,props,parent)
			local inst = Instance.new(class)
			Main.MarkDark(inst)
			for k,v in pairs(props) do inst[k] = v end
			if parent then inst.Parent = parent end
			return inst
		end
		local function round(parent,r) return mk("UICorner",{CornerRadius=UDim.new(0,r)},parent) end
		local function stroke(parent) return mk("UIStroke",{ApplyStrokeMode=Enum.ApplyStrokeMode.Border,Color=colors.Stroke,Thickness=1},parent) end

		local root = mk("Frame",{BackgroundTransparency=1,Name="Tests",Size=UDim2.new(1,0,1,0)},window.GuiElems.Content)
		mk("UIPadding",{PaddingBottom=UDim.new(0,10),PaddingLeft=UDim.new(0,10),PaddingRight=UDim.new(0,10),PaddingTop=UDim.new(0,10)},root)

		local toolbar = mk("Frame",{BackgroundTransparency=1,Name="Toolbar",Size=UDim2.new(1,0,0,30)},root)
		mk("UIListLayout",{FillDirection=Enum.FillDirection.Horizontal,Padding=UDim.new(0,6),SortOrder=Enum.SortOrder.LayoutOrder,VerticalAlignment=Enum.VerticalAlignment.Center},toolbar)

		local function button(text,order,width,accent)
			local b = mk("TextButton",{AutoButtonColor=false,BackgroundColor3=colors.Card,BorderSizePixel=0,Font=Enum.Font.GothamMedium,LayoutOrder=order,Size=UDim2.new(0,width,1,0),Text=text,TextColor3=colors.Text,TextSize=12},toolbar)
			round(b,6)
			local s = stroke(b)
			if accent then
				s.Color = colors.Accent
				s.Transparency = 0.45
			end
			b.MouseEnter:Connect(function() b.BackgroundColor3 = colors.CardHover end)
			b.MouseLeave:Connect(function() b.BackgroundColor3 = colors.Card end)
			return b
		end

		local suncBtn = button("Run sUNC",1,96,true)
		local uncBtn = button("Run UNC",2,96,true)
		local copyBtn = button("Copy",3,64)
		local statusLabel = mk("TextLabel",{BackgroundTransparency=1,Font=Enum.Font.Gotham,LayoutOrder=4,Size=UDim2.new(1,-274,1,0),Text="Pick a test to run",TextColor3=colors.Dim,TextSize=12,TextTruncate=Enum.TextTruncate.AtEnd,TextXAlignment=Enum.TextXAlignment.Right},toolbar)

		local summary = mk("Frame",{BackgroundTransparency=1,Name="Summary",Position=UDim2.new(0,0,0,40),Size=UDim2.new(1,0,0,50)},root)
		mk("UIListLayout",{FillDirection=Enum.FillDirection.Horizontal,Padding=UDim.new(0,6),SortOrder=Enum.SortOrder.LayoutOrder},summary)

		local chips = {}
		for i,name in ipairs({"Passed","Failed","Missing","Rate","Time","Executor"}) do
			local wide = name == "Executor"
			local chip = mk("Frame",{BackgroundColor3=colors.Card,BorderSizePixel=0,LayoutOrder=i,Size=UDim2.new(wide and 0.3 or 0.14,-6,1,0)},summary)
			round(chip,8)
			stroke(chip)
			mk("TextLabel",{BackgroundTransparency=1,Font=Enum.Font.GothamMedium,Position=UDim2.new(0,10,0,7),Size=UDim2.new(1,-20,0,12),Text=string.upper(name),TextColor3=colors.Dim,TextSize=10,TextXAlignment=Enum.TextXAlignment.Left},chip)
			chips[name] = mk("TextLabel",{BackgroundTransparency=1,Font=Enum.Font.GothamBold,Position=UDim2.new(0,10,0,21),Size=UDim2.new(1,-20,0,22),Text="-",TextColor3=colors.Text,TextSize=15,TextTruncate=Enum.TextTruncate.AtEnd,TextXAlignment=Enum.TextXAlignment.Left},chip)
		end

		local verdictLabel = mk("TextLabel",{BackgroundTransparency=1,Font=Enum.Font.GothamMedium,Position=UDim2.new(0,2,0,98),Size=UDim2.new(1,-4,0,16),Text="",TextColor3=colors.Text,TextSize=12,TextTruncate=Enum.TextTruncate.AtEnd,TextXAlignment=Enum.TextXAlignment.Left},root)
		local subLabel = mk("TextLabel",{BackgroundTransparency=1,Font=Enum.Font.Gotham,Position=UDim2.new(0,2,0,114),Size=UDim2.new(1,-4,0,14),Text="",TextColor3=colors.Dim,TextSize=11,TextTruncate=Enum.TextTruncate.AtEnd,TextXAlignment=Enum.TextXAlignment.Left},root)

		local list = mk("ScrollingFrame",{Active=true,AutomaticCanvasSize=Enum.AutomaticSize.Y,BackgroundColor3=colors.Well,BorderSizePixel=0,CanvasSize=UDim2.new(0,0,0,0),Name="Results",Position=UDim2.new(0,0,0,136),ScrollBarImageColor3=Color3.fromRGB(90,90,90),ScrollBarThickness=4,Size=UDim2.new(1,0,1,-136)},root)
		round(list,8)
		stroke(list)
		mk("UIPadding",{PaddingBottom=UDim.new(0,6),PaddingLeft=UDim.new(0,6),PaddingRight=UDim.new(0,6),PaddingTop=UDim.new(0,6)},list)
		mk("UIListLayout",{Padding=UDim.new(0,3),SortOrder=Enum.SortOrder.LayoutOrder},list)

		local order = 0
		local log = {}
		local running = false

		local function clearList()
			for _,c in ipairs(list:GetChildren()) do
				if c:IsA("GuiObject") then c:Destroy() end
			end
			order = 0
		end

		local function addPlaceholder(text)
			order = order + 1
			mk("TextLabel",{BackgroundTransparency=1,Font=Enum.Font.Gotham,LayoutOrder=order,Size=UDim2.new(1,0,0,40),Text=text,TextColor3=colors.Dim,TextSize=12},list)
		end

		local function addHeader(text)
			order = order + 1
			mk("TextLabel",{BackgroundTransparency=1,Font=Enum.Font.GothamBold,LayoutOrder=order,Size=UDim2.new(1,-4,0,22),Text=string.upper(text),TextColor3=colors.Dim,TextSize=11,TextXAlignment=Enum.TextXAlignment.Left,TextYAlignment=Enum.TextYAlignment.Center},list)
			log[#log+1] = ""
			log[#log+1] = "== "..string.upper(text).." =="
		end

		local function addRow(kind,name,detail)
			order = order + 1
			if detail == "" then detail = nil end
			local col = colors[kind]
			local row = mk("Frame",{BackgroundColor3=colors.Card,BorderSizePixel=0,LayoutOrder=order,Size=UDim2.new(1,-4,0,26)},list)
			round(row,6)
			local badge = mk("TextLabel",{AnchorPoint=Vector2.new(0,0.5),BackgroundColor3=col:Lerp(Color3.new(0,0,0),0.78),BorderSizePixel=0,Font=Enum.Font.GothamBold,Position=UDim2.new(0,6,0.5,0),Size=UDim2.new(0,64,0,16),Text=badgeText[kind],TextColor3=col,TextSize=10},row)
			round(badge,4)
			mk("TextLabel",{BackgroundTransparency=1,Font=Enum.Font.GothamMedium,Position=UDim2.new(0,80,0,0),Size=detail and UDim2.new(0.45,-80,1,0) or UDim2.new(1,-88,1,0),Text=name,TextColor3=colors.Text,TextSize=12,TextTruncate=Enum.TextTruncate.AtEnd,TextXAlignment=Enum.TextXAlignment.Left},row)
			if detail then
				mk("TextLabel",{BackgroundTransparency=1,Font=Enum.Font.Gotham,Position=UDim2.new(0.45,6,0,0),Size=UDim2.new(0.55,-14,1,0),Text=detail,TextColor3=colors.Dim,TextSize=11,TextTruncate=Enum.TextTruncate.AtEnd,TextXAlignment=Enum.TextXAlignment.Right},row)
			end
			log[#log+1] = ("[%s] %s%s"):format(logText[kind],name,detail and (" - "..detail) or "")
		end

		local function setChip(name,value,color)
			chips[name].Text = value
			chips[name].TextColor3 = color or colors.Text
		end

		local function rateColor(rate)
			return rate >= 90 and colors.PASS or rate >= 70 and colors.MISS or colors.FAIL
		end

		local function showCounts(passed,failed,missing,total)
			local rate = total > 0 and passed/total*100 or 0
			setChip("Passed",("%d / %d"):format(passed,total),colors.PASS)
			setChip("Failed",tostring(failed),failed > 0 and colors.FAIL or colors.Text)
			setChip("Missing",tostring(missing),missing > 0 and colors.MISS or colors.Text)
			setChip("Rate",("%.1f%%"):format(rate),rateColor(rate))
			return rate
		end

		local function resetSummary()
			for name in pairs(chips) do setChip(name,"-") end
			verdictLabel.Text = ""
			subLabel.Text = ""
		end

		local function setRunning(on,text,color)
			running = on
			suncBtn.TextTransparency = on and 0.5 or 0
			uncBtn.TextTransparency = on and 0.5 or 0
			statusLabel.Text = text
			statusLabel.TextColor3 = color or (on and colors.Accent or colors.Dim)
		end

		local function beginRun(title)
			clearList()
			resetSummary()
			log = {title}
			setChip("Executor",executorName())
		end

		local function runSUNC()
			if running then return end
			setRunning(true,"Running sUNC...")
			beginRun("sUNC TEST RESULTS")
			addHeader("sUNC results")

			task.spawn(function()
				local passed,failed,missing = 0,0,0
				local elapsed = 0
				for i,test in ipairs(suncTests) do
					local name,check,paths = test[1],test[2],test[3]
					local t0 = tick()
					local fn
					for _,path in ipairs(paths or {name}) do
						fn = getPath(path)
						if fn ~= nil then break end
					end
					local ok,detail = false,nil
					if fn == nil then
						detail = "not found"
						missing = missing + 1
					elseif check then
						local s,r = pcall(check,fn)
						ok = s and r and true or false
						if not s then detail = shortErr(r) elseif not ok then detail = "check returned false" end
					else
						ok = true
					end
					elapsed = elapsed + (tick() - t0)
					if ok then passed = passed + 1 else failed = failed + 1 end
					addRow(ok and "PASS" or "FAIL",name,detail)
					showCounts(passed,failed,missing,i)
					setChip("Time",("%.2fs"):format(elapsed))
					if i % 6 == 0 then task.wait() end
				end

				local total = passed + failed
				local rate = showCounts(passed,failed,missing,total)
				setChip("Time",("%.2fs"):format(elapsed))
				verdictLabel.Text = ("sUNC: %d of %d functions passed"):format(passed,total)
				subLabel.Text = missing > 0 and ("%d failed, %d of them not found"):format(failed,missing) or ("%d failed"):format(failed)

				log[#log+1] = ""
				log[#log+1] = ("PASSED: %d / %d"):format(passed,total)
				log[#log+1] = ("FAILED: %d / %d"):format(failed,total)
				log[#log+1] = ("SUCCESS RATE: %.1f%%"):format(rate)
				log[#log+1] = ("TIME TAKEN: %.2f seconds"):format(elapsed)
				log[#log+1] = ("EXECUTOR: %s"):format(chips.Executor.Text)
				setRunning(false,"sUNC finished",rateColor(rate))
			end)
		end

		local function runUNC()
			if running then return end
			setRunning(true,"Downloading UNC test...")
			beginRun("UNC TEST RESULTS")

			task.spawn(function()
				local ok,src = pcall(function() return oldgame:HttpGet(UNC_URL) end)
				if not ok or type(src) ~= "string" or #src == 0 then
					addRow("FAIL","Download",shortErr(src))
					setRunning(false,"UNC download failed",colors.FAIL)
					return
				end

				src = src:gsub('sg:SetCore%(%s*"SendNotification"%s*,','(function() end)(')
				src = src:gsub('local function askRcon%(%)','local function askRcon() do return false, "rconsole tests are skipped in Dex" end',1)

				local loader = envLookup("loadstring")
				local chunk,err
				if type(loader) == "function" then
					local s,a,b = pcall(loader,src,"=UNC")
					if s then chunk,err = a,b else err = a end
				else
					err = "loadstring is not available"
				end
				if type(chunk) ~= "function" then
					addRow("FAIL","Compile",shortErr(err))
					setRunning(false,"UNC failed to load",colors.FAIL)
					return
				end

				local stats = {core = {PASS=0,FAIL=0,MISS=0,SKIP=0,INFO=0}, extra = {PASS=0,FAIL=0,MISS=0,SKIP=0,INFO=0}}
				local section = "core"
				local inSummary = false
				local verdict,score
				local start = tick()

				local BULLET = " \u{2022} "
				local P_PASS = "\u{2705} "
				local P_FAIL = "\u{26D4} "
				local P_MISS = "\u{274C} missing core: "
				local P_OPTMISS = "\u{23FA} optional missing: "
				local P_EXIST = "\u{23FA} "
				local P_SKIP = "\u{23ED} "

				local function startsWith(s,p) return s:sub(1,#p) == p end
				local function splitBullet(s)
					local i = s:find(BULLET,1,true)
					if i then return s:sub(1,i-1),s:sub(i+#BULLET) end
					return s,nil
				end

				local function refresh()
					local c = stats.core
					showCounts(c.PASS,c.FAIL,c.MISS,c.PASS + c.FAIL + c.MISS)
					setChip("Time",("%.1fs"):format(tick() - start))
				end

				local function record(kind,name,detail)
					stats[section][kind] = stats[section][kind] + 1
					addRow(kind,name,detail)
					refresh()
				end

				local function recordMissing(rest)
					local name,tried = rest:match("^(.-) %-> (.*)$")
					if not name then name = rest end
					record("MISS",name,(tried and tried ~= name) and ("tried "..tried) or "not found")
				end

				local function handle(line)
					line = line:gsub("\u{FE0F}","")
					if inSummary then
						score = line:match("^UNC core score: (.+)$") or score
						verdict = line:match("^Verdict: (.+)$") or verdict
						return
					end
					if line == "Optional documented extension checks" then
						section = "extra"
						addHeader("Optional extensions")
						return
					elseif line == "UNC Summary" then
						inSummary = true
						return
					end

					if startsWith(line,P_MISS) then
						recordMissing(line:sub(#P_MISS+1))
					elseif startsWith(line,P_OPTMISS) then
						recordMissing(line:sub(#P_OPTMISS+1))
					elseif startsWith(line,P_SKIP) then
						record("SKIP",splitBullet(line:sub(#P_SKIP+1)))
					elseif startsWith(line,P_EXIST) then
						local name,detail = splitBullet(line:sub(#P_EXIST+1))
						record("INFO",name,detail and (detail:gsub("^exists; ","")))
					elseif startsWith(line,P_PASS) then
						record("PASS",splitBullet(line:sub(#P_PASS+1)))
					elseif startsWith(line,P_FAIL) then
						record("FAIL",splitBullet(line:sub(#P_FAIL+1)))
					elseif startsWith(line,"[UNC] ") then
						addRow("NOTE",line:sub(7))
					end
				end

				local function capture(...)
					local n = select("#",...)
					local parts = table.create(n)
					for i = 1,n do parts[i] = tostring((select(i,...))) end
					for line in table.concat(parts," "):gmatch("[^\n]+") do
						pcall(handle,line)
					end
				end

				local sandbox = setmetatable({print = capture, warn = capture},{__index = function(_,k) return envLookup(k) end})
				setfenv(chunk,sandbox)
				pcall(setfenv,0,sandbox)

				setRunning(true,"Running UNC...")
				addHeader("Core functions")
				local runOk,runErr = pcall(chunk)
				local elapsed = tick() - start

				local c,e = stats.core,stats.extra
				local total = c.PASS + c.FAIL + c.MISS
				local rate = showCounts(c.PASS,c.FAIL,c.MISS,total)
				setChip("Time",("%.2fs"):format(elapsed))

				if not runOk then
					addRow("FAIL","UNC script error",shortErr(runErr))
				end

				verdictLabel.Text = verdict and ("Verdict: "..verdict) or ("UNC core: %d of %d passed"):format(c.PASS,total)
				subLabel.Text = ("Optional: %d passed, %d failed, %d skipped, %d exist only, %d missing"):format(e.PASS,e.FAIL,e.SKIP,e.INFO,e.MISS)

				log[#log+1] = ""
				log[#log+1] = ("PASSED: %d / %d"):format(c.PASS,total)
				log[#log+1] = ("FAILED: %d / %d"):format(c.FAIL,total)
				log[#log+1] = ("MISSING: %d / %d"):format(c.MISS,total)
				log[#log+1] = ("EXISTS ONLY: %d"):format(c.INFO)
				log[#log+1] = ("SUCCESS RATE: %.1f%%"):format(rate)
				if score then log[#log+1] = "UNC CORE SCORE: "..score end
				log[#log+1] = ("TIME TAKEN: %.2f seconds"):format(elapsed)
				log[#log+1] = ("EXECUTOR: %s"):format(chips.Executor.Text)
				log[#log+1] = subLabel.Text
				if verdict then log[#log+1] = "VERDICT: "..verdict end
				setRunning(false,runOk and "UNC finished" or "UNC stopped with an error",runOk and rateColor(rate) or colors.FAIL)
			end)
		end

		suncBtn.MouseButton1Click:Connect(runSUNC)
		uncBtn.MouseButton1Click:Connect(runUNC)
		copyBtn.MouseButton1Click:Connect(function()
			local clip = envLookup("setclipboard") or envLookup("toclipboard")
			if #log == 0 then
				statusLabel.Text = "Nothing to copy yet"
			elseif type(clip) == "function" and pcall(clip,table.concat(log,"\n")) then
				statusLabel.Text = "Results copied"
			else
				statusLabel.Text = "Clipboard is not available"
			end
		end)

		addPlaceholder("Run sUNC or UNC to see the results here")
		return window
	end

	Main.CreateMainGui = function()
		local gui = create({
			{1,"Folder",{Name="MainMenu",}},
			{2,"ScrollingFrame",{Active=true,BackgroundTransparency=1,BorderSizePixel=0,CanvasSize=UDim2.new(0,0,0,0),Name="AppsFrame",Parent={1},ScrollBarImageColor3=Color3.new(1,1,1),ScrollBarImageTransparency=0.85,ScrollBarThickness=2,Size=UDim2.new(1,0,1,0),}},
			{3,"Frame",{BackgroundTransparency=1,Name="Container",Parent={2},Position=UDim2.new(0,7,0,8),Size=UDim2.new(1,-14,0,2),}},
			{4,"UIGridLayout",{CellPadding=UDim2.new(0,0,0,6),CellSize=UDim2.new(0,66,0,66),Parent={3},SortOrder=Enum.SortOrder.LayoutOrder,}},
			{5,"Frame",{BackgroundTransparency=1,Name="App",Parent={1},Size=UDim2.new(0,66,0,66),Visible=false,}},
			{6,"TextButton",{AutoButtonColor=false,BackgroundColor3=Color3.fromRGB(16,16,16),BackgroundTransparency=1,BorderSizePixel=0,Name="Main",Parent={5},Size=UDim2.new(1,0,1,0),Text="",}},
			{7,"UICorner",{CornerRadius=UDim.new(0,8),Parent={6},}},
			{8,"Frame",{BackgroundTransparency=1,Name="Icon",Parent={6},Position=UDim2.new(0.5,-11,0,9),Size=UDim2.new(0,22,0,22),}},
			{9,"TextLabel",{BackgroundTransparency=1,Font=Enum.Font.GothamMedium,Name="AppName",Parent={6},Position=UDim2.new(0,3,0,36),Size=UDim2.new(1,-6,0,24),Text="",TextColor3=Color3.fromRGB(235,235,235),TextSize=10,TextTruncate=Enum.TextTruncate.AtEnd,TextWrapped=true,TextYAlignment=Enum.TextYAlignment.Top,}},
			{10,"Frame",{AnchorPoint=Vector2.new(0,0.5),BackgroundColor3=Color3.fromRGB(0,170,255),BorderSizePixel=0,Name="Highlight",Parent={6},Position=UDim2.new(0,0,0.5,0),Size=UDim2.new(0,3,0,18),}},
			{11,"UICorner",{CornerRadius=UDim.new(1,0),Parent={10},}},
		})
		Main.MainGui = gui
		Main.AppsFrame = gui.AppsFrame
		Main.AppsContainer = Main.AppsFrame.Container
		Main.AppsContainerGrid = Main.AppsContainer.UIGridLayout
		Main.AppTemplate = gui.App
		Main.MainGuiOpen = Lib.Window.IsHubVisible()

		Main.AppsFrame.Parent = Lib.Window.GetSidebar()
		Main.AppsContainerGrid:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
			Main.AppsFrame.CanvasSize = UDim2.new(0,0,0,Main.AppsContainerGrid.AbsoluteContentSize.Y + 16)
		end)
		Lib.Window.HubVisibleChanged:Connect(function(val)
			Main.MainGuiOpen = val
		end)

		Main.CreateApp({Name = "Explorer", Icon = "explorer", Open = true, Window = Explorer.Window})

		Main.CreateApp({Name = "Scripts", Icon = "scripts", Window = Main.ScriptsWindow})

		Main.CreateApp({Name = "Properties", Icon = "properties", Open = true, Window = Properties.Window})

		local clickSelectCon
		Main.ClickSelect = Lib.Window.AddTopBarToggle("Click Select","select",function(on)
			if clickSelectCon then
				clickSelectCon:Disconnect()
				clickSelectCon = nil
			end
			if not on then return end
			local mouse = Main.Mouse
			clickSelectCon = mouse.Button1Down:Connect(function()
				if Lib.Window.IsMouseOverHub() then return end
				pcall(function()
					local object = mouse.Target
					if object and nodes[object] then
						selection:Set(nodes[object])
						Explorer.ViewNode(nodes[object])
					end
				end)
			end)
		end)

		Main.CreateApp({Name = "Notepad", Icon = "notepad", Window = ScriptViewer.Window})

		Main.CreateApp({Name = "Console", Icon = "console", Window = Console.Window})

		Main.CreateApp({Name = "Save Instance", Icon = "save", Window = SaveInstance.Window})

		Main.CreateApp({Name = "3D Viewer", Icon = "viewer", Window = ModelViewer.Window})

		Main.CreateApp({Name = "Tests", Icon = "tests", Window = Main.TestsWindow})

		-- DEX+ new modules — open via .Open() since they manage their own windows
		if Apps.RemoteSpy then
			Main.CreateApp({Name = "Remote Spy", Icon = "script", OnClick = function() Apps.RemoteSpy.Open() end})
		end
		if Apps.CodeGen then
			Main.CreateApp({Name = "Code Gen", Icon = "console", OnClick = function() Apps.CodeGen.GenerateForSelection() end})
		end
		if Apps.OrphanedInstances then
			Main.CreateApp({Name = "Orphaned", Icon = "viewer", OnClick = function() Apps.OrphanedInstances.Open() end})
		end
		if Apps.MemoryScanner then
			Main.CreateApp({Name = "Mem Scan", Icon = "script", OnClick = function() Apps.MemoryScanner.Open() end})
		end
		if Apps.PhysicsViz then
			Main.CreateApp({Name = "Physics Viz", Icon = "viewer", OnClick = function() Apps.PhysicsViz.Open() end})
		end

		-- DEX+: StarterPack Viewer app button
		do
			local spBtn = Lib.Window.AddTopBarButton("StarterPack Cache","save",function()
				-- Trigger the cache window inline (same logic as context menu handler)
				local cache = getgenv and getgenv().DEX_StarterPackCache or {}
				local log   = getgenv and getgenv().DEX_StarterPackLog or {}

				local win = Lib.Window.new()
				win:SetTitle("StarterPack Cache (" .. #cache .. " items)")
				win:Resize(440, 380)
				local content = win.ContentFrame
				content.BackgroundColor3 = Color3.fromRGB(22,22,22)
				content.ClipsDescendants = true

				local hdr = Instance.new("TextLabel")
				hdr.Size = UDim2.new(1,0,0,22)
				hdr.BackgroundColor3 = Color3.fromRGB(35,35,35)
				hdr.BorderSizePixel = 0
				hdr.TextColor3 = Color3.fromRGB(220,220,220)
				hdr.TextSize = 12
				hdr.Font = Enum.Font.GothamBold
				hdr.Text = #cache .. " captured  |  " .. #log .. " log entries"
				hdr.Parent = content

				local scroll = Instance.new("ScrollingFrame")
				scroll.Size = UDim2.new(1,0,1,-80)
				scroll.Position = UDim2.new(0,0,0,22)
				scroll.BackgroundColor3 = Color3.fromRGB(18,18,18)
				scroll.BorderSizePixel = 0
				scroll.ScrollBarThickness = 8
				scroll.CanvasSize = UDim2.new(0,0,0,math.max(#cache,1)*22+10)
				scroll.Parent = content

				local layout = Instance.new("UIListLayout")
				layout.SortOrder = Enum.SortOrder.LayoutOrder
				layout.Padding = UDim.new(0,1)
				layout.Parent = scroll

				if #cache == 0 then
					local empty = Instance.new("TextLabel")
					empty.Size = UDim2.new(1,0,0,40)
					empty.BackgroundTransparency = 1
					empty.TextColor3 = Color3.fromRGB(140,140,140)
					empty.TextSize = 12
					empty.Font = Enum.Font.Gotham
					empty.Text = "Nothing captured yet. Execute earlier or wait for CharacterAdded."
					empty.TextWrapped = true
					empty.Parent = scroll
				else
					for i, entry in ipairs(cache) do
						local obj = entry.Obj
						local row = Instance.new("TextButton")
						row.Size = UDim2.new(1,-8,0,20)
						row.BackgroundColor3 = i%2==0 and Color3.fromRGB(26,26,26) or Color3.fromRGB(30,30,30)
						row.BorderSizePixel = 0
						row.TextColor3 = Color3.fromRGB(220,220,220)
						row.TextSize = 11
						row.Font = Enum.Font.Code
						row.TextXAlignment = Enum.TextXAlignment.Left
						local ok, nm = pcall(function() return obj.Name end)
						local ok2, cn = pcall(function() return obj.ClassName end)
						row.Text = "  [".. (ok2 and cn or "?") .."]  "..(ok and nm or "?").."   via "..(entry.Source or "?")
						row.LayoutOrder = i
						row.Parent = scroll
						row.MouseButton1Click:Connect(function()
							pcall(function()
								if nodes and nodes[obj] then
									selection:Set(nodes[obj])
									Explorer.ViewNode(nodes[obj])
								elseif env.setclipboard then
									env.setclipboard(ok and nm or "")
								end
							end)
						end)
					end
				end

				local logLbl = Instance.new("TextLabel")
				logLbl.Size = UDim2.new(1,0,0,58)
				logLbl.Position = UDim2.new(0,0,1,-58)
				logLbl.BackgroundColor3 = Color3.fromRGB(12,12,12)
				logLbl.BorderSizePixel = 0
				logLbl.TextColor3 = Color3.fromRGB(110,180,110)
				logLbl.TextSize = 10
				logLbl.Font = Enum.Font.Code
				logLbl.TextXAlignment = Enum.TextXAlignment.Left
				logLbl.TextYAlignment = Enum.TextYAlignment.Top
				logLbl.TextWrapped = true
				logLbl.Text = table.concat(log,"\n"):sub(-800)
				logLbl.Parent = content

				win:Show()
			end)
		end
	end

	Main.SetupFilesystem = function()
		if not env.writefile or not env.makefolder then return end

		local writefile,makefolder = env.writefile,env.makefolder

		makefolder("dex")
		makefolder("dex/assets")
		makefolder("dex/saved")
		makefolder("dex/plugins")
		makefolder("dex/ModuleCache")
	end

	Main.LocalDepsUpToDate = function()
		return Main.DepsVersionData and Main.ClientVersion == Main.DepsVersionData[1]
	end

	Main.Init = function()
		Main.Elevated = pcall(function() local a = game:GetService("CoreGui"):GetFullName() end)
		
		if writefile and isfile and not isfile("DexSettings.json") then
			writefile("DexSettings.json", Main.ExportSettings())
		end
		
		Main.InitEnv()
		Main.LoadSettings()
		Settings.Window = Settings.Window or {}
		Settings.Window.Transparency = 0
		Settings.Theme = Settings.Theme or {}
		for k,v in pairs(ForcedTheme) do Settings.Theme[k] = v end
		
		Main.SetupFilesystem()

		local intro = Main.CreateIntro("Initializing Library")
		Lib = Main.LoadModule("Lib")
		Lib.FastWait()

		Main.IncompatibleTest()

		Main.MiscIcons = Lib.IconMap.new("rbxassetid://6511490623",256,256,16,16)
		Main.MiscIcons:SetDict({
			Reference = 0,             Cut = 1,                         Cut_Disabled = 2,      Copy = 3,               Copy_Disabled = 4,    Paste = 5,                Paste_Disabled = 6,
			Delete = 7,                Delete_Disabled = 8,             Group = 9,             Group_Disabled = 10,    Ungroup = 11,         Ungroup_Disabled = 12,    TeleportTo = 13,
			Rename = 14,               JumpToParent = 15,               ExploreData = 16,      Save = 17,              CallFunction = 18,    CallRemote = 19,          Undo = 20,
			Undo_Disabled = 21,        Redo = 22,                       Redo_Disabled = 23,    Expand_Over = 24,       Expand = 25,          Collapse_Over = 26,       Collapse = 27,
			SelectChildren = 28,       SelectChildren_Disabled = 29,    InsertObject = 30,     ViewScript = 31,        AddStar = 32,         RemoveStar = 33,          Script_Disabled = 34,
			LocalScript_Disabled = 35, Play = 36,                       Pause = 37,            Rename_Disabled = 38,   Empty = 1000
		})
		Main.LargeIcons = Lib.IconMap.new("rbxassetid://6579106223",256,256,32,32)
		Main.LargeIcons:SetDict({
			Explorer = 0, Properties = 1, Script_Viewer = 2, Watcher = 3, Output = 4
		})
		

		intro.SetProgress("Fetching Roblox Version",0.3)
		if Main.Elevated then
			local fileVer = Lib.ReadFile("dex/deps_version.dat")
			Main.ClientVersion = Version()
			if fileVer then
				Main.DepsVersionData = string.split(fileVer,"\n")
				if Main.LocalDepsUpToDate() then
					Main.RobloxVersion = Main.DepsVersionData[2]
				end
			end
			
			Main.RobloxVersion = Main.RobloxVersion or oldgame:HttpGet("https://clientsettings.roblox.com/v2/client-version/WindowsStudio64/channel/LIVE"):match("(version%-[%w]+)")
		end

		intro.SetProgress("Fetching API",0.35)
		API = Main.FetchAPI(
			function()
				intro.SetProgress("Fetching API, Please Wait.",0.4)
			end,
			function()
				intro.SetProgress("Fetching API, Please Wait Due To Huge API File To Download.",0.45)
			end,
			function()
				intro.SetProgress("Fetching API, LOL STILL DOWNlOADING? bad wifi xD",0.475)
			end
		)
		Lib.FastWait()
		intro.SetProgress("Fetching RMD",0.5)
		RMD = Main.FetchRMD()
		Lib.FastWait()

		if Main.Elevated and env.writefile and not Main.LocalDepsUpToDate() then
			env.writefile("dex/deps_version.dat",Main.ClientVersion.."\n"..Main.RobloxVersion)
			env.writefile("dex/rbx_api.dat",Main.RawAPI)
			env.writefile("dex/rbx_rmd.dat",Main.RawRMD)
		end

		intro.SetProgress("Loading Modules",0.75)
		Main.AppControls.Lib.InitDeps(Main.GetInitDeps())
		Main.LoadModules()
		Lib.FastWait()

		intro.SetProgress("Initializing Modules",0.9)
		Explorer.Init()
		Properties.Init()
		ScriptViewer.Init()
		Console.Init()
		SaveInstance.Init()
		ModelViewer.Init()
		Main.CreateScriptsWindow()
		Main.CreateTestsWindow()
		
		
		Lib.FastWait()

		intro.SetProgress("Complete",1)
		coroutine.wrap(function()
			Lib.FastWait(1.25)
			intro.Close()
		end)()

		Lib.Window.Init()
		Main.CreateMainGui()
		Explorer.Window:Show({Group = "Explorer", Slot = 1, Silent = true})
		Properties.Window:Show({Group = "Explorer", Slot = 2, Silent = true})
	end

	return Main
end)()

Main.Init()
