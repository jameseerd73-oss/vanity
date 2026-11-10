--[[
	API ---------------------------------------------------------------------------------------
	local window = Library.new("Window")  -- Args(<string> Name, <boolean?> ConstrainToScreen, <number?> Width,
	                                      --      <number?> Height, <string?> VisibilityToggleKey)
	window:LockScreenBoundaries(true)     -- Args(<boolean> ConstrainToScreen)
	local tab = window:Tab("Tab")         -- Args(<string> Name, <string?> TabImage)
	local section = tab:Section("Section")-- Args(<string> Name)

	Elements (on a tab, section, dropdown or search bar):
	  :Title(Name)                                   -> :ChangeText(NewText)
	  :Label(LabelText, TextSize?, TextColor?)       -> :ChangeText(NewText, PlayAnimation?)
	  :Toggle(Name, Callback(bool))                  -> :Set(bool, Callback?)  :Get()
	  :Button(Name, Callback())
	  :Dropdown(Name)                                -> a row that opens its own page; add elements to it
	  :Slider(Name, Callback(value), Max?, Min?, Step?) -> :Set(number)  :Get()
	  :SearchBar(PlaceholderText)                    -> add elements to it; typing filters them
	  :Keybind(Name, Callback(), DefaultKey?)        -> :Set("G" | "None")  :Get()
	  :TextBox(Name, Callback(text), Placeholder?)   -> :Set(text)  :Get()
	  :ColorWheel(Name, Callback(Color3), Default?)  -> :Set(Color3)  :Get()
	  Every element also has :ChangeText(text) and :Tooltip(text) (hint at the bottom of the screen).

	Extras:
	  :Section(Name) also works on dropdowns       dropdown:Tab(Name) gives a dropdown's page tabs
	  :Selector(Name, {Options}, Callback(option), Default?)   "< Option >" row
	  :PlayerDropdown(Name, Callback(player))      "< Player >" row
	  :PlayerList(Callback({players}))             tickable player list -> :GetSelected()
	  window:Notify(Title, Text?, "info"|"success"|"warning"|"error", Duration?)   (also Library:Notify)
	  window:SetFooter(Text)  window:SetBannerText(Text)  window:SetBanner("Smoke"|"Brush"|"Synthwave"|"Waves"|"Nebula"|"Stripes")
	  window:SetTheme("Purple"|"Blue"|"Cyan"|"Green"|"Yellow"|"Orange"|"Red"|"Pink")
	  window:SetToggleKey("F2")  window:SetKeyPrompt(false)  window:Toggle(open?)  window:IsOpen()
	  window:GetSelectedPlayers()  window:Destroy()
	  Library.Defaults.<Setting> = value before Library.new restyles the window (sizes, fonts, keys...)

	Controls ----------------------------------------------------------------------------------
	  Toggle key (F2) .. open / close; on launch the menu asks which key to use
	  Up / Down ........ move (hold to repeat)       Enter ..... activate / open
	  Left / Right ..... slider, selector, player; otherwise switch tabs
	  E / Q ............ next / previous tab         Backspace . back one page
	  F5 ............... give the highlighted toggle / button a keybind
	  Gamepad .......... D-pad, A = Enter, B = Back, RB / LB = tabs, R3 = open / close
	  Mouse ............ click rows, tabs, toggles, sliders; wheel moves the selection; drag the
	                     banner to move the window; scrollbar on long lists

	Player data comes from attributes on the Player (or their Character):
	  CharacterName, Phone, Radio, Job, Group, Armor (info card), ServerId (number before names),
	  InHouse = true (house icon), SpectatingUserId = <UserId watched> (Spectators list; set it on the server)
	Keybinds, theme and banner last for the session.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

-- "F2", "RightShift", Enum.KeyCode.G ... -> KeyCode (nil for nil / "None" / unknown names)
local function toKeyCode(key)
	if typeof(key) == "EnumItem" and key.EnumType == Enum.KeyCode then
		return key
	elseif type(key) == "string" and key ~= "" and string.lower(key) ~= "none" then
		local ok, keyCode = pcall(function()
			return Enum.KeyCode[key]
		end)
		return ok and keyCode or nil
	end
	return nil
end

--------------------------------------------------------------------------------
-- DEFAULTS (Library.Defaults - change these before Library.new to restyle every window)
--------------------------------------------------------------------------------
local DEFAULTS = {
	ToggleKey = Enum.KeyCode.F2, -- Library.new's VisibilityToggleKey argument overrides this
	ConstrainToScreen = true, -- keep the window inside the screen when it is dragged
	GamepadToggleKey = Enum.KeyCode.ButtonR3,
	TabNextKey = Enum.KeyCode.E,
	TabPrevKey = Enum.KeyCode.Q,

	BindKey = Enum.KeyCode.F5, -- press on a highlighted toggle / button to give it a keybind
	AskOpenKey = true, -- on launch, ask which key opens the menu (Enter confirms, Backspace keeps ToggleKey)
	TooltipOffset = 70, -- tooltip distance from the bottom of the screen
	PromptOffset = 120, -- open-key prompt distance from the bottom of the screen

	-- Font: Source Sans Semibold (same face as Enum.Font.SourceSansSemibold)
	FontFamily = "rbxasset://fonts/families/SourceSansPro.json",
	TextWeight = Enum.FontWeight.SemiBold,
	SmallTextWeight = Enum.FontWeight.SemiBold,
	TextSize = 17, -- rows, tabs, values
	SmallTextSize = 15, -- footer, section labels, player panel, HUD lists
	TitleTextSize = 18, -- page title

	-- HUD (notifications, keybind list, spectator list)
	NotifyDuration = 4,
	MaxNotifications = 5,
	HUDMargin = 20,

	-- Branding: swap in your own artwork / text
	BannerImage = "", -- "rbxassetid://..." full banner artwork ("" = built-in placeholder art)
	BannerLogoImage = "", -- "rbxassetid://..." logo centred on the banner
	BannerTitle = "MENU", -- text on the banner (Library.new's Name sets it)
	FooterText = "Build 1.0.0 | your.link/here", -- window:SetFooter changes it

	-- Geometry (unscaled pixels)
	Width = 380, -- Library.new's Width argument
	Height = 519, -- maximum window height (Library.new's Height argument); sets how many rows fit
	PanelWidth = 250,
	PanelGap = 10,
	RowHeight = 35,
	ScreenMargin = 48,

	-- Scaling
	BaseViewportHeight = 1080, -- viewport height at which the UI is drawn 1:1
	MinScale = 0.7,

	-- Behaviour
	RepeatDelay = 0.35, -- hold time before arrow keys repeat
	RepeatRate = 0.06, -- seconds between repeats
	TweenTime = 0.14,
	UnlockMouse = true, -- frees the cursor (first person / shift-lock) while open
	SelfTargetInStudio = true, -- solo Studio test: list yourself so player selectors can be previewed
	StudsToMeters = 0.28,

	-- Optional image ids for the player-info icons ("" = built-in drawn icons)
	Icons = {
		Character = "", Phone = "", Radio = "", Job = "", Group = "",
		Health = "", Armor = "", Distance = "", Vehicle = "", Weapon = "", Speed = "",
	},
}

local Library = { Defaults = DEFAULTS, Version = "1.0" }
local activeWindow = nil

--------------------------------------------------------------------------------
-- Library.new: builds the window (one at a time - a new one replaces the old one)
--------------------------------------------------------------------------------
function Library.new(name, constrainToScreen, width, height, visibilityToggleKey)
	if activeWindow then
		activeWindow:Destroy()
	end

	local CONFIG = table.clone(DEFAULTS)
	CONFIG.Icons = table.clone(DEFAULTS.Icons)
	if name ~= nil then
		CONFIG.BannerTitle = tostring(name)
	end
	if constrainToScreen ~= nil then
		CONFIG.ConstrainToScreen = constrainToScreen == true
	end
	CONFIG.Width = math.max(300, tonumber(width) or DEFAULTS.Width)
	CONFIG.Height = tonumber(height) or DEFAULTS.Height
	CONFIG.ToggleKey = toKeyCode(visibilityToggleKey) or DEFAULTS.ToggleKey
	-- rows that fit: height minus banner (114), title (31), tabs (29) and footer (30)
	CONFIG.MaxVisibleRows = math.max(3, math.floor((CONFIG.Height - 204) / CONFIG.RowHeight))

	local THEME = {
		Background = Color3.fromRGB(5, 5, 7),
		Panel = Color3.fromRGB(8, 8, 11),
		Secondary = Color3.fromRGB(13, 13, 18),
		Section = Color3.fromRGB(17, 17, 23),
		TabBar = Color3.fromRGB(9, 9, 12),
		Accent = Color3.fromRGB(122, 0, 255),
		AccentIcon = Color3.fromRGB(150, 74, 255),
		ToggleOn = Color3.fromRGB(140, 72, 255),
		ToggleOff = Color3.fromRGB(53, 56, 66),
		Track = Color3.fromRGB(44, 46, 54),
		Text = Color3.fromRGB(255, 255, 255),
		TextRow = Color3.fromRGB(226, 226, 230),
		TextSecondary = Color3.fromRGB(200, 200, 200),
		TextDisabled = Color3.fromRGB(119, 119, 119),
		Line = Color3.fromRGB(255, 255, 255),
		Health = Color3.fromRGB(86, 222, 112),
		Armor = Color3.fromRGB(74, 144, 255),
		Highlight = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(96, 0, 204)),
			ColorSequenceKeypoint.new(0.35, Color3.fromRGB(121, 12, 246)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(58, 0, 128)),
		}),
		TabGradient = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(128, 26, 255)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(84, 0, 178)),
		}),
		Danger = Color3.fromRGB(226, 64, 64),
		Warning = Color3.fromRGB(240, 170, 60),
		Success = Color3.fromRGB(86, 222, 112),
		House = Color3.fromRGB(70, 150, 255),
		Car = Color3.fromRGB(235, 80, 80),
		Arrow = Color3.fromRGB(236, 150, 72),
		StateOn = Color3.fromRGB(184, 140, 255),
		Small = Font.new(CONFIG.FontFamily, CONFIG.SmallTextWeight),
		Body = Font.new(CONFIG.FontFamily, CONFIG.TextWeight),
		Bold = Font.new(CONFIG.FontFamily, Enum.FontWeight.Bold),
		Heavy = Font.new(CONFIG.FontFamily, Enum.FontWeight.Heavy),
	}

	-- Colour themes (Settings > Theme). accent = lines and fills, highlight = selected row
	-- (dark enough for white text), light = icons and ON states.
	local THEMES = {
		{ name = "Purple", accent = Color3.fromRGB(122, 0, 255), highlight = Color3.fromRGB(121, 12, 246), light = Color3.fromRGB(150, 74, 255), toggle = Color3.fromRGB(140, 72, 255) },
		{ name = "Blue", accent = Color3.fromRGB(0, 112, 255), highlight = Color3.fromRGB(12, 96, 230), light = Color3.fromRGB(84, 156, 255) },
		{ name = "Cyan", accent = Color3.fromRGB(0, 196, 230), highlight = Color3.fromRGB(0, 128, 160), light = Color3.fromRGB(96, 218, 240) },
		{ name = "Green", accent = Color3.fromRGB(34, 200, 96), highlight = Color3.fromRGB(22, 138, 66), light = Color3.fromRGB(104, 222, 144) },
		{ name = "Yellow", accent = Color3.fromRGB(255, 204, 0), highlight = Color3.fromRGB(168, 128, 0), light = Color3.fromRGB(255, 218, 84) },
		{ name = "Orange", accent = Color3.fromRGB(255, 122, 0), highlight = Color3.fromRGB(200, 90, 0), light = Color3.fromRGB(255, 164, 84) },
		{ name = "Red", accent = Color3.fromRGB(232, 32, 52), highlight = Color3.fromRGB(184, 20, 40), light = Color3.fromRGB(244, 104, 114) },
		{ name = "Pink", accent = Color3.fromRGB(255, 56, 164), highlight = Color3.fromRGB(196, 30, 120), light = Color3.fromRGB(255, 124, 192) },
	}

	local themeHooks = {}
	-- runs fn now and again after every theme change (for UI that is built once and kept)
	local function themed(fn)
		table.insert(themeHooks, fn)
		fn()
	end

	local function applyTheme(index)
		local theme = THEMES[index] or THEMES[1]
		local function scaled(color, factor)
			return Color3.new(color.R * factor, color.G * factor, color.B * factor)
		end
		local highlight = theme.highlight
		THEME.Accent = theme.accent
		THEME.AccentIcon = theme.light
		THEME.ToggleOn = theme.toggle or theme.accent:Lerp(theme.light, 0.35)
		THEME.StateOn = theme.light:Lerp(Color3.new(1, 1, 1), 0.35)
		THEME.Arrow = theme.light
		THEME.Highlight = ColorSequence.new({
			ColorSequenceKeypoint.new(0, scaled(highlight, 0.8)),
			ColorSequenceKeypoint.new(0.35, highlight),
			ColorSequenceKeypoint.new(1, scaled(highlight, 0.48)),
		})
		THEME.TabGradient = ColorSequence.new({
			ColorSequenceKeypoint.new(0, highlight:Lerp(theme.light, 0.2)),
			ColorSequenceKeypoint.new(1, scaled(highlight, 0.7)),
		})
		THEME.BannerBase = scaled(highlight, 0.09)
		THEME.BannerMid = scaled(highlight, 0.72)
		THEME.BannerDark = scaled(highlight, 0.4)
		for _, hook in ipairs(themeHooks) do
			hook()
		end
	end
	applyTheme(1)

	-- Banner styles (Settings > Banner), drawn in the HEADER BANNER section
	local BANNERS = { "Smoke", "Brush", "Synthwave", "Waves", "Nebula", "Stripes" }
	if CONFIG.BannerImage ~= "" then
		table.insert(BANNERS, 1, "Custom Image")
	end

	--------------------------------------------------------------------------------
	-- CONSTANTS
	--------------------------------------------------------------------------------
	local ROW_H = CONFIG.RowHeight
	local BANNER_H = 112
	local HEADER_H = BANNER_H + 2
	local TITLE_H = 30
	local TABS_H = 28
	local FOOTER_H = 30
	local PANEL_ROW_H = 20
	local PANEL_X = CONFIG.Width + CONFIG.PanelGap
	local TOTAL_W = CONFIG.Width + CONFIG.PanelGap + CONFIG.PanelWidth
	local MAX_MENU_H = HEADER_H + TITLE_H + 1 + TABS_H + 1 + CONFIG.MaxVisibleRows * ROW_H + FOOTER_H
	local FULL = UDim.new(1, 0)

	--------------------------------------------------------------------------------
	-- UTILITIES
	--------------------------------------------------------------------------------
	local function new(className, props, children)
		local inst = Instance.new(className)
		if inst:IsA("GuiObject") then
			inst.BorderSizePixel = 0
		end
		if inst:IsA("GuiButton") then
			inst.AutoButtonColor = false
			inst.Selectable = false
		end
		local parent
		for key, value in pairs(props or {}) do
			if key == "Parent" then
				parent = value
			else
				inst[key] = value
			end
		end
		for _, child in ipairs(children or {}) do
			child.Parent = inst
		end
		if parent then
			inst.Parent = parent
		end
		return inst
	end

	local function corner(inst, radius)
		return new("UICorner", { CornerRadius = radius, Parent = inst })
	end

	local function styled(className, props)
		if props.BackgroundTransparency == nil then
			props.BackgroundTransparency = 1
		end
		if props.FontFace == nil then
			props.FontFace = THEME.Body
		end
		if props.TextSize == nil then
			props.TextSize = CONFIG.TextSize
		end
		if props.TextColor3 == nil then
			props.TextColor3 = THEME.Text
		end
		return new(className, props)
	end

	local function label(props)
		return styled("TextLabel", props)
	end

	local State = { values = {}, defaults = {} }

	function State.get(key, fallback)
		local value = State.values[key]
		if value == nil then
			return fallback
		end
		return value
	end

	function State.set(key, value)
		State.values[key] = value
	end

	function State.register(key, default)
		State.defaults[key] = default
		if State.values[key] == nil then
			State.values[key] = default
		end
	end

	local function animationsOn()
		return State.get("settings.animations", true) ~= false
	end

	local function tween(inst, props, duration, onDone)
		if not animationsOn() or duration == 0 then
			for key, value in pairs(props) do
				inst[key] = value
			end
			if onDone then
				task.defer(onDone)
			end
			return nil
		end
		local info = TweenInfo.new(duration or CONFIG.TweenTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		local tw = TweenService:Create(inst, info, props)
		if onDone then
			tw.Completed:Once(onDone)
		end
		tw:Play()
		return tw
	end

	-- short display name for a key (KeypadSeven -> pad7, LeftShift -> LShift)
	local keyName
	do
		local DIGITS = {
			Zero = "0", One = "1", Two = "2", Three = "3", Four = "4",
			Five = "5", Six = "6", Seven = "7", Eight = "8", Nine = "9",
		}
		local SHORT_KEYS = {
			LeftShift = "LShift", RightShift = "RShift", LeftControl = "LCtrl", RightControl = "RCtrl",
			LeftAlt = "LAlt", RightAlt = "RAlt", CapsLock = "Caps", PageUp = "PgUp", PageDown = "PgDn",
			Insert = "Ins", KeypadPlus = "pad+", KeypadMinus = "pad-", KeypadMultiply = "pad*",
			KeypadDivide = "pad/", KeypadPeriod = "pad.", ButtonX = "Pad X", ButtonY = "Pad Y",
			ButtonL2 = "LT", ButtonR2 = "RT", ButtonL3 = "LS", ButtonR3 = "RS",
		}

		function keyName(keyCode)
			local name = keyCode.Name
			if SHORT_KEYS[name] then
				return SHORT_KEYS[name]
			end
			local padDigit = string.match(name, "^Keypad(%a+)$")
			if padDigit and DIGITS[padDigit] then
				return "pad" .. DIGITS[padDigit] -- KeypadSeven -> pad7
			end
			return DIGITS[name] or name
		end
	end

	local function shorten(str, maxChars)
		local length = utf8.len(str)
		if not length or length <= maxChars then
			return str
		end
		local cut = utf8.offset(str, maxChars)
		return string.sub(str, 1, cut - 1) .. "…"
	end

	local connections = {}
	local function connect(signal, fn)
		local connection = signal:Connect(fn)
		table.insert(connections, connection)
		return connection
	end

	-- runs an element's callback without letting an error (or a yield) break the menu
	local function emit(item, ...)
		local callback = item.callback
		if type(callback) ~= "function" then
			return
		end
		local args = table.pack(...)
		task.spawn(function()
			local ok, err = pcall(callback, table.unpack(args, 1, args.n))
			if not ok then
				warn(("[PurpleUI] %q callback error: %s"):format(tostring(item.label), tostring(err)))
			end
		end)
	end

	--------------------------------------------------------------------------------
	-- NAVIGATION STATE + PLAYER TARGETS
	--------------------------------------------------------------------------------
	local Nav = { stack = {}, isOpen = false, target = nil, toggleKey = CONFIG.ToggleKey, constrain = CONFIG.ConstrainToScreen, askKey = CONFIG.AskOpenKey, destroyed = false, customPos = nil }
	local current = { view = nil, list = nil }
	local Popup = nil

	local function currentEntry()
		return Nav.stack[#Nav.stack]
	end

	-- forward declarations (assigned further down)
	local renderPage, mountList, switchTab, activate, moveSelection, goBack, pushPage
	local updateSelection, updatePanel, applyLayout, setOpen, refreshRows
	local openPopup, closePopup, popupMove, popupConfirm
	local selectRow, setToggle, applySlider, stepSelector, stepPlayer, selectorChanged, pulse
	local notify, refreshKeybindList, refreshSpectators, refreshHUD, resetHUDPositions
	local togglePlayer, activateItem, modalOpen, setSearch
	local rebuildBanner, openKeyPrompt, bindToggle, updateTooltip
	local keybindName, openBinder, selectionChanged

	local departing = {}

	local function getTargets()
		local list = {}
		for _, player in ipairs(Players:GetPlayers()) do
			if player ~= LocalPlayer and not departing[player] then
				table.insert(list, player)
			end
		end
		table.sort(list, function(a, b)
			local an, bn = string.lower(a.DisplayName), string.lower(b.DisplayName)
			if an == bn then
				return a.UserId < b.UserId
			end
			return an < bn
		end)
		if #list == 0 and CONFIG.SelfTargetInStudio and RunService:IsStudio() then
			table.insert(list, LocalPlayer)
		end
		return list
	end

	local function isTarget(player)
		return player ~= nil and table.find(getTargets(), player) ~= nil
	end

	-- Players ticked in Online > List. Options that act on players run once per ticked player.
	local Selected = {} -- [Player] = order in which it was ticked
	local selectCounter = 0

	local function isSelected(player)
		return Selected[player] ~= nil
	end

	local function setSelected(player, on)
		if on then
			selectCounter += 1
			Selected[player] = selectCounter
		else
			Selected[player] = nil
		end
	end

	local function selectedPlayers()
		local list = {}
		for _, player in ipairs(getTargets()) do
			if Selected[player] then
				table.insert(list, player)
			end
		end
		return list
	end

	-- the most recently ticked player that is still in the server
	local function focusTarget()
		local best, bestOrder
		for player, order in pairs(Selected) do
			if isTarget(player) and (not bestOrder or order > bestOrder) then
				best, bestOrder = player, order
			end
		end
		return best
	end

	local function getSharedTarget()
		if not isTarget(Nav.target) then
			Nav.target = focusTarget() or getTargets()[1]
		end
		return Nav.target
	end

	local function playerId(player)
		return tostring(player:GetAttribute("ServerId") or player.UserId)
	end

	local function playerStatus(player)
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local seat = humanoid and humanoid.SeatPart
		return {
			inVehicle = seat ~= nil and seat:IsA("VehicleSeat"),
			inHouse = player:GetAttribute("InHouse") == true,
		}
	end

	-- players matching a player-list search (name, display name or id)
	local function filteredPlayers(query)
		query = string.lower(query or "")
		local list = {}
		for _, player in ipairs(getTargets()) do
			if query == ""
				or string.find(string.lower(player.DisplayName), query, 1, true)
				or string.find(string.lower(player.Name), query, 1, true)
				or string.find(playerId(player), query, 1, true)
			then
				table.insert(list, player)
			end
		end
		return list
	end

	local function getItemTarget(item)
		if item.shared then
			return getSharedTarget()
		end
		local player = State.values[item.key]
		if not isTarget(player) then
			player = getTargets()[1]
			State.values[item.key] = player
		end
		return player
	end

	--------------------------------------------------------------------------------
	-- ITEM CONSTRUCTORS
	--------------------------------------------------------------------------------
	local Item = {}

	function Item.submenu(text, page)
		return { kind = "submenu", label = text, page = page }
	end

	function Item.toggle(text, key, default, opts)
		opts = opts or {}
		State.register(key, default == true)
		return { kind = "toggle", label = text, key = key, onChange = opts.onChange, silent = opts.silent }
	end

	function Item.slider(text, key, opts)
		State.register(key, opts.default or opts.min)
		return {
			kind = "slider", label = text, key = key, min = opts.min, max = opts.max,
			step = opts.step or 1, format = opts.format or "%d", onChange = opts.onChange, silent = opts.silent,
		}
	end

	function Item.selector(text, key, options, opts)
		opts = opts or {}
		State.register(key, opts.default or 1)
		return {
			kind = "selector", label = text, key = key, options = options, dropdown = opts.dropdown,
			onChange = opts.onChange, silent = opts.silent,
			run = opts.run, -- Enter runs run(optionText) instead of opening the option list
		}
	end

	-- a row that opens a text box on Enter: a search bar (filters the rows under it) or a TextBox element
	function Item.search(text, key, placeholder, isSearch)
		State.register(key, "")
		return { kind = "input", label = text, key = key, placeholder = placeholder or "", isSearch = isSearch ~= false }
	end

	-- "< PlayerName >" selector; all of them share one target, which follows the last ticked player
	function Item.player(text)
		return { kind = "player", label = text, key = "target:" .. text, shared = true }
	end

	function Item.action(text, opts)
		opts = opts or {}
		return { kind = "action", label = text, run = opts.run }
	end

	-- read-only "Label  value" row; value may be a function. opts.run makes Enter do something.
	function Item.value(text, value, opts)
		return { kind = "value", label = text, value = value, run = opts and opts.run }
	end

	-- one option of a pick-one group (themes, banners): ON when State[key] == index
	function Item.choice(text, key, index, opts)
		opts = opts or {}
		State.register(key, 1)
		return { kind = "choice", label = text, key = key, index = index, swatch = opts.swatch, onChange = opts.onChange }
	end

	function Item.divider(text)
		return { kind = "divider", label = text }
	end

	function Item.playerEntry(player)
		return { kind = "playerEntry", label = player.DisplayName, player = player, key = "player:" .. player.UserId }
	end

	--------------------------------------------------------------------------------
	-- PAGES
	--------------------------------------------------------------------------------
	local Pages = {}

	-- Tooltips for the built-in Settings tab (elements set theirs with :Tooltip(text))
	local TIPS = {
		["Menu Key"] = "Press Enter to choose a different key for opening the menu",
		["Keybind Key"] = "Press this on a toggle or button to give it a keybind",
		["settings.wrap"] = "When on: going past the last row jumps back to the first",
		["settings.restore"] = "When on: the menu reopens where you left it",
		["settings.animations"] = "When on: the menu fades and slides",
		["settings.notifications"] = "When on: shows messages at the top of the screen",
		["settings.tooltips"] = "When on: shows hints like this one",
		["settings.keybindList"] = "When on: shows your keybinds on screen",
		["settings.spectatorList"] = "When on: shows who is spectating you",
		["settings.panel"] = "When on: shows player info next to the menu",
		["settings.scale"] = "Makes the menu bigger or smaller",
		["settings.position"] = "Moves the menu to the left, centre or right",
		["Reset Settings"] = "Puts every setting back to default",
	}

	local function themeChanged()
		applyTheme(State.get("settings.theme", 1))
		renderPage(0) -- rebuild the open page in the new colours
		refreshHUD()
		updatePanel()
	end

	local settingsItems = {
		Item.divider("General"),
		Item.value("Menu Key", function()
			return keyName(Nav.toggleKey)
		end, {
			run = function()
				openKeyPrompt()
			end,
		}),
		Item.value("Keybind Key", keyName(CONFIG.BindKey)),
		Item.toggle("Wrap Navigation", "settings.wrap", true, { silent = true }),
		Item.toggle("Restore Last Page", "settings.restore", true, { silent = true }),
		Item.toggle("Animations", "settings.animations", true, { silent = true }),
		Item.toggle("Notifications", "settings.notifications", true, { silent = true }),
		Item.toggle("Tooltips", "settings.tooltips", true, {
			silent = true,
			onChange = function()
				updateTooltip()
			end,
		}),
		Item.divider("Interface"),
		Item.toggle("Keybind List", "settings.keybindList", true, {
			silent = true,
			onChange = function()
				refreshKeybindList()
			end,
		}),
		Item.toggle("Spectator List", "settings.spectatorList", true, {
			silent = true,
			onChange = function()
				refreshSpectators()
			end,
		}),
		Item.toggle("Player Info Panel", "settings.panel", true, {
			silent = true,
			onChange = function()
				updatePanel()
			end,
		}),
		Item.slider("UI Scale", "settings.scale", {
			min = 70, max = 140, step = 5, default = 100, format = "%d%%", silent = true,
			onChange = function()
				applyLayout(false)
			end,
		}),
		Item.selector("Menu Position", "settings.position", { "Left", "Center", "Right" }, {
			dropdown = true, silent = true,
			onChange = function()
				Nav.customPos = nil -- forget a dragged position
				applyLayout(true)
			end,
		}),
		Item.divider("Theme"),
	}
	for index, theme in ipairs(THEMES) do
		table.insert(settingsItems, Item.choice(theme.name, "settings.theme", index, { swatch = theme.accent, onChange = themeChanged }))
	end
	table.insert(settingsItems, Item.divider("Banner"))
	for index, style in ipairs(BANNERS) do
		table.insert(settingsItems, Item.choice(style, "settings.banner", index, {
			onChange = function()
				rebuildBanner()
			end,
		}))
	end
	table.insert(settingsItems, Item.divider("Reset"))
	table.insert(settingsItems, Item.action("Reset Settings", {
		run = function()
			for key, default in pairs(State.defaults) do
				if string.sub(key, 1, 9) == "settings." then
					State.values[key] = default
				end
			end
			Nav.customPos = nil
			applyLayout(true)
			resetHUDPositions()
			themeChanged() -- also redraws the banner and the open page
			notify("Settings", "All settings are back to default", "info")
		end,
	}))

	-- Root page: the window's tabs (added with window:Tab) followed by the built-in Settings tab.
	-- Its title shows the selected tab's name.
	local settingsTab = { name = "Settings", items = settingsItems }
	Pages.main = {
		title = function(entry)
			local tab = entry.page.tabs[entry.tab]
			return tab and tab.name or CONFIG.BannerTitle
		end,
		tabs = { settingsTab },
	}

	-- player lists (section:PlayerList) whose callbacks hear about selection changes
	local playerLists = {}
	selectionChanged = function()
		local selected = selectedPlayers()
		for _, list in ipairs(playerLists) do
			emit(list.item, selected)
		end
	end

	local function bulkAction(option, players)
		if option == "Select All" then
			for _, player in ipairs(players) do
				if not isSelected(player) then
					setSelected(player, true)
				end
			end
			notify("Selection", ("Selected %d player%s"):format(#players, #players == 1 and "" or "s"), "info")
		else
			table.clear(Selected)
			notify("Selection", "Selection cleared", "info")
		end
		refreshRows(true)
		updatePanel()
		selectionChanged()
	end

	--------------------------------------------------------------------------------
	-- SCREEN + MAIN WINDOW
	--------------------------------------------------------------------------------
	local existing = PlayerGui:FindFirstChild("PurpleUI")
	if existing then
		existing:Destroy()
	end

	local screen = new("ScreenGui", {
		Name = "PurpleUI",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 100,
		Enabled = false,
		Parent = PlayerGui,
	})

	-- A modal button frees the mouse cursor while the menu is open
	new("TextButton", {
		Name = "MouseUnlock", Text = "", BackgroundTransparency = 1,
		Size = UDim2.fromOffset(1, 1), Modal = CONFIG.UnlockMouse, Parent = screen,
	})

	local root = new("Frame", {
		Name = "MenuRoot", BackgroundTransparency = 1,
		Size = UDim2.fromOffset(TOTAL_W, MAX_MENU_H), Parent = screen,
	})
	local uiScale = new("UIScale", { Parent = root })
	local holder = new("Frame", { Name = "Holder", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = root })

	local menuFrame = new("Frame", {
		Name = "MainMenu", BackgroundTransparency = 1,
		Size = UDim2.fromOffset(CONFIG.Width, 480), Parent = holder,
	})
	corner(menuFrame, UDim.new(0, 6))
	local menuStroke = new("UIStroke", { Color = THEME.Line, Transparency = 1, Thickness = 1, Parent = menuFrame })

	local menuCanvas = new("CanvasGroup", {
		Name = "Canvas", BackgroundColor3 = THEME.Background, BackgroundTransparency = 0.12,
		Size = UDim2.fromScale(1, 1), GroupTransparency = 1, Parent = menuFrame,
	})
	corner(menuCanvas, UDim.new(0, 6))

	--------------------------------------------------------------------------------
	-- DRAWING HELPERS (vector icons and shapes built from frames)
	--------------------------------------------------------------------------------
	local Draw = {} -- frame-drawn icons / shapes, shared by the panel, rows and HUD
	do
		local function shape(parent, cx, cy, w, h, color, radius, rotation, transparency)
			local f = new("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(cx, cy), Size = UDim2.fromOffset(w, h),
				BackgroundColor3 = color, BackgroundTransparency = transparency or 0, Rotation = rotation or 0, Parent = parent,
			})
			if radius then
				corner(f, radius)
			end
			return f
		end

		local function ring(parent, cx, cy, d, color, thickness)
			local f = shape(parent, cx, cy, d, d, color, FULL, 0, 1)
			new("UIStroke", { Color = color, Thickness = thickness, Parent = f })
			return f
		end

		-- Tiny vector icons drawn from frames (14x14). Override with CONFIG.Icons image ids.
		local IconDraw = {
			person = function(p, c)
				shape(p, 7, 4, 6, 6, c, FULL)
				shape(p, 7, 11.5, 11, 5, c, UDim.new(0, 3))
			end,
			phone = function(p, c)
				shape(p, 7, 7, 8, 13, c, UDim.new(0, 2))
				shape(p, 7, 11, 2, 2, THEME.Section, FULL)
			end,
			radio = function(p, c)
				shape(p, 7, 7, 4, 4, c, FULL)
				ring(p, 7, 7, 12, c, 1.5)
			end,
			job = function(p, c)
				local handle = shape(p, 7, 3.5, 6, 4, c, UDim.new(0, 1), 0, 1)
				new("UIStroke", { Color = c, Thickness = 1.5, Parent = handle })
				shape(p, 7, 9, 13, 8, c, UDim.new(0, 2))
			end,
			group = function(p, c)
				shape(p, 10, 4, 5, 5, c, FULL, 0, 0.45)
				shape(p, 10.5, 10.5, 7, 5, c, UDim.new(0, 2), 0, 0.45)
				shape(p, 5.5, 5, 5, 5, c, FULL)
				shape(p, 5.5, 11.5, 9, 5, c, UDim.new(0, 2))
			end,
			heart = function(p, c)
				shape(p, 4.6, 5.4, 6.4, 6.4, c, FULL)
				shape(p, 9.4, 5.4, 6.4, 6.4, c, FULL)
				shape(p, 7, 8.2, 6.6, 6.6, c, nil, 45)
			end,
			shield = function(p, c)
				shape(p, 7, 4.5, 11, 6, c, UDim.new(0, 2))
				shape(p, 7, 7.6, 7.8, 7.8, c, nil, 45)
			end,
			crosshair = function(p, c)
				ring(p, 7, 7, 10, c, 1.5)
				shape(p, 7, 7, 3, 3, c, FULL)
				shape(p, 7, 0.8, 1.5, 3, c)
				shape(p, 7, 13.2, 1.5, 3, c)
				shape(p, 0.8, 7, 3, 1.5, c)
				shape(p, 13.2, 7, 3, 1.5, c)
			end,
			car = function(p, c)
				shape(p, 7, 5, 7, 4.5, c, UDim.new(0, 2))
				shape(p, 7, 8.6, 13, 5, c, UDim.new(0, 2))
				shape(p, 3.8, 11.8, 3.4, 3.4, c, FULL)
				shape(p, 10.2, 11.8, 3.4, 3.4, c, FULL)
			end,
			weapon = function(p, c)
				shape(p, 7.5, 5, 12, 3.5, c, UDim.new(0, 1))
				shape(p, 4.4, 9.2, 3.6, 7, c, UDim.new(0, 1), 14)
			end,
			gauge = function(p, c)
				ring(p, 7, 7, 12, c, 1.5)
				shape(p, 9.1, 4.9, 1.6, 6, c, FULL, 45)
				shape(p, 7, 7, 3, 3, c, FULL)
			end,
			house = function(p, c)
				shape(p, 7, 5.6, 8.4, 8.4, c, nil, 45)
				shape(p, 7, 10, 10, 7, c)
				shape(p, 7, 11.5, 3, 4, THEME.Background)
			end,
			eye = function(p, c)
				local outline = shape(p, 7, 7, 13, 8, c, FULL, 0, 1)
				new("UIStroke", { Color = c, Thickness = 1.5, Parent = outline })
				shape(p, 7, 7, 4.5, 4.5, c, FULL)
			end,
			keyboard = function(p, c)
				shape(p, 7, 7, 14, 10, c, UDim.new(0, 2))
				for i = 0, 2 do
					shape(p, 3.5 + i * 3.5, 5, 2, 2, THEME.Panel)
				end
				shape(p, 7, 9.5, 8, 1.5, THEME.Panel)
			end,
		}

		-- up / down arrow (spectator list), drawn from frames so it doesn't depend on font glyphs
		local function drawArrow(parent, up, color, x, y)
			local box = new("Frame", {
				Name = up and "ArrowUp" or "ArrowDown", BackgroundTransparency = 1, Position = UDim2.fromOffset(x, y),
				Size = UDim2.fromOffset(10, 14), Rotation = up and 0 or 180, Parent = parent,
			})
			shape(box, 5, 8, 2, 11, color)
			shape(box, 3.25, 3.75, 2, 5, color, nil, 45)
			shape(box, 6.75, 3.75, 2, 5, color, nil, -45)
			return box
		end

		-- color is a Color3, or a THEME key (e.g. "AccentIcon") to follow theme changes
		local function makeIcon(parent, name, kind, color, x, y)
			local box = new("Frame", { Name = name .. "Icon", BackgroundTransparency = 1, Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(14, 14), Parent = parent })
			local image = CONFIG.Icons[name]
			local function paint()
				box:ClearAllChildren()
				local c = type(color) == "string" and THEME[color] or color
				if image and image ~= "" then
					new("ImageLabel", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Image = image, ImageColor3 = c, Parent = box })
				else
					IconDraw[kind](box, c)
				end
			end
			if type(color) == "string" then
				themed(paint)
			else
				paint()
			end
			return box
		end

		-- the menu's own mark: a diamond outline around a solid diamond
		local function emblem(parent, size, color)
			local box = new("Frame", { Name = "Emblem", BackgroundTransparency = 1, Size = UDim2.fromOffset(size, size), Parent = parent })
			local outer = new("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.66, 0.66),
				Rotation = 45, BackgroundTransparency = 1, Parent = box,
			})
			new("UIStroke", { Color = color, Thickness = math.max(1.5, size * 0.075), Parent = outer })
			new("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.28, 0.28),
				Rotation = 45, BackgroundColor3 = color, Parent = box,
			})
			return box
		end

		-- small ^ chevron (scrollbar arrows); up = false points it down
		local function chevron(parent, up, color)
			local box = new("Frame", {
				Name = "Chevron", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(10, 10), Rotation = up and 0 or 180, Parent = parent,
			})
			shape(box, 3.4, 5, 1.6, 5.5, color, nil, 45)
			shape(box, 6.6, 5, 1.6, 5.5, color, nil, -45)
			return box
		end

		Draw.shape, Draw.ring, Draw.icons, Draw.arrow, Draw.icon = shape, ring, IconDraw, drawArrow, makeIcon
		Draw.emblem, Draw.chevron = emblem, chevron
	end

	--------------------------------------------------------------------------------
	-- HEADER BANNER
	--------------------------------------------------------------------------------
	local banner = new("Frame", {
		Name = "Banner", BackgroundColor3 = THEME.BannerBase,
		Size = UDim2.new(1, 0, 0, BANNER_H), ClipsDescendants = true, Parent = menuCanvas,
	})

	-- Banner styles (Settings > Banner). All are drawn from frames in the theme colours;
	-- set CONFIG.BannerImage to add your own artwork as "Custom Image".
	do
		local W, H = CONFIG.Width, BANNER_H
		local WHITE = Color3.new(1, 1, 1)

		local function nk(t, v)
			return NumberSequenceKeypoint.new(t, v)
		end
		local function fade(frame, keypoints, rotation)
			new("UIGradient", { Rotation = rotation or 0, Transparency = NumberSequence.new(keypoints), Parent = frame })
		end
		local function blob(cx, cy, d, color, transparency)
			local f = new("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(cx, cy), Size = UDim2.fromOffset(d, d),
				BackgroundColor3 = color, BackgroundTransparency = transparency or 0, Parent = banner,
			})
			corner(f, FULL)
			return f
		end
		-- soft glow: stacked translucent circles approximate a radial gradient
		local function glow(cx, cy, r, color, strength)
			for step = 1, 6 do
				blob(cx, cy, r * 2 * (1 - (step - 1) * 0.14), color, 1 - (strength or 0.12))
			end
		end
		-- straight line between two points (Rotation turns around the frame's centre)
		local function line(x1, y1, x2, y2, thickness, color, transparency)
			local dx, dy = x2 - x1, y2 - y1
			return new("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset((x1 + x2) / 2, (y1 + y2) / 2),
				Size = UDim2.fromOffset(thickness, math.sqrt(dx * dx + dy * dy)), Rotation = math.deg(math.atan2(-dx, dy)),
				BackgroundColor3 = color, BackgroundTransparency = transparency or 0, Parent = banner,
			})
		end
		local function darkEdges()
			local sides = new("Frame", { Name = "Vignette", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), ZIndex = 3, Parent = banner })
			fade(sides, { nk(0, 0.15), nk(0.22, 1), nk(0.78, 1), nk(1, 0.15) })
			local vertical = new("Frame", { Name = "Vignette", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), ZIndex = 3, Parent = banner })
			fade(vertical, { nk(0, 0.55), nk(0.3, 1), nk(0.75, 1), nk(1, 0.35) }, 90)
		end
		-- the title (or CONFIG.BannerLogoImage), optionally with the emblem in front of it
		local function wordmark(font, size, opts)
			opts = opts or {}
			if CONFIG.BannerLogoImage ~= "" then
				new("ImageLabel", {
					Name = "Logo", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
					Size = UDim2.fromOffset(86, 86), BackgroundTransparency = 1, Image = CONFIG.BannerLogoImage,
					ScaleType = Enum.ScaleType.Fit, ZIndex = 5, Parent = banner,
				})
				return
			end
			local logo = new("Frame", {
				Name = "Logo", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(0.5, 0, 0.5, opts.y or 0), Size = UDim2.fromOffset(0, H), AutomaticSize = Enum.AutomaticSize.X,
				ZIndex = 5, Parent = banner,
			})
			new("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center,
				VerticalAlignment = Enum.VerticalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder,
				Padding = UDim.new(0, 12), Parent = logo,
			})
			if opts.emblem then
				local mark = Draw.emblem(logo, 54, WHITE)
				mark.LayoutOrder = 1
			end
			local title = label({
				Name = "Title", LayoutOrder = 2, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, H),
				Text = CONFIG.BannerTitle, FontFace = font, TextSize = size, Parent = logo,
			})
			new("UIStroke", {
				Color = opts.glow or Color3.new(0, 0, 0), Transparency = opts.glow and 0.35 or 0.55,
				Thickness = opts.glow and 3 or 2, Parent = title,
			})
		end

		local STYLES = {}

		STYLES.Smoke = function(p)
			local rng = Random.new(1337)
			glow(W * 0.28, H * 0.55, 120, p.mid)
			glow(W * 0.74, H * 0.35, 110, p.light)
			glow(W * 0.52, H * 1.05, 150, p.dark)
			local centres = { Vector2.new(W * 0.30, H * 0.55), Vector2.new(W * 0.70, H * 0.45), Vector2.new(W * 0.50, H * 0.20) }
			for i = 1, 46 do
				local centre = centres[(i % #centres) + 1]
				local radius = rng:NextNumber(18, 95)
				local angle = rng:NextNumber(0, math.pi * 2)
				local brightness = rng:NextNumber()
				local strand = new("Frame", {
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromOffset(centre.X + math.cos(angle) * radius * 1.35, centre.Y + math.sin(angle) * radius * 0.55),
					Size = UDim2.fromOffset(rng:NextNumber(40, 150), rng:NextNumber(1.5, 7)),
					Rotation = math.deg(math.atan2(math.cos(angle) * 0.55, -math.sin(angle) * 1.35)),
					BackgroundColor3 = p.mid:Lerp(p.pale, brightness * brightness), Parent = banner,
				})
				corner(strand, FULL)
				fade(strand, { nk(0, 1), nk(0.5, rng:NextNumber(0.35, 0.8)), nk(1, 1) })
			end
			darkEdges()
			wordmark(THEME.Heavy, 40)
		end

		-- slanted paint strokes with the emblem next to a marker-pen title
		STYLES.Brush = function(p)
			local rng = Random.new(7)
			glow(W * 0.5, H * 0.5, 150, p.dark, 0.1)
			for i = 1, 10 do
				local stroke = new("Frame", {
					AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(rng:NextNumber(0, W), rng:NextNumber(8, H - 8)),
					Size = UDim2.fromOffset(rng:NextNumber(160, 320), rng:NextNumber(8, 26)), Rotation = rng:NextNumber(-16, -6),
					BackgroundColor3 = (i % 3 == 0) and p.light or p.mid, Parent = banner,
				})
				corner(stroke, FULL)
				fade(stroke, { nk(0, 1), nk(0.15, rng:NextNumber(0.45, 0.75)), nk(0.85, rng:NextNumber(0.55, 0.85)), nk(1, 1) })
			end
			for _ = 1, 18 do
				blob(rng:NextNumber(0, W), rng:NextNumber(0, H), rng:NextNumber(2, 6), p.light, rng:NextNumber(0.4, 0.8))
			end
			darkEdges()
			wordmark(Font.fromEnum(Enum.Font.PermanentMarker), 46, { emblem = true })
		end

		-- retro sun over a perspective grid
		STYLES.Synthwave = function(p)
			local horizon = math.floor(H * 0.64)
			local sky = new("Frame", { Name = "Sky", Size = UDim2.new(1, 0, 0, horizon), BackgroundColor3 = p.mid, Parent = banner })
			fade(sky, { nk(0, 0.9), nk(1, 0.35) }, 90)
			local radius, cx = 46, W / 2
			for y = -radius, 0, 3 do -- sun drawn in slices so the lower half can have gaps
				local stripe = y > -radius * 0.45 and ((y // 3) % 2 == 0)
				if not stripe then
					local half = math.sqrt(math.max(radius * radius - y * y, 0))
					new("Frame", {
						AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(cx, horizon + y - 2), Size = UDim2.fromOffset(half * 2, 3),
						BackgroundColor3 = p.pale:Lerp(p.accent, (y + radius) / radius), Parent = banner,
					})
				end
			end
			local ground = new("Frame", {
				Name = "Ground", Position = UDim2.fromOffset(0, horizon), Size = UDim2.new(1, 0, 1, -horizon),
				BackgroundColor3 = p.base, Parent = banner,
			})
			ground.ZIndex = 1
			for i = 1, 6 do
				local y = horizon + (H - horizon) * (i / 6) ^ 1.7
				new("Frame", {
					Position = UDim2.fromOffset(0, y), Size = UDim2.new(1, 0, 0, 1), BackgroundColor3 = p.light,
					BackgroundTransparency = 0.35 + i * 0.05, ZIndex = 2, Parent = banner,
				})
			end
			for i = -9, 9 do
				local l = line(cx + i * 7, horizon, cx + i * 58, H + 4, 1, p.light, 0.45)
				l.ZIndex = 2
			end
			local horizonLine = new("Frame", {
				Position = UDim2.fromOffset(0, horizon), Size = UDim2.new(1, 0, 0, 2), BackgroundColor3 = p.light, ZIndex = 2, Parent = banner,
			})
			fade(horizonLine, { nk(0, 1), nk(0.5, 0), nk(1, 1) })
			darkEdges()
			wordmark(Font.fromEnum(Enum.Font.Michroma), 30, { glow = p.accent, y = -20 })
		end

		-- rolling waves
		STYLES.Waves = function(p)
			local back = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = p.dark, Parent = banner })
			fade(back, { nk(0, 0.25), nk(1, 0.9) }, 90)
			local waves = {
				{ x = 0.18, crest = 0.42, d = 420, color = p.mid, t = 0.55 },
				{ x = 0.95, crest = 0.5, d = 380, color = p.mid, t = 0.45 },
				{ x = 0.6, crest = 0.62, d = 560, color = p.dark, t = 0.3 },
				{ x = 0.3, crest = 0.8, d = 620, color = p.base, t = 0.1 },
			}
			for _, wave in ipairs(waves) do
				local cy = H * wave.crest + wave.d / 2
				blob(W * wave.x, cy, wave.d, wave.color, wave.t)
				local rim = blob(W * wave.x, cy, wave.d, wave.color, 1)
				new("UIStroke", { Color = p.light, Transparency = 0.5, Thickness = 1.5, Parent = rim })
			end
			darkEdges()
			wordmark(Font.new(Font.fromEnum(Enum.Font.Oswald).Family, Enum.FontWeight.Bold), 44)
		end

		-- stars and coloured gas
		STYLES.Nebula = function(p)
			local rng = Random.new(42)
			glow(W * 0.25, H * 0.4, 110, p.mid, 0.14)
			glow(W * 0.72, H * 0.65, 130, p.dark, 0.16)
			glow(W * 0.55, H * 0.15, 80, p.light, 0.1)
			for _ = 1, 70 do
				blob(rng:NextNumber(0, W), rng:NextNumber(0, H), rng:NextNumber(1, 2.6), WHITE, rng:NextNumber(0.1, 0.7))
			end
			for _ = 1, 5 do
				local x, y = rng:NextNumber(20, W - 20), rng:NextNumber(10, H - 10)
				for _, size in ipairs({ Vector2.new(1, 9), Vector2.new(9, 1) }) do
					new("Frame", {
						AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(size.X, size.Y),
						BackgroundColor3 = p.pale, Parent = banner,
					})
				end
			end
			darkEdges()
			wordmark(Font.new(Font.fromEnum(Enum.Font.TitilliumWeb).Family, Enum.FontWeight.Bold), 42)
		end

		-- diagonal stripes
		STYLES.Stripes = function(p)
			local back = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE, Parent = banner })
			new("UIGradient", { Color = ColorSequence.new(p.mid, p.base), Rotation = 20, Parent = back })
			for i = -6, 16 do
				local x = i * 30
				line(x, -20, x + 70, H + 20, 12, p.light, (i % 2 == 0) and 0.82 or 0.9)
			end
			darkEdges()
			wordmark(Font.new(Font.fromEnum(Enum.Font.Sarpanch).Family, Enum.FontWeight.Bold), 44)
		end

		STYLES["Custom Image"] = function()
			new("ImageLabel", {
				Name = "Artwork", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1),
				Image = CONFIG.BannerImage, ScaleType = Enum.ScaleType.Crop, Parent = banner,
			})
			wordmark(THEME.Heavy, 40)
		end

		rebuildBanner = function()
			banner:ClearAllChildren()
			banner.BackgroundColor3 = THEME.BannerBase
			local style = BANNERS[State.get("settings.banner", 1)] or BANNERS[1]
			STYLES[style]({
				base = THEME.BannerBase, mid = THEME.BannerMid, dark = THEME.BannerDark, accent = THEME.Accent,
				light = THEME.AccentIcon, pale = THEME.AccentIcon:Lerp(WHITE, 0.55),
			})
		end
		themed(rebuildBanner)

		local bannerLine = new("Frame", {
			Name = "BannerLine", Position = UDim2.fromOffset(0, BANNER_H), Size = UDim2.new(1, 0, 0, 2),
			BackgroundColor3 = THEME.Accent, ZIndex = 3, Parent = menuCanvas,
		})
		themed(function()
			bannerLine.BackgroundColor3 = THEME.Accent
		end)
	end

	--------------------------------------------------------------------------------
	-- PAGE HOST, POPUP LAYER, FOOTER
	--------------------------------------------------------------------------------
	local pageHost = new("Frame", {
		Name = "PageHost", BackgroundTransparency = 1, ClipsDescendants = true,
		Position = UDim2.fromOffset(0, HEADER_H), Size = UDim2.new(1, 0, 1, -(HEADER_H + FOOTER_H)),
		ZIndex = 2, Parent = menuCanvas,
	})

	local popupLayer = new("Frame", {
		Name = "PopupLayer", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 50, Parent = menuCanvas,
	})

	local footer = new("Frame", {
		Name = "Footer", AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, FOOTER_H), BackgroundColor3 = THEME.Background, ZIndex = 5, Parent = menuCanvas,
	})
	do
		local footerLine = new("Frame", { Name = "FooterLine", Size = UDim2.new(1, 0, 0, 2), BackgroundColor3 = THEME.Accent, Parent = footer })
		themed(function()
			footerLine.BackgroundColor3 = THEME.Accent
		end)
	end
	label({
		Name = "BuildText", Position = UDim2.fromOffset(14, 2), Size = UDim2.new(1, -100, 1, -2),
		Text = CONFIG.FooterText, TextSize = CONFIG.SmallTextSize, FontFace = THEME.Small,
		TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Parent = footer,
	})
	local counterLabel = label({
		Name = "Counter", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 2),
		Size = UDim2.new(0, 80, 1, -2), Text = "1 / 1", TextSize = CONFIG.SmallTextSize, FontFace = THEME.Bold,
		TextXAlignment = Enum.TextXAlignment.Right, Parent = footer,
	})

	--------------------------------------------------------------------------------
	-- PLAYER INFO PANEL (floating card to the right of the menu)
	--------------------------------------------------------------------------------

	local Panel = { target = nil, shown = false, token = 0 }
	do
		local panelFrame = new("Frame", {
			Name = "PlayerInfo", BackgroundTransparency = 1, Visible = false,
			Position = UDim2.fromOffset(PANEL_X, 0), Size = UDim2.fromOffset(CONFIG.PanelWidth, 314), Parent = holder,
		})
		corner(panelFrame, UDim.new(0, 6))
		local panelStroke = new("UIStroke", { Color = THEME.Line, Transparency = 1, Thickness = 1, Parent = panelFrame })
		local panelCanvas = new("CanvasGroup", {
			Name = "Canvas", BackgroundColor3 = Color3.fromRGB(6, 6, 8), BackgroundTransparency = 0.08,
			Size = UDim2.fromScale(1, 1), GroupTransparency = 1, Parent = panelFrame,
		})
		corner(panelCanvas, UDim.new(0, 6))

		local panelHeader = new("Frame", { Name = "Header", BackgroundColor3 = Color3.fromRGB(16, 16, 21), Size = UDim2.new(1, 0, 0, 30), Parent = panelCanvas })
		local panelName = label({
			Name = "PlayerName", Position = UDim2.fromOffset(14, 0), Size = UDim2.new(1, -120, 1, 0), Text = "",
			FontFace = THEME.Bold, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Parent = panelHeader,
		})
		local panelId = label({
			Name = "PlayerId", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 0), Size = UDim2.fromOffset(100, 30),
			Text = "", TextSize = CONFIG.SmallTextSize, TextXAlignment = Enum.TextXAlignment.Right, Parent = panelHeader,
		})
		local panelLine = new("Frame", { Name = "AccentLine", Position = UDim2.fromOffset(0, 30), Size = UDim2.new(1, 0, 0, 2), BackgroundColor3 = THEME.Accent, Parent = panelCanvas })
		themed(function()
			panelLine.BackgroundColor3 = THEME.Accent
		end)

		local function panelSection(name, y, rows)
			local sectionFrame = new("Frame", {
				Name = name, Position = UDim2.fromOffset(8, y), Size = UDim2.new(1, -16, 0, rows * PANEL_ROW_H + 10),
				BackgroundColor3 = THEME.Section, BackgroundTransparency = 0.15, Parent = panelCanvas,
			})
			corner(sectionFrame, UDim.new(0, 4))
			return sectionFrame
		end

		local function infoRow(sectionFrame, index, text, iconName, iconKind, iconColor, labelX)
			local y = 5 + (index - 1) * PANEL_ROW_H
			Draw.icon(sectionFrame, iconName, iconKind, iconColor, 8, y + 3)
			label({
				Name = text, Position = UDim2.fromOffset(labelX or 30, y), Size = UDim2.fromOffset(90, PANEL_ROW_H),
				Text = text, TextSize = CONFIG.SmallTextSize, TextXAlignment = Enum.TextXAlignment.Left, Parent = sectionFrame,
			})
			return label({
				Name = text .. "Value", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -8, 0, y),
				Size = UDim2.new(1, -124, 0, PANEL_ROW_H), Text = "-", TextSize = CONFIG.SmallTextSize,
				TextXAlignment = Enum.TextXAlignment.Right, TextTruncate = Enum.TextTruncate.AtEnd, Parent = sectionFrame,
			})
		end

		local function statBar(sectionFrame, index, color)
			local y = 5 + (index - 1) * PANEL_ROW_H
			local track = new("Frame", {
				Position = UDim2.fromOffset(28, y + 3), Size = UDim2.fromOffset(3, 14),
				BackgroundColor3 = Color3.fromRGB(45, 45, 52), Parent = sectionFrame,
			})
			return new("Frame", {
				AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.fromScale(1, 1),
				BackgroundColor3 = color, Parent = track,
			})
		end

		local PanelFields = {}
		do
			local identity = panelSection("Identity", 40, 5)
			PanelFields.Character = infoRow(identity, 1, "Character", "Character", "person", "AccentIcon")
			PanelFields.Phone = infoRow(identity, 2, "Phone", "Phone", "phone", "AccentIcon")
			PanelFields.Radio = infoRow(identity, 3, "Radio", "Radio", "radio", "AccentIcon")
			PanelFields.Job = infoRow(identity, 4, "Job", "Job", "job", "AccentIcon")
			PanelFields.Group = infoRow(identity, 5, "Group", "Group", "group", "AccentIcon")

			local vitals = panelSection("HealthArmor", 158, 2)
			PanelFields.Health = infoRow(vitals, 1, "Health", "Health", "heart", THEME.Health, 40)
			PanelFields.Armor = infoRow(vitals, 2, "Armor", "Armor", "shield", THEME.Armor, 40)
			PanelFields.HealthBar = statBar(vitals, 1, THEME.Health)
			PanelFields.ArmorBar = statBar(vitals, 2, THEME.Armor)

			local details = panelSection("Details", 216, 4)
			PanelFields.Distance = infoRow(details, 1, "Distance", "Distance", "crosshair", "AccentIcon")
			PanelFields.Vehicle = infoRow(details, 2, "Vehicle", "Vehicle", "car", "AccentIcon")
			PanelFields.Weapon = infoRow(details, 3, "Weapon", "Weapon", "weapon", "AccentIcon")
			PanelFields.Speed = infoRow(details, 4, "Speed", "Speed", "gauge", "AccentIcon")
		end
		Panel.frame, Panel.stroke, Panel.canvas = panelFrame, panelStroke, panelCanvas
		Panel.nameLabel, Panel.idLabel, Panel.fields = panelName, panelId, PanelFields
	end

	--------------------------------------------------------------------------------
	-- COMPONENTS
	--------------------------------------------------------------------------------
	local function createToggle(parent, rightInset, onClick)
		local pill = new("TextButton", {
			Name = "Toggle", Text = "", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -rightInset, 0.5, 0),
			Size = UDim2.fromOffset(40, 22), BackgroundColor3 = THEME.ToggleOff, ZIndex = 2, Parent = parent,
		})
		corner(pill, FULL)
		local knob = new("Frame", {
			Name = "Knob", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 4, 0.5, 0),
			Size = UDim2.fromOffset(14, 14), BackgroundColor3 = Color3.new(1, 1, 1), Parent = pill,
		})
		corner(knob, FULL)
		if onClick then
			pill.Activated:Connect(onClick)
		end
		local toggle = { Frame = pill }
		function toggle.set(on, animate)
			local color = on and THEME.ToggleOn or THEME.ToggleOff
			local position = on and UDim2.new(1, -18, 0.5, 0) or UDim2.new(0, 4, 0.5, 0)
			if animate then
				tween(pill, { BackgroundColor3 = color }, 0.14)
				tween(knob, { Position = position }, 0.14)
			else
				pill.BackgroundColor3 = color
				knob.Position = position
			end
		end
		return toggle
	end

	local function createSlider(parent)
		local hit = new("TextButton", {
			Name = "Slider", Text = "", BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -16, 0.5, 0), Size = UDim2.fromOffset(88, 24), ZIndex = 2, Parent = parent,
		})
		local track = new("Frame", {
			Name = "Track", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(0, 0.5),
			Size = UDim2.new(1, 0, 0, 5), BackgroundColor3 = THEME.Track, Parent = hit,
		})
		corner(track, FULL)
		local fill = new("Frame", { Name = "Fill", Size = UDim2.fromScale(0, 1), BackgroundColor3 = THEME.Accent, Parent = track })
		corner(fill, FULL)
		local knob = new("Frame", {
			Name = "Knob", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0, 0.5),
			Size = UDim2.fromOffset(11, 11), BackgroundColor3 = Color3.new(1, 1, 1), ZIndex = 2, Parent = track,
		})
		corner(knob, FULL)
		local valueLabel = label({
			Name = "Value", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(0, -10, 0.5, 0),
			Size = UDim2.fromOffset(80, 20), Text = "", TextXAlignment = Enum.TextXAlignment.Right, Parent = hit,
		})
		local slider = { Hit = hit, Track = track, Fill = fill }
		function slider.set(ratio, valueText, animate)
			valueLabel.Text = valueText
			local fillSize = UDim2.fromScale(ratio, 1)
			local knobPosition = UDim2.fromScale(ratio, 0.5)
			if animate then
				tween(fill, { Size = fillSize }, 0.08)
				tween(knob, { Position = knobPosition }, 0.08)
			else
				fill.Size = fillSize
				knob.Position = knobPosition
			end
		end
		return slider
	end

	-- "‹ Value ›" selector used for option selectors, dropdowns and player targets
	local function createSelector(parent, rightInset, onStep)
		local box = new("Frame", {
			Name = "Selector", BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -rightInset, 0.5, 0), Size = UDim2.fromOffset(0, 24),
			AutomaticSize = Enum.AutomaticSize.X, ZIndex = 2, Parent = parent,
		})
		new("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 4), Parent = box,
		})
		local function arrowButton(glyph, order, dir)
			local button = styled("TextButton", {
				Name = dir < 0 and "Previous" or "Next", LayoutOrder = order, Size = UDim2.fromOffset(14, 24),
				Text = glyph, TextSize = 22, TextColor3 = THEME.TextSecondary, Parent = box,
			})
			button.Activated:Connect(function()
				onStep(dir)
			end)
		end
		arrowButton("‹", 1, -1)
		local value = label({
			Name = "Value", LayoutOrder = 2, AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, 24), Text = "", Parent = box,
		})
		arrowButton("›", 3, 1)
		return { Frame = box, Value = value }
	end

	local function makeHighlight(parent, height)
		local highlight = new("Frame", {
			Name = "Highlight", BackgroundColor3 = Color3.new(1, 1, 1), Size = UDim2.new(1, 0, 0, height),
			Visible = false, ZIndex = 1, Parent = parent,
		})
		corner(highlight, UDim.new(0, 2))
		new("UIGradient", { Color = THEME.Highlight, Parent = highlight })
		new("Frame", {
			Name = "Sheen", Size = UDim2.new(1, 0, 0, 1), BackgroundColor3 = Color3.fromRGB(196, 150, 255),
			BackgroundTransparency = 0.5, Parent = highlight,
		})
		new("Frame", {
			Name = "Pulse", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1),
			BackgroundTransparency = 1, Parent = highlight,
		})
		return highlight
	end

	local INSTANT = {
		submenu = true, toggle = true, action = true, playerEntry = true, input = true, choice = true, keybind = true, color = true,
	}

	-- 18px status icon for player rows (the 14px vector icons scaled up)
	local function rowIcon(parent, name, kind, color, order)
		local holder = new("Frame", {
			Name = name, BackgroundTransparency = 1, LayoutOrder = order, Size = UDim2.fromOffset(18, 18),
			Visible = false, Parent = parent,
		})
		local inner = new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(14, 14), Parent = holder })
		new("UIScale", { Scale = 18 / 14, Parent = inner })
		Draw.icons[kind](inner, color)
		return holder
	end

	local function rowKey(item)
		if item.kind == "choice" then
			return item.key .. ":" .. item.index -- options of one group share a key
		end
		return item.key or item.label
	end

	local function buildRow(list, item, index)
		local y = (index - 1) * ROW_H
		local row: { [string]: any } = { item = item, list = list, selectable = false }
		row.refresh = function(_animate: boolean?) end
		row.setSelected = function(_selected: boolean) end

		if item.kind == "divider" then
			local frame = new("Frame", {
				Name = "Divider", BackgroundTransparency = 1, Position = UDim2.fromOffset(0, y),
				Size = UDim2.new(1, 0, 0, ROW_H), ZIndex = 2, Parent = list.Content,
			})
			new("UIPadding", { PaddingLeft = UDim.new(0, 18), PaddingRight = UDim.new(0, 18), Parent = frame })
			new("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center,
				VerticalAlignment = Enum.VerticalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder,
				Padding = UDim.new(0, 14), Parent = frame,
			})
			for order = 1, 3, 2 do
				local line = new("Frame", {
					LayoutOrder = order, Size = UDim2.new(0, 0, 0, 1), BackgroundColor3 = THEME.Line,
					BackgroundTransparency = 0.4, Parent = frame,
				})
				new("UIFlexItem", { FlexMode = Enum.UIFlexMode.Fill, Parent = line })
			end
			label({
				LayoutOrder = 2, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromScale(0, 1),
				Text = item.label, TextSize = CONFIG.SmallTextSize, TextColor3 = THEME.TextSecondary, Parent = frame,
			})
			row.Frame = frame
			return row
		end

		if item.kind == "title" or item.kind == "label" then
			local isTitle = item.kind == "title"
			local textLabel = label({
				Name = isTitle and "TitleRow" or "LabelRow", Position = UDim2.fromOffset(16, y), Size = UDim2.new(1, -32, 0, ROW_H),
				Text = item.label, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
				FontFace = isTitle and THEME.Bold or THEME.Body, ZIndex = 2, Parent = list.Content,
				TextSize = isTitle and CONFIG.TitleTextSize or (item.size or CONFIG.SmallTextSize + 1),
				TextColor3 = isTitle and THEME.Text or (item.color or THEME.TextSecondary),
			})
			if item.animate then -- label:ChangeText(text, true) types the new text out
				item.animate = nil
				textLabel.MaxVisibleGraphemes = 0
				tween(textLabel, { MaxVisibleGraphemes = utf8.len(item.label) or #item.label }, 0.35)
			end
			row.Frame = textLabel
			return row
		end

		if item.kind == "colorPreview" then
			local holder = new("Frame", {
				Name = "ColorPreview", BackgroundTransparency = 1, Position = UDim2.fromOffset(0, y),
				Size = UDim2.new(1, 0, 0, ROW_H), ZIndex = 2, Parent = list.Content,
			})
			local swatch = new("Frame", {
				Name = "Swatch", Position = UDim2.fromOffset(16, 6), Size = UDim2.new(1, -116, 1, -12), Parent = holder,
			})
			corner(swatch, UDim.new(0, 4))
			new("UIStroke", { Color = THEME.Line, Transparency = 0.8, Thickness = 1, Parent = swatch })
			local hex = label({
				Name = "Hex", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -16, 0.5, 0), Size = UDim2.fromOffset(84, 20),
				TextColor3 = THEME.TextSecondary, TextXAlignment = Enum.TextXAlignment.Right, Text = "", Parent = holder,
			})
			row.Frame = holder
			row.refresh = function()
				local color = item.getColor()
				swatch.BackgroundColor3 = color
				hex.Text = "#" .. string.upper(color:ToHex())
			end
			row.refresh(false)
			return row
		end

		if item.kind == "empty" then
			row.Frame = label({
				Name = "Empty", Position = UDim2.fromOffset(0, y), Size = UDim2.new(1, 0, 0, ROW_H),
				Text = item.label, TextColor3 = THEME.TextDisabled, ZIndex = 2, Parent = list.Content,
			})
			return row
		end

		row.selectable = true
		local kind = item.kind
		local button = new("TextButton", {
			Name = "Row", Text = "", BackgroundTransparency = 1, Position = UDim2.fromOffset(0, y),
			Size = UDim2.new(1, 0, 0, ROW_H), ZIndex = 2, Parent = list.Content,
		})
		row.Frame = button
		local hover = new("Frame", {
			Name = "Hover", BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1), Parent = button,
		})
		new("Frame", {
			Name = "Separator", AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1),
			Size = UDim2.new(1, 0, 0, 1), BackgroundColor3 = THEME.Line, BackgroundTransparency = 0.955, Parent = button,
		})
		local title = label({
			Name = "Label", Position = UDim2.fromOffset(16, 0), Size = UDim2.new(0.62, -16, 1, 0), Text = item.label,
			TextColor3 = THEME.TextRow, TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd, Parent = button,
		})
		local arrow

		local function usable()
			return row.list == current.list and not modalOpen()
		end

		if kind == "submenu" then
			arrow = label({
				Name = "Arrow", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -16, 0.5, 0),
				Size = UDim2.fromOffset(14, 20), Text = "›", TextSize = 24, TextColor3 = THEME.TextSecondary,
				TextXAlignment = Enum.TextXAlignment.Right, Parent = button,
			})
		elseif kind == "playerEntry" then
			-- "10452 - Name"   [house] [car]   [toggle]   (Enter / click ticks the player)
			local player = item.player
			local toggle = createToggle(button, 16, function()
				if usable() then
					selectRow(row)
					togglePlayer(player)
				end
			end)
			local icons = new("Frame", {
				Name = "Icons", BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -(16 + 40 + 10), 0.5, 0), Size = UDim2.fromOffset(44, 18), Parent = button,
			})
			new("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Right,
				VerticalAlignment = Enum.VerticalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder,
				Padding = UDim.new(0, 6), Parent = icons,
			})
			local house = rowIcon(icons, "House", "house", THEME.House, 1)
			local car = rowIcon(icons, "Car", "car", THEME.Car, 2)
			title.Size = UDim2.new(1, -(16 + 16 + 40 + 10 + 44), 1, 0)
			row.refreshStatus = function()
				local status = playerStatus(player)
				house.Visible = status.inHouse
				car.Visible = status.inVehicle
			end
			row.refresh = function(animate)
				title.Text = playerId(player) .. " - " .. player.DisplayName
				toggle.set(isSelected(player), animate)
				row.refreshStatus()
			end
		elseif kind == "input" then
			local valueLabel = label({
				Name = "Value", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -16, 0.5, 0),
				Size = UDim2.fromOffset(170, 22), Text = "", TextColor3 = THEME.TextSecondary,
				TextXAlignment = Enum.TextXAlignment.Right, TextTruncate = Enum.TextTruncate.AtEnd, Parent = button,
			})
			row.refresh = function()
				valueLabel.Text = State.get(item.key, "")
			end
			row.openInput = function()
				if row.box then
					return
				end
				valueLabel.Visible = false
				local box = styled("TextBox", {
					Name = "SearchBox", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0),
					Size = UDim2.fromOffset(190, 24), BackgroundTransparency = 0, BackgroundColor3 = THEME.Secondary,
					Text = State.get(item.key, ""), PlaceholderText = item.placeholder, PlaceholderColor3 = THEME.TextDisabled,
					ClearTextOnFocus = false, TextSize = CONFIG.SmallTextSize, TextXAlignment = Enum.TextXAlignment.Left,
					TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 3, Parent = button,
				})
				corner(box, UDim.new(0, 3))
				new("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8), Parent = box })
				new("UIStroke", {
					Color = THEME.Accent, Transparency = 0.2, Thickness = 1,
					ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = box,
				})
				row.box = box
				box.FocusLost:Connect(function()
					local text = box.Text
					row.box = nil
					box:Destroy()
					valueLabel.Visible = true
					if item.isSearch then
						setSearch(item, text)
					elseif item.onSubmit then
						item.onSubmit(text)
					else -- TextBox element
						State.set(item.key, text)
						row.refresh(false)
						emit(item, text)
					end
				end)
				box:CaptureFocus()
			end
		elseif kind == "choice" then
			-- pick-one option (theme / banner): toggle shows whether it's the active one
			local toggle = createToggle(button, 16, function()
				if usable() then
					selectRow(row)
					activateItem(item)
				end
			end)
			if item.swatch then
				local swatch = new("Frame", {
					Name = "Swatch", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -(16 + 40 + 12), 0.5, 0),
					Size = UDim2.fromOffset(14, 14), BackgroundColor3 = item.swatch, Parent = button,
				})
				corner(swatch, UDim.new(0, 3))
				new("UIStroke", { Color = THEME.Line, Transparency = 0.8, Thickness = 1, Parent = swatch })
			end
			row.refresh = function(animate)
				toggle.set(State.get(item.key, 1) == item.index, animate)
			end
		elseif kind == "toggle" then
			local toggle = createToggle(button, 16, function()
				if usable() then
					selectRow(row)
					setToggle(item, not State.get(item.key, false))
				end
			end)
			row.refresh = function(animate)
				toggle.set(State.get(item.key, false), animate)
			end
		elseif kind == "slider" then
			local slider = createSlider(button)
			local gradient
			if item.gradient then -- colour picker: the track shows the colour range instead of a fill
				slider.Fill.BackgroundTransparency = 1
				slider.Track.BackgroundColor3 = Color3.new(1, 1, 1)
				gradient = new("UIGradient", { Parent = slider.Track })
			end
			row.refresh = function(animate)
				local value = State.get(item.key, item.min)
				local span = item.max - item.min
				slider.set(span > 0 and (value - item.min) / span or 0, string.format(item.format, value), animate)
				if gradient then
					gradient.Color = item.gradient()
				end
			end
			slider.Hit.InputBegan:Connect(function(input)
				local inputType = input.UserInputType
				if inputType ~= Enum.UserInputType.MouseButton1 and inputType ~= Enum.UserInputType.Touch then
					return
				end
				if not usable() then
					return
				end
				selectRow(row)
				local function setFromX(x)
					local track = slider.Track
					local ratio = math.clamp((x - track.AbsolutePosition.X) / math.max(track.AbsoluteSize.X, 1), 0, 1)
					applySlider(item, item.min + ratio * (item.max - item.min), false)
				end
				setFromX(input.Position.X)
				local moveConn, endConn
				moveConn = UserInputService.InputChanged:Connect(function(move)
					local moveType = move.UserInputType
					if moveType ~= Enum.UserInputType.MouseMovement and moveType ~= Enum.UserInputType.Touch then
						return
					end
					if row.list ~= current.list or not slider.Track.Parent then
						moveConn:Disconnect()
						endConn:Disconnect()
						return
					end
					setFromX(move.Position.X)
				end)
				endConn = UserInputService.InputEnded:Connect(function(ended)
					if ended.UserInputType == inputType then
						moveConn:Disconnect()
						endConn:Disconnect()
					end
				end)
			end)
		elseif kind == "selector" then
			local selector = createSelector(button, 16, function(dir)
				if usable() then
					selectRow(row)
					stepSelector(item, dir)
				end
			end)
			row.refresh = function()
				selector.Value.Text = shorten(tostring(item.options[State.get(item.key, 1)] or "-"), 18)
			end
		elseif kind == "player" then
			local selector = createSelector(button, 16, function(dir)
				if usable() then
					selectRow(row)
					stepPlayer(item, dir)
				end
			end)
			row.refresh = function()
				local target = getItemTarget(item)
				selector.Value.Text = target and shorten(target.DisplayName, 16) or "No Players"
			end
		elseif kind == "keybind" then
			-- current key in a small keycap; Enter / click asks for a new one
			local keycap = new("Frame", {
				Name = "Key", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -16, 0.5, 0), Size = UDim2.fromOffset(0, 22),
				AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = THEME.Secondary, Parent = button,
			})
			corner(keycap, UDim.new(0, 4))
			new("UIStroke", { Color = THEME.Line, Transparency = 0.85, Thickness = 1, Parent = keycap })
			new("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8), Parent = keycap })
			local keyText = label({
				Name = "Text", AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromScale(0, 1), Text = "",
				TextSize = CONFIG.SmallTextSize, Parent = keycap,
			})
			row.refresh = function()
				keyText.Text = keybindName(item)
			end
		elseif kind == "color" then
			local swatch = new("Frame", {
				Name = "Swatch", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -16, 0.5, 0),
				Size = UDim2.fromOffset(34, 18), Parent = button,
			})
			corner(swatch, UDim.new(0, 4))
			new("UIStroke", { Color = THEME.Line, Transparency = 0.75, Thickness = 1, Parent = swatch })
			row.refresh = function()
				swatch.BackgroundColor3 = State.get(item.key, Color3.new(1, 1, 1))
			end
		elseif kind == "value" then
			local valueLabel = label({
				Name = "Value", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -16, 0.5, 0),
				Size = UDim2.fromOffset(140, 20), Text = "", TextColor3 = THEME.TextSecondary,
				TextXAlignment = Enum.TextXAlignment.Right, Parent = button,
			})
			row.refresh = function()
				local value = item.value
				if type(value) == "function" then
					value = value()
				end
				valueLabel.Text = tostring(value)
			end
		end

		row.setSelected = function(selected)
			title.TextColor3 = selected and THEME.Text or THEME.TextRow
			if arrow then
				arrow.TextColor3 = selected and THEME.Text or THEME.TextSecondary
			end
		end

		button.MouseEnter:Connect(function()
			hover.BackgroundTransparency = 0.965
			Nav.hoverRow = row -- F5 binds the hovered row when the mouse was used last
			Nav.mouseFresh = true
		end)
		button.MouseLeave:Connect(function()
			hover.BackgroundTransparency = 1
			if Nav.hoverRow == row then
				Nav.hoverRow = nil
			end
		end)
		button.Activated:Connect(function()
			if not usable() then
				return
			end
			local changed = selectRow(row)
			if not changed or INSTANT[kind] or (kind == "selector" and item.dropdown) then
				activate()
			end
		end)

		row.refresh(false)
		return row
	end

	-- moves a list's view; keyboard navigation keeps the selection visible, the scrollbar can move it freely
	local function scrollList(list, value, animate)
		value = math.clamp(value, 0, math.max(0, #list.Rows * ROW_H - list.Height))
		if value == list.Scroll then
			return
		end
		list.Scroll = value
		local position = UDim2.fromOffset(0, -value)
		if animate then
			tween(list.Content, { Position = position }, 0.12)
		else
			list.Content.Position = position
		end
		if list.updateScrollbar then
			list.updateScrollbar(animate)
		end
	end

	-- thin scrollbar at the right edge: arrows step one row, the track pages, the thumb drags
	local function addScrollbar(list)
		local total, view = #list.Rows * ROW_H, list.Height
		local trackHeight = view - 4 - 28
		local thumbHeight = math.max(18, math.floor(trackHeight * view / total))
		local maxScroll, travel = total - view, trackHeight - thumbHeight
		local bar = new("Frame", {
			Name = "Scrollbar", BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -2, 0, 2), Size = UDim2.new(0, 12, 1, -4), ZIndex = 6, Parent = list.Frame,
		})
		local up = new("TextButton", { Name = "Up", Text = "", BackgroundTransparency = 1, Size = UDim2.fromOffset(12, 14), ZIndex = 7, Parent = bar })
		Draw.chevron(up, true, THEME.TextSecondary)
		local down = new("TextButton", {
			Name = "Down", Text = "", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1),
			Size = UDim2.fromOffset(12, 14), ZIndex = 7, Parent = bar,
		})
		Draw.chevron(down, false, THEME.TextSecondary)
		local track = new("TextButton", {
			Name = "Track", Text = "", BackgroundColor3 = THEME.Track, BackgroundTransparency = 0.3, AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 14), Size = UDim2.fromOffset(5, trackHeight), ZIndex = 6, Parent = bar,
		})
		corner(track, FULL)
		local thumb = new("TextButton", {
			Name = "Thumb", Text = "", BackgroundColor3 = Color3.new(1, 1, 1), Size = UDim2.new(1, 0, 0, thumbHeight), ZIndex = 7, Parent = track,
		})
		corner(thumb, FULL)
		new("UIGradient", { Color = ColorSequence.new(THEME.AccentIcon, THEME.Accent), Rotation = 90, Parent = thumb })

		list.updateScrollbar = function(animate)
			local position = UDim2.fromOffset(0, math.floor(travel * (list.Scroll / maxScroll) + 0.5))
			if animate then
				tween(thumb, { Position = position }, 0.12)
			else
				thumb.Position = position
			end
		end
		list.updateScrollbar(false)

		local function usable()
			return list == current.list and not modalOpen()
		end
		up.Activated:Connect(function()
			if usable() then
				scrollList(list, list.Scroll - ROW_H, true)
			end
		end)
		down.Activated:Connect(function()
			if usable() then
				scrollList(list, list.Scroll + ROW_H, true)
			end
		end)
		track.Activated:Connect(function()
			if usable() then -- page towards the click
				local above = UserInputService:GetMouseLocation().Y < thumb.AbsolutePosition.Y
				scrollList(list, list.Scroll + (above and -view or view), true)
			end
		end)
		thumb.InputBegan:Connect(function(input)
			if input.UserInputType ~= Enum.UserInputType.MouseButton1 or not usable() then
				return
			end
			local startY, startScroll = UserInputService:GetMouseLocation().Y, list.Scroll
			local moveConn, endConn
			moveConn = UserInputService.InputChanged:Connect(function(move)
				if move.UserInputType ~= Enum.UserInputType.MouseMovement then
					return
				end
				if list ~= current.list then
					moveConn:Disconnect()
					endConn:Disconnect()
					return
				end
				local delta = (UserInputService:GetMouseLocation().Y - startY) / uiScale.Scale
				scrollList(list, startScroll + delta * maxScroll / travel, false)
			end)
			endConn = UserInputService.InputEnded:Connect(function(ended)
				if ended.UserInputType == Enum.UserInputType.MouseButton1 then
					moveConn:Disconnect()
					endConn:Disconnect()
				end
			end)
		end)
	end

	local function buildList(items)
		local count = #items
		local visible = math.clamp(count, 1, CONFIG.MaxVisibleRows)
		local frame = new("Frame", {
			Name = "List", BackgroundTransparency = 1, ClipsDescendants = true, Size = UDim2.new(1, 0, 0, visible * ROW_H),
		})
		local content = new("Frame", {
			Name = "Content", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, math.max(count, 1) * ROW_H), Parent = frame,
		})
		local list = {
			Frame = frame, Content = content, Highlight = makeHighlight(content, ROW_H),
			Rows = {}, Selectable = {}, Height = visible * ROW_H, Scroll = 0, Selected = nil,
		}
		for index, item in ipairs(items) do
			local row = buildRow(list, item, index)
			list.Rows[index] = row
			if row.selectable then
				table.insert(list.Selectable, index)
				row.selIndex = #list.Selectable
			end
		end
		if count > visible then
			addScrollbar(list)
		end
		return list
	end

	local function buildTabBar(tabs, selectedIndex, onPick)
		local count = #tabs
		local bar = new("Frame", { Name = "Tabs", BackgroundColor3 = THEME.TabBar, Size = UDim2.new(1, 0, 0, TABS_H) })
		local highlight = new("Frame", {
			Name = "TabHighlight", BackgroundColor3 = Color3.new(1, 1, 1), Size = UDim2.new(1 / count, 0, 1, 0),
			Position = UDim2.fromScale((selectedIndex - 1) / count, 0), Parent = bar,
		})
		new("UIGradient", { Color = THEME.TabGradient, Rotation = 90, Parent = highlight })
		local buttons = {}
		for index, tab in ipairs(tabs) do
			local button = styled("TextButton", {
				Name = tab.name, Position = UDim2.fromScale((index - 1) / count, 0), Size = UDim2.new(1 / count, 0, 1, 0),
				Text = tab.name, TextColor3 = index == selectedIndex and THEME.Text or THEME.TextRow, ZIndex = 2, Parent = bar,
			})
			button.Activated:Connect(function()
				onPick(index)
			end)
			buttons[index] = button
			if tab.image then -- window:Tab(name, image): icon in front of the name
				button.Text = ""
				local content = new("Frame", {
					Name = "Content", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
					Size = UDim2.fromOffset(0, TABS_H), AutomaticSize = Enum.AutomaticSize.X, ZIndex = 2, Parent = button,
				})
				new("UIListLayout", {
					FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center,
					SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 6), Parent = content,
				})
				new("ImageLabel", {
					Name = "Icon", LayoutOrder = 1, BackgroundTransparency = 1, Size = UDim2.fromOffset(16, 16),
					Image = tab.image, ZIndex = 2, Parent = content,
				})
				buttons[index] = label({
					Name = "Label", LayoutOrder = 2, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromScale(0, 1),
					Text = tab.name, TextColor3 = button.TextColor3, ZIndex = 2, Parent = content,
				})
			end
			if index > 1 then
				new("Frame", {
					Position = UDim2.new((index - 1) / count, 0, 0.25, 0), Size = UDim2.new(0, 1, 0.5, 0),
					BackgroundColor3 = THEME.Line, BackgroundTransparency = 0.9, ZIndex = 2, Parent = bar,
				})
			end
		end
		local tabBar = { Frame = bar }
		function tabBar.set(index, animate)
			local position = UDim2.fromScale((index - 1) / count, 0)
			if animate then
				tween(highlight, { Position = position }, 0.12)
			else
				highlight.Position = position
			end
			for i, button in ipairs(buttons) do
				button.TextColor3 = i == index and THEME.Text or THEME.TextRow
			end
		end
		return tabBar
	end

	local function buildPageView(entry)
		local page = entry.page
		local frame = new("CanvasGroup", { Name = "Page", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 100) })
		local view = { Frame = frame }

		local titleBar = new("Frame", {
			Name = "TitleBar", BackgroundColor3 = THEME.Panel, BackgroundTransparency = 0.04,
			Size = UDim2.new(1, 0, 0, TITLE_H), Parent = frame,
		})
		view.TitleLabel = label({
			Name = "Title", Size = UDim2.fromScale(1, 1), TextSize = CONFIG.TitleTextSize, Parent = titleBar,
			Text = type(page.title) == "function" and page.title(entry) or page.title,
		})
		if #Nav.stack > 1 then
			local back = styled("TextButton", {
				Name = "Back", Position = UDim2.fromOffset(6, 0), Size = UDim2.fromOffset(30, TITLE_H),
				Text = "‹", TextSize = 26, TextColor3 = THEME.TextSecondary, Parent = titleBar,
			})
			back.MouseEnter:Connect(function()
				back.TextColor3 = THEME.Text
			end)
			back.MouseLeave:Connect(function()
				back.TextColor3 = THEME.TextSecondary
			end)
			back.Activated:Connect(function()
				if current.view == view and not modalOpen() then
					goBack()
				end
			end)
		end
		new("Frame", {
			Name = "TitleLine", Position = UDim2.fromOffset(0, TITLE_H), Size = UDim2.new(1, 0, 0, 1),
			BackgroundColor3 = THEME.Accent, BackgroundTransparency = 0.15, Parent = frame,
		})

		local top = TITLE_H + 1
		if page.tabs then
			view.TabBar = buildTabBar(page.tabs, entry.tab, function(index)
				if current.view == view and not modalOpen() then
					switchTab(index)
				end
			end)
			view.TabBar.Frame.Position = UDim2.fromOffset(0, top)
			view.TabBar.Frame.Parent = frame
			top += TABS_H
			new("Frame", {
				Name = "TabLine", Position = UDim2.fromOffset(0, top), Size = UDim2.new(1, 0, 0, 1),
				BackgroundColor3 = THEME.Accent, BackgroundTransparency = 0.15, Parent = frame,
			})
			top += 1
		end

		view.ListHost = new("Frame", {
			Name = "ListHost", BackgroundTransparency = 1, ClipsDescendants = true,
			Position = UDim2.fromOffset(0, top), Size = UDim2.new(1, 0, 0, 0), Parent = frame,
		})
		view.Top = top
		return view
	end

	--------------------------------------------------------------------------------
	-- NAVIGATION CORE
	--------------------------------------------------------------------------------
	local function getSource(entry)
		local page = entry.page
		if page.tabs then
			return page.tabs[entry.tab]
		end
		return page
	end

	local function getItems(entry)
		local items = getSource(entry).items
		if type(items) == "function" then
			items = items(entry)
		end
		return items or {}
	end

	local function newEntry(page)
		return { page = page, tab = (page.tabs and page.defaultTab) or 1, sel = 1, selKey = nil }
	end

	local function selectedRow()
		local list, entry = current.list, currentEntry()
		if not list or not entry or entry.sel < 1 then
			return nil
		end
		local rowIndex = list.Selectable[entry.sel]
		return rowIndex and list.Rows[rowIndex] or nil
	end

	local function ensureVisible(list, rowIndex, animate)
		local top = (rowIndex - 1) * ROW_H
		local bottom = top + ROW_H
		local previous = list.Rows[rowIndex - 1]
		if previous and previous.item.kind == "divider" then
			top -= ROW_H -- keep the section label visible above its first row
		end
		local scroll = list.Scroll
		if top < scroll then
			scroll = top
		elseif bottom > scroll + list.Height then
			scroll = bottom - list.Height
		end
		scrollList(list, scroll, animate)
	end

	updateSelection = function(animate)
		local list, entry = current.list, currentEntry()
		if not list or not entry then
			return
		end
		local count = #list.Selectable
		counterLabel.Text = string.format("%d / %d", math.max(entry.sel, 0), count)
		if list.Selected then
			list.Selected.setSelected(false)
			list.Selected = nil
		end
		local row = selectedRow()
		if not row then
			list.Highlight.Visible = false
			updatePanel()
			updateTooltip()
			return
		end
		local rowIndex = list.Selectable[entry.sel]
		row.setSelected(true)
		list.Selected = row
		entry.selKey = rowKey(row.item)
		local position = UDim2.fromOffset(0, (rowIndex - 1) * ROW_H)
		if animate and list.Highlight.Visible then
			tween(list.Highlight, { Position = position }, 0.1)
		else
			list.Highlight.Position = position
		end
		list.Highlight.Visible = true
		ensureVisible(list, rowIndex, animate)
		updatePanel()
		updateTooltip()
	end

	refreshRows = function(animate)
		if current.list then
			for _, row in ipairs(current.list.Rows) do
				row.refresh(animate)
			end
		end
	end

	mountList = function(entry, slideDir)
		closePopup(true)
		local view = current.view
		local items = getItems(entry)
		if #items == 0 then
			items = { { kind = "empty", label = getSource(entry).emptyText or "Nothing here" } }
		end
		local old = current.list
		local list = buildList(items)
		current.list = list
		for _, item in ipairs(items) do
			if item.kind == "playerEntry" or item.kind == "player" or item.playerList then
				list.playerContext = true -- the info panel shows the last ticked player here
				break
			end
		end

		local count = #list.Selectable
		if count == 0 then
			entry.sel = 0
		else
			local found
			if entry.selKey then
				for selIndex, rowIndex in ipairs(list.Selectable) do
					if rowKey(list.Rows[rowIndex].item) == entry.selKey then
						found = selIndex
						break
					end
				end
			end
			entry.sel = found or math.clamp(entry.sel, 1, count)
		end

		list.Frame.Parent = view.ListHost
		if old then
			old.Frame:Destroy()
		end

		view.ListHost.Size = UDim2.new(1, 0, 0, list.Height)
		local viewHeight = view.Top + list.Height
		view.Frame.Size = UDim2.new(1, 0, 0, viewHeight)
		local windowSize = UDim2.fromOffset(CONFIG.Width, HEADER_H + viewHeight + FOOTER_H)
		if Nav.isOpen and menuFrame.Size ~= windowSize then
			tween(menuFrame, { Size = windowSize }, 0.14)
		else
			menuFrame.Size = windowSize
		end

		if slideDir and Nav.isOpen and animationsOn() then
			list.Frame.Position = UDim2.fromOffset(16 * slideDir, 0)
			tween(list.Frame, { Position = UDim2.fromOffset(0, 0) }, 0.12)
			local cover = new("Frame", {
				Name = "Cover", BackgroundColor3 = THEME.Background, BackgroundTransparency = 0.2,
				Size = UDim2.fromScale(1, 1), ZIndex = 20, Parent = list.Frame,
			})
			tween(cover, { BackgroundTransparency = 1 }, 0.14, function()
				cover:Destroy()
			end)
		end
		updateSelection(false)
	end

	renderPage = function(direction)
		closePopup(true)
		local entry = currentEntry()
		local oldView = current.view
		local view = buildPageView(entry)
		current.view = view
		current.list = nil
		view.Frame.Parent = pageHost
		mountList(entry, nil)

		if oldView then
			if direction ~= 0 and Nav.isOpen and animationsOn() then
				view.Frame.Position = UDim2.fromOffset(22 * direction, 0)
				view.Frame.GroupTransparency = 1
				tween(view.Frame, { Position = UDim2.fromOffset(0, 0), GroupTransparency = 0 }, 0.14)
				tween(oldView.Frame, { Position = UDim2.fromOffset(-22 * direction, 0), GroupTransparency = 1 }, 0.14, function()
					oldView.Frame:Destroy()
				end)
			else
				oldView.Frame:Destroy()
			end
		end
		updatePanel()
	end

	pushPage = function(page)
		table.insert(Nav.stack, newEntry(page))
		renderPage(1)
	end

	goBack = function()
		if #Nav.stack <= 1 then
			return -- root page: Backspace does nothing (F2 closes the menu)
		end
		table.remove(Nav.stack)
		renderPage(-1)
	end

	local function wrapIndex(index, count)
		if index < 1 then
			return State.get("settings.wrap", true) and count or 1
		elseif index > count then
			return State.get("settings.wrap", true) and 1 or count
		end
		return index
	end

	switchTab = function(index, dir)
		local entry = currentEntry()
		local tabs = entry and entry.page.tabs
		if not tabs then
			return
		end
		index = wrapIndex(index, #tabs)
		if index == entry.tab then
			return
		end
		dir = dir or (index > entry.tab and 1 or -1)
		entry.tab = index
		entry.sel = 1
		entry.selKey = nil
		current.view.TabBar.set(index, true)
		if type(entry.page.title) == "function" then -- root page: the title shows the tab's name
			current.view.TitleLabel.Text = entry.page.title(entry)
		end
		mountList(entry, dir)
	end

	moveSelection = function(delta)
		local entry, list = currentEntry(), current.list
		if not entry or not list then
			return
		end
		local count = #list.Selectable
		if count == 0 then
			return
		end
		local index = wrapIndex(entry.sel + delta, count)
		if index ~= entry.sel then
			entry.sel = index
			updateSelection(true)
		end
	end

	selectRow = function(row)
		local entry = currentEntry()
		if not entry or row.list ~= current.list or not row.selIndex then
			return false
		end
		if entry.sel == row.selIndex then
			return false
		end
		entry.sel = row.selIndex
		updateSelection(true)
		return true
	end

	pulse = function()
		local list = current.list
		local flash = list and list.Highlight:FindFirstChild("Pulse")
		if flash then
			flash.BackgroundTransparency = 0.72
			tween(flash, { BackgroundTransparency = 1 }, 0.25)
		end
	end

	local function findRow(item)
		if current.list then
			for _, row in ipairs(current.list.Rows) do
				if row.item == item then
					return row
				end
			end
		end
		return nil
	end

	-- options are driven by item (not row) so keybinds can run them while their page isn't shown
	local function refreshItem(item, animate)
		local row = findRow(item)
		if row then
			row.refresh(animate)
		end
	end

	local function refreshPlayerRows(animate)
		if current.list then
			for _, row in ipairs(current.list.Rows) do
				local kind = row.item.kind
				if kind == "player" or kind == "playerEntry" then
					row.refresh(animate)
				end
			end
		end
	end

	setToggle = function(item, value)
		State.set(item.key, value)
		refreshItem(item, true)
		if item.onChange then
			item.onChange(value)
		end
		refreshKeybindList()
		if not item.silent then
			emit(item, value)
		end
		return true
	end

	applySlider = function(item, raw, animate)
		local steps = math.floor((raw - item.min) / item.step + 0.5)
		local value = math.clamp(item.min + steps * item.step, item.min, item.max)
		value = math.floor(value * 1000 + 0.5) / 1000 -- strip float noise
		if value == State.get(item.key) then
			return
		end
		State.set(item.key, value)
		refreshItem(item, animate)
		if item.onChange then
			item.onChange(value)
		end
		if not item.silent then
			emit(item, value)
		end
	end

	selectorChanged = function(item, index)
		if item.onChange then
			item.onChange(index, item.options[index])
		end
		if not item.silent and not item.run then
			emit(item, item.options[index])
		end
	end

	stepSelector = function(item, dir)
		local count = #item.options
		local index = ((State.get(item.key, 1) - 1 + dir) % count) + 1
		State.set(item.key, index)
		refreshItem(item, true)
		selectorChanged(item, index)
	end

	stepPlayer = function(item, dir)
		local targets = getTargets()
		if #targets == 0 then
			return
		end
		local index = table.find(targets, getItemTarget(item)) or 1
		index = ((index - 1 + dir) % #targets) + 1
		if item.shared then
			Nav.target = targets[index]
		else
			State.values[item.key] = targets[index]
		end
		refreshPlayerRows(true)
		updatePanel()
	end

	-- tick / untick a player in Online > List
	togglePlayer = function(player)
		if not isTarget(player) then
			return
		end
		local on = not isSelected(player)
		setSelected(player, on)
		if on then
			Nav.target = player -- "Teleport To < Player >" follows the last ticked player
		elseif Nav.target == player then
			Nav.target = focusTarget() or player
		end
		refreshPlayerRows(true)
		updatePanel()
		selectionChanged()
	end

	setSearch = function(item, text)
		text = string.gsub(string.gsub(text, "^%s+", ""), "%s+$", "")
		if text == State.get(item.key, "") then
			refreshItem(item, false)
			return
		end
		State.set(item.key, text)
		local entry = currentEntry()
		if entry and type(getSource(entry).items) == "function" then
			mountList(entry, nil) -- rebuild the filtered player list, keeping the selection
		else
			refreshItem(item, false)
		end
	end

	local function horizontal(dir)
		local row = selectedRow()
		if row then
			local item = row.item
			local kind = item.kind
			if kind == "slider" then
				applySlider(item, State.get(item.key, item.min) + dir * item.step, true)
				return
			elseif kind == "selector" then
				stepSelector(item, dir)
				return
			elseif kind == "player" then
				stepPlayer(item, dir)
				return
			end
		end
		local entry = currentEntry()
		if entry and entry.page.tabs then
			switchTab(entry.tab + dir, dir)
		end
	end

	-- page opened by a ColorWheel element: preview, hue / saturation / brightness sliders and a hex box
	local function colorPage(item)
		if item.page then
			return item.page
		end
		local key = item.key
		local hKey = key .. ".h"
		local sKey = key .. ".s"
		local vKey = key .. ".v"
		local hexKey = key .. ".hex"
		local function currentColor()
			return State.get(key, Color3.new(1, 1, 1))
		end
		local function hsv()
			return State.get(hKey, 0) / 360, State.get(sKey, 0) / 100, State.get(vKey, 100) / 100
		end
		local function apply()
			local color = Color3.fromHSV(hsv())
			State.set(key, color)
			State.set(hexKey, "#" .. string.upper(color:ToHex()))
			refreshRows(false)
			emit(item, color)
		end
		local h, sat, v = currentColor():ToHSV()
		local hue = Item.slider("Hue", hKey, { min = 0, max = 360, step = 5, default = math.floor(h * 360 + 0.5), format = "%d", silent = true, onChange = apply })
		local saturation = Item.slider("Saturation", sKey, { min = 0, max = 100, step = 5, default = math.floor(sat * 100 + 0.5), format = "%d%%", silent = true, onChange = apply })
		local brightness = Item.slider("Brightness", vKey, { min = 0, max = 100, step = 5, default = math.floor(v * 100 + 0.5), format = "%d%%", silent = true, onChange = apply })
		local rainbow = {}
		for i = 0, 6 do
			table.insert(rainbow, ColorSequenceKeypoint.new(i / 6, Color3.fromHSV((i / 6) % 1, 1, 1)))
		end
		hue.gradient = function()
			return ColorSequence.new(rainbow)
		end
		saturation.gradient = function()
			local hh, _, vv = hsv()
			return ColorSequence.new(Color3.fromHSV(hh, 0, vv), Color3.fromHSV(hh, 1, vv))
		end
		brightness.gradient = function()
			local hh, ss = hsv()
			return ColorSequence.new(Color3.new(0, 0, 0), Color3.fromHSV(hh, ss, 1))
		end
		local hex = Item.search("Hex", hexKey, "#RRGGBB", false)
		State.set(hexKey, "#" .. string.upper(currentColor():ToHex()))
		hex.onSubmit = function(text)
			local ok, color = pcall(Color3.fromHex, (string.gsub(text, "#", "")))
			if ok and color then
				local nh, ns, nv = color:ToHSV()
				State.set(hKey, math.floor(nh * 360 + 0.5))
				State.set(sKey, math.floor(ns * 100 + 0.5))
				State.set(vKey, math.floor(nv * 100 + 0.5))
				apply()
			else
				notify("Colour", "Use a hex code like #7A00FF", "warning")
				refreshRows(false)
			end
		end
		item.page = {
			title = item.label,
			items = { { kind = "colorPreview", label = "Preview", getColor = currentColor }, hue, saturation, brightness, hex },
			sync = function(color) -- ColorWheel:Set moves the sliders too
				local nh, ns, nv = color:ToHSV()
				State.set(hKey, math.floor(nh * 360 + 0.5))
				State.set(sKey, math.floor(ns * 100 + 0.5))
				State.set(vKey, math.floor(nv * 100 + 0.5))
				State.set(hexKey, "#" .. string.upper(color:ToHex()))
			end,
		}
		return item.page
	end

	-- Enter on the highlighted row
	activate = function()
		local row = selectedRow()
		if not row then
			return
		end
		local item = row.item
		if item.kind == "input" then
			row.openInput()
		elseif item.kind == "keybind" then
			openBinder(row)
		elseif item.kind == "selector" and item.dropdown and not item.run then
			openPopup(row)
		else
			activateItem(item)
		end
	end

	-- Runs an option (Enter, mouse click or keybind). Returns false when nothing happened.
	activateItem = function(item)
		local kind = item.kind
		if kind == "submenu" then
			local page = item.page
			if type(page) == "function" then
				page = page()
			end
			if page then
				pushPage(page)
			end
		elseif kind == "color" then
			pushPage(colorPage(item))
		elseif kind == "playerEntry" then
			togglePlayer(item.player)
		elseif kind == "choice" then
			pulse()
			if State.get(item.key, 1) ~= item.index then
				State.set(item.key, item.index)
				refreshRows(true)
				if item.onChange then
					item.onChange(item.index)
				end
			end
		elseif kind == "value" then
			pulse()
			if item.run then
				item.run()
			end
		elseif kind == "toggle" then
			return setToggle(item, not State.get(item.key, false))
		elseif kind == "selector" then
			local option = item.options[State.get(item.key, 1)]
			pulse()
			if item.run then
				item.run(option)
			else
				stepSelector(item, 1)
			end
		elseif kind == "player" then
			local target = getItemTarget(item)
			if not target then
				notify("No players", "There is nobody to target.", "warning")
				return false
			end
			pulse()
			emit(item, target)
		elseif kind == "action" then
			pulse()
			if item.run then
				item.run()
			else
				emit(item)
			end
		elseif kind == "keybind" then
			pulse()
			emit(item)
		else
			pulse()
		end
		return true
	end

	--------------------------------------------------------------------------------
	-- DROPDOWN POPUP
	--------------------------------------------------------------------------------
	local OPTION_H = 26
	local POPUP_MAX = 6
	local POPUP_W = 172

	local function popupRefresh(animate)
		local popup = Popup
		if not popup then
			return
		end
		local position = UDim2.fromOffset(0, (popup.index - 1) * OPTION_H)
		if animate then
			tween(popup.highlight, { Position = position }, 0.08)
		else
			popup.highlight.Position = position
		end
		for i, optionLabel in ipairs(popup.labels) do
			optionLabel.TextColor3 = i == popup.index and THEME.Text or THEME.TextRow
		end
		local top = (popup.index - 1) * OPTION_H
		local viewHeight = popup.shown * OPTION_H
		if top < popup.scroll then
			popup.scroll = top
		elseif top + OPTION_H > popup.scroll + viewHeight then
			popup.scroll = top + OPTION_H - viewHeight
		end
		popup.content.Position = UDim2.fromOffset(0, -popup.scroll)
	end

	closePopup = function(instant)
		local popup = Popup
		if not popup then
			return
		end
		Popup = nil
		task.defer(updateTooltip)
		popup.blocker:Destroy()
		if instant then
			popup.frame:Destroy()
		else
			tween(popup.frame, { Size = UDim2.fromOffset(POPUP_W, 0) }, 0.08, function()
				popup.frame:Destroy()
			end)
		end
	end

	openPopup = function(row)
		closePopup(true)
		local item = row.item
		local options = item.options
		local shown = math.min(#options, POPUP_MAX)
		local height = shown * OPTION_H + 6
		local scale = uiScale.Scale
		local rowY = (row.Frame.AbsolutePosition.Y - menuCanvas.AbsolutePosition.Y) / scale
		local windowHeight = menuFrame.Size.Y.Offset
		local y = rowY + ROW_H - 2
		if y + height > windowHeight - FOOTER_H - 4 then
			y = rowY - height + 2 -- not enough room below: open upward
		end
		y = math.max(HEADER_H + 4, math.floor(y))

		local blocker = new("TextButton", {
			Name = "PopupBlocker", Text = "", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 1, Parent = popupLayer,
		})
		local frame = new("Frame", {
			Name = "Dropdown", Position = UDim2.fromOffset(CONFIG.Width - POPUP_W - 12, y), Size = UDim2.fromOffset(POPUP_W, 0),
			BackgroundColor3 = THEME.Secondary, ClipsDescendants = true, ZIndex = 2, Parent = popupLayer,
		})
		corner(frame, UDim.new(0, 4))
		new("UIStroke", { Color = THEME.Accent, Transparency = 0.35, Thickness = 1, Parent = frame })
		local clip = new("Frame", {
			BackgroundTransparency = 1, ClipsDescendants = true, Position = UDim2.fromOffset(0, 3),
			Size = UDim2.new(1, 0, 0, shown * OPTION_H), Parent = frame,
		})
		local content = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, #options * OPTION_H), Parent = clip })
		local highlight = new("Frame", { BackgroundColor3 = Color3.new(1, 1, 1), Size = UDim2.new(1, 0, 0, OPTION_H), Parent = content })
		new("UIGradient", { Color = THEME.Highlight, Parent = highlight })

		local applied = State.get(item.key, 1)
		local popup = {
			row = row, item = item, frame = frame, blocker = blocker, content = content, highlight = highlight,
			index = applied, shown = shown, scroll = 0, labels = {},
		}
		for i, optionText in ipairs(options) do
			local button = new("TextButton", {
				Name = "Option", Text = "", BackgroundTransparency = 1, Position = UDim2.fromOffset(0, (i - 1) * OPTION_H),
				Size = UDim2.new(1, 0, 0, OPTION_H), ZIndex = 2, Parent = content,
			})
			popup.labels[i] = label({
				Position = UDim2.fromOffset(12, 0), Size = UDim2.new(1, -36, 1, 0), Text = optionText, TextSize = CONFIG.SmallTextSize,
				TextXAlignment = Enum.TextXAlignment.Left, Parent = button,
			})
			if i == applied then
				local mark = new("Frame", {
					AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0), Size = UDim2.fromOffset(6, 6),
					BackgroundColor3 = THEME.Text, Parent = button,
				})
				corner(mark, FULL)
			end
			button.MouseEnter:Connect(function()
				if Popup == popup then
					popup.index = i
					popupRefresh(true)
				end
			end)
			button.Activated:Connect(function()
				if Popup == popup then
					popup.index = i
					popupConfirm()
				end
			end)
		end
		blocker.Activated:Connect(function()
			if Popup == popup then
				closePopup(false)
			end
		end)

		Popup = popup
		popupRefresh(false)
		updateTooltip()
		tween(frame, { Size = UDim2.fromOffset(POPUP_W, height) }, 0.1)
	end

	popupMove = function(delta)
		local popup = Popup
		if not popup then
			return
		end
		popup.index = wrapIndex(popup.index + delta, #popup.labels)
		popupRefresh(true)
	end

	popupConfirm = function()
		local popup = Popup
		if not popup then
			return
		end
		local index = popup.index
		closePopup(false)
		State.set(popup.item.key, index)
		if popup.row.list == current.list then
			popup.row.refresh(true)
		end
		selectorChanged(popup.item, index)
		pulse()
	end

	--------------------------------------------------------------------------------
	-- PLAYER INFO PANEL LOGIC
	--------------------------------------------------------------------------------

	local function readAttribute(player, name)
		local value = player:GetAttribute(name)
		if value == nil and player.Character then
			value = player.Character:GetAttribute(name)
		end
		return value
	end

	local function rootOf(character)
		return character and (character:FindFirstChild("HumanoidRootPart") or character.PrimaryPart)
	end

	function Panel.refresh()
		local player = Panel.target
		if not player then
			return
		end
		Panel.nameLabel.Text = player.DisplayName
		Panel.idLabel.Text = playerId(player)

		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local rootPart = rootOf(character)
		local myRoot = rootOf(LocalPlayer.Character)

		Panel.fields.Character.Text = tostring(readAttribute(player, "CharacterName") or "-")
		Panel.fields.Phone.Text = tostring(readAttribute(player, "Phone") or "-")
		Panel.fields.Radio.Text = tostring(readAttribute(player, "Radio") or "-")
		Panel.fields.Job.Text = tostring(readAttribute(player, "Job") or (player.Team and player.Team.Name) or "-")
		Panel.fields.Group.Text = tostring(readAttribute(player, "Group") or "user")

		local health = humanoid and math.max(0, humanoid.Health) or 0
		local maxHealth = humanoid and math.max(1, humanoid.MaxHealth) or 100
		Panel.fields.Health.Text = tostring(math.floor(health + 0.5))
		Panel.fields.HealthBar.Size = UDim2.fromScale(1, math.clamp(health / maxHealth, 0, 1))
		local armor = tonumber(readAttribute(player, "Armor")) or 0
		Panel.fields.Armor.Text = tostring(math.floor(armor + 0.5))
		Panel.fields.ArmorBar.Size = UDim2.fromScale(1, math.clamp(armor / 100, 0, 1))

		if rootPart and myRoot then
			local meters = (rootPart.Position - myRoot.Position).Magnitude * CONFIG.StudsToMeters
			Panel.fields.Distance.Text = string.format("%.1fm", meters)
		else
			Panel.fields.Distance.Text = "-"
		end

		local seat = humanoid and humanoid.SeatPart
		if seat and seat:IsA("VehicleSeat") then
			-- climb to the outermost vehicle model (Workspace also counts as a Model, so stop below it)
			local model = seat.Parent
			while model and model ~= workspace and model.Parent and model.Parent ~= workspace and model.Parent:IsA("Model") do
				model = model.Parent
			end
			local isVehicleModel = model ~= nil and model ~= workspace and model:IsA("Model")
			Panel.fields.Vehicle.Text = isVehicleModel and model.Name or "Vehicle"
		elseif seat then
			Panel.fields.Vehicle.Text = "Seated"
		else
			Panel.fields.Vehicle.Text = "On Foot"
		end

		local tool = character and character:FindFirstChildOfClass("Tool")
		Panel.fields.Weapon.Text = tool and tool.Name or "Unarmed"

		local speed = rootPart and rootPart.AssemblyLinearVelocity.Magnitude * CONFIG.StudsToMeters * 3.6 or 0
		Panel.fields.Speed.Text = string.format("%.1f km/h", speed)
	end

	function Panel.show(show)
		Panel.shown = show
		Panel.token += 1
		local token = Panel.token
		if show then
			Panel.frame.Visible = true
			Panel.frame.Position = UDim2.fromOffset(PANEL_X - 8, 0)
			tween(Panel.frame, { Position = UDim2.fromOffset(PANEL_X, 0) }, 0.16)
		end
		tween(Panel.stroke, { Transparency = show and 0.9 or 1 }, 0.14)
		tween(Panel.canvas, { GroupTransparency = show and 0 or 1 }, 0.14, function()
			if token == Panel.token and not show then
				Panel.frame.Visible = false
			end
		end)
	end

	-- Which player the floating card should describe right now (nil = hide it)
	local function panelTarget()
		if not current.list or not State.get("players.showInfo", true) then
			return nil -- "Show selected player info" is off
		end
		local row = selectedRow()
		if row then
			if row.item.kind == "playerEntry" then
				return isTarget(row.item.player) and row.item.player or nil
			elseif row.item.kind == "player" then
				return getItemTarget(row.item)
			end
		end
		if current.list.playerContext then
			return focusTarget() -- last ticked player, on lists that contain a player list / selector
		end
		return nil
	end

	updatePanel = function()
		local target = nil
		if Nav.isOpen and State.get("settings.panel", true) then
			target = panelTarget()
		end
		if target ~= Panel.target then
			Panel.target = target
			if target then
				Panel.refresh()
			end
		end
		local show = target ~= nil
		if show ~= Panel.shown then
			Panel.show(show)
		end
	end

	local panelClock = 0
	connect(RunService.Heartbeat, function(dt)
		if not (Nav.isOpen and Panel.shown and Panel.target) then
			return
		end
		panelClock += dt
		if panelClock >= 0.1 then
			panelClock = 0
			Panel.refresh()
		end
	end)

	--------------------------------------------------------------------------------
	-- HUD: notifications, keybind list, spectator list
	-- Lives in its own ScreenGui so it stays on screen while the menu is closed.
	--------------------------------------------------------------------------------
	local HUD = { scales = {}, notes = {}, noteOrder = 0, widgets = {} }
	local Binder: { [string]: any } = { active = false, list = {}, byKey = {}, byItem = {}, swallow = {}, context = "" }
	do
		local existingHud = PlayerGui:FindFirstChild("PurpleUIHUD")
		if existingHud then
			existingHud:Destroy()
		end

		local KeyPrompt = { active = false, selected = nil, token = 0, flash = 0, hint = "" }

		local hudScreen = new("ScreenGui", {
			Name = "PurpleUIHUD", ResetOnSpawn = false, IgnoreGuiInset = true,
			ZIndexBehavior = Enum.ZIndexBehavior.Sibling, DisplayOrder = 99, Parent = PlayerGui,
		})

		local NOTE_W, NOTE_H = 300, 64
		local WIDGET_W, HUD_ROW_H, HUD_HEADER_H = 220, 22, 28
		local KIND_COLORS = { info = THEME.Accent, success = THEME.Success, warning = THEME.Warning, error = THEME.Danger }

		local function escapeRich(text)
			return (string.gsub(text, "[&<>\"']", {
				["&"] = "&amp;", ["<"] = "&lt;", [">"] = "&gt;", ['"'] = "&quot;", ["'"] = "&apos;",
			}))
		end

		local function hudScaled(frame)
			table.insert(HUD.scales, new("UIScale", { Parent = frame }))
		end

		-- notifications: top centre, newest at the bottom of the stack ------------------
		local notifyHolder = new("Frame", {
			Name = "Notifications", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 70), Size = UDim2.fromOffset(NOTE_W, 420), Parent = hudScreen,
		})
		hudScaled(notifyHolder)
		new("UIListLayout", {
			SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 8),
			HorizontalAlignment = Enum.HorizontalAlignment.Center, Parent = notifyHolder,
		})

		local function dismissNote(note)
			if note.closing then
				return
			end
			note.closing = true
			local index = table.find(HUD.notes, note)
			if index then
				table.remove(HUD.notes, index)
			end
			tween(note.card, { Position = UDim2.fromOffset(0, -10), GroupTransparency = 1 }, 0.16)
			tween(note.slot, { Size = UDim2.fromOffset(NOTE_W, 0) }, 0.2, function()
				note.slot:Destroy()
			end)
		end

		notify = function(title, text, kind, duration)
			if not State.get("settings.notifications", true) then
				return
			end
			local accent = (kind ~= "info" and KIND_COLORS[kind]) or THEME.Accent
			duration = duration or CONFIG.NotifyDuration
			HUD.noteOrder += 1
			local slot = new("Frame", {
				Name = "Notification", BackgroundTransparency = 1, LayoutOrder = HUD.noteOrder,
				Size = UDim2.fromOffset(NOTE_W, NOTE_H), ClipsDescendants = true, Parent = notifyHolder,
			})
			local card = new("CanvasGroup", {
				Name = "Card", BackgroundColor3 = THEME.Background, BackgroundTransparency = 0.08,
				Position = UDim2.fromOffset(0, -10), Size = UDim2.fromOffset(NOTE_W, NOTE_H), GroupTransparency = 1, Parent = slot,
			})
			corner(card, UDim.new(0, 4))
			new("Frame", { Name = "Accent", BackgroundColor3 = accent, Size = UDim2.new(0, 3, 1, 0), Parent = card })
			label({
				Name = "Title", Position = UDim2.fromOffset(14, 7), Size = UDim2.new(1, -26, 0, 20), Text = title,
				TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Parent = card,
			})
			label({
				Name = "Message", Position = UDim2.fromOffset(14, 27), Size = UDim2.new(1, -26, 0, 32), Text = text or "",
				TextSize = CONFIG.SmallTextSize, TextColor3 = THEME.TextSecondary, TextWrapped = true,
				TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
				TextTruncate = Enum.TextTruncate.AtEnd, Parent = card,
			})
			local progress = new("Frame", {
				Name = "Progress", AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1),
				Size = UDim2.new(1, 0, 0, 2), BackgroundColor3 = accent, BackgroundTransparency = 0.25, Parent = card,
			})
			local note = { slot = slot, card = card }
			table.insert(HUD.notes, note)
			while #HUD.notes > CONFIG.MaxNotifications do
				dismissNote(HUD.notes[1])
			end
			tween(card, { Position = UDim2.fromOffset(0, 0), GroupTransparency = 0 }, 0.18)
			if animationsOn() then
				TweenService:Create(progress, TweenInfo.new(duration, Enum.EasingStyle.Linear), { Size = UDim2.new(0, 0, 0, 2) }):Play()
			end
			task.delay(duration, function()
				dismissNote(note)
			end)
		end

		local notifyEvent = new("BindableEvent", { Name = "Notify", Parent = hudScreen })
		notifyEvent.Event:Connect(function(title, text, kind, duration)
			notify(tostring(title), text ~= nil and tostring(text) or "", kind, tonumber(duration))
		end)

		-- floating lists (Keybinds / Spectators); drag them by the header while the menu is open --
		local function makeWidget(name, title, accent, iconKind, defaultPos)
			local frame = new("Frame", {
				Name = name, AnchorPoint = Vector2.new(1, 0), Position = defaultPos, Size = UDim2.fromOffset(WIDGET_W, HUD_HEADER_H),
				BackgroundColor3 = THEME.Background, BackgroundTransparency = 0.12, Visible = false, Parent = hudScreen,
			})
			corner(frame, UDim.new(0, 4))
			new("UIStroke", { Color = THEME.Line, Transparency = 0.92, Thickness = 1, Parent = frame })
			hudScaled(frame)
			local header = new("Frame", {
				Name = "Header", BackgroundColor3 = THEME.Panel, Size = UDim2.new(1, 0, 0, HUD_HEADER_H), Parent = frame,
			})
			corner(header, UDim.new(0, 4))
			local tint = new("Frame", { Name = "Tint", Size = UDim2.fromScale(1, 1), Parent = header })
			corner(tint, UDim.new(0, 4))
			new("UIGradient", {
				Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 1) }),
				Parent = tint,
			})
			local icon = new("Frame", {
				Name = "Icon", BackgroundTransparency = 1, Position = UDim2.fromOffset(9, 7), Size = UDim2.fromOffset(14, 14), Parent = header,
			})
			label({
				Name = "Title", Position = UDim2.fromOffset(30, 0), Size = UDim2.new(1, -40, 1, 0), Text = title,
				TextXAlignment = Enum.TextXAlignment.Left, Parent = header,
			})
			local line = new("Frame", {
				Name = "Line", Position = UDim2.fromOffset(0, HUD_HEADER_H), Size = UDim2.new(1, 0, 0, 1),
				BackgroundTransparency = 0.25, Parent = frame,
			})
			themed(function() -- accent is a THEME key, so the list recolours with the theme
				local color = THEME[accent]
				tint.BackgroundColor3 = color
				line.BackgroundColor3 = color
				icon:ClearAllChildren()
				Draw.icons[iconKind](icon, color)
			end)
			local body = new("Frame", {
				Name = "Rows", BackgroundTransparency = 1, Position = UDim2.fromOffset(0, HUD_HEADER_H + 3),
				Size = UDim2.new(1, 0, 0, 0), Parent = frame,
			})
			local widget = { Frame = frame, Header = header, Body = body, defaultPos = defaultPos, posKey = "hud." .. name }
			table.insert(HUD.widgets, widget)

			header.InputBegan:Connect(function(input)
				if not Nav.isOpen or input.UserInputType ~= Enum.UserInputType.MouseButton1 then
					return
				end
				local startMouse, startPos = input.Position, frame.Position
				local moveConn, endConn
				moveConn = UserInputService.InputChanged:Connect(function(move)
					if move.UserInputType == Enum.UserInputType.MouseMovement then
						local dx, dy = move.Position.X - startMouse.X, move.Position.Y - startMouse.Y
						frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + dx, startPos.Y.Scale, startPos.Y.Offset + dy)
					end
				end)
				endConn = UserInputService.InputEnded:Connect(function(ended)
					if ended.UserInputType == Enum.UserInputType.MouseButton1 then
						moveConn:Disconnect()
						endConn:Disconnect()
						State.set(widget.posKey, frame.Position)
					end
				end)
			end)
			return widget
		end

		local function setWidgetRows(widget, rows, emptyText)
			local body = widget.Body
			body:ClearAllChildren()
			local count = #rows
			if count == 0 then
				label({
					Name = "Empty", Position = UDim2.fromOffset(10, 0), Size = UDim2.new(1, -20, 0, HUD_ROW_H),
					Text = emptyText, TextSize = CONFIG.SmallTextSize, TextColor3 = THEME.TextDisabled,
					TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Parent = body,
				})
				count = 1
			end
			for index, info in ipairs(rows) do
				local rowFrame = new("Frame", {
					Name = "Row", BackgroundTransparency = 1, Position = UDim2.fromOffset(0, (index - 1) * HUD_ROW_H),
					Size = UDim2.new(1, 0, 0, HUD_ROW_H), Parent = body,
				})
				local x = 10
				if info.arrow ~= nil then
					Draw.arrow(rowFrame, info.arrow, THEME.Arrow, 10, 4)
					x = 26
				end
				label({
					Name = "Label", RichText = true, Position = UDim2.fromOffset(x, 0), Size = UDim2.new(1, -(x + 62), 1, 0),
					Text = info.left, TextSize = CONFIG.SmallTextSize, TextXAlignment = Enum.TextXAlignment.Left,
					TextTruncate = Enum.TextTruncate.AtEnd, Parent = rowFrame,
				})
				label({
					Name = "Value", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 0),
					Size = UDim2.fromOffset(56, HUD_ROW_H), Text = info.right or "", TextSize = CONFIG.SmallTextSize,
					TextColor3 = info.rightColor or THEME.TextSecondary, TextXAlignment = Enum.TextXAlignment.Right, Parent = rowFrame,
				})
			end
			body.Size = UDim2.new(1, 0, 0, count * HUD_ROW_H)
			widget.Frame.Size = UDim2.fromOffset(WIDGET_W, HUD_HEADER_H + 3 + count * HUD_ROW_H + 5)
		end

		HUD.keybinds = makeWidget("Keybinds", "Keybinds", "AccentIcon", "keyboard", UDim2.new(1, -CONFIG.HUDMargin, 0.22, 0))
		HUD.spectators = makeWidget("Spectators", "Spectators", "AccentIcon", "eye", UDim2.new(1, -CONFIG.HUDMargin, 0.52, 0))

		resetHUDPositions = function()
			for _, widget in ipairs(HUD.widgets) do
				widget.Frame.Position = widget.defaultPos
				State.set(widget.posKey, nil)
			end
		end

		--------------------------------------------------------------------------------
		-- KEYBINDS: F5 on a highlighted toggle / button asks for a key
		--------------------------------------------------------------------------------
		local CAPTURE_ACTION = "PurpleUI_Capture"
		local CAPTURE_PRIORITY = Enum.ContextActionPriority.High.Value + 150

		-- keys the menu itself uses (or Roblox needs) can't be bound
		local RESERVED = {}
		for _, keyCode in ipairs({
			CONFIG.ToggleKey, CONFIG.BindKey, CONFIG.TabNextKey, CONFIG.TabPrevKey, CONFIG.GamepadToggleKey,
			Enum.KeyCode.Up, Enum.KeyCode.Down, Enum.KeyCode.Left, Enum.KeyCode.Right, Enum.KeyCode.Return,
			Enum.KeyCode.KeypadEnter, Enum.KeyCode.Backspace, Enum.KeyCode.Delete, Enum.KeyCode.Escape,
			Enum.KeyCode.Slash, Enum.KeyCode.Tab, Enum.KeyCode.DPadUp, Enum.KeyCode.DPadDown, Enum.KeyCode.DPadLeft,
			Enum.KeyCode.DPadRight, Enum.KeyCode.ButtonA, Enum.KeyCode.ButtonB, Enum.KeyCode.ButtonL1,
			Enum.KeyCode.ButtonR1, Enum.KeyCode.ButtonStart, Enum.KeyCode.ButtonSelect,
		}) do
			RESERVED[keyCode] = true
		end

		function Binder.isReserved(keyCode)
			return RESERVED[keyCode] == true or keyCode == Nav.toggleKey
		end

		-- state key shown as ON / OFF in the keybind list (nil for one-shot buttons)
		local function bindStateKey(item)
			if item.kind == "toggle" then
				return item.key
			end
			return nil
		end

		-- toggles, buttons, player selectors, Keybind elements and run-selectors can hold a key
		function Binder.bindable(item)
			local kind = item.kind
			return kind == "toggle" or kind == "action" or kind == "keybind" or kind == "player"
				or (kind == "selector" and item.run ~= nil)
		end

		keybindName = function(item)
			local bind = Binder.byItem[item]
			return bind and keyName(bind.key) or "None"
		end

		local function bindName(bind)
			local same = 0
			for _, other in ipairs(Binder.list) do
				if other.item.label == bind.item.label then
					same += 1
				end
			end
			if same > 1 and bind.context ~= "" then
				return bind.context .. " " .. bind.item.label -- e.g. two "Enable" toggles on different tabs
			end
			return bind.item.label
		end

		refreshKeybindList = function()
			local widget = HUD.keybinds
			local rows = {}
			local sorted = table.clone(Binder.list)
			table.sort(sorted, function(a, b)
				return string.lower(bindName(a)) < string.lower(bindName(b))
			end)
			for _, bind in ipairs(sorted) do
				local name = escapeRich(bindName(bind))
				local key = escapeRich(keyName(bind.key))
				local stateKey = bindStateKey(bind.item)
				if stateKey then
					local on = State.get(stateKey, false)
					table.insert(rows, {
						left = name .. ' <font color="#8C8C96">(' .. key .. ")</font>",
						right = on and "ON" or "OFF",
						rightColor = on and THEME.StateOn or THEME.TextDisabled,
					})
				else
					table.insert(rows, { left = name, right = key })
				end
			end
			local visible = State.get("settings.keybindList", true) and (#rows > 0 or Nav.isOpen)
			widget.Frame.Visible = visible
			widget.Header.Active = Nav.isOpen
			if visible then
				setWidgetRows(widget, rows, "Press " .. keyName(CONFIG.BindKey) .. " on an option")
			end
		end

		refreshSpectators = function()
			local widget = HUD.spectators
			local enabled = State.get("settings.spectatorList", true)
			local rows = {}
			if enabled then
				local myRoot = rootOf(LocalPlayer.Character)
				local found = {}
				for _, player in ipairs(Players:GetPlayers()) do
					if player ~= LocalPlayer and not departing[player]
						and player:GetAttribute("SpectatingUserId") == LocalPlayer.UserId
					then
						local root = rootOf(player.Character)
						local spectator = { player = player }
						if root and myRoot then
							spectator.distance = (root.Position - myRoot.Position).Magnitude * CONFIG.StudsToMeters
							spectator.above = root.Position.Y >= myRoot.Position.Y
						end
						table.insert(found, spectator)
					end
				end
				table.sort(found, function(a, b)
					return (a.distance or math.huge) < (b.distance or math.huge)
				end)
				for _, spectator in ipairs(found) do
					local group = spectator.player:GetAttribute("Group")
					local tag = ""
					if type(group) == "string" and group ~= "" and string.lower(group) ~= "user" then
						tag = '<font color="#E04848">[' .. escapeRich(string.upper(group)) .. "]</font> "
					end
					table.insert(rows, {
						left = tag .. escapeRich(spectator.player.DisplayName),
						right = spectator.distance and string.format("%dm", math.floor(spectator.distance + 0.5)) or "-",
						arrow = spectator.above, -- up = above you, down = below you
					})
				end
			end
			local visible = enabled and (#rows > 0 or Nav.isOpen)
			widget.Frame.Visible = visible
			widget.Header.Active = Nav.isOpen
			if visible then
				setWidgetRows(widget, rows, "No spectators")
			end
		end

		refreshHUD = function()
			refreshKeybindList()
			refreshSpectators()
		end

		modalOpen = function()
			return Popup ~= nil or Binder.active or KeyPrompt.active
		end

		function Binder.remove(item)
			local bind = Binder.byItem[item]
			if not bind then
				return nil
			end
			Binder.byItem[item] = nil
			Binder.byKey[bind.key] = nil
			local index = table.find(Binder.list, bind)
			if index then
				table.remove(Binder.list, index)
			end
			refreshKeybindList()
			refreshItem(item, false)
			return bind
		end

		-- returns the bind that used this key before (it gets moved), if any
		function Binder.set(item, keyCode, context)
			Binder.remove(item)
			local previous = Binder.byKey[keyCode]
			if previous then
				Binder.remove(previous.item)
			end
			local bind = { item = item, key = keyCode, context = context or "" }
			table.insert(Binder.list, bind)
			Binder.byKey[keyCode] = bind
			Binder.byItem[item] = bind
			refreshKeybindList()
			refreshItem(item, false)
			return previous
		end

		local function closeBinder(delay)
			if not Binder.active then
				return
			end
			Binder.active = false
			task.defer(updateTooltip)
			Binder.item = nil
			ContextActionService:UnbindAction(CAPTURE_ACTION)
			local ui = Binder.ui
			Binder.ui = nil
			if ui then
				local function remove()
					ui.blocker:Destroy()
					tween(ui.box, { GroupTransparency = 1 }, 0.12, function()
						ui.box:Destroy()
					end)
				end
				if delay then
					task.delay(delay, remove) -- leave the chosen key on screen for a moment
				else
					remove()
				end
			end
		end
		Binder.close = closeBinder

		local function binderFlash(text)
			local ui = Binder.ui
			if not ui then
				return
			end
			ui.flashToken += 1
			local token = ui.flashToken
			ui.keyText.Text = text
			ui.keyText.TextColor3 = THEME.Danger
			task.delay(1.2, function()
				if Binder.ui == ui and ui.flashToken == token then
					ui.keyText.Text = "Press a key…"
					ui.keyText.TextColor3 = THEME.TextSecondary
				end
			end)
		end

		-- captures the next key while the prompt is open (sinks everything so nothing else reacts)
		local function onCapture(_, inputState, input)
			if inputState ~= Enum.UserInputState.Begin or not Binder.active then
				return Enum.ContextActionResult.Sink
			end
			local keyCode = input.KeyCode
			if input.UserInputType ~= Enum.UserInputType.Keyboard and not string.find(keyCode.Name, "^Button") then
				return Enum.ContextActionResult.Sink -- thumbsticks and other analog input
			end
			local item, context = Binder.item, Binder.context
			if keyCode == Nav.toggleKey or keyCode == CONFIG.GamepadToggleKey then
				closeBinder()
				setOpen(false)
			elseif keyCode == Enum.KeyCode.Backspace or keyCode == Enum.KeyCode.ButtonB or keyCode == CONFIG.BindKey then
				closeBinder()
			elseif keyCode == Enum.KeyCode.Delete then
				closeBinder()
				if Binder.remove(item) then
					notify("Keybind removed", item.label .. " has no key now", "info")
				end
			elseif RESERVED[keyCode] then
				binderFlash(keyName(keyCode) .. " is reserved")
			else
				Binder.swallow[keyCode] = true -- this same press must not also run the option
				Binder.ui.keyText.Text = keyName(keyCode)
				Binder.ui.keyText.TextColor3 = THEME.Text
				local previous = Binder.set(item, keyCode, context)
				closeBinder(0.35)
				local message = item.label .. " is bound to " .. keyName(keyCode)
				if previous and previous.item ~= item then
					message ..= " (moved from " .. previous.item.label .. ")"
				end
				notify("Keybind set", message, "success")
			end
			return Enum.ContextActionResult.Sink
		end

		function Binder.open(row)
			if not row then
				return
			end
			local item = row.item
			if not Binder.bindable(item) then
				notify("Can't bind this", "Only toggles and buttons can have a keybind.", "warning")
				return
			end
			closeBinder()
			local entry = currentEntry()
			Binder.active = true
			Binder.item = item
			Binder.context = entry and (entry.page.tabs and entry.page.tabs[entry.tab].name or entry.page.title) or ""

			local blocker = new("TextButton", {
				Name = "BindBlocker", Text = "", BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.45,
				Size = UDim2.fromScale(1, 1), ZIndex = 10, Parent = popupLayer,
			})
			local box = new("CanvasGroup", {
				Name = "KeybindPrompt", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 8),
				Size = UDim2.fromOffset(300, 170), BackgroundColor3 = THEME.Panel, GroupTransparency = 1, ZIndex = 11,
				Parent = popupLayer,
			})
			corner(box, UDim.new(0, 5))
			local header = new("Frame", { Name = "Header", BackgroundColor3 = THEME.Secondary, Size = UDim2.new(1, 0, 0, 32), Parent = box })
			local icon = new("Frame", {
				Name = "Icon", BackgroundTransparency = 1, Position = UDim2.fromOffset(12, 9), Size = UDim2.fromOffset(14, 14), Parent = header,
			})
			Draw.icons.keyboard(icon, THEME.AccentIcon)
			label({
				Name = "Title", Position = UDim2.fromOffset(34, 0), Size = UDim2.new(1, -44, 1, 0), Text = "Set Keybind",
				TextXAlignment = Enum.TextXAlignment.Left, Parent = header,
			})
			new("Frame", { Name = "Line", Position = UDim2.fromOffset(0, 32), Size = UDim2.new(1, 0, 0, 2), BackgroundColor3 = THEME.Accent, Parent = box })
			label({
				Name = "Option", Position = UDim2.fromOffset(12, 42), Size = UDim2.new(1, -24, 0, 22), Text = item.label,
				TextColor3 = THEME.StateOn, TextTruncate = Enum.TextTruncate.AtEnd, Parent = box,
			})
			local keycap = new("Frame", {
				Name = "Keycap", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 70),
				Size = UDim2.fromOffset(170, 36), BackgroundColor3 = THEME.Background, Parent = box,
			})
			corner(keycap, UDim.new(0, 4))
			local capStroke = new("UIStroke", { Color = THEME.Accent, Thickness = 1, Transparency = 0.1, Parent = keycap })
			local keyText = label({
				Name = "Key", Size = UDim2.fromScale(1, 1), Text = "Press a key…", TextColor3 = THEME.TextSecondary, Parent = keycap,
			})
			local existingBind = Binder.byItem[item]
			label({
				Name = "Current", Position = UDim2.fromOffset(12, 112), Size = UDim2.new(1, -24, 0, 20),
				Text = "Current: " .. (existingBind and keyName(existingBind.key) or "none"),
				TextSize = CONFIG.SmallTextSize, TextColor3 = THEME.TextSecondary, Parent = box,
			})
			label({
				Name = "Hint", Position = UDim2.fromOffset(12, 138), Size = UDim2.new(1, -24, 0, 20),
				Text = "Backspace: cancel    |    Delete: remove", TextSize = CONFIG.SmallTextSize - 1,
				TextColor3 = THEME.TextDisabled, Parent = box,
			})
			blocker.Activated:Connect(function()
				if Binder.ui and Binder.ui.blocker == blocker then
					closeBinder()
				end
			end)
			Binder.ui = { blocker = blocker, box = box, keyText = keyText, flashToken = 0 }
		updateTooltip()
			tween(box, { GroupTransparency = 0, Position = UDim2.new(0.5, 0, 0.5, 0) }, 0.14)
			if animationsOn() then
				local blink = TweenInfo.new(0.7, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
				TweenService:Create(capStroke, blink, { Transparency = 0.75 }):Play()
			end
			ContextActionService:BindActionAtPriority(
				CAPTURE_ACTION, onCapture, false, CAPTURE_PRIORITY, Enum.UserInputType.Keyboard, Enum.UserInputType.Gamepad1
			)
		end

		function Binder.trigger(bind)
			local item = bind.item
			if activateItem(item) == false then
				return
			end
			local stateKey = bindStateKey(item)
			if stateKey then
				local on = State.get(stateKey, false)
				notify(item.label, on and "Enabled" or "Disabled", on and "success" or "info", 2.5)
			elseif item.kind ~= "selector" and item.kind ~= "keybind" then
				notify(item.label, "Activated", "info", 2.5)
			end
		end
		openBinder = Binder.open

		-- bound keys work with the menu open or closed (not while typing in chat / a text box)
		connect(UserInputService.InputBegan, function(input, gameProcessed)
			local keyCode = input.KeyCode
			if Binder.swallow[keyCode] then
				Binder.swallow[keyCode] = nil
				return
			end
			if gameProcessed or Binder.active or KeyPrompt.active then
				return
			end
			local bind = Binder.byKey[keyCode]
			if bind then
				Binder.trigger(bind)
			end
		end)
		connect(UserInputService.InputEnded, function(input)
			Binder.swallow[input.KeyCode] = nil
		end)

		-- spectators + player-row icons refresh twice a second
		local hudClock = 0
		connect(RunService.Heartbeat, function(dt)
			hudClock += dt
			if hudClock < 0.5 then
				return
			end
			hudClock = 0
			refreshSpectators()
			if Nav.isOpen and current.list then
				for _, row in ipairs(current.list.Rows) do
					if row.refreshStatus then
						row.refreshStatus()
					end
				end
			end
		end)

		-- open-key prompt: "Selected: F2 - Press Enter" (on launch, and from Settings > Menu Key) --
		local KEYPROMPT_ACTION = "PurpleUI_OpenKey"
		local OPEN_KEY_BLOCKED = {}
		for _, keyCode in ipairs({
			Enum.KeyCode.Up, Enum.KeyCode.Down, Enum.KeyCode.Left, Enum.KeyCode.Right, Enum.KeyCode.Return,
			Enum.KeyCode.KeypadEnter, Enum.KeyCode.Backspace, Enum.KeyCode.Escape, Enum.KeyCode.Slash, Enum.KeyCode.Tab,
			Enum.KeyCode.W, Enum.KeyCode.A, Enum.KeyCode.S, Enum.KeyCode.D, Enum.KeyCode.Space,
			CONFIG.BindKey, CONFIG.TabNextKey, CONFIG.TabPrevKey,
		}) do
			OPEN_KEY_BLOCKED[keyCode] = true
		end

		local promptHolder = new("Frame", {
			Name = "OpenKeyPrompt", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -CONFIG.PromptOffset), Size = UDim2.fromOffset(560, 96), Visible = false, Parent = hudScreen,
		})
		corner(promptHolder, UDim.new(0, 8))
		hudScaled(promptHolder)
		local promptStroke = new("UIStroke", { Color = THEME.Line, Transparency = 1, Thickness = 1, Parent = promptHolder })
		local promptCard = new("CanvasGroup", {
			Name = "Card", BackgroundColor3 = Color3.fromRGB(22, 22, 25), BackgroundTransparency = 0.04,
			Size = UDim2.fromScale(1, 1), GroupTransparency = 1, Parent = promptHolder,
		})
		corner(promptCard, UDim.new(0, 8))
		local promptBar = new("Frame", {
			Name = "AccentBar", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 18, 0.5, 0),
			Size = UDim2.fromOffset(4, 52), Parent = promptCard,
		})
		corner(promptBar, FULL)
		themed(function()
			promptBar.BackgroundColor3 = THEME.Accent
		end)
		local promptTop = label({
			Name = "Top", Position = UDim2.fromOffset(40, 9), Size = UDim2.new(1, -96, 0, 36),
			TextSize = CONFIG.TitleTextSize + 2, Text = "", TextTruncate = Enum.TextTruncate.AtEnd, Parent = promptCard,
		})
		local promptMark = Draw.emblem(promptCard, 24, THEME.Text)
		promptMark.Position = UDim2.new(1, -40, 0, 14)
		new("Frame", {
			Name = "Separator", Position = UDim2.fromOffset(40, 50), Size = UDim2.new(1, -80, 0, 1),
			BackgroundColor3 = THEME.Line, BackgroundTransparency = 0.9, Parent = promptCard,
		})
		local promptBottom = label({
			Name = "Bottom", Position = UDim2.fromOffset(40, 56), Size = UDim2.new(1, -80, 0, 28), Text = "",
			TextSize = CONFIG.SmallTextSize, TextColor3 = THEME.TextSecondary, TextTruncate = Enum.TextTruncate.AtEnd, Parent = promptCard,
		})

		local function setPromptHint(text, color)
			promptBottom.Text = text
			promptBottom.TextColor3 = color or THEME.TextSecondary
		end

		local function closeKeyPrompt()
			if not KeyPrompt.active then
				return
			end
			KeyPrompt.active = false
			ContextActionService:UnbindAction(KEYPROMPT_ACTION)
			KeyPrompt.token += 1
			local token = KeyPrompt.token
			tween(promptHolder, { Position = UDim2.new(0.5, 0, 1, -CONFIG.PromptOffset + 12) }, 0.16)
			tween(promptStroke, { Transparency = 1 }, 0.16)
			tween(promptCard, { GroupTransparency = 1 }, 0.16, function()
				if token == KeyPrompt.token then
					promptHolder.Visible = false
				end
			end)
			updateTooltip()
			local done = KeyPrompt.onDone
			KeyPrompt.onDone = nil
			if done then
				done()
			end
		end

		local function promptFlash(text)
			KeyPrompt.flash += 1
			local token = KeyPrompt.flash
			setPromptHint(text, THEME.Danger)
			task.delay(1.4, function()
				if KeyPrompt.flash == token and KeyPrompt.active then
					setPromptHint(KeyPrompt.hint)
				end
			end)
		end

		-- sinks every key while the prompt is up, so nothing else reacts to the choice
		local function onOpenKeyInput(_, inputState, input)
			if inputState ~= Enum.UserInputState.Begin or not KeyPrompt.active then
				return Enum.ContextActionResult.Sink
			end
			local keyCode = input.KeyCode
			if keyCode == Enum.KeyCode.Return or keyCode == Enum.KeyCode.KeypadEnter or keyCode == Enum.KeyCode.ButtonA then
				if KeyPrompt.selected then
					Nav.toggleKey = KeyPrompt.selected
					bindToggle()
					refreshRows(false) -- Settings > Menu Key shows the new key
					notify("Menu key set", "Press " .. keyName(Nav.toggleKey) .. " to open the menu.", "success")
					closeKeyPrompt()
				else
					promptFlash("Press the key you want first")
				end
			elseif keyCode == Enum.KeyCode.Backspace or keyCode == Enum.KeyCode.Escape or keyCode == Enum.KeyCode.ButtonB then
				notify("Menu key", "Press " .. keyName(Nav.toggleKey) .. " to open the menu.", "info")
				closeKeyPrompt()
			elseif input.UserInputType == Enum.UserInputType.Keyboard then
				if OPEN_KEY_BLOCKED[keyCode] then
					promptFlash(keyName(keyCode) .. " can't open the menu - try another key")
				elseif Binder.byKey[keyCode] then
					promptFlash(keyName(keyCode) .. " is already a keybind - try another key")
				else
					KeyPrompt.selected = keyCode
					KeyPrompt.flash += 1
					promptTop.Text = "Selected: " .. keyName(keyCode) .. " - Press Enter"
					KeyPrompt.hint = "Press another key to change or Backspace to cancel"
					setPromptHint(KeyPrompt.hint)
				end
			end
			return Enum.ContextActionResult.Sink
		end

		openKeyPrompt = function(onDone)
			if KeyPrompt.active then
				return
			end
			if not UserInputService.KeyboardEnabled then -- phones, tablets and consoles keep the default key
				if onDone then
					onDone()
				end
				return
			end
			Binder.close()
			closePopup(true)
			KeyPrompt.active = true
			KeyPrompt.selected = nil
			KeyPrompt.onDone = onDone
			KeyPrompt.token += 1
			KeyPrompt.flash += 1
			promptTop.Text = "Which key should open the menu?"
			KeyPrompt.hint = "Press a key, then Enter  -  Backspace keeps " .. keyName(Nav.toggleKey)
			setPromptHint(KeyPrompt.hint)
			promptHolder.Visible = true
			promptHolder.Position = UDim2.new(0.5, 0, 1, -CONFIG.PromptOffset + 12)
			tween(promptHolder, { Position = UDim2.new(0.5, 0, 1, -CONFIG.PromptOffset) }, 0.18)
			tween(promptStroke, { Transparency = 0.85 }, 0.18)
			tween(promptCard, { GroupTransparency = 0 }, 0.18)
			updateTooltip()
			ContextActionService:BindActionAtPriority(
				KEYPROMPT_ACTION, onOpenKeyInput, false, CAPTURE_PRIORITY + 10, Enum.UserInputType.Keyboard, Enum.UserInputType.Gamepad1
			)
		end

		-- tooltip: what the highlighted option does, bottom centre of the screen -------------
		local tip = label({
			Name = "Tooltip", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -CONFIG.TooltipOffset),
			Size = UDim2.fromOffset(0, 0), AutomaticSize = Enum.AutomaticSize.XY, BackgroundColor3 = Color3.new(0, 0, 0),
			BackgroundTransparency = 1, TextTransparency = 1, Text = "", ZIndex = 20, Parent = screen,
		})
		corner(tip, UDim.new(0, 6))
		new("UIPadding", {
			PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12), PaddingTop = UDim.new(0, 5),
			PaddingBottom = UDim.new(0, 5), Parent = tip,
		})
		hudScaled(tip)

		local function tipFor(item)
			local text = item.tip or TIPS[item.key or ""] or TIPS[item.label]
			if text then
				return text
			elseif item.kind == "submenu" then
				return "Opens " .. item.label
			elseif item.kind == "playerEntry" then
				return "Enter selects or unselects this player"
			elseif item.kind == "keybind" then
				return "Press Enter to choose a different key"
			elseif item.kind == "color" then
				return "Opens the colour picker"
			elseif item.kind == "input" then
				return item.isSearch and "Press Enter, type, then press Enter again to filter" or "Press Enter to type"
			elseif item.kind == "player" then
				return "Left / Right picks a player, Enter confirms"
			elseif item.kind == "selector" and not item.run then
				return "Left / Right changes it, Enter shows the list"
			elseif item.kind == "choice" then
				return item.key == "settings.theme" and ("Switches the menu colour to " .. item.label)
					or ("Uses the " .. item.label .. " banner")
			end
			return nil
		end

		updateTooltip = function()
			local row = Nav.isOpen and State.get("settings.tooltips", true) and not modalOpen() and selectedRow()
			local text = row and tipFor(row.item)
			if text then
				tip.Text = text
				tween(tip, { BackgroundTransparency = 0.12, TextTransparency = 0 }, 0.12)
			else
				tween(tip, { BackgroundTransparency = 1, TextTransparency = 1 }, 0.12)
			end
		end

		HUD.screen = hudScreen
	end

	--------------------------------------------------------------------------------
	-- INPUT
	--------------------------------------------------------------------------------
	local NAV_ACTION = "PurpleUI_Navigate"
	local WHEEL_ACTION = "PurpleUI_Wheel"
	local TOGGLE_ACTION = "PurpleUI_Toggle"
	local PRIORITY = Enum.ContextActionPriority.High.Value + 50

	local KEYMAP = {
		[Enum.KeyCode.Up] = "up",
		[Enum.KeyCode.Down] = "down",
		[Enum.KeyCode.Left] = "left",
		[Enum.KeyCode.Right] = "right",
		[Enum.KeyCode.Return] = "enter",
		[Enum.KeyCode.KeypadEnter] = "enter",
		[Enum.KeyCode.Backspace] = "back",
		[Enum.KeyCode.DPadUp] = "up",
		[Enum.KeyCode.DPadDown] = "down",
		[Enum.KeyCode.DPadLeft] = "left",
		[Enum.KeyCode.DPadRight] = "right",
		[Enum.KeyCode.ButtonA] = "enter",
		[Enum.KeyCode.ButtonB] = "back",
		[CONFIG.TabNextKey] = "tabNext",
		[CONFIG.TabPrevKey] = "tabPrev",
		[CONFIG.BindKey] = "bind",
		[Enum.KeyCode.ButtonR1] = "tabNext",
		[Enum.KeyCode.ButtonL1] = "tabPrev",
	}
	local REPEATS = { up = true, down = true, left = true, right = true }
	local NAV_KEYS = {}
	for keyCode in pairs(KEYMAP) do
		table.insert(NAV_KEYS, keyCode)
	end

	local function dispatch(command)
		if not Nav.isOpen or Binder.active then
			return
		end
		if command == "bind" then
			if Popup then
				return
			end
			-- the row under the mouse if the mouse was used last, otherwise the highlighted row
			local hovered = Nav.hoverRow
			if Nav.mouseFresh and hovered and hovered.list == current.list then
				Binder.open(hovered)
			else
				Binder.open(selectedRow())
			end
			return
		end
		Nav.mouseFresh = false
		if command == "tabNext" or command == "tabPrev" then
			-- E / Q always switch tabs, even when a slider or player selector is selected
			local entry = currentEntry()
			if entry and entry.page.tabs then
				local dir = command == "tabNext" and 1 or -1
				switchTab(entry.tab + dir, dir)
			end
			return
		end
		if Popup then
			if command == "up" then
				popupMove(-1)
			elseif command == "down" then
				popupMove(1)
			elseif command == "enter" then
				popupConfirm()
			elseif command == "back" then
				closePopup(false)
			end
			return
		end
		if command == "up" then
			moveSelection(-1)
		elseif command == "down" then
			moveSelection(1)
		elseif command == "left" then
			horizontal(-1)
		elseif command == "right" then
			horizontal(1)
		elseif command == "enter" then
			activate()
		elseif command == "back" then
			goBack()
		end
	end

	local repeatToken = 0

	local function isHeld(input)
		if input.UserInputType == Enum.UserInputType.Keyboard then
			return UserInputService:IsKeyDown(input.KeyCode)
		end
		return UserInputService:IsGamepadButtonDown(input.UserInputType, input.KeyCode)
	end

	local function onNavigate(_, inputState, input)
		local command = KEYMAP[input.KeyCode]
		if not Nav.isOpen or not command then
			return Enum.ContextActionResult.Pass
		end
		if inputState == Enum.UserInputState.Begin then
			dispatch(command) -- exactly one step per press
			if REPEATS[command] then
				repeatToken += 1
				local token = repeatToken
				task.delay(CONFIG.RepeatDelay, function()
					while token == repeatToken and Nav.isOpen and isHeld(input) do
						dispatch(command)
						task.wait(CONFIG.RepeatRate)
					end
				end)
			end
		elseif inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel then
			repeatToken += 1
		end
		return Enum.ContextActionResult.Sink
	end

	local function pointInside(gui, point)
		local position, size = gui.AbsolutePosition, gui.AbsoluteSize
		return point.X >= position.X and point.X <= position.X + size.X and point.Y >= position.Y and point.Y <= position.Y + size.Y
	end

	local function onWheel(_, inputState, input)
		if not Nav.isOpen or inputState ~= Enum.UserInputState.Change then
			return Enum.ContextActionResult.Pass
		end
		local mouse = UserInputService:GetMouseLocation()
		local dir = input.Position.Z > 0 and -1 or 1
		if Popup then
			if pointInside(Popup.frame, mouse) then
				popupMove(dir)
				return Enum.ContextActionResult.Sink
			end
		elseif not Binder.active and current.list and pointInside(current.list.Frame, mouse) then
			moveSelection(dir)
			return Enum.ContextActionResult.Sink
		end
		if pointInside(menuFrame, mouse) or (Panel.frame.Visible and pointInside(Panel.frame, mouse)) then
			return Enum.ContextActionResult.Sink -- don't zoom the camera while scrolling over the menu
		end
		return Enum.ContextActionResult.Pass
	end

	local function bindNavigation()
		ContextActionService:BindActionAtPriority(NAV_ACTION, onNavigate, false, PRIORITY, table.unpack(NAV_KEYS))
		ContextActionService:BindActionAtPriority(WHEEL_ACTION, onWheel, false, PRIORITY, Enum.UserInputType.MouseWheel)
	end

	local function unbindNavigation()
		ContextActionService:UnbindAction(NAV_ACTION)
		ContextActionService:UnbindAction(WHEEL_ACTION)
		repeatToken += 1
	end

	--------------------------------------------------------------------------------
	-- LAYOUT / SCALING
	--------------------------------------------------------------------------------
	local function viewportSize()
		local camera = workspace.CurrentCamera
		if camera then
			return camera.ViewportSize
		end
		return screen.AbsoluteSize
	end

	applyLayout = function(animate)
		local viewport = viewportSize()
		if viewport.X < 10 or viewport.Y < 10 then
			return
		end
		local scale = math.max(viewport.Y / CONFIG.BaseViewportHeight, CONFIG.MinScale) * (State.get("settings.scale", 100) / 100)
		scale = math.min(scale, (viewport.Y - 24) / MAX_MENU_H, (viewport.X - 16) / CONFIG.Width)
		scale = math.max(scale, 0.35)
		uiScale.Scale = scale
		for _, hudScale in ipairs(HUD.scales) do
			hudScale.Scale = scale
		end

		local margin = CONFIG.ScreenMargin * scale
		local mode = State.get("settings.position", 1)
		local x
		if mode == 2 then
			x = (viewport.X - CONFIG.Width * scale) / 2
		elseif mode == 3 then
			x = viewport.X - margin - TOTAL_W * scale
		else
			x = margin
		end
		x = math.max(8, x)
		local y = math.max(12, (viewport.Y - MAX_MENU_H * scale) / 2)
		if Nav.customPos then -- dragged by the banner
			x, y = Nav.customPos.X, Nav.customPos.Y
			if Nav.constrain then -- window:LockScreenBoundaries(true)
				x = math.clamp(x, 0, math.max(0, viewport.X - CONFIG.Width * scale))
				y = math.clamp(y, 0, math.max(0, viewport.Y - menuFrame.Size.Y.Offset * scale))
			end
		end
		local position = UDim2.fromOffset(math.floor(x + 0.5), math.floor(y + 0.5))
		if animate and Nav.isOpen then
			tween(root, { Position = position }, 0.18)
		else
			root.Position = position
		end
	end

	-- drag the window by its banner while it is open (mouse)
	banner.Active = true
	banner.InputBegan:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 or not Nav.isOpen or modalOpen() then
			return
		end
		local startMouse = UserInputService:GetMouseLocation()
		local startPos = Vector2.new(root.Position.X.Offset, root.Position.Y.Offset)
		local moveConn, endConn
		moveConn = UserInputService.InputChanged:Connect(function(move)
			if move.UserInputType ~= Enum.UserInputType.MouseMovement then
				return
			end
			local mouse = UserInputService:GetMouseLocation()
			Nav.customPos = Vector2.new(startPos.X + mouse.X - startMouse.X, startPos.Y + mouse.Y - startMouse.Y)
			applyLayout(false)
		end)
		endConn = UserInputService.InputEnded:Connect(function(ended)
			if ended.UserInputType == Enum.UserInputType.MouseButton1 then
				moveConn:Disconnect()
				endConn:Disconnect()
			end
		end)
	end)

	local cameraConnection
	local function hookCamera()
		if cameraConnection then
			cameraConnection:Disconnect()
			cameraConnection = nil
		end
		local camera = workspace.CurrentCamera
		if camera then
			cameraConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
				applyLayout(false)
			end)
		end
		applyLayout(false)
	end
	connect(workspace:GetPropertyChangedSignal("CurrentCamera"), hookCamera)

	--------------------------------------------------------------------------------
	-- OPEN / CLOSE (F2)
	--------------------------------------------------------------------------------
	local openToken = 0

	setOpen = function(open)
		if Nav.isOpen == open then
			return
		end
		Nav.isOpen = open
		openToken += 1
		local token = openToken

		if open then
			if not State.get("settings.restore", true) then
				Nav.stack = { newEntry(Pages.main) }
				renderPage(0)
			end
			screen.Enabled = true
			applyLayout(false)
			bindNavigation()
			refreshRows(false)
			holder.Position = UDim2.fromOffset(0, 14)
			tween(holder, { Position = UDim2.fromOffset(0, 0) }, 0.18)
			tween(menuCanvas, { GroupTransparency = 0 }, 0.18)
			tween(menuStroke, { Transparency = 0.9 }, 0.18)
			updateSelection(false)
			refreshHUD() -- lists also show while the menu is open, even when empty, so they can be moved
		else
			unbindNavigation()
			closePopup(true)
			Binder.close()
			Nav.hoverRow = nil
			refreshHUD()
			updateTooltip()
			tween(holder, { Position = UDim2.fromOffset(0, 14) }, 0.15)
			tween(menuStroke, { Transparency = 1 }, 0.15)
			tween(menuCanvas, { GroupTransparency = 1 }, 0.15, function()
				if token == openToken and not Nav.isOpen then
					screen.Enabled = false -- nothing left on screen to capture input
				end
			end)
			updatePanel()
		end
	end

	-- (re)binds the open / close key; called again when the menu key is changed
	bindToggle = function()
		ContextActionService:BindActionAtPriority(TOGGLE_ACTION, function(_, inputState)
			if inputState == Enum.UserInputState.Begin then
				setOpen(not Nav.isOpen)
			end
			return Enum.ContextActionResult.Sink
		end, true, PRIORITY, Nav.toggleKey, CONFIG.GamepadToggleKey)
		ContextActionService:SetTitle(TOGGLE_ACTION, "Menu") -- on-screen button on touch devices
	end
	bindToggle()

	--------------------------------------------------------------------------------
	-- PLAYERS JOINING / LEAVING
	--------------------------------------------------------------------------------
	local function onRosterChanged()
		local entry = currentEntry()
		if not entry or not current.list then
			return
		end
		if type(getSource(entry).items) == "function" then
			mountList(entry, nil) -- rebuild the live player list, keeping the selection
		else
			for _, row in ipairs(current.list.Rows) do
				if row.item.kind == "player" then
					row.refresh(false)
				end
			end
		end
		updatePanel()
	end

	connect(Players.PlayerAdded, function()
		task.defer(onRosterChanged)
	end)

	connect(Players.PlayerRemoving, function(player)
		local before = getTargets()
		local index = table.find(before, player)
		departing[player] = true

		Selected[player] = nil

		-- move the shared target to a neighbouring player instead of leaving it empty
		if Nav.target == player then
			local after = getTargets()
			Nav.target = after[math.clamp(index or 1, 1, math.max(#after, 1))]
		end
		for key, value in pairs(State.values) do
			if value == player then
				State.values[key] = nil -- per-row targets re-resolve to a valid player
			end
		end

		onRosterChanged()
		refreshSpectators()

		task.delay(5, function()
			departing[player] = nil
		end)
	end)

	--------------------------------------------------------------------------------
	-- START
	--------------------------------------------------------------------------------
	Nav.stack = { newEntry(Pages.main) }
	renderPage(0)
	hookCamera()
	refreshHUD()
	-- ask for the open key once the calling script has finished adding tabs (window:SetKeyPrompt(false) skips it)
	task.defer(function()
		if Nav.destroyed then
			return
		end
		if Nav.askKey then
			openKeyPrompt()
		else
			notify("Menu loaded", "Press " .. keyName(Nav.toggleKey) .. " to open the menu.", "info")
		end
	end)

	--------------------------------------------------------------------------------
	-- PUBLIC API: window, tabs, sections and elements
	--------------------------------------------------------------------------------
	local window = {}
	do
		local elementCount = 0
		local refreshPending = false

		local function newKey()
			elementCount += 1
			return "element." .. elementCount
		end

		-- content added or renamed after the window was built: redraw the open page next frame
		local function scheduleRefresh()
			if refreshPending then
				return
			end
			refreshPending = true
			task.defer(function()
				refreshPending = false
				if not Nav.destroyed and current.view then
					renderPage(0)
				end
			end)
		end

		-- the content tree (tabs > sections > elements, dropdowns and search bars nest) becomes
		-- the flat list of rows the menu draws
		local function flatten(children, out)
			for _, node in ipairs(children) do
				if node.section then
					if node.item then
						table.insert(out, node.item) -- "--- Name ---" divider (unnamed sections have none)
					end
					flatten(node.children, out)
				elseif node.search then
					table.insert(out, node.item)
					local query = string.lower(State.get(node.item.key, ""))
					if query == "" then
						flatten(node.children, out)
					else
						local found = {}
						for _, child in ipairs(node.children) do
							local item = child.item
							if item and item.label and string.find(string.lower(item.label), query, 1, true) then
								table.insert(found, child)
							end
						end
						flatten(found, out)
					end
				elseif node.playerList then
					for _, item in ipairs(node.header) do
						table.insert(out, item)
					end
					local query = State.get(node.header[1].key, "")
					local players = filteredPlayers(query)
					for _, player in ipairs(players) do
						table.insert(out, Item.playerEntry(player))
					end
					if #players == 0 then
						table.insert(out, { kind = "empty", label = query ~= "" and "No matching players" or "No Players" })
					end
				elseif node.item then
					table.insert(out, node.item)
				end
			end
			return out
		end

		local function toImage(image)
			if image == nil or image == "" then
				return nil
			elseif tonumber(image) then
				return "rbxassetid://" .. tostring(image)
			end
			return tostring(image)
		end

		----------------------------------------------------------------------------
		-- every element: ChangeText, Tooltip, Set, Get
		----------------------------------------------------------------------------
		local Element = {}
		Element.__index = Element
		local Container = setmetatable({}, { __index = Element })
		Container.__index = Container

		local function element(node)
			return setmetatable({ _node = node, _item = node.item }, Element)
		end

		local function container(node, children)
			return setmetatable({ _node = node, _item = node.item, _children = children }, Container)
		end

		local function add(parent, node)
			table.insert(parent._children, node)
			scheduleRefresh()
			return node
		end

		-- Args(<String> NewText, <Boolean?> PlayAnimation)
		function Element:ChangeText(text, playAnimation)
			local item = self._item
			if item then
				item.label = tostring(text)
				if type(item.page) == "table" then
					item.page.title = item.label
				end
				item.animate = playAnimation == true or nil
				scheduleRefresh()
			end
			return self
		end

		-- Args(<String?> Text) - hint shown at the bottom of the screen while this element is highlighted
		function Element:Tooltip(text)
			if self._item then
				self._item.tip = text ~= nil and tostring(text) or nil
				updateTooltip()
			end
			return self
		end

		-- Args(<Any> Value, <Function?> Callback)
		-- Toggle: true / false   Slider: number   Keybind: "G" / Enum.KeyCode.G / "None"
		-- TextBox: string        ColorWheel: Color3   Selector: option   Title / Label: text
		function Element:Set(value, callback)
			local item = self._item
			local kind = item and item.kind
			if kind == "toggle" then
				local state = value == true
				State.set(item.key, state)
				refreshItem(item, true)
				refreshKeybindList()
				local run = callback or item.callback
				if run then
					emit({ label = item.label, callback = run }, state)
				end
			elseif kind == "slider" then
				applySlider(item, tonumber(value) or item.min, true)
			elseif kind == "keybind" then
				local keyCode = toKeyCode(value)
				if keyCode then
					Binder.set(item, keyCode, "")
				else
					Binder.remove(item)
				end
			elseif kind == "input" then
				State.set(item.key, tostring(value or ""))
				refreshItem(item, false)
				local run = callback or item.callback
				if run then
					emit({ label = item.label, callback = run }, State.get(item.key, ""))
				end
			elseif kind == "color" then
				if typeof(value) == "Color3" then
					State.set(item.key, value)
					if item.page then
						item.page.sync(value)
					end
					refreshRows(false)
					emit(item, value)
				end
			elseif kind == "selector" then
				local index = table.find(item.options, tostring(value)) or tonumber(value)
				if index and item.options[index] then
					State.set(item.key, index)
					refreshItem(item, true)
					selectorChanged(item, index)
				end
			elseif kind == "title" or kind == "label" then
				self:ChangeText(value)
			end
			return self
		end

		-- current value (Toggle bool, Slider number, TextBox text, ColorWheel Color3, Selector option, Keybind key name)
		function Element:Get()
			local item = self._item
			if not item then
				return nil
			elseif item.kind == "keybind" then
				return keybindName(item)
			elseif item.kind == "selector" then
				return item.options[State.get(item.key, 1)]
			elseif item.kind == "title" or item.kind == "label" then
				return item.label
			end
			return State.get(item.key)
		end

		----------------------------------------------------------------------------
		-- containers (tab, section, dropdown, search bar) create elements
		----------------------------------------------------------------------------
		-- Args(<String> Name)
		function Container:Section(name)
			local node = { section = true, children = {} }
			if name ~= nil and tostring(name) ~= "" then
				node.item = Item.divider(tostring(name))
			end
			add(self, node)
			return container(node, node.children)
		end

		-- Args(<String> Name)
		function Container:Title(name)
			return element(add(self, { item = { kind = "title", label = tostring(name) } }))
		end

		-- Args(<String> LabelText, <Number?> TextSize, <Color3?> TextColor)
		function Container:Label(text, textSize, textColor)
			return element(add(self, { item = { kind = "label", label = tostring(text), size = textSize, color = textColor } }))
		end

		-- Args(<String> Name, <Function> Callback)  Callback(<Boolean> State)
		function Container:Toggle(name, callback)
			local item = Item.toggle(tostring(name), newKey(), false)
			item.callback = callback
			return element(add(self, { item = item }))
		end

		-- Args(<String> Name, <Function> Callback)
		function Container:Button(name, callback)
			local item = Item.action(tostring(name))
			item.callback = callback
			return element(add(self, { item = item }))
		end

		-- Args(<String> Name) - a row with an arrow that opens its own page; add elements to it like a section
		function Container:Dropdown(name)
			local node = { children = {} }
			node.page = {
				title = tostring(name),
				items = function()
					return flatten(node.children, {})
				end,
			}
			node.item = Item.submenu(tostring(name), node.page)
			add(self, node)
			return container(node, node.children)
		end

		-- Args(<String> Name, <String?> TabImage) - on a dropdown: gives its page tabs (E / Q switch them)
		function Container:Tab(name, image)
			local page = self._node and self._node.page
			if not page then
				error("Tab works on the window or on a dropdown", 2)
			end
			page.tabs = page.tabs or {}
			local tabNode = { children = {} }
			table.insert(page.tabs, {
				name = tostring(name),
				image = toImage(image),
				items = function()
					return flatten(tabNode.children, {})
				end,
			})
			scheduleRefresh()
			return container(tabNode, tabNode.children)
		end

		-- Args(<String> Name, <Function> Callback, <Number?> MaximumValue, <Number?> MinimumValue, <Number?> Step)
		-- Without Step it moves about 1% of the range per Left / Right (0-100 -> 1, 50-2000 -> 10)
		function Container:Slider(name, callback, maximum, minimum, increment)
			local maxValue, minValue = tonumber(maximum) or 100, tonumber(minimum) or 0
			if maxValue < minValue then
				maxValue, minValue = minValue, maxValue
			end
			local range = maxValue - minValue
			local step = tonumber(increment) or (range > 0 and 10 ^ (math.floor(math.log10(range)) - 2) or 1)
			local format = step >= 1 and "%d" or (step >= 0.1 and "%.1f" or "%.2f")
			local item = Item.slider(tostring(name), newKey(), {
				min = minValue, max = maxValue, step = step, default = minValue, format = format,
			})
			item.callback = callback
			return element(add(self, { item = item }))
		end

		-- Args(<String> PlaceholderText) - rows added to it are filtered by what you type
		function Container:SearchBar(placeholder)
			local node = { search = true, children = {} }
			node.item = Item.search(tostring(placeholder or "Search..."), newKey(), "Type to filter")
			add(self, node)
			return container(node, node.children)
		end

		-- Args(<String> Name, <Function> Callback, <String?> DefaultKey) - Callback runs when the key is pressed
		function Container:Keybind(name, callback, defaultKey)
			local item = { kind = "keybind", label = tostring(name), key = newKey(), callback = callback }
			local object = element(add(self, { item = item }))
			local keyCode = toKeyCode(defaultKey)
			if keyCode then
				if Binder.isReserved(keyCode) then
					warn(("[PurpleUI] Keybind %q: %s is used by the menu"):format(item.label, keyCode.Name))
				else
					Binder.set(item, keyCode, "")
				end
			end
			return object
		end

		-- Args(<String> Name, <Function> Callback, <String?> PlaceholderText)  Callback(<String> Text)
		function Container:TextBox(name, callback, placeholder)
			local item = Item.search(tostring(name), newKey(), placeholder or "Type here", false)
			item.callback = callback
			return element(add(self, { item = item }))
		end

		-- Args(<String> Name, <Function> Callback, <Color3?> Default)  Callback(<Color3> Color)
		function Container:ColorWheel(name, callback, default)
			local item = { kind = "color", label = tostring(name), key = newKey(), callback = callback }
			State.register(item.key, typeof(default) == "Color3" and default or Color3.new(1, 1, 1))
			return element(add(self, { item = item }))
		end

		-- extras --------------------------------------------------------------------

		-- Args(<String> Name, <Table> Options, <Function> Callback, <String?> Default)
		-- "< Option >": Left / Right change it, Enter shows the whole list. Callback(<String> Option)
		function Container:Selector(name, options, callback, default)
			local list = {}
			for _, option in ipairs(options or {}) do
				table.insert(list, tostring(option))
			end
			if #list == 0 then
				list = { "-" }
			end
			local item = Item.selector(tostring(name), newKey(), list, {
				dropdown = true, default = table.find(list, tostring(default)) or 1,
			})
			item.callback = callback
			return element(add(self, { item = item }))
		end

		-- Args(<String> Name, <Function> Callback) - "< Player >": Left / Right pick a player,
		-- Enter runs Callback(<Player>). Follows the last player ticked in a PlayerList.
		function Container:PlayerDropdown(name, callback)
			local item = Item.player(tostring(name))
			item.key = item.key .. "#" .. newKey()
			item.callback = callback
			return element(add(self, { item = item }))
		end

		-- Args(<Function?> Callback) - Search, Bulk Action, Show selected player info and a tickable
		-- row per player (ID - Name, house / car icons). Callback(<{Player}> Selected) on every change.
		function Container:PlayerList(callback)
			local node = { playerList = true }
			local search = Item.search("Search", newKey(), "Name or ID")
			local bulk = Item.selector("Bulk Action", newKey(), { "Unselect All", "Select All" }, {
				run = function(option)
					bulkAction(option, filteredPlayers(State.get(search.key, "")))
				end,
			})
			local info = Item.toggle("Show selected player info", "players.showInfo", true, {
				silent = true,
				onChange = function()
					updatePanel()
				end,
			})
			search.playerList, bulk.playerList, info.playerList = true, true, true
			search.tip = "Press Enter, type a name or ID, then press Enter again"
			bulk.tip = "Left / Right picks an action, Enter applies it to the list"
			info.tip = "When on: the card on the right shows the highlighted player"
			node.header = { search, bulk, info, Item.divider("Players") }
			node.item = { label = "Players", callback = callback }
			table.insert(playerLists, node)
			add(self, node)
			local object = element(node)
			function object.GetSelected()
				return selectedPlayers()
			end
			return object
		end

		----------------------------------------------------------------------------
		-- the window
		----------------------------------------------------------------------------
		-- Args(<String> Name, <String?> TabImage)
		function window:Tab(name, image)
			local tabNode = { children = {} }
			local tab = {
				name = tostring(name),
				image = toImage(image),
				items = function()
					return flatten(tabNode.children, {})
				end,
			}
			local tabs = Pages.main.tabs
			local at = table.find(tabs, settingsTab) or (#tabs + 1)
			table.insert(tabs, at, tab)
			local rootEntry = Nav.stack[1]
			if Nav.isOpen and rootEntry and rootEntry.tab >= at then
				rootEntry.tab += 1 -- stay on the tab you're looking at
			end
			scheduleRefresh()
			return container(tabNode, tabNode.children)
		end

		-- Args(<Boolean> ConstrainToScreen) - keep the window inside the screen while it is dragged
		function window:LockScreenBoundaries(enabled)
			Nav.constrain = enabled ~= false
			applyLayout(false)
			return self
		end

		-- Args(<String> Title, <String?> Text, <String?> Kind "info" | "success" | "warning" | "error", <Number?> Duration)
		function window:Notify(title, text, kind, duration)
			notify(tostring(title), text ~= nil and tostring(text) or "", kind, tonumber(duration))
			return self
		end

		-- Args(<String> Text)
		function window:SetFooter(text)
			menuCanvas.Footer.BuildText.Text = tostring(text)
			return self
		end

		-- Args(<String> Text) - the title drawn on the banner
		function window:SetBannerText(text)
			CONFIG.BannerTitle = tostring(text)
			rebuildBanner()
			return self
		end

		-- Args(<String> Name) - "Smoke", "Brush", "Synthwave", "Waves", "Nebula", "Stripes"
		function window:SetBanner(name)
			for index, style in ipairs(BANNERS) do
				if string.lower(style) == string.lower(tostring(name)) then
					State.set("settings.banner", index)
					rebuildBanner()
					refreshRows(false)
				end
			end
			return self
		end

		-- Args(<String> Name) - "Purple", "Blue", "Cyan", "Green", "Yellow", "Orange", "Red", "Pink"
		function window:SetTheme(name)
			for index, theme in ipairs(THEMES) do
				if string.lower(theme.name) == string.lower(tostring(name)) then
					State.set("settings.theme", index)
					themeChanged()
				end
			end
			return self
		end

		-- Args(<String | KeyCode> Key) - key that opens / closes the window
		function window:SetToggleKey(key)
			local keyCode = toKeyCode(key)
			if keyCode then
				Nav.toggleKey = keyCode
				bindToggle()
				refreshRows(false)
			end
			return self
		end

		-- Args(<Boolean> Enabled) - ask which key opens the menu when the window is created (default true)
		function window:SetKeyPrompt(enabled)
			Nav.askKey = enabled ~= false
			return self
		end

		-- Args(<Boolean?> Open) - open / close from code (no argument flips it)
		function window:Toggle(open)
			if open == nil then
				open = not Nav.isOpen
			end
			setOpen(open == true)
			return self
		end

		function window:IsOpen()
			return Nav.isOpen
		end

		-- players ticked in any PlayerList
		function window:GetSelectedPlayers()
			return selectedPlayers()
		end

		function window:Destroy()
			if Nav.destroyed then
				return
			end
			setOpen(false)
			Binder.close()
			Nav.destroyed = true
			for _, connection in ipairs(connections) do
				connection:Disconnect()
			end
			if cameraConnection then
				cameraConnection:Disconnect()
			end
			for _, action in ipairs({ TOGGLE_ACTION, NAV_ACTION, WHEEL_ACTION, "PurpleUI_Capture", "PurpleUI_OpenKey" }) do
				ContextActionService:UnbindAction(action)
			end
			screen:Destroy()
			HUD.screen:Destroy()
		end
	end

	activeWindow = window
	return window
end

-- Args(<String> Title, <String?> Text, <String?> Kind, <Number?> Duration) - toast on the current window
function Library:Notify(title, text, kind, duration)
	if activeWindow then
		activeWindow:Notify(title, text, kind, duration)
	end
end

return Library
