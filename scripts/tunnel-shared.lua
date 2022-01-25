local Utils = require("utility/utils")
local Colors = require("utility/colors")
local EventScheduler = require("utility/event-scheduler")
local PlayerAlerts = require("utility/player-alerts")
local TunnelShared = {}

TunnelShared.OnLoad = function()
    EventScheduler.RegisterScheduledEventType("TunnelShared.SetTrainToManual_Scheduled", TunnelShared.SetTrainToManual_Scheduled)
    EventScheduler.RegisterScheduledEventType("TunnelShared.CheckIfAlertingTrainStillStopped_Scheduled", TunnelShared.CheckIfAlertingTrainStillStopped_Scheduled)
end

---@param builtEntity LuaEntity
---@return boolean
TunnelShared.IsPlacementOnRailGrid = function(builtEntity)
    local builtEntity_position = builtEntity.position
    if builtEntity_position.x % 2 == 0 or builtEntity_position.y % 2 == 0 then
        return false
    else
        return true
    end
end

---@param builtEntity LuaEntity
---@param placer EntityActioner
---@param mine boolean @ If to mine and return the item to the placer, or just destroy it.
TunnelShared.UndoInvalidTunnelPartPlacement = function(builtEntity, placer, mine)
    TunnelShared.UndoInvalidPlacement(builtEntity, placer, mine, true, {"message.railway_tunnel-tunnel_part_must_be_on_rail_grid"}, "tunnel part")
end

---@param builtEntity LuaEntity
---@param placer EntityActioner
---@param mine boolean @ If to mine and return the item to the placer, or just destroy it.
---@param highlightValidRailGridPositions boolean @ If to show to the placer valid positions on the rail grid.
---@param warningMessageText LocalisedString @ Text shown to the placer
---@param errorEntityNameText string @ Entity name shown if the process errors.
TunnelShared.UndoInvalidPlacement = function(builtEntity, placer, mine, highlightValidRailGridPositions, warningMessageText, errorEntityNameText)
    if placer ~= nil then
        local position, surface, entityName, ghostName, direction = builtEntity.position, builtEntity.surface, builtEntity.name, nil, builtEntity.direction
        if entityName == "entity-ghost" then
            ghostName = builtEntity.ghost_name
        end
        TunnelShared.EntityErrorMessage(placer, warningMessageText, surface, position)
        if mine then
            local result
            if placer.is_player() then
                result = placer.mine_entity(builtEntity, true)
            else
                -- Is construction bot
                result = builtEntity.mine({inventory = placer.get_inventory(defines.inventory.robot_cargo), force = true, raise_destroyed = false, ignore_minable = true})
            end
            if result ~= true then
                error("couldn't mine invalidly placed " .. errorEntityNameText .. " entity")
            end
        else
            builtEntity.destroy()
        end
        if highlightValidRailGridPositions then
            TunnelShared.HighlightValidPlacementPositionsOnRailGrid(placer, position, surface, entityName, ghostName, direction)
        end
    else
        local builtEntity_position = builtEntity.position
        builtEntity.destroy()
        game.print({"message.railway_tunnel-invalid_placement_by_script", errorEntityNameText, tostring(builtEntity_position.x), tostring(builtEntity_position.y)}, Colors.red)
    end
end

--- Highlights the single tiles to the placer player/force that are valid centres for an entity on the rail grid.
---@param placer EntityActioner
---@param position Position
---@param surface LuaSurface
---@param entityName string
---@param ghostName string
---@param direction defines.direction @ Direction of the entity trying to be placed.
TunnelShared.HighlightValidPlacementPositionsOnRailGrid = function(placer, position, surface, entityName, ghostName, direction)
    local highlightAudiencePlayers, highlightAudienceForces = Utils.GetRenderPlayersForcesFromActioner(placer)
    -- Get the minimum position from where the attempt as made and then mark out the 4 iterations from that.
    local minX, maxX, minY, maxY
    if position.x % 2 == 1 then
        --Correct X position.
        minX = position.x
        maxX = position.x
    else
        -- Wrong X position.
        minX = position.x - 1
        maxX = position.x + 1
    end
    if position.y % 2 == 1 then
        --Correct Y position.
        minY = position.y
        maxY = position.y
    else
        -- Wrong Y position.
        minY = position.y - 1
        maxY = position.y + 1
    end
    local validHighlightSprite, invalidHighlightSprite = "railway_tunnel-valid_placement_highlight", "railway_tunnel-invalid_placement_highlight"
    for x = minX, maxX, 2 do
        for y = minY, maxY, 2 do
            local thisPlacementPosition = {x = x, y = y}
            local thisHighlightSprite
            if surface.can_place_entity {name = entityName, inner_name = ghostName, position = thisPlacementPosition, direction = direction, force = placer.force, build_check_type = defines.build_check_type.manual_ghost, forced = true} then
                thisHighlightSprite = validHighlightSprite
            else
                thisHighlightSprite = invalidHighlightSprite
            end
            rendering.draw_sprite {sprite = thisHighlightSprite, target = thisPlacementPosition, surface = surface, time_to_live = 300, players = highlightAudiencePlayers, forces = highlightAudienceForces}
        end
    end
