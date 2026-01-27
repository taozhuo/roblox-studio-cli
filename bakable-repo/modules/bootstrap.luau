-- Bootstrap: Initialize Bakable namespace
-- Bakable table is provided directly by the eval sandbox

-- Initialize if not already done
if not Bakable.version then
    Bakable.version = "0.1.0"
    Bakable.installed = {}
end

-- Utility: mark a module as installed
function Bakable.register(name, module)
    Bakable[name] = module
    Bakable.installed[name] = true
    print(("[Bakable] Installed: %s"):format(name))
end

-- Utility: check if module is installed
function Bakable.has(name)
    return Bakable.installed[name] == true
end

-- Utility: list installed modules
function Bakable.list()
    local names = {}
    for name in pairs(Bakable.installed) do
        table.insert(names, name)
    end
    table.sort(names)
    return names
end

-- Utility: uninstall all modules
function Bakable.reset()
    for name in pairs(Bakable.installed) do
        if Bakable[name] and Bakable[name].destroy then
            pcall(Bakable[name].destroy)
        end
        Bakable[name] = nil
    end
    Bakable.installed = {}
    print("[Bakable] Reset complete")
end

print("[Bakable] Bootstrap ready (v0.1.0)")
return Bakable
