local Events = require("utility/events")
local Interfaces = require("utility/interfaces")
local Utils = require("utility/utils")
local TunnelCommon = require("scripts/common/tunnel-common")
local TunnelPortals = {}

local SetupValues = {
    entranceFromCenter = 25,
    -- Tunnels distance starts from the first entrace tile.
    entrySignalsDistance = 1.5,
    farInvisibleSiganlsDistance = 48.5,
    endSiganlBlockingLocomotiveDistance = 45.5,
    endSignalsDistance = 44.5,
    straightRailCountFromEntrance = 17,
    invisibleRailCountFromEntrance = 8
}

TunnelPortals.CreateGlobals = function()
    global.tunnelPortals = global.tunnelPortals or {}
    global.tunnelPortals.portals = global.tunnelPortals.portals or {}
    --[[
        [id] = {
            id = unit_number of the placed tunnel portal entity.
            entity = ref to the entity of the placed main tunnel portal entity.
            endSignals = table of endSignal global objects for the end signals of this portal. These are the inner locked red signals. Key'd as "in" and "out".
            entrySignals = table of entrySignal global objects for the entry signals of this portal. These are the outer ones that detect a train approaching the tunnel train path. Key'd as "in" and "out".
            tunnel = the tunnel global object this portal is part of.
            portalRailEntities = table of the rail entities that are part of the portal itself. key'd by the rail unit_number.
            tunnelRailEntities = table of the rail entities that are part of the connected tunnel for the portal. key'd by the rail unit_number.
            tunnelOtherEntities = table of the non rail entities that are part of the connected tunnel for the portal. Will be deleted before the tunnelRailEntities. key'd by the entities unit_number.
            trainManagersClosingEntranceSignal = table of TrainManager global objects that currently state this entrance should be closed. key'd by TrainManager id.
        }
    ]]
end

TunnelPortals.OnLoad = function()
    local portalEntityNames_Filter = {}
    for _, name in pairs(TunnelCommon.tunnelPortalPlacedPlacementEntityNames) do
        table.insert(portalEntityNames_Filter, {filter = "name", name = name})
    end
    Events.RegisterHandlerEvent(defines.events.on_built_entity, "TunnelPortals.OnBuiltEntity", TunnelPortals.OnBuiltEntity, "TunnelPortals.OnBuiltEntity", portalEntityNames_Filter)
    Events.RegisterHandlerEvent(defines.events.on_robot_built_entity, "TunnelPortals.OnBuiltEntity", TunnelPortals.OnBuiltEntity, "TunnelPortals.OnBuiltEntity", portalEntityNames_Filter)
    Events.RegisterHandlerEvent(defines.events.script_raised_built, "TunnelPortals.OnBuiltEntity", TunnelPortals.OnBuiltEntity, "TunnelPortals.OnBuiltEntity", portalEntityNames_Filter)
    Events.RegisterHandlerEvent(defines.events.script_raised_revive, "TunnelPortals.OnBuiltEntity", TunnelPortals.OnBuiltEntity, "TunnelPortals.OnBuiltEntity", portalEntityNames_Filter)
    Events.RegisterHandlerEvent(defines.events.on_pre_player_mined_item, "TunnelPortals.OnPreMinedEntity", TunnelPortals.OnPreMinedEntity, "TunnelPortals.OnPreMinedEntity", portalEntityNames_Filter)
    Events.RegisterHandlerEvent(defines.events.on_robot_pre_mined, "TunnelPortals.OnPreMinedEntity", TunnelPortals.OnPreMinedEntity, "TunnelPortals.OnPreMinedEntity", portalEntityNames_Filter)
    Events.RegisterHandlerEvent(defines.events.on_entity_died, "TunnelPortals.OnDiedEntity", TunnelPortals.OnDiedEntity, "TunnelPortals.OnDiedEntity", portalEntityNames_Filter)
    Events.RegisterHandlerEvent(defines.events.script_raised_destroy, "TunnelPortals.OnDiedEntity", TunnelPortals.OnDiedEntity, "TunnelPortals.OnDiedEntity", portalEntityNames_Filter)

    local portalEntityGhostNames_Filter = {}
    for _, name in pairs(TunnelCommon.tunnelPortalPlacedPlacementEntityNames) do
        table.insert(portalEntityGhostNames_Filter, {filter = "ghost_name", name = name})
    end
    Events.RegisterHandlerEvent(defines.events.on_built_entity, "TunnelPortals.OnBuiltEntityGhost", TunnelPortals.OnBuiltEntityGhost, "TunnelPortals.OnBuiltEntityGhost", portalEntityGhostNames_Filter)
    Events.RegisterHandlerEvent(defines.events.on_robot_built_entity, "TunnelPortals.OnBuiltEntityGhost", TunnelPortals.OnBuiltEntityGhost, "TunnelPortals.OnBuiltEntityGhost", portalEntityGhostNames_Filter)
    Events.RegisterHandlerEvent(defines.events.script_raised_built, "TunnelPortals.OnBuiltEntityGhost", TunnelPortals.OnBuiltEntityGhost, "TunnelPortals.OnBuiltEntityGhost", portalEntityGhostNames_Filter)

    Interfaces.RegisterInterface("TunnelPortals.TunnelCompleted", TunnelPortals.TunnelCompleted)
    Interfaces.RegisterInterface("TunnelPortals.TunnelRemoved", TunnelPortals.TunnelRemoved)
    Interfaces.RegisterInterface("TunnelPortals.CloseEntranceSignalForTrainManagerEntry", TunnelPortals.CloseEntranceSignalForTrainManagerEntry)
    Interfaces.RegisterInterface("TunnelPortals.OpenEntranceSignalForTrainManagerEntry", TunnelPortals.OpenEntranceSignalForTrainManagerEntry)