end

--- Shows warning/error text on the map to either the player (character) or the force (construction robots) doign the interaction.
---@param entityDoingInteraction EntityActioner
---@param text LocalisedString @ Text shown.
---@param surface LuaSurface
---@param position Position
TunnelShared.EntityErrorMessage = function(entityDoingInteraction, text, surface, position)
    local textAudiencePlayers, textAudienceForces = Utils.GetRenderPlayersForcesFromActioner(entityDoingInteraction)
    rendering.draw_text {text = text, surface = surface, target = position, time_to_live = 180, players = textAudiencePlayers, forces = textAudienceForces, color = {r = 1, g = 0, b = 0, a = 1}, scale_with_zoom = true}
end

--- Correctly stops a train when it collides with an entity. As the Factorio game engine will return a manual train upon collision the following tick. So we have to stop it this tick and set it to be manual again next tick.
---@param train LuaTrain
---@param train_id Id
---@param currentTick Tick
TunnelShared.StopTrainOnEntityCollision = function(train, train_id, currentTick)
    train.manual_mode = true
    train.speed = 0
    EventScheduler.ScheduleEventOnce(currentTick + 1, "TunnelShared.SetTrainToManual_Scheduled", train_id, {train = train})
end

--- Set the train to manual.
---@param event UtilityScheduledEvent_CallbackObject
TunnelShared.SetTrainToManual_Scheduled = function(event)
    local train = event.data.train ---@type LuaTrain
    if train.valid then
        train.manual_mode = true
    end
end

--- Train can't enter the portal so stop it, set it to manual and alert the players. This stops the train the following tick if Facotrio engine decides to restart it.
---@param train LuaTrain
---@param train_id Id
---@param alertEntity LuaEntity
---@param currentTick Tick
TunnelShared.StopTrainFromEnteringTunnel = function(train, train_id, alertEntity, currentTick, message)
    -- Stop the train now and next tick.
    TunnelShared.StopTrainOnEntityCollision(train, train_id, currentTick)
    TunnelShared.AlertOnTrain(train, train_id, alertEntity, alertEntity.force, currentTick, message)
end

--- Alerts the player to a train via onscreen text and alert icon.
---@param train LuaTrain
---@param train_id Id
---@param alertEntity LuaEntity
---@param forceToSeeAlert LuaForce
---@param currentTick Tick
TunnelShared.AlertOnTrain = function(train, train_id, alertEntity, forceToSeeAlert, currentTick, message)
    -- Show a text message at the tunnel entrance for a short period.
    rendering.draw_text {
        text = message,
        surface = alertEntity.surface,
        target = alertEntity,
        time_to_live = 300,
        forces = {forceToSeeAlert},
        color = {r = 1, g = 0, b = 0, a = 1},
        scale_with_zoom = true
    }

    -- Add the alert for the tunnel force.
    local alertId = PlayerAlerts.AddCustomAlertToForce(forceToSeeAlert, train_id, alertEntity, {type = "virtual", name = "railway_tunnel"}, message, true)

    -- Setup a schedule to detect when the train is either moving or changed (not valid LuaTrain) and the alert can be removed.
    EventScheduler.ScheduleEventOnce(currentTick + 1, "TunnelShared.CheckIfAlertingTrainStillStopped_Scheduled", train_id, {train = train, alertEntity = alertEntity, alertId = alertId, force = forceToSeeAlert})
end

--- Checks a train until it is no longer stopped and then removes the alert associated with it.
---@param event UtilityScheduledEvent_CallbackObject
TunnelShared.CheckIfAlertingTrainStillStopped_Scheduled = function(event)
    local train = event.data.train ---@type LuaTrain
    local alertEntity = event.data.alertEntity ---@type LuaEntity
    local trainStopped = true

    if not train.valid then
        -- Train is not valid any more so alert should be removed.
        trainStopped = false
    elseif not alertEntity.valid then
        -- The alert target entity is not valid any more so alert should be removed.
        trainStopped = false
    elseif train.speed ~= 0 then
        -- The train has speed and so isn't stopped any more.
        trainStopped = false
    elseif not train.manual_mode then
        -- The train is in automatic so isn't stopped any more.
        trainStopped = false
    end

    -- Handle the stopped state.
    if not trainStopped then
        -- Train isn't stopped so remove the alert.
        PlayerAlerts.RemoveCustomAlertFromForce(event.data.force, event.data.alertId)
    else
        -- Train is still stopped so schedule a check for next tick.
        EventScheduler.ScheduleEventOnce(event.tick + 1, "TunnelShared.CheckIfAlertingTrainStillStopped_Scheduled", event.instanceId, event.data)
    end
end

return TunnelShared
