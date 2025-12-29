--!strict
--[[
	studioctl Plugin
	Full Studio control via WebSocket - scripts, instances, simulation.
]]

local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local LogService = game:GetService("LogService")
local ScriptEditorService = game:GetService("ScriptEditorService")
local ChangeHistoryService = game:GetService("ChangeHistoryService")
local Selection = game:GetService("Selection")

-- Configuration
local SERVER_URL = "ws://localhost:4848"
local TOKEN = ""
local RECONNECT_DELAY = 2
local MAX_RECONNECT_DELAY = 30

-- State
local wsClient: any = nil
local connected = false
local reconnectDelay = RECONNECT_DELAY
local logBuffer: {any} = {}
local LOG_FLUSH_INTERVAL = 0.1

-- Utility: JSON encode/decode
local function jsonEncode(data: any): string?
	local ok, result = pcall(function()
		return HttpService:JSONEncode(data)
	end)
	return ok and result or nil
end

local function jsonDecode(str: string): any?
	local ok, result = pcall(function()
		return HttpService:JSONDecode(str)
	end)
	return ok and result or nil
end

-- Resolve instance path like "ServerScriptService.MyFolder.MyScript"
local function resolvePath(path: string): Instance?
	local parts = path:split(".")
	local current: Instance = game

	for _, part in parts do
		local child = current:FindFirstChild(part)
		if not child then
			return nil
		end
		current = child
	end

	return current
end

-- Get full path of an instance
local function getFullPath(instance: Instance): string
	local parts = {}
	local current = instance

	while current and current ~= game do
		table.insert(parts, 1, current.Name)
		current = current.Parent :: Instance
	end

	return table.concat(parts, ".")
end

-- Check if instance is a script type
local function isScript(instance: Instance): boolean
	return instance:IsA("LuaSourceContainer")
end

-- Send message to server
local function send(message: any)
	if not wsClient or not connected then
		return false
	end

	local json = jsonEncode(message)
	if not json then
		warn("[studioctl] Failed to encode message")
		return false
	end

	local ok, err = pcall(function()
		wsClient:Send(json)
	end)

	if not ok then
		warn("[studioctl] Send failed:", err)
		return false
	end

	return true
end

-- Send result back to CLI
local function sendResult(cmd: string, ok: boolean, info: any?)
	local infoStr = info
	if type(info) == "table" then
		infoStr = jsonEncode(info)
	elseif info ~= nil then
		infoStr = tostring(info)
	end

	send({
		type = "result",
		cmd = cmd,
		ok = ok,
		info = infoStr,
		t = os.time()
	})
end

-- ============ Command Handlers ============

local function cmdRun()
	local ok, err = pcall(function()
		RunService:Run()
	end)
	sendResult("run", ok, err)
end

local function cmdStop()
	local ok, err = pcall(function()
		RunService:Stop()
	end)
	sendResult("stop", ok, err)
end

local function cmdPause()
	local ok, err = pcall(function()
		RunService:Pause()
	end)
	sendResult("pause", ok, err)
end

local function cmdPing()
	sendResult("ping", true, "pong")
end

local function cmdStatus()
	sendResult("status", true, {
		running = RunService:IsRunning(),
		isClient = RunService:IsClient(),
		isServer = RunService:IsServer()
	})
end

-- List all scripts in the DataModel
local function cmdListScripts(message: any)
	local scripts = {}
	local filter = message.filter -- optional: "server", "local", "module", or nil for all

	local function scan(instance: Instance)
		if isScript(instance) then
			local scriptType = "unknown"
			if instance:IsA("Script") then
				scriptType = "server"
			elseif instance:IsA("LocalScript") then
				scriptType = "local"
			elseif instance:IsA("ModuleScript") then
				scriptType = "module"
			end

			if not filter or filter == scriptType then
				table.insert(scripts, {
					path = getFullPath(instance),
					name = instance.Name,
					type = scriptType,
					className = instance.ClassName
				})
			end
		end

		for _, child in instance:GetChildren() do
			scan(child)
		end
	end

	scan(game)
	sendResult("list-scripts", true, scripts)
end

