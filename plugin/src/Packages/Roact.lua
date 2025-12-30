--!strict
--[[
    Minimal Roact implementation for DetAI plugin
    Based on Roact patterns but simplified for plugin use
]]

local Roact = {}

-- Component base class
Roact.Component = {}
Roact.Component.__index = Roact.Component

function Roact.Component:extend(name: string)
    local class = setmetatable({}, Roact.Component)
    class.__index = class
    class.className = name
    return class
end

function Roact.Component:setState(partialState)
    if type(partialState) == "function" then
        partialState = partialState(self.state)
    end

    for key, value in pairs(partialState) do
        self.state[key] = value
    end

    if self._mounted and self.render then
        self:_update()
    end
end

function Roact.Component:_update()
    if self._instance and self.render then
        local newTree = self:render()
        Roact._reconcile(self._instance, newTree)
    end
end

-- Create element
function Roact.createElement(component, props, children)
    return {
        type = "element",
        component = component,
        props = props or {},
        children = children or {}
    }
end

-- Fragment for multiple children
Roact.Fragment = { type = "fragment" }

-- Refs
function Roact.createRef()
    return { current = nil }
end

-- Bindings (simplified)
function Roact.createBinding(initialValue)
    local value = initialValue
    local listeners = {}

    local function getValue()
        return value
    end

    local function setValue(newValue)
        value = newValue
        for _, listener in ipairs(listeners) do
            listener(value)
        end
    end

    local binding = {
        getValue = getValue,
        map = function(self, mapper)
            return {
                getValue = function()
                    return mapper(value)
                end
            }
        end
    }

    return binding, setValue
end

-- Mount tree to parent
function Roact.mount(element, parent, key)
    if not element then return nil end

    local instance = Roact._createInstance(element, parent, key)
    return instance
end

-- Unmount tree
function Roact.unmount(tree)
    if not tree then return end
    Roact._destroyInstance(tree)
end

-- Update existing tree
function Roact.update(tree, newElement)
    if not tree then return Roact.mount(newElement, nil, nil) end
    return Roact._reconcile(tree, newElement)
end

-- Internal: create instance from element
function Roact._createInstance(element, parent, key)
    if not element then return nil end

    -- Handle string (host component)
    if type(element.component) == "string" then
        local className = element.component
        local instance = Instance.new(className)

        -- Apply props
        for propName, propValue in pairs(element.props) do
            if propName == "ref" then
                if type(propValue) == "table" and propValue.current ~= nil or propValue.current == nil then
                    propValue.current = instance
                end
            elseif propName:sub(1, 2) == "On" then
                -- Event handler
                local eventName = propName:sub(3)
                local event = instance[eventName]
                if event and typeof(event) == "RBXScriptSignal" then
                    event:Connect(propValue)
                end
            elseif propName ~= "children" and propName ~= "key" then
                pcall(function()
                    instance[propName] = propValue
                end)
            end
        end

        -- Create children
        if element.children then
            for childKey, childElement in pairs(element.children) do
                Roact._createInstance(childElement, instance, childKey)
            end
        end

        if key then
            instance.Name = tostring(key)
        end

        if parent then
            instance.Parent = parent
        end

        return instance
    end

    -- Handle function component
    if type(element.component) == "function" then
        local result = element.component(element.props)
        return Roact._createInstance(result, parent, key)
    end

    -- Handle class component
    if type(element.component) == "table" then
        local componentClass = element.component
        local componentInstance = setmetatable({
            props = element.props,
            state = {},
            _mounted = false
        }, componentClass)

        if componentInstance.init then
            componentInstance:init()
        end

        local rendered = componentInstance:render()
        local instance = Roact._createInstance(rendered, parent, key)

        componentInstance._instance = instance
        componentInstance._mounted = true

        if componentInstance.didMount then
            componentInstance:didMount()
        end

        return instance
    end

    return nil
end

-- Internal: destroy instance
function Roact._destroyInstance(instance)
    if typeof(instance) == "Instance" then
        instance:Destroy()
    end
end

-- Internal: reconcile (simplified)
function Roact._reconcile(oldInstance, newElement)
    if not newElement then
        Roact._destroyInstance(oldInstance)
        return nil
    end

    -- For now, just recreate (full reconciliation is complex)
    local parent = typeof(oldInstance) == "Instance" and oldInstance.Parent or nil
    local name = typeof(oldInstance) == "Instance" and oldInstance.Name or nil

    Roact._destroyInstance(oldInstance)
    return Roact._createInstance(newElement, parent, name)
end

return Roact