end

TunnelPortals.OnBuiltEntity = function(event)
    local createdEntity = event.created_entity or event.entity
    if not createdEntity.valid or TunnelCommon.tunnelPortalPlacedPlacementEntityNames[createdEntity.name] == nil then
        return
    end
    local placer = event.robot -- Will be nil for player or script placed.
    if placer == nil and event.player_index ~= nil then
        placer = game.get_player(event.player_index)
    end
    TunnelPortals.PlacementTunnelPortalBuilt(createdEntity, placer)
end

TunnelPortals.PlacementTunnelPortalBuilt = function(placementEntity, placer)
    local centerPos, force, lastUser, directionValue, aboveSurface = placementEntity.position, placementEntity.force, placementEntity.last_user, placementEntity.direction, placementEntity.surface
    local orientation = directionValue / 8
    local entracePos = Utils.ApplyOffsetToPosition(centerPos, Utils.RotatePositionAround0(orientation, {x = 0, y = 0 - SetupValues.entranceFromCenter}))

    if not TunnelPortals.TunnelPortalPlacementValid(placementEntity) then
        TunnelCommon.UndoInvalidPlacement(placementEntity, placer, true)
        return
    end

    placementEntity.destroy()
    local abovePlacedPortal = aboveSurface.create_entity {name = "railway_tunnel-tunnel_portal_surface-placed", position = centerPos, direction = directionValue, force = force, player = lastUser}
    local portal = {
        id = abovePlacedPortal.unit_number,
        entity = abovePlacedPortal,
        portalRailEntities = {}
    }
    global.tunnelPortals.portals[portal.id] = portal

    local nextRailPos = Utils.ApplyOffsetToPosition(entracePos, Utils.RotatePositionAround0(orientation, {x = 0, y = 1}))
    local railOffsetFromEntrancePos = Utils.RotatePositionAround0(orientation, {x = 0, y = 2}) -- Steps away from the entrance position by rail placement
    for _ = 1, SetupValues.straightRailCountFromEntrance do
        local placedRail = aboveSurface.create_entity {name = "railway_tunnel-internal_rail-on_map", position = nextRailPos, force = force, direction = directionValue}
        portal.portalRailEntities[placedRail.unit_number] = placedRail
        nextRailPos = Utils.ApplyOffsetToPosition(nextRailPos, railOffsetFromEntrancePos)
    end

    local tunnelComplete, tunnelPortals, tunnelSegments = TunnelPortals.CheckTunnelCompleteFromPortal(abovePlacedPortal, placer)
    if not tunnelComplete then
        return false
    end
    Interfaces.Call("Tunnel.CompleteTunnel", tunnelPortals, tunnelSegments)
end

TunnelPortals.TunnelPortalPlacementValid = function(placementEntity)
    if placementEntity.position.x % 2 == 0 or placementEntity.position.y % 2 == 0 then
        return false
    else
        return true
    end
end

