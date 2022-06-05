--[[
    All Factorio LuaEntity related utils functions.
]]
--

local EntityUtils = {}
local PositionUtils = require("utility.position-utils")

--- Uses unit number if both support it, otherwise has to compare a lot of attributes to try and work out if they are the same base entity. Assumes the entity won't ever move or change.
---@param entity1 LuaEntity
---@param entity2 LuaEntity
EntityUtils.Are2EntitiesTheSame = function(entity1, entity2)
    if not entity1.valid or not entity2.valid then
        return false
    end
    if entity1.unit_number ~= nil and entity2.unit_number ~= nil then
        if entity1.unit_number == entity2.unit_number then
            return true
        else
            return false
        end
    else
        if entity1.type == entity2.type and entity1.name == entity2.name and entity1.surface.index == entity2.surface.index and entity1.position.x == entity2.position.x and entity1.position.y == entity2.position.y and entity1.force.index == entity2.force.index and entity1.health == entity2.health then
            return true
        else
            return false
        end
    end
end

---@param surface LuaSurface
---@param positionedBoundingBox BoundingBox
---@param collisionBoxOnlyEntities boolean
---@param onlyForceAffected? LuaForce|null
---@param onlyDestructible boolean
---@param onlyKillable boolean
---@param entitiesExcluded? LuaEntity[]|null
---@return table<int, LuaEntity>
EntityUtils.ReturnAllObjectsInArea = function(surface, positionedBoundingBox, collisionBoxOnlyEntities, onlyForceAffected, onlyDestructible, onlyKillable, entitiesExcluded)
    local entitiesFound, filteredEntitiesFound = surface.find_entities(positionedBoundingBox), {}
    for k, entity in pairs(entitiesFound) do
        if entity.valid then
            local entityExcluded = false
            if entitiesExcluded ~= nil and #entitiesExcluded > 0 then
                for _, excludedEntity in pairs(entitiesExcluded) do
                    if EntityUtils.Are2EntitiesTheSame(entity, excludedEntity) then
                        entityExcluded = true
                        break
                    end
                end
            end
            if not entityExcluded then
                if (onlyForceAffected == nil) or (entity.force == onlyForceAffected) then
                    if (not onlyDestructible) or (entity.destructible) then
                        if (not onlyKillable) or (entity.health ~= nil) then
                            if (not collisionBoxOnlyEntities) or (PositionUtils.IsCollisionBoxPopulated(entity.prototype.collision_box)) then
                                table.insert(filteredEntitiesFound, entity)
                            end
                        end
                    end
                end
            end
        end
    end
    return filteredEntitiesFound
end

---@param surface LuaSurface
---@param positionedBoundingBox BoundingBox
---@param killerEntity? LuaEntity|null
---@param collisionBoxOnlyEntities boolean
---@param onlyForceAffected boolean
---@param entitiesExcluded? LuaEntity[]|null
---@param killerForce? LuaForce|null
EntityUtils.KillAllKillableObjectsInArea = function(surface, positionedBoundingBox, killerEntity, collisionBoxOnlyEntities, onlyForceAffected, entitiesExcluded, killerForce)
    if killerForce == nil then
        killerForce = "neutral"
    end
    for _, entity in pairs(EntityUtils.ReturnAllObjectsInArea(surface, positionedBoundingBox, collisionBoxOnlyEntities, onlyForceAffected, true, true, entitiesExcluded)) do
        if killerEntity ~= nil then
            entity.die(killerForce, killerEntity)
        else
            entity.die(killerForce)
        end
    end
end

---@param surface LuaSurface
---@param positionedBoundingBox BoundingBox
---@param killerEntity? LuaEntity|null
---@param onlyForceAffected boolean
---@param entitiesExcluded? LuaEntity[]|null
---@param killerForce? LuaForce|null
EntityUtils.KillAllObjectsInArea = function(surface, positionedBoundingBox, killerEntity, onlyForceAffected, entitiesExcluded, killerForce)
    if killerForce == nil then
        killerForce = "neutral"
    end
    for k, entity in pairs(EntityUtils.ReturnAllObjectsInArea(surface, positionedBoundingBox, false, onlyForceAffected, false, false, entitiesExcluded)) do
        if entity.destructible then
            if killerEntity ~= nil then
                entity.die(killerForce, killerEntity)
            else
                entity.die(killerForce)
            end
        else
            entity.destroy {do_cliff_correction = true, raise_destroy = true}
        end
    end
end

---@param surface LuaSurface
---@param positionedBoundingBox BoundingBox
---@param collisionBoxOnlyEntities boolean
---@param onlyForceAffected boolean
---@param entitiesExcluded? LuaEntity[]|null
EntityUtils.DestroyAllKillableObjectsInArea = function(surface, positionedBoundingBox, collisionBoxOnlyEntities, onlyForceAffected, entitiesExcluded)
    for k, entity in pairs(EntityUtils.ReturnAllObjectsInArea(surface, positionedBoundingBox, collisionBoxOnlyEntities, onlyForceAffected, true, true, entitiesExcluded)) do
        entity.destroy {do_cliff_correction = true, raise_destroy = true}
    end
end

---@param surface LuaSurface
---@param positionedBoundingBox BoundingBox
---@param onlyForceAffected boolean
---@param entitiesExcluded? LuaEntity[]|null
EntityUtils.DestroyAllObjectsInArea = function(surface, positionedBoundingBox, onlyForceAffected, entitiesExcluded)
    for k, entity in pairs(EntityUtils.ReturnAllObjectsInArea(surface, positionedBoundingBox, false, onlyForceAffected, false, false, entitiesExcluded)) do
        entity.destroy {do_cliff_correction = true, raise_destroy = true}
    end
end

-- Kills an entity and handles the optional arguments as Facotrio API doesn't accept nil arguments.
---@param entity LuaEntity
---@param killerForce LuaForce
---@param killerCauseEntity? LuaEntity|null
EntityUtils.EntityDie = function(entity, killerForce, killerCauseEntity)
    if killerCauseEntity ~= nil then
        entity.die(killerForce, killerCauseEntity)
    else
        entity.die(killerForce)
    end
end

return EntityUtils