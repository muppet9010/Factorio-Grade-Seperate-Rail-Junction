-- Manages the cached data of trains for use by other modules.

local TrainCachedData = {}
local Events = require("utility/events")
local Common = require("scripts/common")
local Utils = require("utility/utils")

---@class TrainCachedData
---@field id Id @ Train Id
---@field carriagesCachedData Utils_TrainCarriageData[] @ The cached carriage details of the train.
---@field forwardMovingTrainSpeedCalculationData? Utils_TrainSpeedCalculationData|null @ Only populated when required for the forward movement of this cached train.
---@field backwardMovingTrainSpeedCalculationData? Utils_TrainSpeedCalculationData|null @ Only populated when required for the backwards movement of this cached train.

TrainCachedData.CreateGlobals = function()
    global.trainCachedData = global.trainCachedData or {}
    global.trainCachedData.trains = global.trainCachedData.trains or {} ---@type table<Id, TrainCachedData> @ Id is the train's Id.
end

TrainCachedData.OnLoad = function()
    local rollingStockTypeFilter = {}
    for _, rollingStockType in pairs(Common.RollingStockTypes) do
        table.insert(rollingStockTypeFilter, {filter = "type", type = rollingStockType})
    end
    Events.RegisterHandlerEvent(defines.events.on_player_mined_entity, "TrainCachedData.OnRollingStockRemoved", TrainCachedData.OnRollingStockRemoved, rollingStockTypeFilter)
    Events.RegisterHandlerEvent(defines.events.on_robot_mined_entity, "TrainCachedData.OnRollingStockRemoved", TrainCachedData.OnRollingStockRemoved, rollingStockTypeFilter)
    Events.RegisterHandlerEvent(defines.events.on_entity_died, "TrainCachedData.OnRollingStockRemoved", TrainCachedData.OnRollingStockRemoved, rollingStockTypeFilter)
    Events.RegisterHandlerEvent(defines.events.script_raised_destroy, "TrainCachedData.OnRollingStockRemoved", TrainCachedData.OnRollingStockRemoved, rollingStockTypeFilter)

    MOD.Interfaces.TrainCachedData = MOD.Interfaces.TrainCachedData or {}
    MOD.Interfaces.TrainCachedData.GetCreateTrainCache = TrainCachedData.GetCreateTrainCache
    MOD.Interfaces.TrainCachedData.UpdateTrainCacheId = TrainCachedData.UpdateTrainCacheId
    MOD.Interfaces.TrainCachedData.UpdateTrainSpeedCalculationData = TrainCachedData.UpdateTrainSpeedCalculationData
end

--- Called by all the events that remove rolling stock.
---@param event on_player_mined_entity|on_robot_mined_entity|on_entity_died|script_raised_destroy
TrainCachedData.OnRollingStockRemoved = function(event)
    local entity = event.entity
    -- Handle any other registrations of this event across the mod.
    if Common.RollingStockTypes[entity.type] == nil then
        return
    end

    -- Check if the entity's train was one we had cached and if so remove the cache.
    local trainId = entity.train.id
    if global.trainCachedData.trains[trainId] ~= nil then
        -- Removed the cached data for this train as the train is no longer valid.
        global.trainCachedData.trains[trainId] = nil
    end
end

--- Gets a train cache for the supplied train and if one doesn't exist it creates it first.
---@param train LuaTrain
---@param train_id Id
---@return TrainCachedData trainCachedData
TrainCachedData.GetCreateTrainCache = function(train, train_id)
    -- If cache already exists return this.
    local trainCache = global.trainCachedData.trains[train_id]
    if trainCache ~= nil then
        return trainCache
    end

    -- No cache found so create the initial cache's data.
    ---@type Utils_TrainCarriageData[]
    local carriagesCachedData = {}
    for i, carriage in pairs(train.carriages) do
        carriagesCachedData[i] = {entity = carriage}
        if i == 1 then
            carriagesCachedData[1].unitNumber = carriage.unit_number
        end
    end
    ---@type TrainCachedData
    local trainCachedData = {
        id = train_id,
        carriagesCachedData = carriagesCachedData
    }
    -- Regsiter the cache.
    global.trainCachedData.trains[train_id] = trainCachedData

    return trainCachedData
end

--- Updates an existing train cache to a new train Id. Used when teleporting a train from 1 location to another.
---@param oldId Id
---@param newId Id
TrainCachedData.UpdateTrainCacheId = function(oldId, newId)
    local trainCache = global.trainCachedData.trains[oldId]
    global.trainCachedData.trains[oldId] = nil
    global.trainCachedData.trains[newId] = trainCache
    trainCache.id = newId
end

--- Updates the train cache's trainSpeedCalculationData for the supplied train based on its movement direction.
---@param train LuaTrain
---@param train_speed double
---@param trainCachedData TrainCachedData
TrainCachedData.UpdateTrainSpeedCalculationData = function(train, train_speed, trainCachedData)
    local trainMovingForwards = train_speed > 0
    -- Looked at using the other direction's data if populated as base for new data, but the values that can be just copied are all cached base data already so basically just as quick to regenerate it and much simplier logic.
    local trainSpeedCalculationData
    if trainMovingForwards then
        -- Train moving forwards.
        if trainCachedData.forwardMovingTrainSpeedCalculationData == nil then
            -- No data held for current direction so generate it.
            trainCachedData.forwardMovingTrainSpeedCalculationData = Utils.GetTrainSpeedCalculationData(train, train_speed, nil, trainCachedData.carriagesCachedData)
            return
        else
            -- Just update the locomotiveAccelerationPower.
            trainSpeedCalculationData = trainCachedData.forwardMovingTrainSpeedCalculationData
        end
    else
        -- Train moving backwards.
        if trainCachedData.backwardMovingTrainSpeedCalculationData == nil then
            -- No data held for current direction so generate it.
            trainCachedData.backwardMovingTrainSpeedCalculationData = Utils.GetTrainSpeedCalculationData(train, train_speed, nil, trainCachedData.carriagesCachedData)
            return
        else
            -- Just update the locomotiveAccelerationPower.
            trainSpeedCalculationData = trainCachedData.backwardMovingTrainSpeedCalculationData
        end
    end

    -- Update the acceleration value back in to the cache on each calling.
    local fuelAccelerationBonus
    for _, carriageCachedData in pairs(trainCachedData.carriagesCachedData) do
        -- Note: this is a partial clone from Utils.GetTrainSpeedCalculationData().
        -- Only process locomotives that are powering the trains movement.
        if carriageCachedData.prototypeName == "locomotive" and trainMovingForwards == carriageCachedData.faceingFrontOfTrain then
            local carriage = carriageCachedData.entity
            local currentFuelPrototype = Utils.GetLocomotivesCurrentFuelPrototype(carriage)
            if currentFuelPrototype ~= nil then
                -- No benefit to using PrototypeAttributes.GetAttribute() as we'd have to get the prototypeName to load from the cache each time and theres only 1 attribute we want in this case.
                fuelAccelerationBonus = currentFuelPrototype.fuel_acceleration_multiplier
                -- Just get fuel from one forward facing loco that has fuel. Have to check the inventory as the train ill be breaking for the signal theres no currently burning.
                break
            end
        end
    end
    trainSpeedCalculationData.locomotiveAccelerationPower = 10 * trainSpeedCalculationData.forwardFacingLocoCount * ((fuelAccelerationBonus or 1) / trainSpeedCalculationData.trainWeight)
end

return TrainCachedData