TunnelPortals.CheckTunnelCompleteFromPortal = function(startingTunnelPortal, placer)
    local tunnelPortals, tunnelSegments, directionValue, orientation = {startingTunnelPortal}, {}, startingTunnelPortal.direction, startingTunnelPortal.direction / 8
    local startingTunnelPartPoint = Utils.ApplyOffsetToPosition(startingTunnelPortal.position, Utils.RotatePositionAround0(orientation, {x = 0, y = -1 + SetupValues.entranceFromCenter}))
    return TunnelCommon.CheckTunnelPartsInDirection(startingTunnelPortal, startingTunnelPartPoint, tunnelPortals, tunnelSegments, directionValue, placer), tunnelPortals, tunnelSegments
end

TunnelPortals.TunnelCompleted = function(portalEntities, force, aboveSurface)
    local portals = {}

    for _, portalEntity in pairs(portalEntities) do
        local portal = global.tunnelPortals.portals[portalEntity.unit_number]
        table.insert(portals, portal)
        local centerPos, directionValue = portalEntity.position, portalEntity.direction
        local orientation = directionValue / 8
        local entracePos = Utils.ApplyOffsetToPosition(centerPos, Utils.RotatePositionAround0(orientation, {x = 0, y = 0 - SetupValues.entranceFromCenter}))

        -- Add the invisble rails to connect the tunnel portal's normal rails to the adjoining tunnel segment.
        local nextRailPos = Utils.ApplyOffsetToPosition(entracePos, Utils.RotatePositionAround0(orientation, {x = 0, y = 1 + (SetupValues.straightRailCountFromEntrance * 2)}))
        local railOffsetFromEntrancePos = Utils.RotatePositionAround0(orientation, {x = 0, y = 2}) -- Steps away from the entrance position by rail placement.
        portal.tunnelRailEntities = {}
        for _ = 1, SetupValues.invisibleRailCountFromEntrance do
            local placedRail = aboveSurface.create_entity {name = "railway_tunnel-invisible_rail", position = nextRailPos, force = force, direction = directionValue}
            portal.tunnelRailEntities[placedRail.unit_number] = placedRail
            nextRailPos = Utils.ApplyOffsetToPosition(nextRailPos, railOffsetFromEntrancePos)
        end

        -- Add the signals at the entrance to the tunnel.
        local entrySignalInEntity =
            aboveSurface.create_entity {
            name = "railway_tunnel-internal_signal-on_map",
            position = Utils.ApplyOffsetToPosition(entracePos, Utils.RotatePositionAround0(orientation, {x = -1.5, y = SetupValues.entrySignalsDistance})),
            force = force,
            direction = directionValue
        }
        local entrySignalIn = Interfaces.Call("Tunnel.RegisterEntrySignalEntity", entrySignalInEntity, portal)
        local entrySignalOutEntity =
            aboveSurface.create_entity {
            name = "railway_tunnel-internal_signal-on_map",
            position = Utils.ApplyOffsetToPosition(entracePos, Utils.RotatePositionAround0(orientation, {x = 1.5, y = SetupValues.entrySignalsDistance})),
            force = force,
            direction = Utils.LoopDirectionValue(directionValue + 4)
        }
        local entrySignalOut = Interfaces.Call("Tunnel.RegisterEntrySignalEntity", entrySignalOutEntity, portal)
        portal.entrySignals = {["in"] = entrySignalIn, ["out"] = entrySignalOut}

        -- Add the signals that mark the end of the usable tunnel rails.
        local endSignalInEntity =
            aboveSurface.create_entity {
            name = "railway_tunnel-tunnel_portal_end_rail_signal",
            position = Utils.ApplyOffsetToPosition(entracePos, Utils.RotatePositionAround0(orientation, {x = -1.5, y = SetupValues.endSignalsDistance})),
            force = force,
            direction = directionValue
        }
        local endSignalIn = Interfaces.Call("Tunnel.RegisterEndSiganlEntity", endSignalInEntity, portal)
        local endSignalOutEntity =
            aboveSurface.create_entity {
            name = "railway_tunnel-tunnel_portal_end_rail_signal",
            position = Utils.ApplyOffsetToPosition(entracePos, Utils.RotatePositionAround0(orientation, {x = 1.5, y = SetupValues.endSignalsDistance})),
            force = force,
            direction = Utils.LoopDirectionValue(directionValue + 4)
        }
        local endSignalOut = Interfaces.Call("Tunnel.RegisterEndSiganlEntity", endSignalOutEntity, portal)
        portal.endSignals = {["in"] = endSignalIn, ["out"] = endSignalOut}

        -- Add the blocking loco and extra signals after where the END siganls are. These make the END signals go red and stop paths reserving across the track.
        local farInvisibleSignalInEntity =
            aboveSurface.create_entity {
            name = "railway_tunnel-tunnel_portal_end_rail_signal",
            position = Utils.ApplyOffsetToPosition(entracePos, Utils.RotatePositionAround0(orientation, {x = -1.5, y = SetupValues.farInvisibleSiganlsDistance})),
            force = force,
            direction = directionValue
        }
        local farInvisibleSignalOutEntity =
            aboveSurface.create_entity {
            name = "railway_tunnel-tunnel_portal_end_rail_signal",
            position = Utils.ApplyOffsetToPosition(entracePos, Utils.RotatePositionAround0(orientation, {x = 1.5, y = SetupValues.farInvisibleSiganlsDistance})),
            force = force,
            direction = Utils.LoopDirectionValue(directionValue + 4)
        }
        local endSiganlBlockingLocomotiveEntity =
            aboveSurface.create_entity {
            name = "railway_tunnel-tunnel_portal_red_signal_locomotive",
            position = Utils.ApplyOffsetToPosition(entracePos, Utils.RotatePositionAround0(orientation, {x = 0, y = SetupValues.endSiganlBlockingLocomotiveDistance})),
            force = "enemy",
            direction = Utils.LoopDirectionValue(directionValue + 2)
        }
        endSiganlBlockingLocomotiveEntity.train.schedule = {
            current = 1,
            records = {
                {
                    rail = aboveSurface.find_entity("railway_tunnel-invisible_rail", Utils.ApplyOffsetToPosition(entracePos, Utils.RotatePositionAround0(orientation, {x = 0, y = SetupValues.endSiganlBlockingLocomotiveDistance + 1.5})))
                }
            }
        }
        endSiganlBlockingLocomotiveEntity.train.manual_mode = false
        endSiganlBlockingLocomotiveEntity.destructible = false
        portal.tunnelOtherEntities = {
            [farInvisibleSignalInEntity.unit_number] = farInvisibleSignalInEntity,
            [farInvisibleSignalOutEntity.unit_number] = farInvisibleSignalOutEntity,
            [endSiganlBlockingLocomotiveEntity.unit_number] = endSiganlBlockingLocomotiveEntity
        }
    end

    return portals
