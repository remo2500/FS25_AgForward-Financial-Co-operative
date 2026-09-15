AGFServiceContainer = {}
AGFServiceContainer_mt = Class(AGFServiceContainer)

function AGFServiceContainer.new()
    local self = setmetatable({}, AGFServiceContainer_mt)
    self.services = {}
    return self
end

function AGFServiceContainer:register(name, service)
    if name == nil or service == nil then
        return false
    end
    self.services[name] = service
    return true
end

function AGFServiceContainer:get(name)
    return self.services[name]
end

function AGFServiceContainer:has(name)
    return self.services[name] ~= nil
end

function AGFServiceContainer:clear()
    self.services = {}
end