-- Get script source
local function cmdGetSource(message: any)
	local path = message.path
	if not path then
		sendResult("get-source", false, "no path provided")
		return
	end

	local instance = resolvePath(path)
	if not instance then
		sendResult("get-source", false, "instance not found: " .. path)
		return
	end

	if not isScript(instance) then
		sendResult("get-source", false, "not a script: " .. path)
		return
	end

	-- Use ScriptEditorService for reliable source reading
	local ok, source = pcall(function()
		return ScriptEditorService:GetEditorSource(instance :: LuaSourceContainer)
	end)

	if ok then
		sendResult("get-source", true, source)
	else
		-- Fallback to direct Source property
		local ok2, source2 = pcall(function()
			return (instance :: any).Source
		end)
		if ok2 then
			sendResult("get-source", true, source2)
		else
			sendResult("get-source", false, "failed to read source: " .. tostring(source))
		end
	end
end

-- Set script source with undo support
local function cmdSetSource(message: any)
	local path = message.path
	local source = message.source

	if not path then
		sendResult("set-source", false, "no path provided")
		return
	end

	if source == nil then
		sendResult("set-source", false, "no source provided")
		return
	end

	local instance = resolvePath(path)
	if not instance then
		sendResult("set-source", false, "instance not found: " .. path)
		return
	end

	if not isScript(instance) then
		sendResult("set-source", false, "not a script: " .. path)
		return
	end

	-- Record for undo
	local recordId = ChangeHistoryService:TryBeginRecording("studioctl: set-source " .. path)

	local ok, err = pcall(function()
		ScriptEditorService:UpdateSourceAsync(instance :: LuaSourceContainer, function(_old)
			return source
		end)
	end)

	if recordId then
		if ok then
			ChangeHistoryService:FinishRecording(recordId, Enum.FinishRecordingOperation.Commit)
		else
			ChangeHistoryService:FinishRecording(recordId, Enum.FinishRecordingOperation.Cancel)
		end
	end

	sendResult("set-source", ok, ok and "source updated" or tostring(err))
end

-- Patch script (find/replace)
local function cmdPatch(message: any)
	local path = message.path
	local find = message.find
	local replace = message.replace

	if not path or not find then
		sendResult("patch", false, "path and find are required")
		return
	end

	replace = replace or ""

	local instance = resolvePath(path)
	if not instance then
		sendResult("patch", false, "instance not found: " .. path)
		return
	end

	if not isScript(instance) then
		sendResult("patch", false, "not a script: " .. path)
		return
	end

	local recordId = ChangeHistoryService:TryBeginRecording("studioctl: patch " .. path)
	local count = 0

	local ok, err = pcall(function()
		ScriptEditorService:UpdateSourceAsync(instance :: LuaSourceContainer, function(old)
			local new, n = old:gsub(find, replace)
			count = n
			return new
		end)
	end)

	if recordId then
		if ok and count > 0 then
			ChangeHistoryService:FinishRecording(recordId, Enum.FinishRecordingOperation.Commit)
		else
			ChangeHistoryService:FinishRecording(recordId, Enum.FinishRecordingOperation.Cancel)
		end
	end

	if ok then
		sendResult("patch", true, { replaced = count })
	else
		sendResult("patch", false, tostring(err))
	end
end

-- Insert new script
local function cmdInsertScript(message: any)
	local parentPath = message.parent or "ServerScriptService"
	local name = message.name or "NewScript"
	local scriptType = message.scriptType or "server"
	local source = message.source or ""

	local parent = resolvePath(parentPath)
	if not parent then
		sendResult("insert-script", false, "parent not found: " .. parentPath)
		return
	end

	local recordId = ChangeHistoryService:TryBeginRecording("studioctl: insert " .. name)

	local ok, err = pcall(function()
		local script: LuaSourceContainer

		if scriptType == "module" then
			script = Instance.new("ModuleScript")
		elseif scriptType == "local" then
			script = Instance.new("LocalScript")
		else
			script = Instance.new("Script")
		end

		script.Name = name
		ScriptEditorService:UpdateSourceAsync(script, function(_)
			return source
		end)
		script.Parent = parent
	end)

	if recordId then
		if ok then
			ChangeHistoryService:FinishRecording(recordId, Enum.FinishRecordingOperation.Commit)
		else
			ChangeHistoryService:FinishRecording(recordId, Enum.FinishRecordingOperation.Cancel)
		end
	end

	if ok then
		sendResult("insert-script", true, parentPath .. "." .. name)
	else
		sendResult("insert-script", false, tostring(err))
	end