end

TunnelPortals.OnBuiltEntityGhost = function(event)
    local createdEntity = event.created_entity or event.entity
    if not createdEntity.valid or createdEntity.type ~= "entity-ghost" or TunnelCommon.tunnelPortalPlacedPlacementEntityNames[createdEntity.ghost_name] == nil then
        return
    end
    local placer = event.robot -- Will be nil for player or script placed.
    if placer == nil and event.player_index ~= nil then
        placer = game.get_player(event.player_index)
    end

    if not TunnelPortals.TunnelPortalPlacementValid(createdEntity) then
        TunnelCommon.UndoInvalidPlacement(createdEntity, placer, false)
        return
    end
end

TunnelPortals.OnPreMinedEntity = function(event)
    local minedEntity = event.entity
    if not minedEntity.valid or TunnelCommon.tunnelPortalPlacedPlacementEntityNames[minedEntity.name] == nil then
        return
    end
    local portal = global.tunnelPortals.portals[minedEntity.unit_number]
    if portal == nil then
        return
    end

    local miner = event.robot -- Will be nil for player mined.
    if miner == nil and event.player_index ~= nil then
        miner = game.get_player(event.player_index)
    end

    for _, railEntity in pairs(portal.portalRailEntities) do
        if not railEntity.can_be_destroyed() then
            TunnelCommon.EntityErrorMessage(miner, "Can not mine tunnel portal while train is on tunnel track", minedEntity)
            TunnelPortals.ReplacePortalEntity(portal)
            return
        end
    end
    if portal.tunnel == nil then
        TunnelPortals.EntityRemoved(portal)
    else
        if Interfaces.Call("TrainManager.IsTunnelInUse", portal.tunnel) then
            TunnelCommon.EntityErrorMessage(miner, "Can not mine tunnel portal while train is using tunnel", minedEntity)
            TunnelPortals.ReplacePortalEntity(portal)
        else
            Interfaces.Call("Tunnel.RemoveTunnel", portal.tunnel)
            TunnelPortals.EntityRemoved(portal)
        end
    end