end

-- Execute Lua code
local function cmdExec(message: any)
	local code = message.code
	if not code then
		sendResult("exec", false, "no code provided")
		return
	end

	local fn, loadErr = loadstring(code)
	if not fn then
		sendResult("exec", false, "syntax error: " .. tostring(loadErr))
		return
	end

	local ok, result = pcall(fn)
	sendResult("exec", ok, tostring(result))
end

-- Get instance info
local function cmdGetInstance(message: any)
	local path = message.path
	if not path then
		sendResult("get-instance", false, "no path provided")
		return
	end

	local instance = resolvePath(path)
	if not instance then
		sendResult("get-instance", false, "instance not found: " .. path)
		return
	end

	local info = {
		path = getFullPath(instance),
		name = instance.Name,
		className = instance.ClassName,
		children = {}
	}

	for _, child in instance:GetChildren() do
		table.insert(info.children, {
			name = child.Name,
			className = child.ClassName
		})
	end

	sendResult("get-instance", true, info)
end

-- ============ Command Router ============

local function handleCommand(message: any)
	local cmd = message.cmd
	print("[studioctl] Executing:", cmd)

	if cmd == "run" then cmdRun()
	elseif cmd == "stop" then cmdStop()
	elseif cmd == "pause" then cmdPause()
	elseif cmd == "ping" then cmdPing()
	elseif cmd == "status" then cmdStatus()
	elseif cmd == "list-scripts" then cmdListScripts(message)
	elseif cmd == "get-source" then cmdGetSource(message)
	elseif cmd == "set-source" then cmdSetSource(message)
	elseif cmd == "patch" then cmdPatch(message)
	elseif cmd == "insert-script" then cmdInsertScript(message)
	elseif cmd == "exec" then cmdExec(message)
	elseif cmd == "get-instance" then cmdGetInstance(message)
	else
		sendResult(cmd, false, "unknown command")
	end
end

-- ============ WebSocket Connection ============

local function onMessage(data: string)
	local message = jsonDecode(data)
	if not message then
		warn("[studioctl] Invalid JSON")
		return
	end

	if message.type == "welcome" then
		print("[studioctl] Connected as", message.role)
		reconnectDelay = RECONNECT_DELAY
	elseif message.type == "cmd" then
		handleCommand(message)
	elseif message.type == "error" then
		warn("[studioctl] Server error:", message.error)
	end
end

local function connect()
	if wsClient then
		pcall(function() wsClient:Close() end)
		wsClient = nil
	end

	print("[studioctl] Connecting to", SERVER_URL)

	local ok, result = pcall(function()
		return HttpService:CreateWebStreamClient(
			Enum.WebStreamClientType.WebSocket,
			{ Url = SERVER_URL }
		)
	end)

	if not ok then
		warn("[studioctl] WebSocket error:", result)
		task.delay(reconnectDelay, function()
			reconnectDelay = math.min(reconnectDelay * 2, MAX_RECONNECT_DELAY)
			connect()
		end)
		return false
	end

	wsClient = result

	wsClient.MessageReceived:Connect(function(msg: string)
		onMessage(msg)
	end)

	wsClient.Closed:Connect(function()
		print("[studioctl] Disconnected")
		connected = false
		wsClient = nil
		task.delay(reconnectDelay, function()
			reconnectDelay = math.min(reconnectDelay * 2, MAX_RECONNECT_DELAY)
			connect()
		end)
	end)

	connected = true
	send({ role = "studio", token = TOKEN })
	return true
end

-- Log streaming
local function setupLogStreaming()
	LogService.MessageOut:Connect(function(message: string, messageType: Enum.MessageType)
		local level = "Output"
		if messageType == Enum.MessageType.MessageWarning then
			level = "Warning"
		elseif messageType == Enum.MessageType.MessageError then
			level = "Error"
		end

		table.insert(logBuffer, {
			type = "log",
			level = level,
			text = message,
			t = os.time()
		})
	end)

	task.spawn(function()
		while true do
			task.wait(LOG_FLUSH_INTERVAL)
			if connected and #logBuffer > 0 then
				local logs = logBuffer
				logBuffer = {}
				for _, log in logs do
					send(log)
				end
			end
		end
	end)
end

-- Initialize
print("[studioctl] Plugin loaded")
setupLogStreaming()
connect()