end

TunnelPortals.ReplacePortalEntity = function(oldPortal)
    local centerPos, force, lastUser, directionValue, aboveSurface, entityName = oldPortal.entity.position, oldPortal.entity.force, oldPortal.entity.last_user, oldPortal.entity.direction, oldPortal.entity.surface, oldPortal.entity.name
    oldPortal.entity.destroy()

    local newPortalEntity = aboveSurface.create_entity {name = entityName, position = centerPos, direction = directionValue, force = force, player = lastUser}
    local newPortal = {
        id = newPortalEntity.unit_number,
        entity = newPortalEntity,
        endSignals = oldPortal.endSignals,
        entrySignals = oldPortal.entrySignals,
        tunnel = oldPortal.tunnel,
        portalRailEntities = oldPortal.portalRailEntities,
        tunnelRailEntities = oldPortal.tunnelRailEntities,
        tunnelOtherEntities = oldPortal.tunnelOtherEntities
    }
    global.tunnelPortals.portals[newPortal.id] = newPortal
    if newPortal.tunnel ~= nil then
        for i, portal in pairs(newPortal.tunnel.portals) do
            if portal.id == oldPortal.id then
                portal.tunnel.portals[i] = newPortal
                break
            end
        end
    end
    global.tunnelPortals.portals[oldPortal.id] = nil
end

TunnelPortals.EntityRemoved = function(portal, killForce, killerCauseEntity)
    TunnelCommon.DestroyCarriagesOnRailEntityList(portal.portalRailEntities, killForce, killerCauseEntity)
    for _, railEntity in pairs(portal.portalRailEntities) do
        railEntity.destroy()
    end
    global.tunnelPortals.portals[portal.id] = nil
end

TunnelPortals.TunnelRemoved = function(portal, killForce, killerCauseEntity)
    TunnelCommon.DestroyCarriagesOnRailEntityList(portal.tunnelRailEntities, killForce, killerCauseEntity)
    portal.tunnel = nil
    for _, otherEntity in pairs(portal.tunnelOtherEntities) do
        otherEntity.destroy()
    end
    for _, railEntity in pairs(portal.tunnelRailEntities) do
        railEntity.destroy()
    end
    portal.tunnelRailEntities = nil
    for _, entrySignal in pairs(portal.entrySignals) do
        Interfaces.Call("Tunnel.DeregisterEntrySignal", entrySignal)
        entrySignal.entity.destroy()
    end
    portal.entrySignals = nil
    for _, endSignal in pairs(portal.endSignals) do
        Interfaces.Call("Tunnel.DeregisterEndSignal", endSignal)
        endSignal.entity.destroy()
    end
    portal.endSignals = nil
end

TunnelPortals.OnDiedEntity = function(event)
    local diedEntity, killerForce, killerCauseEntity = event.entity, event.force, event.cause -- The killer variables will be nil in some cases.
    if not diedEntity.valid or TunnelCommon.tunnelPortalPlacedPlacementEntityNames[diedEntity.name] == nil then
        return
    end
    local portal = global.tunnelPortals.portals[diedEntity.unit_number]
    if portal == nil then
        return
    end

    if portal.tunnel == nil then
        TunnelPortals.EntityRemoved(portal, killerForce, killerCauseEntity)
    else
        Interfaces.Call("Tunnel.RemoveTunnel", portal.tunnel)
        TunnelPortals.EntityRemoved(portal, killerForce, killerCauseEntity)
    end
end

--TODO: need to detect if an entrance signal changes and mark it as an approaching unknown train. Happens if train is going slowly and the train is inside the portal signal block before it triggers the END signal.

TunnelPortals.CloseEntranceSignalForTrainManagerEntry = function(portal, trainManagerEntry)
    -- TODO: log and do if not already done
    -- Log to trainManagersClosingEntranceSignal
    game.print(trainManagerEntry.id .. " has closed entrance at: " .. Utils.FormatPositionTableToString(portal.entrySignals["in"].entity.position))
end

TunnelPortals.OpenEntranceSignalForTrainManagerEntry = function(portal, trainManagerEntry)
    -- TODO: log and do if not already done
    -- Log to trainManagersClosingEntranceSignal
    game.print(trainManagerEntry.id .. " has opened entrance at: " .. Utils.FormatPositionTableToString(portal.entrySignals["in"].entity.position))
end

return TunnelPortals
