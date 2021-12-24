local Events = require("utility/events")
local Interfaces = require("utility/interfaces")
local Utils = require("utility/utils")
local TunnelShared = require("scripts/tunnel-shared")
local Common = require("scripts/common")
local PortalEndAndSegmentEntityNames, TunnelSignalDirection, TunnelUsageParts = Common.PortalEndAndSegmentEntityNames, Common.TunnelSignalDirection, Common.TunnelUsageParts
local TunnelPortals = {}
local EventScheduler = require("utility/event-scheduler")

-- Distances are from entry end portal position in the Portal.entryDirection direction.
local EntryEndPortalSetup = {
    trackEntryPointFromCenter = 3, -- the border of the portal on the entry side.
    entrySignalsDistance = 1.5,
    enteringTrainUsageDetectorEntityDistance = 0.5 -- Detector on the entry side of the portal. Its positioned so that a train entering the tunnel doesn't hit it until just before it triggers the signal, but a leaving train won't touch it either when waiting at the exit signals. This is a judgement call as trains can actually collide when manaully driven over signals without triggering them. Positioned to minimise UPS usage
}

-- Distances are from blocking end portal position in the Portal.entryDirection direction.
local BlockingEndPortalSetup = {
    dummyLocomotiveDistance = 1.8, -- as far back in to the end portal without touching the blocking locomotive.
    transitionUsageDetectorEntityDistance = 4.1, -- can't go further back as otherwise the entering train will release the signal and thus the tunnel.
    transitionSignalsDistance = 2.5,
    transitionSignalBlockingLocomotiveDistance = -1.3, -- As far away from entry end as possible, but can't stick out beyond the portal's collision box.
    blockedInvisibleSignalsDistance = -1.5
}

---@class Portal
---@field id uint @ unique id of the portal object.
---@field isComplete boolean @ if the portal has 2 connected portal end objects or not.
---@field portalEnds table<UnitNumber, PortalEnd> @ the portal end objects of this portal. No direction, orientation or role information implied by this array. Key'd by the portal end entity unit_number (id).
---@field portalSegments table<UnitNumber, PortalSegment> @ the portal segment objects of this portal. Key'd by the portal segment entity unit_number (id).
---@field trainWaitingAreaTilesLength int @ how many tiles this portal has for trains to wait in it when using the tunnel.
---@field force LuaForce @ the force this portal object belongs to.
---@field surface LuaSurface @ the surface this portal part object is on.
---@field portalTunnelConnectionSurfacePositions table<SurfacePositionString, PortalTunnelConnectionSurfacePositionObject> @ the 2 entries in global.tunnelPortals.portalTunnelConnectionSurfacePositions for this portal. Populated on a complete portal.
---@field entryPortalEnd PortalEnd @ the entry portal object of this portal. Only established once this portal is part of a valid tunnel.
---@field blockedPortalEnd PortalEnd @ the blocked portal object of this portal. Only established once this portal is part of a valid tunnel.
---@field transitionSignals table<TunnelSignalDirection, PortalTransitionSignal> @ These are the inner locked red signals that a train paths at to enter the tunnel. Only established once this portal is part of a valid tunnel.
---@field entrySignals table<TunnelSignalDirection, PortalEntrySignal> @ These are the signals that are visible to the wider train network and player. The portals 2 IN entry signals are connected by red wire. Only established once this portal is part of a valid tunnel.
---@field tunnel Tunnel @ ref to tunnel object if this portal is part of one. Only established once this portal is part of a valid tunnel.
---@field portalRailEntities table<UnitNumber, LuaEntity> @ the rail entities that are part of the portal. Only established once this portal is part of a valid tunnel.
---@field portalOtherEntities table<UnitNumber, LuaEntity> @ table of the non rail entities that are part of the portal. Will be deleted before the portalRailEntities. Only established once this portal is part of a valid tunnel.
---@field portalEntryPointPosition Position @ the position of the entry point to the portal. Only established once this portal is part of a valid tunnel.
---@field enteringTrainUsageDetectorEntity LuaEntity @ hidden entity on the entry point to the portal that's death signifies a train is coming on to the portal's rails. Only established once this portal is part of a valid tunnel.
---@field enteringTrainUsageDetectorPosition Position @ the position of this portals enteringTrainUsageDetectorEntity. Only established once this portal is part of a valid tunnel.
---@field transitionUsageDetectorEntity LuaEntity @ hidden entity on the transition point of the portal track that's death signifies a train has reached the entering tunnel stage. Only established once this portal is part of a valid tunnel.
---@field transitionUsageDetectorPosition Position @ the position of this portals transitionUsageDetectorEntity. Only established once this portal is part of a valid tunnel.
---@field dummyLocomotivePosition Position @ the position where the dummy locomotive should be plaed for this portal. Only established once this portal is part of a valid tunnel.
---@field entryDirection defines.direction @ the direction a train would be heading if it was entering this portal. So the entry signals are at the rear of this direction. Only established once this portal is part of a valid tunnel.
---@field leavingDirection defines.direction @ the direction a train would be heading if leaving the tunnel via this portal. Only established once this portal is part of a valid tunnel.

---@class PortalPart @ a generic part (entity) object making up part of a potral.
---@field id UnitNumber @ unit_number of the portal part entity.
---@field entity LuaEntity @ ref to the portal part entity.
---@field entity_name string @ cache of the portal part's entity's name.
---@field entity_position Position @ cache of the entity's position.
---@field entity_direction defines.direction @ cache of the entity's direction.
---@field entity_orientation RealOrientation @ cache of the entity's orientation.
---@field frontPosition Position @ used as base to look for other parts' portalPartSurfacePositions global object entries. These are present on each connecting end of the part 0.5 tile in from its connecting center. This is to handle various shapes.
---@field rearPosition Position @ used as base to look for other parts' portalPartSurfacePositions global object entries. These are present on each connecting end of the part 0.5 tile in from its connecting center. This is to handle various shapes.
---@field portal Portal @ ref to the parent portal object.
---@field typeData PortalPartTypeData @ ref to generic data about this type of portal part.
---@field surface LuaSurface @ the surface this portal part object is on.
---@field surface_index uint @ cached index of the surface this portal part is on.
---@field force LuaForce @ the force this portal part object belongs to.
---@field nonConnectedSurfacePositions table<SurfacePositionString, SurfacePositionString> @ a table of this end part's non connected external positions to check outside of the entity.

---@class PortalEnd : PortalPart @ the end part of a portal.
---@field endPortalType EndPortalType|null @ the type of role this end portal is providing to the parent portal. Only populated when its part of a full tunnel and thus direciotn is known.
---@field connectedToUnderground boolean @ if theres an underground segment connected to this portal on one side as part of the completed tunnel.

---@class EndPortalType
local EndPortalType = {
    entry = "entry",
    blocker = "blocker"
}

---@class PortalSegment : PortalPart @ a middle segment of a portal.
---@field segmentShape PortalSegmentShape

---@class PortalSignal
---@field id UnitNumber @ unit_number of this signal.
---@field direction TunnelSignalDirection
---@field entity LuaEntity
---@field entity_position Position
---@field portal Portal

---@class PortalTransitionSignal : PortalSignal

---@class PortalEntrySignal : PortalSignal

---@class PortalPartSurfacePositionObject
---@field id SurfacePositionString
---@field portalPart PortalPart

---@class PortalTunnelConnectionSurfacePositionObject
---@field id SurfacePositionString
---@field portal Portal
---@field endPortalPart PortalEnd

---@class PortalPartType @ if the portal part is an End or Segment.
local PortalPartType = {
    portalEnd = "portalEnd",
    portalSegment = "portalSegment"
}

---@class PortalSegmentShape @ the shape of the segment part.
local SegmentShape = {
    straight = "straight", -- Short straight piece for horizontal and vertical.
    diagonal = "diagonal", -- Short diagonal piece.
    curveStart = "curveStart", -- The start of a curve, so between Straight and Diagonal.
    curveInner = "curveInner" -- The inner part of a curve that connects 2 curveStart's togeather to make a 90 degree corner.
}

---@class PortalPartTypeData
---@field name string
---@field partType PortalPartType
---@field trainWaitingAreaTilesLength int @ how many tiles this part has for trains to wait in it when using the tunnel.
---@field tracksPositionOffset PortalPartTrackPositionOffset[] @the type of track and its position offset from the center of the part when in a 0 orientation.

---@class EndPortalTypeData:PortalPartTypeData

---@class SegmentPortalTypeData:PortalPartTypeData
---@field segmentShape PortalSegmentShape

---@class PortalPartTrackPositionOffset @ type of track and its position offset from the center of the part when in a 0 orientation.
---@field trackEntityName string
---@field positionOffset Position
---@field baseDirection defines.direction

---@type PortalPartTypeData[]
local PortalTypeData = {
    ---@type EndPortalTypeData
    ["railway_tunnel-portal_end"] = {
        name = "railway_tunnel-portal_end",
        partType = PortalPartType.portalEnd,
        trainWaitingAreaTilesLength = 0,
        tracksPositionOffset = {
            {
                trackEntityName = "railway_tunnel-portal_rail-on_map",
                positionOffset = {x = 0, y = -2},
                baseDirection = defines.direction.north
            },
            {
                trackEntityName = "railway_tunnel-portal_rail-on_map",
                positionOffset = {x = 0, y = 0},
                baseDirection = defines.direction.north
            },
            {
                trackEntityName = "railway_tunnel-portal_rail-on_map",
                positionOffset = {x = 0, y = 2},
                baseDirection = defines.direction.north
            }
        }
    },
    ---@type SegmentPortalTypeData
    ["railway_tunnel-portal_segment-straight"] = {
        name = "railway_tunnel-portal_segment-straight",
        partType = PortalPartType.portalSegment,
        segmentShape = SegmentShape.straight,
        trainWaitingAreaTilesLength = 2,
        tracksPositionOffset = {
            {
                trackEntityName = "railway_tunnel-portal_rail-on_map",
                positionOffset = {x = 0, y = 0},
                baseDirection = defines.direction.north
            }
        }
    }
}

TunnelPortals.CreateGlobals = function()
    global.tunnelPortals = global.tunnelPortals or {}
    global.tunnelPortals.nextPortalId = global.tunnelPortals.nextPortalId or 1
    global.tunnelPortals.portals = global.tunnelPortals.portals or {} ---@type table<Id, Portal>
    global.tunnelPortals.portalEnds = global.tunnelPortals.portaportalEndslParts or {} ---@type table<UnitNumber, PortalEnd>
    global.tunnelPortals.portalSegments = global.tunnelPortals.portalSegments or {} ---@type table<UnitNumber, PortalSegment>
    global.tunnelPortals.enteringTrainUsageDetectorEntityIdToPortal = global.tunnelPortals.enteringTrainUsageDetectorEntityIdToPortal or {} ---@type table<UnitNumber, Portal> @ Used to be able to identify the portal when the entering train detection entity is killed.
    global.tunnelPortals.transitionUsageDetectorEntityIdToPortal = global.tunnelPortals.transitionUsageDetectorEntityIdToPortal or {} ---@type table<UnitNumber, Portal> @ Used to be able to identify the portal when the transition train detection entity is killed.
    global.tunnelPortals.portalPartConnectionSurfacePositions = global.tunnelPortals.portalPartConnectionSurfacePositions or {} ---@type table<Id, PortalPartSurfacePositionObject> @ a lookup for positions that portal parts can connect to each other on. It is 0.5 tiles within the edge of their connection border. Saves searching for entities on the map via API.
    global.tunnelPortals.portalTunnelConnectionSurfacePositions = global.tunnelPortals.portalTunnelConnectionSurfacePositions or {} ---@type table<SurfacePositionString, PortalTunnelConnectionSurfacePositionObject> @ a lookup for portal by an external position string for truing to connect to an underground. It is 0.5 tiles outside the end portal entity border, where the underground segments connection point is. Saves searching for entities on the map via API.
end

TunnelPortals.OnLoad = function()
    local portalEntityNames_Filter = {}
    for _, name in pairs(PortalEndAndSegmentEntityNames) do
        table.insert(portalEntityNames_Filter, {filter = "name", name = name})
    end

    Events.RegisterHandlerEvent(defines.events.on_built_entity, "TunnelPortals.OnBuiltEntity", TunnelPortals.OnBuiltEntity, portalEntityNames_Filter)
    Events.RegisterHandlerEvent(defines.events.on_robot_built_entity, "TunnelPortals.OnBuiltEntity", TunnelPortals.OnBuiltEntity, portalEntityNames_Filter)
    Events.RegisterHandlerEvent(defines.events.script_raised_built, "TunnelPortals.OnBuiltEntity", TunnelPortals.OnBuiltEntity, portalEntityNames_Filter)
    Events.RegisterHandlerEvent(defines.events.script_raised_revive, "TunnelPortals.OnBuiltEntity", TunnelPortals.OnBuiltEntity, portalEntityNames_Filter)
    Events.RegisterHandlerEvent(defines.events.on_pre_player_mined_item, "TunnelPortals.OnPreMinedEntity", TunnelPortals.OnPreMinedEntity, portalEntityNames_Filter)
    Events.RegisterHandlerEvent(defines.events.on_robot_pre_mined, "TunnelPortals.OnPreMinedEntity", TunnelPortals.OnPreMinedEntity, portalEntityNames_Filter)
    Events.RegisterHandlerEvent(defines.events.on_entity_died, "TunnelPortals.OnDiedEntity", TunnelPortals.OnDiedEntity, portalEntityNames_Filter)
    Events.RegisterHandlerEvent(defines.events.script_raised_destroy, "TunnelPortals.OnDiedEntity", TunnelPortals.OnDiedEntity, portalEntityNames_Filter)

    local portalEntityGhostNames_Filter = {}
    for _, name in pairs(PortalEndAndSegmentEntityNames) do
        table.insert(portalEntityGhostNames_Filter, {filter = "ghost_name", name = name})
    end
    Events.RegisterHandlerEvent(defines.events.on_built_entity, "TunnelPortals.OnBuiltEntityGhost", TunnelPortals.OnBuiltEntityGhost, portalEntityGhostNames_Filter)
    Events.RegisterHandlerEvent(defines.events.on_robot_built_entity, "TunnelPortals.OnBuiltEntityGhost", TunnelPortals.OnBuiltEntityGhost, portalEntityGhostNames_Filter)
    Events.RegisterHandlerEvent(defines.events.script_raised_built, "TunnelPortals.OnBuiltEntityGhost", TunnelPortals.OnBuiltEntityGhost, portalEntityGhostNames_Filter)

    Interfaces.RegisterInterface("TunnelPortals.On_PreTunnelCompleted", TunnelPortals.On_PreTunnelCompleted)
    Interfaces.RegisterInterface("TunnelPortals.On_TunnelRemoved", TunnelPortals.On_TunnelRemoved)
    Interfaces.RegisterInterface("TunnelPortals.AddEnteringTrainUsageDetectionEntityToPortal", TunnelPortals.AddEnteringTrainUsageDetectionEntityToPortal)
    Interfaces.RegisterInterface("TunnelPortals.CanAPortalConnectAtPosition", TunnelPortals.CanAPortalConnectAtPosition)
    Interfaces.RegisterInterface("TunnelPortals.PortalPartsAboutToBeInNewTunnel", TunnelPortals.PortalPartsAboutToBeInNewTunnel)
    Interfaces.RegisterInterface("TunnelPortals.On_PostTunnelCompleted", TunnelPortals.On_PostTunnelCompleted)

    EventScheduler.RegisterScheduledEventType("TunnelPortals.TryCreateEnteringTrainUsageDetectionEntityAtPosition", TunnelPortals.TryCreateEnteringTrainUsageDetectionEntityAtPosition)

    local portalEntryTrainDetector1x1_Filter = {{filter = "name", name = "railway_tunnel-portal_entry_train_detector_1x1"}}
    Events.RegisterHandlerEvent(defines.events.on_entity_died, "TunnelPortals.OnDiedEntityPortalEntryTrainDetector", TunnelPortals.OnDiedEntityPortalEntryTrainDetector, portalEntryTrainDetector1x1_Filter)
    Events.RegisterHandlerEvent(defines.events.script_raised_destroy, "TunnelPortals.OnDiedEntityPortalEntryTrainDetector", TunnelPortals.OnDiedEntityPortalEntryTrainDetector, portalEntryTrainDetector1x1_Filter)

    local portalTransitionTrainDetector1x1_Filter = {{filter = "name", name = "railway_tunnel-portal_transition_train_detector_1x1"}}
    Events.RegisterHandlerEvent(defines.events.on_entity_died, "TunnelPortals.OnDiedEntityPortalTransitionTrainDetector", TunnelPortals.OnDiedEntityPortalTransitionTrainDetector, portalTransitionTrainDetector1x1_Filter)
    Events.RegisterHandlerEvent(defines.events.script_raised_destroy, "TunnelPortals.OnDiedEntityPortalTransitionTrainDetector", TunnelPortals.OnDiedEntityPortalTransitionTrainDetector, portalTransitionTrainDetector1x1_Filter)
end

---@param event on_built_entity|on_robot_built_entity|script_raised_built|script_raised_revive
TunnelPortals.OnBuiltEntity = function(event)
    local createdEntity = event.created_entity or event.entity
    if not createdEntity.valid then
        return
    end
    local createdEntity_name = createdEntity.name
    if PortalEndAndSegmentEntityNames[createdEntity_name] == nil then
        return
    end
    local placer = event.robot -- Will be nil for player or script placed.
    if placer == nil and event.player_index ~= nil then
        placer = game.get_player(event.player_index)
    end
    TunnelPortals.TunnelPortalPartBuilt(createdEntity, placer, createdEntity_name)
end

---@param builtEntity LuaEntity
---@param placer EntityActioner
---@param builtEntity_name string
---@return boolean
TunnelPortals.TunnelPortalPartBuilt = function(builtEntity, placer, builtEntity_name)
    -- Check the placement is on rail grid, if not then undo the placement and stop.
    if not TunnelShared.IsPlacementOnRailGrid(builtEntity) then
        TunnelShared.UndoInvalidTunnelPartPlacement(builtEntity, placer, true)
        return
    end

    -- Get the generic attributes of the built entity needed for the object.
    local builtEntity_position, builtEntity_direction, surface, builtEntity_orientation = builtEntity.position, builtEntity.direction, builtEntity.surface, builtEntity.orientation
    local portalTypeData, surface_index = PortalTypeData[builtEntity_name], surface.index
    ---@type PortalPart
    local portalPartObject = {
        id = builtEntity.unit_number,
        entity = builtEntity,
        entity_name = builtEntity_name,
        entity_position = builtEntity_position,
        entity_direction = builtEntity_direction,
        entity_orientation = builtEntity_orientation,
        surface = surface,
        surface_index = surface_index,
        force = builtEntity.force,
        typeData = portalTypeData,
        nonConnectedSurfacePositions = {}
    }

    -- Handle the caching of specific portal part type information and to their globals.
    if portalTypeData.partType == PortalPartType.portalEnd then
        -- Placed entity is an end.
        local endPortal = portalPartObject ---@type PortalEnd
        -- Has 2 positions that other portal parts can check it for as a connection. 2.5 tiles from centre in both connecting directions (0.5 tile in from its edge).
        endPortal.frontPosition = Utils.ApplyOffsetToPosition(builtEntity_position, Utils.RotatePositionAround0(builtEntity_orientation, {x = 0, y = -2.5}))
        endPortal.rearPosition = Utils.ApplyOffsetToPosition(builtEntity_position, Utils.RotatePositionAround0(builtEntity_orientation, {x = 0, y = 2.5}))
        endPortal.connectedToUnderground = false
        global.tunnelPortals.portalEnds[portalPartObject.id] = endPortal
    elseif portalTypeData.partType == PortalPartType.portalSegment then
        -- Placed entity is a segment.
        ---@typelist SegmentPortalTypeData, PortalSegment
        local segmentPortalTypeData, segmentPortal = portalTypeData, portalPartObject
        if segmentPortalTypeData.segmentShape == SegmentShape.straight then
            segmentPortal.segmentShape = segmentPortalTypeData.segmentShape
            segmentPortal.frontPosition = Utils.ApplyOffsetToPosition(builtEntity_position, Utils.RotatePositionAround0(builtEntity_orientation, {x = 0, y = -0.5}))
            segmentPortal.rearPosition = Utils.ApplyOffsetToPosition(builtEntity_position, Utils.RotatePositionAround0(builtEntity_orientation, {x = 0, y = 0.5}))
        else
            error("unrecognised segmentPortalTypeData.segmentShape: " .. segmentPortalTypeData.segmentShape)
        end
        global.tunnelPortals.portalSegments[portalPartObject.id] = segmentPortal
    else
        error("unrecognised portalTypeData.partType: " .. portalTypeData.partType)
    end

    -- Register the parts surfacePositionStrings for reverse lookup.
    local frontSurfacePositionString = Utils.FormatSurfacePositionTableToString(surface_index, portalPartObject.frontPosition)
    global.tunnelPortals.portalPartConnectionSurfacePositions[frontSurfacePositionString] = {
        id = frontSurfacePositionString,
        portalPart = portalPartObject
    }
    local rearSurfacePositionString = Utils.FormatSurfacePositionTableToString(surface_index, portalPartObject.rearPosition)
    global.tunnelPortals.portalPartConnectionSurfacePositions[rearSurfacePositionString] = {
        id = rearSurfacePositionString,
        portalPart = portalPartObject
    }

    TunnelPortals.UpdatePortalsForNewPortalPart(portalPartObject)

    if portalPartObject.portal ~= nil and portalPartObject.portal.isComplete then
        TunnelPortals.CheckAndHandleTunnelCompleteFromPortal(portalPartObject.portal)
    end
end

--- Check if this portal part is next to another portal part on either/both sides. If it is create/add to a portal object for them. A single portal part doesn't get a portal object.
---@param portalPartObject PortalPart
TunnelPortals.UpdatePortalsForNewPortalPart = function(portalPartObject)
    local firstComplictedConnectedPart, secondComplictedConnectedPart = nil, nil

    -- TODO: this doesn't stop odd part ordering that arises from 2 incompatible portals being joined, like:  S S E S S BUILD_S_HERE E S

    -- Check for a connected viable portal part in both directions from our portal part.
    for _, checkDetails in pairs(
        {
            {
                refPos = portalPartObject.frontPosition,
                refOrientation = portalPartObject.entity_orientation
            },
            {
                refPos = portalPartObject.rearPosition,
                refOrientation = Utils.LoopOrientationValue(portalPartObject.entity_orientation + 0.5)
            }
        }
    ) do
        local checkPos = Utils.ApplyOffsetToPosition(checkDetails.refPos, Utils.RotatePositionAround0(checkDetails.refOrientation, {x = 0, y = -1})) -- The position 1 tiles in front of our facing position, so 0.5 tiles outside the entity border.
        local checkSurfacePositionString = Utils.FormatSurfacePositionTableToString(portalPartObject.surface_index, checkPos)
        local foundPortalPartPositionObject = global.tunnelPortals.portalPartConnectionSurfacePositions[checkSurfacePositionString]
        -- If a portal reference at this position is found next to this one add this part to its/new portal.
        if foundPortalPartPositionObject ~= nil then
            local connectedPortalPart = foundPortalPartPositionObject.portalPart
            local connectedPortalPartPositionNowConnected = Utils.FormatSurfacePositionTableToString(portalPartObject.surface_index, checkDetails.refPos) -- This is the connected portal part's external checking position.
            -- If the connected part has a completed portal we can't join to it.
            if connectedPortalPart.portal == nil or (connectedPortalPart.portal and not connectedPortalPart.portal.isComplete) then
                -- Valid portal to create connection too, just work out how to handle this. Note some scenarios are not handled in this loop.
                if portalPartObject.portal and connectedPortalPart.portal == nil then
                    -- We have a portal and they don't, so add them to our portal.
                    TunnelPortals.AddPartToPortal(portalPartObject.portal, connectedPortalPart)
                elseif portalPartObject.portal == nil and connectedPortalPart.portal then
                    -- We don't have a portal and they do, so add us to their portal.
                    TunnelPortals.AddPartToPortal(connectedPortalPart.portal, portalPartObject)
                else
                    -- Either we both have portals or neither have portals. Just flag this and review after checking both directions.
                    if firstComplictedConnectedPart == nil then
                        firstComplictedConnectedPart = connectedPortalPart
                    else
                        secondComplictedConnectedPart = connectedPortalPart
                    end
                end
                portalPartObject.nonConnectedSurfacePositions[checkSurfacePositionString] = nil
                connectedPortalPart.nonConnectedSurfacePositions[connectedPortalPartPositionNowConnected] = nil
            else
                portalPartObject.nonConnectedSurfacePositions[checkSurfacePositionString] = checkSurfacePositionString
            end
        else
            portalPartObject.nonConnectedSurfacePositions[checkSurfacePositionString] = checkSurfacePositionString
        end
    end

    -- Handle any weird situations where theres lots of portals or none. Note that the scenarios handled are limited based on the logic outcomes of the direciton checking logic.
    if firstComplictedConnectedPart ~= nil then
        if portalPartObject.portal == nil then
            -- none has a portal, so create one for all.
            local portalId = global.tunnelPortals.nextPortalId
            global.tunnelPortals.nextPortalId = global.tunnelPortals.nextPortalId + 1
            ---@type Portal
            local portal = {
                id = portalId,
                isComplete = false,
                portalEnds = {},
                portalSegments = {},
                trainWaitingAreaTilesLength = 0,
                force = portalPartObject.force,
                surface = portalPartObject.surface,
                portalRailEntities = {},
                portalTunnelConnectionSurfacePositions = {}
                --portalEntryPointPosition = Utils.ApplyOffsetToPosition(portalEntity_position, Utils.RotatePositionAround0(builtEntity.orientation, {x = 0, y = 0 - math.abs(EntryEndPortalSetup.trackEntryPointFromCenter)})) -- OVERHAUL - not sure what this is really, fix later.
            }
            global.tunnelPortals.portals[portalId] = portal
            TunnelPortals.AddPartToPortal(portal, portalPartObject)
            TunnelPortals.AddPartToPortal(portal, firstComplictedConnectedPart)
            if secondComplictedConnectedPart ~= nil then
                TunnelPortals.AddPartToPortal(portal, secondComplictedConnectedPart)
            end
        else
            -- Us and the one complicated part both have a portal, so merge them. Use whichever has more segments as new master as this is generally the best one.
            if Utils.GetTableNonNilLength(portalPartObject.portal.portalSegments) >= Utils.GetTableNonNilLength(firstComplictedConnectedPart.portal.portalSegments) then
                TunnelPortals.MergePortalInToOtherPortal(firstComplictedConnectedPart.portal, portalPartObject.portal)
            else
                TunnelPortals.MergePortalInToOtherPortal(portalPartObject.portal, firstComplictedConnectedPart.portal)
            end
        end
    end

    -- Check if portal is complete.
    if portalPartObject.portal ~= nil and Utils.GetTableNonNilLength(portalPartObject.portal.portalEnds) == 2 then
        TunnelPortals.PortalComplete(portalPartObject.portal)
    end
end

--- Add the portalPart to the portal based on its type.
---@param portal Portal
---@param portalPart PortalPart
TunnelPortals.AddPartToPortal = function(portal, portalPart)
    portalPart.portal = portal
    if portalPart.typeData.partType == PortalPartType.portalEnd then
        portal.portalEnds[portalPart.id] = portalPart
    elseif portalPart.typeData.partType == PortalPartType.portalSegment then
        portal.portalSegments[portalPart.id] = portalPart
        portal.trainWaitingAreaTilesLength = portal.trainWaitingAreaTilesLength + portalPart.typeData.trainWaitingAreaTilesLength
    else
        error("invalid portal type: " .. portalPart.typeData.partType)
    end
end

--- Moves the old partal parts to the new portal and removes the old portal object.
---@param oldPortal Portal
---@param newPortal Portal
TunnelPortals.MergePortalInToOtherPortal = function(oldPortal, newPortal)
    for id, part in pairs(oldPortal.portalEnds) do
        newPortal.portalEnds[id] = part
        part.portal = newPortal
    end
    for id, part in pairs(oldPortal.portalSegments) do
        newPortal.portalSegments[id] = part
        part.portal = newPortal
    end
    newPortal.trainWaitingAreaTilesLength = newPortal.trainWaitingAreaTilesLength + oldPortal.trainWaitingAreaTilesLength
    global.tunnelPortals.portals[oldPortal.id] = nil
end

---@param portal Portal
TunnelPortals.PortalComplete = function(portal)
    portal.isComplete = true
    game.print("DEBUG: portal complete: " .. portal.id)
    -- OVERHAUL - will create the stats on the portal length and make the clickable bit here. As these should be inspectable before the whole tunnel is made. Also add some sort of visual confirmation the portal is complete, maybe the concrete top graphic. No track until its a full tunnel to avoid complications.
    -- Work out where a tunnel could connect to the portal based on the unconnected sides of the End Portals.
    for _, endPortalPart in pairs(portal.portalEnds) do
        local undergroundConnectionSurfacePositionString = next(endPortalPart.nonConnectedSurfacePositions)
        local portalTunnelConnectionSurfacePositionObject = {
            id = undergroundConnectionSurfacePositionString,
            portal = portal,
            endPortalPart = endPortalPart
        }
        global.tunnelPortals.portalTunnelConnectionSurfacePositions[undergroundConnectionSurfacePositionString] = portalTunnelConnectionSurfacePositionObject
        portal.portalTunnelConnectionSurfacePositions[undergroundConnectionSurfacePositionString] = portalTunnelConnectionSurfacePositionObject
    end
end

-- Checks if the tunnel is complete and if it is triggers the tunnel complete code.
---@param portal Portal
TunnelPortals.CheckAndHandleTunnelCompleteFromPortal = function(portal)
    for surfacePositionString, portalTunnelConnectionSurfacePositionObject in pairs(portal.portalTunnelConnectionSurfacePositions) do
        ---@typelist Underground, UndergroundSegment, UndergroundSegment
        local underground, otherEndSegment = Interfaces.Call("UndergroundSegments.CanAnUndergroundConnectAtPosition", surfacePositionString)
        if underground ~= nil then
            local foundPortal, foundEndPortalPart = Interfaces.Call("UndergroundSegments.DoesUndergroundSegmentConnectToAPortal", otherEndSegment, portal)
            if foundPortal ~= nil then
                TunnelPortals.PortalPartsAboutToBeInNewTunnel({portalTunnelConnectionSurfacePositionObject.endPortalPart, foundEndPortalPart})
                Interfaces.Call("Tunnel.CompleteTunnel", {portal, foundPortal}, underground)
            end
        end
    end
end

--- Checks if a complete Portal has a connection at a set point. If it does returns the objects, otherwise nil for all.
---@param surfacePositionString SurfacePositionString
---@return Portal|null portal
---@return PortalEnd|null portalEnd
TunnelPortals.CanAPortalConnectAtPosition = function(surfacePositionString)
    local portalTunnelConnectionSurfacePositionObject = global.tunnelPortals.portalTunnelConnectionSurfacePositions[surfacePositionString]
    if portalTunnelConnectionSurfacePositionObject ~= nil and portalTunnelConnectionSurfacePositionObject.portal.isComplete then
        return portalTunnelConnectionSurfacePositionObject.portal, portalTunnelConnectionSurfacePositionObject.endPortalPart
    end
end

--- Called when a tunnel is about to be created and the 2 end portal parts that connect to the underground are known.
---@param endPortalParts PortalEnd[]
TunnelPortals.PortalPartsAboutToBeInNewTunnel = function(endPortalParts)
    endPortalParts[1].connectedToUnderground = true
    endPortalParts[2].connectedToUnderground = true
end

-- Registers and sets up the tunnel's portals prior to the tunnel object being created and references created.
---@param portals Portal[]
TunnelPortals.On_PreTunnelCompleted = function(portals)
    -- Add all the bits to each portal that only appear when the portal is part of a completed tunnel.
    for _, portal in pairs(portals) do
        -- Work out which portal end is the blocked end.
        ---@typelist PortalEnd, PortalEnd
        local entryPortalEnd, blockedPortalEnd
        for _, endPortalPart in pairs(portal.portalEnds) do
            if endPortalPart.connectedToUnderground then
                blockedPortalEnd = endPortalPart
                endPortalPart.endPortalType = EndPortalType.blocker
                portal.blockedPortalEnd = blockedPortalEnd
            else
                entryPortalEnd = endPortalPart
                endPortalPart.endPortalType = EndPortalType.entry
                portal.entryPortalEnd = entryPortalEnd
            end
        end

        -- Work out which direction an entering train would be heading in to this portal. Assumes portal is built in a straight line.
        local entryDirection = Utils.GetCardinalDirectionHeadingToPosition(entryPortalEnd.entity_position, blockedPortalEnd.entity_position)
        if entryDirection < 0 then
            error("failed to calculate valid entryDirection")
        end
        local reverseEntryDirection = Utils.LoopDirectionValue(entryDirection + 4)
        portal.entryDirection, portal.leavingDirection = entryDirection, reverseEntryDirection
        local entryOrientation = Utils.DirectionToOrientation(entryDirection)
        local surface, force = portal.surface, portal.force

        TunnelPortals.BuildRailForPortalsParts(portal)

        -- Add the signals at the entry part to the tunnel.
        local entrySignalInEntityPosition = Utils.ApplyOffsetToPosition(entryPortalEnd.entity_position, Utils.RotatePositionAround0(entryOrientation, {x = 1.5, y = EntryEndPortalSetup.entrySignalsDistance}))
        ---@type LuaEntity
        local entrySignalInEntity =
            surface.create_entity {
            name = "railway_tunnel-internal_signal-not_on_map",
            position = entrySignalInEntityPosition,
            force = force,
            direction = reverseEntryDirection
        }
        local entrySignalOutEntityPosition = Utils.ApplyOffsetToPosition(entryPortalEnd.entity_position, Utils.RotatePositionAround0(entryOrientation, {x = -1.5, y = EntryEndPortalSetup.entrySignalsDistance}))
        ---@type LuaEntity
        local entrySignalOutEntity =
            surface.create_entity {
            name = "railway_tunnel-internal_signal-not_on_map",
            position = entrySignalOutEntityPosition,
            force = force,
            direction = entryDirection
        }
        portal.entrySignals = {
            [TunnelSignalDirection.inSignal] = {
                id = entrySignalInEntity.unit_number,
                entity = entrySignalInEntity,
                entity_position = entrySignalInEntityPosition,
                portal = portal,
                direction = TunnelSignalDirection.inSignal
            },
            [TunnelSignalDirection.outSignal] = {
                id = entrySignalOutEntity.unit_number,
                entity = entrySignalOutEntity,
                entity_position = entrySignalOutEntityPosition,
                portal = portal,
                direction = TunnelSignalDirection.outSignal
            }
        }
        entrySignalInEntity.connect_neighbour {wire = defines.wire_type.green, target_entity = entrySignalOutEntity}

        -- Cache the objects details for later use.
        portal.dummyLocomotivePosition = Utils.ApplyOffsetToPosition(blockedPortalEnd.entity_position, Utils.RotatePositionAround0(entryOrientation, {x = 0, y = BlockingEndPortalSetup.dummyLocomotiveDistance}))
        portal.enteringTrainUsageDetectorPosition = Utils.ApplyOffsetToPosition(entryPortalEnd.entity_position, Utils.RotatePositionAround0(entryOrientation, {x = 0, y = EntryEndPortalSetup.enteringTrainUsageDetectorEntityDistance}))
        portal.transitionUsageDetectorPosition = Utils.ApplyOffsetToPosition(blockedPortalEnd.entity_position, Utils.RotatePositionAround0(entryOrientation, {x = 0, y = BlockingEndPortalSetup.transitionUsageDetectorEntityDistance}))

        -- Add the signals that mark the Tranisition point of the portal.
        local transitionSignalInEntityPosition = Utils.ApplyOffsetToPosition(blockedPortalEnd.entity_position, Utils.RotatePositionAround0(entryOrientation, {x = 1.5, y = BlockingEndPortalSetup.transitionSignalsDistance}))
        ---@type LuaEntity
        local transitionSignalInEntity =
            surface.create_entity {
            name = "railway_tunnel-invisible_signal-not_on_map",
            position = transitionSignalInEntityPosition,
            force = force,
            direction = reverseEntryDirection
        }
        local transitionSignalOutEntityPosition = Utils.ApplyOffsetToPosition(blockedPortalEnd.entity_position, Utils.RotatePositionAround0(entryOrientation, {x = -1.5, y = BlockingEndPortalSetup.transitionSignalsDistance}))
        ---@type LuaEntity
        local transitionSignalOutEntity =
            surface.create_entity {
            name = "railway_tunnel-invisible_signal-not_on_map",
            position = transitionSignalOutEntityPosition,
            force = force,
            direction = entryDirection
        }
        portal.transitionSignals = {
            [TunnelSignalDirection.inSignal] = {
                id = transitionSignalInEntity.unit_number,
                entity = transitionSignalInEntity,
                entity_position = transitionSignalInEntityPosition,
                portal = portal,
                direction = TunnelSignalDirection.inSignal
            },
            [TunnelSignalDirection.outSignal] = {
                id = transitionSignalOutEntity.unit_number,
                entity = transitionSignalOutEntity,
                entity_position = transitionSignalOutEntityPosition,
                portal = portal,
                direction = TunnelSignalDirection.outSignal
            }
        }
        Interfaces.Call("Tunnel.RegisterTransitionSignal", portal.transitionSignals[TunnelSignalDirection.inSignal])

        -- Add blocking loco and extra signals after where the Transition signals are at the very end of the portal. These make the Transition signals go red and stop paths being reservable across the underground track, thus leading trains to target the transitional signal.
        ---@type LuaEntity
        local blockedInvisibleSignalInEntity =
            surface.create_entity {
            name = "railway_tunnel-invisible_signal-not_on_map",
            position = Utils.ApplyOffsetToPosition(blockedPortalEnd.entity_position, Utils.RotatePositionAround0(entryOrientation, {x = 1.5, y = BlockingEndPortalSetup.blockedInvisibleSignalsDistance})),
            force = force,
            direction = reverseEntryDirection
        }
        ---@type LuaEntity
        local blockedInvisibleSignalOutEntity =
            surface.create_entity {
            name = "railway_tunnel-invisible_signal-not_on_map",
            position = Utils.ApplyOffsetToPosition(blockedPortalEnd.entity_position, Utils.RotatePositionAround0(entryOrientation, {x = -1.5, y = BlockingEndPortalSetup.blockedInvisibleSignalsDistance})),
            force = force,
            direction = entryDirection
        }
        ---@type LuaEntity
        local transitionSignalBlockingLocomotiveEntity =
            surface.create_entity {
            name = "railway_tunnel-tunnel_portal_blocking_locomotive",
            position = Utils.ApplyOffsetToPosition(blockedPortalEnd.entity_position, Utils.RotatePositionAround0(entryOrientation, {x = 0, y = BlockingEndPortalSetup.transitionSignalBlockingLocomotiveDistance})),
            force = global.force.tunnelForce,
            direction = reverseEntryDirection
        }
        transitionSignalBlockingLocomotiveEntity.train.schedule = {
            current = 1,
            records = {
                {
                    rail = surface.find_entities_filtered {
                        name = Common.TunnelSurfaceRailEntityNames,
                        position = Utils.ApplyOffsetToPosition(blockedPortalEnd.entity_position, Utils.RotatePositionAround0(entryOrientation, {x = 0, y = BlockingEndPortalSetup.transitionSignalBlockingLocomotiveDistance + 3})),
                        limit = 1
                    }[1]
                }
            }
        }
        transitionSignalBlockingLocomotiveEntity.train.manual_mode = false
        transitionSignalBlockingLocomotiveEntity.destructible = false
        portal.portalOtherEntities = {
            [blockedInvisibleSignalInEntity.unit_number] = blockedInvisibleSignalInEntity,
            [blockedInvisibleSignalOutEntity.unit_number] = blockedInvisibleSignalOutEntity,
            [transitionSignalBlockingLocomotiveEntity.unit_number] = transitionSignalBlockingLocomotiveEntity
        }
    end

    portals[1].entrySignals[TunnelSignalDirection.inSignal].entity.connect_neighbour {wire = defines.wire_type.red, target_entity = portals[2].entrySignals[TunnelSignalDirection.inSignal].entity}
    TunnelPortals.LinkRailSignalsToCloseWhenOtherIsntOpen(portals[1].entrySignals[TunnelSignalDirection.inSignal].entity, "signal-1", "signal-2")
    TunnelPortals.LinkRailSignalsToCloseWhenOtherIsntOpen(portals[2].entrySignals[TunnelSignalDirection.inSignal].entity, "signal-2", "signal-1")
end

-- Add the rails to the tunnel portal's parts.
---@param portal Portal
TunnelPortals.BuildRailForPortalsParts = function(portal)
    ---@param portalPart PortalPart
    ---@param tracksPositionOffset PortalPartTrackPositionOffset
    local PlaceRail = function(portalPart, tracksPositionOffset)
        local railPos = Utils.ApplyOffsetToPosition(portalPart.entity_position, Utils.RotatePositionAround0(portalPart.entity_orientation, tracksPositionOffset.positionOffset))
        -- OVERHAUL - possibly building via blueprint might be lower UPS usage for this - test and see.
        local placedRail = portal.surface.create_entity {name = tracksPositionOffset.trackEntityName, position = railPos, force = portal.force, direction = Utils.RotateDirectionByDirection(tracksPositionOffset.baseDirection, defines.direction.north, portalPart.entity_direction)}
        placedRail.destructible = false
        portal.portalRailEntities[placedRail.unit_number] = placedRail
    end
    for _, portalPart in pairs(portal.portalEnds) do
        for _, tracksPositionOffset in pairs(portalPart.typeData.tracksPositionOffset) do
            PlaceRail(portalPart, tracksPositionOffset)
        end
    end
    for _, portalPart in pairs(portal.portalSegments) do
        for _, tracksPositionOffset in pairs(portalPart.typeData.tracksPositionOffset) do
            PlaceRail(portalPart, tracksPositionOffset)
        end
    end
end

-- Sets a rail signal with circuit condition to output nonGreenSignalOutputName named signal when not open and to close when recieveing closeOnSignalName named signal. Used as part of cross linking 2 signals to close when the other isn't open.
---@param railSignalEntity LuaEntity
---@param nonGreenSignalOutputName string @ Virtual signal name to be output to the cirtuit network when the signal state isn't green.
---@param closeOnSignalName string @ Virtual signal name that triggers the singal state to be closed when its greater than 0 on the circuit network.
TunnelPortals.LinkRailSignalsToCloseWhenOtherIsntOpen = function(railSignalEntity, nonGreenSignalOutputName, closeOnSignalName)
    local controlBehavior = railSignalEntity.get_or_create_control_behavior() ---@type LuaRailSignalControlBehavior
    controlBehavior.read_signal = true
    controlBehavior.red_signal = {type = "virtual", name = nonGreenSignalOutputName}
    controlBehavior.orange_signal = {type = "virtual", name = nonGreenSignalOutputName}
    controlBehavior.close_signal = true
    controlBehavior.circuit_condition = {condition = {first_signal = {type = "virtual", name = closeOnSignalName}, comparator = ">", constant = 0}, fulfilled = true}
end

-- Registers and sets up the portal elements after the tunnel has been created.
---@param portals Portal[]
TunnelPortals.On_PostTunnelCompleted = function(portals)
    for _, portal in pairs(portals) do
        -- Both of these functions require the tunnel to be present in the portal object as they are called throughout the portals lifetime.
        TunnelPortals.AddEnteringTrainUsageDetectionEntityToPortal(portal, false)
        TunnelPortals.AddTransitionUsageDetectionEntityToPortal(portal)
    end
end

-- If the built entity was a ghost of an underground segment then check it is on the rail grid.
---@param event on_built_entity|on_robot_built_entity|script_raised_built
TunnelPortals.OnBuiltEntityGhost = function(event)
    -- TODO: move this to somewhere central and merge with underground check as identical code. Save UPS in event functions triggered within mod.
    local createdEntity = event.created_entity or event.entity
    if not createdEntity.valid or createdEntity.type ~= "entity-ghost" or PortalEndAndSegmentEntityNames[createdEntity.ghost_name] == nil then
        return
    end
    local placer = event.robot -- Will be nil for player or script placed.
    if placer == nil and event.player_index ~= nil then
        placer = game.get_player(event.player_index)
    end

    if not TunnelShared.IsPlacementOnRailGrid(createdEntity) then
        TunnelShared.UndoInvalidTunnelPartPlacement(createdEntity, placer, false)
        return
    end
end

-- TODO: GOT UP TO HERE IN THIS FILE
---@param event on_pre_player_mined_item|on_robot_pre_mined
TunnelPortals.OnPreMinedEntity = function(event)
    local minedEntity = event.entity
    if not minedEntity.valid or PortalEndAndSegmentEntityNames[minedEntity.name] == nil then
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

    if portal.tunnel == nil then
        TunnelPortals.EntityRemoved(portal)
    else
        if Interfaces.Call("Tunnel.GetTunnelsUsageEntry", portal.tunnel) then
            TunnelShared.EntityErrorMessage(miner, "Can not mine tunnel portal while train is using tunnel", minedEntity.surface, minedEntity.position)
            TunnelPortals.ReplacePortalEntity(portal)
        else
            Interfaces.Call("Tunnel.RemoveTunnel", portal.tunnel)
            TunnelPortals.EntityRemoved(portal)
        end
    end
end

---@param oldPortal Portal
TunnelPortals.ReplacePortalEntity = function(oldPortal)
    local centerPos, force, lastUser, directionValue, surface, entityName = oldPortal.entity.position, oldPortal.entity.force, oldPortal.entity.last_user, oldPortal.entity.direction, oldPortal.entity.surface, oldPortal.entity.name
    oldPortal.entity.destroy()

    local newPortalEntity = surface.create_entity {name = entityName, position = centerPos, direction = directionValue, force = force, player = lastUser}
    local newPortal = {
        id = newPortalEntity.unit_number,
        entityDirection = oldPortal.entityDirection,
        entity = newPortalEntity,
        transitionSignals = oldPortal.transitionSignals,
        entrySignals = oldPortal.entrySignals,
        tunnel = oldPortal.tunnel,
        portalRailEntities = oldPortal.portalRailEntities,
        portalOtherEntities = oldPortal.portalOtherEntities,
        enteringTrainUsageDetectorEntity = oldPortal.enteringTrainUsageDetectorEntity,
        entryPointDistanceFromCenter = oldPortal.entryPointDistanceFromCenter,
        portalEntryPointPosition = oldPortal.portalEntryPointPosition
    }

    -- Update the signals ref back to portal if the signals exist.
    if newPortal.transitionSignals ~= nil then
        newPortal.transitionSignals[TunnelSignalDirection.inSignal].portal = newPortal
        newPortal.transitionSignals[TunnelSignalDirection.outSignal].portal = newPortal
        newPortal.entrySignals[TunnelSignalDirection.inSignal].portal = newPortal
        newPortal.entrySignals[TunnelSignalDirection.outSignal].portal = newPortal
    end
    global.tunnelPortals.portals[newPortal.id] = newPortal
    global.tunnelPortals.portals[oldPortal.id] = nil
    Interfaces.Call("Tunnel.On_PortalReplaced", newPortal.tunnel, oldPortal, newPortal)
end

---@param portal Portal
---@param killForce LuaForce
---@param killerCauseEntity LuaEntity
TunnelPortals.EntityRemoved = function(portal, killForce, killerCauseEntity)
    -- TODO: remove the global portalPart position references when updating this function.
    TunnelPortals.RemoveEnteringTrainUsageDetectionEntityFromPortal(portal)
    TunnelPortals.RemoveTransitionUsageDetectionEntityFromPortal(portal)
    TunnelShared.DestroyCarriagesOnRailEntityList(portal.portalRailEntities, killForce, killerCauseEntity)
    for _, entrySignal in pairs(portal.entrySignals) do
        if entrySignal.entity.valid then
            entrySignal.entity.destroy()
        end
    end
    portal.entrySignals = nil
    for _, railEntity in pairs(portal.portalRailEntities) do
        if railEntity.valid then
            railEntity.destroy()
        end
    end
    portal.portalRailEntities = nil
    portal.isComplete = false
    global.tunnelPortals.portals[portal.id] = nil
end

---@param portals Portal[]
---@param killForce LuaForce
---@param killerCauseEntity LuaEntity
TunnelPortals.On_TunnelRemoved = function(portals, killForce, killerCauseEntity)
    for _, portal in pairs(portals) do
        TunnelShared.DestroyCarriagesOnRailEntityList(portal.portalRailEntities, killForce, killerCauseEntity)
        portal.tunnel = nil
        for _, otherEntity in pairs(portal.portalOtherEntities) do
            if otherEntity.valid then
                otherEntity.destroy()
            end
        end
        portal.portalOtherEntities = nil
        for _, railEntity in pairs(portal.portalRailEntities) do
            if railEntity.valid then
                railEntity.destroy()
            end
        end
        portal.portalRailEntities = nil
        for _, transitionSignal in pairs(portal.transitionSignals) do
            if transitionSignal.entity.valid then
                Interfaces.Call("Tunnel.DeregisterTransitionSignal", transitionSignal)
                transitionSignal.entity.destroy()
            end
        end
        portal.transitionSignals = nil

        TunnelPortals.RemoveTransitionUsageDetectionEntityFromPortal(portal)
    end
end

---@param event on_entity_died|script_raised_destroy
TunnelPortals.OnDiedEntity = function(event)
    local diedEntity, killerForce, killerCauseEntity = event.entity, event.force, event.cause -- The killer variables will be nil in some cases.
    if not diedEntity.valid or PortalEndAndSegmentEntityNames[diedEntity.name] == nil then
        return
    end

    local portal = global.tunnelPortals.portals[diedEntity.unit_number]
    if portal == nil then
        return
    end

    if portal.tunnel ~= nil then
        Interfaces.Call("Tunnel.RemoveTunnel", portal.tunnel)
    end
    TunnelPortals.EntityRemoved(portal, killerForce, killerCauseEntity)
end

-- Occurs when a train tries to pass through the border of a portal, when entering and exiting.
---@param event on_entity_died|script_raised_destroy
TunnelPortals.OnDiedEntityPortalEntryTrainDetector = function(event)
    local diedEntity, carriageEnteringPortalTrack = event.entity, event.cause
    if not diedEntity.valid or diedEntity.name ~= "railway_tunnel-portal_entry_train_detector_1x1" then
        -- Needed due to how died event handlers are all bundled togeather.
        return
    end

    local diedEntity_unitNumber = diedEntity.unit_number
    -- Tidy up the blocker reference as in all cases it has been removed.
    local portal = global.tunnelPortals.enteringTrainUsageDetectorEntityIdToPortal[diedEntity_unitNumber]
    global.tunnelPortals.enteringTrainUsageDetectorEntityIdToPortal[diedEntity_unitNumber] = nil
    if portal == nil then
        -- No portal any more so nothing further to do.
        return
    end
    portal.enteringTrainUsageDetectorEntity = nil

    if portal.tunnel == nil then
        -- if no tunnel then the portal won';'t have tracks, so nothing further to do.
        return
    end

    if carriageEnteringPortalTrack == nil then
        -- As there's no cause this should only occur when a script removes the entity. Try to return the detection entity and if the portal is being removed that will handle all scenarios.
        TunnelPortals.AddEnteringTrainUsageDetectionEntityToPortal(portal, true)
        return
    end
    local train = carriageEnteringPortalTrack.train

    -- Is a scheduled train following its schedule so check if its already reserved the tunnel.
    if not train.manual_mode and train.state ~= defines.train_state.no_schedule then
        local train_id = train.id
        local trainIdToManagedTrain = Interfaces.Call("TrainManager.GetTrainIdsManagedTrainDetails", train_id) ---@type TrainIdToManagedTrain
        if trainIdToManagedTrain ~= nil then
            -- This train has reserved a tunnel somewhere.
            local managedTrain = trainIdToManagedTrain.managedTrain
            if managedTrain.tunnel.id == portal.tunnel.id then
                -- The train has reserved this tunnel.
                if trainIdToManagedTrain.tunnelUsagePart == TunnelUsageParts.enteringTrain then
                    -- Train had reserved the tunnel via signals at distance and is now trying to pass in to the tunnels entry portal track. This is healthy activity.
                    return
                elseif trainIdToManagedTrain.tunnelUsagePart == TunnelUsageParts.leavingTrain then
                    -- Train has been using the tunnel and is now trying to pass out of the tunnels exit portal track. This is healthy activity.
                    return
                else
                    error("Train is crossing a tunnel portal's threshold while not in an expected state.\ntrainId: " .. train_id .. "\nenteredPortalId: " .. portal.id .. "\nreservedTunnelId: " .. managedTrain.tunnel.id)
                    return
                end
            else
                error("Train has entered one portal in automatic mode, while it has a reservation on another.\ntrainId: " .. train_id .. "\nenteredPortalId: " .. portal.id .. "\nreservedTunnelId: " .. managedTrain.tunnel.id)
                return
            end
        else
            -- This train hasn't reserved any tunnel.
            if portal.tunnel.managedTrain == nil then
                -- Portal's tunnel isn't reserved so this train can grab the portal.
                Interfaces.Call("TrainManager.RegisterTrainOnPortalTrack", train, portal)
                return
            else
                -- Portal's tunnel is already being used so stop this train entering. Not sure how this could have happened, but just stop the new train here and restore the entering train detection entity.
                if global.strictStateHandling then
                    -- This being a strict failure will be removed when future tests functionality is added. Is just in short term as we don't expect to reach this state ever.
                    error("Train has entered one portal in automatic mode, while the portal's tunnel was reserved by another train.\nthisTrainId: " .. train_id .. "\nenteredPortalId: " .. portal.id .. "\nreservedTunnelId: " .. portal.tunnel.managedTrain.tunnel.id .. "\reservedTrainId: " .. portal.tunnel.managedTrain.tunnel.managedTrain.id)
                    return
                else
                    train.speed = 0
                    TunnelPortals.AddEnteringTrainUsageDetectionEntityToPortal(portal, true)
                    rendering.draw_text {
                        text = "Tunnel in use",
                        surface = portal.tunnel.surface,
                        target = portal.entrySignals[TunnelSignalDirection.inSignal].entity_position,
                        time_to_live = 180,
                        forces = {portal.force},
                        color = {r = 1, g = 0, b = 0, a = 1},
                        scale_with_zoom = true
                    }
                    return
                end
            end
        end
    end

    -- Train has a player in it so we assume its being actively driven. Can only detect if player input is being entered right now, not the players intention.
    if #train.passengers ~= 0 then
        -- Future support for player driven train will expand this logic as needed. For now we just assume everything is fine.
        error("suspected player driving train")
        return
    end

    -- Train is coasting so stop it at the border and try to put the detection entity back.
    train.speed = 0
    TunnelPortals.AddEnteringTrainUsageDetectionEntityToPortal(portal, true)
    rendering.draw_text {
        text = "Unpowered trains can't use tunnels",
        surface = portal.tunnel.surface,
        target = portal.entrySignals[TunnelSignalDirection.inSignal].entity_position,
        time_to_live = 180,
        forces = {portal.force},
        color = {r = 1, g = 0, b = 0, a = 1},
        scale_with_zoom = true
    }
end

--- Will try and place the entering train detection entity now and if not possible will keep on trying each tick until either successful or a tunnel state setting stops the attempts. Is safe to call if the entity already exists as will just abort (initally or when in per tick loop).
---@param portal Portal
---@param retry boolean @ If to retry next tick should it not be placable.
---@return LuaEntity @ The enteringTrainUsageDetectorEntity if successfully placed.
TunnelPortals.AddEnteringTrainUsageDetectionEntityToPortal = function(portal, retry)
    if portal.tunnel == nil or not portal.isComplete or portal.enteringTrainUsageDetectorEntity ~= nil then
        -- The portal has been removed, so we shouldn't add the detection entity back. Or another task has added the dector back and so we can stop.
        return
    end
    return TunnelPortals.TryCreateEnteringTrainUsageDetectionEntityAtPosition(nil, portal, retry)
end

---@param event ScheduledEvent
---@param portal Portal
---@param retry boolean @ If to retry next tick should it not be placable.
---@return LuaEntity @ The enteringTrainUsageDetectorEntity if successfully placed.
TunnelPortals.TryCreateEnteringTrainUsageDetectionEntityAtPosition = function(event, portal, retry)
    local eventData
    if event ~= nil then
        eventData = event.data
        portal, retry = eventData.portal, eventData.retry
    end
    if portal.tunnel == nil or not portal.isComplete or portal.enteringTrainUsageDetectorEntity ~= nil then
        -- The portal has been removed, so we shouldn't add the detection entity back. Or another task has added the dector back and so we can stop.
        return
    end

    -- The left train will initially be within the collision box of where we want to place this. So check if it can be placed. For odd reasons the entity will "create" on top of a train and instantly be killed, so have to explicitly check.
    -- OVERHAUL - in tests 2/3 of the time we can create the entity and the cost of the can_place check is only slightly less than just doing it. So just try it and if it fails loop around for a retry.
    if
        portal.surface.can_place_entity {
            name = "railway_tunnel-portal_entry_train_detector_1x1",
            force = global.force.tunnelForce,
            position = portal.enteringTrainUsageDetectorPosition
        }
     then
        portal.enteringTrainUsageDetectorEntity =
            portal.surface.create_entity {
            name = "railway_tunnel-portal_entry_train_detector_1x1",
            force = global.force.tunnelForce,
            position = portal.enteringTrainUsageDetectorPosition
        }
        global.tunnelPortals.enteringTrainUsageDetectorEntityIdToPortal[portal.enteringTrainUsageDetectorEntity.unit_number] = portal
        return portal.enteringTrainUsageDetectorEntity
    elseif retry then
        -- Schedule this to be tried again next tick.
        local postbackData
        if eventData ~= nil then
            postbackData = eventData
        else
            postbackData = {portal = portal, retry = retry}
        end
        EventScheduler.ScheduleEventOnce(nil, "TunnelPortals.TryCreateEnteringTrainUsageDetectionEntityAtPosition", portal.id, postbackData)
    end
end

---@param portal Portal
TunnelPortals.RemoveEnteringTrainUsageDetectionEntityFromPortal = function(portal)
    if portal.enteringTrainUsageDetectorEntity ~= nil then
        if portal.enteringTrainUsageDetectorEntity.valid then
            global.tunnelPortals.enteringTrainUsageDetectorEntityIdToPortal[portal.enteringTrainUsageDetectorEntity.unit_number] = nil
            portal.enteringTrainUsageDetectorEntity.destroy()
        end
        portal.enteringTrainUsageDetectorEntity = nil
    end
end

-- Occurs when a train passes through the transition point of a portal when fully entering the tunnel.
---@param event on_entity_died|script_raised_destroy
TunnelPortals.OnDiedEntityPortalTransitionTrainDetector = function(event)
    local diedEntity, carriageAtTransitionOfPortalTrack = event.entity, event.cause
    if not diedEntity.valid or diedEntity.name ~= "railway_tunnel-portal_transition_train_detector_1x1" then
        -- Needed due to how died event handlers are all bundled togeather.
        return
    end

    local diedEntity_unitNumber = diedEntity.unit_number
    -- Tidy up the blocker reference as in all cases it has been removed.
    local portal = global.tunnelPortals.transitionUsageDetectorEntityIdToPortal[diedEntity_unitNumber]
    global.tunnelPortals.transitionUsageDetectorEntityIdToPortal[diedEntity_unitNumber] = nil
    if portal == nil then
        -- No portal any more so nothing further to do.
        return
    end
    portal.transitionUsageDetectorEntity = nil

    if portal.tunnel == nil then
        -- if no tunnel then the portal won't have tracks, so nothing further to do.
        return
    end

    if carriageAtTransitionOfPortalTrack == nil then
        -- As there's no cause this should only occur when a script removes the entity. Try to return the detection entity and if the portal is being removed that will handle all scenarios.
        TunnelPortals.AddTransitionUsageDetectionEntityToPortal(portal)
        return
    end
    local train = carriageAtTransitionOfPortalTrack.train

    -- OVERHAUL: this is new code and likely has logic holes in it.
    -- Is a scheduled train following its schedule so check if its already reserved the tunnel.
    if not train.manual_mode and train.state ~= defines.train_state.no_schedule then
        local train_id = train.id
        local trainIdToManagedTrain = Interfaces.Call("TrainManager.GetTrainIdsManagedTrainDetails", train_id) ---@type TrainIdToManagedTrain
        if trainIdToManagedTrain ~= nil then
            -- This train has reserved a tunnel somewhere.
            local managedTrain = trainIdToManagedTrain.managedTrain
            if managedTrain.tunnel.id == portal.tunnel.id then
                -- The train has reserved this tunnel.
                if trainIdToManagedTrain.tunnelUsagePart == TunnelUsageParts.enteringTrain then
                    -- Train had reserved the tunnel via signals at distance and is now ready to fully enter the tunnel.
                    Interfaces.Call("TrainManager.TrainEnterTunnel", managedTrain)
                    TunnelPortals.AddTransitionUsageDetectionEntityToPortal(portal)
                    return
                elseif trainIdToManagedTrain.tunnelUsagePart == TunnelUsageParts.leavingTrain then
                    error("Train has been using the tunnel and is now trying to pass backwards through the tunnel. This may be supported in future, but error for now.")
                    return
                else
                    error("Train is crossing a tunnel portal's transition threshold while not in an expected state.\ntrainId: " .. train_id .. "\nenteredPortalId: " .. portal.id .. "\nreservedTunnelId: " .. managedTrain.tunnel.id)
                    return
                end
            else
                error("Train has reached the transition point of one portal, while it has a reservation on another portal.\ntrainId: " .. train_id .. "\nenteredPortalId: " .. portal.id .. "\nreservedTunnelId: " .. managedTrain.tunnel.id)
                return
            end
        else
            -- This train hasn't reserved any tunnel.
            if portal.tunnel.managedTrain == nil then
                -- Portal's tunnel isn't reserved so this train can just use the tunnel to commit now.
                error("unsupported unexpected train entering tunnel without having passed through entry detector at present")
                Interfaces.Call("TrainManager.TrainEnterTunnel", nil, train)
                return
            else
                -- Portal's tunnel is already being used so stop this train from using the tunnel. Not sure how this could have happened, but just stop the new train here and restore the transition detection entity.
                if global.strictStateHandling then
                    -- This being a strict failure will be removed when future tests functionality is added. Is just in short term as we don't expect to reach this state ever.
                    error("Train has reached the transition of a portal in automatic mode, while the portal's tunnel was reserved by another train.\nthisTrainId: " .. train_id .. "\nenteredPortalId: " .. portal.id .. "\nreservedTunnelId: " .. portal.tunnel.managedTrain.tunnel.id .. "\reservedTrainId: " .. portal.tunnel.managedTrain.tunnel.managedTrain.id)
                    return
                else
                    train.speed = 0
                    TunnelPortals.AddTransitionUsageDetectionEntityToPortal(portal)
                    rendering.draw_text {
                        text = "Tunnel in use",
                        surface = portal.tunnel.surface,
                        target = portal.entrySignals[TunnelSignalDirection.inSignal].entity_position,
                        time_to_live = 180,
                        forces = {portal.force},
                        color = {r = 1, g = 0, b = 0, a = 1},
                        scale_with_zoom = true
                    }
                    return
                end
            end
        end
    end

    -- Train has a player in it so we assume its being actively driven. Can only detect if player input is being entered right now, not the players intention.
    if #train.passengers ~= 0 then
        -- Future support for player driven train will expand this logic as needed. For now we just assume everything is fine.
        error("suspected player driving train")
        return
    end

    -- Train is coasting so stop it dead and try to put the detection entity back. This shouldn't be reachable really.
    error("Train is coasting at transition of portal track. This shouldn't be reachable really.")
    train.speed = 0
    TunnelPortals.AddTransitionUsageDetectionEntityToPortal(portal)
    rendering.draw_text {
        text = "Unpowered trains can't use tunnels",
        surface = portal.tunnel.surface,
        target = portal.entrySignals[TunnelSignalDirection.inSignal].entity_position,
        time_to_live = 180,
        forces = {portal.force},
        color = {r = 1, g = 0, b = 0, a = 1},
        scale_with_zoom = true
    }
end

--- Will place the transition detection entity and should only be called when the train has been cloned and removed.
---@param portal Portal
TunnelPortals.AddTransitionUsageDetectionEntityToPortal = function(portal)
    if portal.tunnel == nil or not portal.isComplete or portal.transitionUsageDetectorEntity ~= nil then
        -- The portal has been removed, so we shouldn't add the detection entity back. Or another task has added the dector back and so we can stop.
        return
    end

    local transitionUsageDetectorEntity =
        portal.surface.create_entity {
        name = "railway_tunnel-portal_transition_train_detector_1x1",
        force = global.force.tunnelForce,
        position = portal.transitionUsageDetectorPosition
    }
    if transitionUsageDetectorEntity == nil then
        error("Failed to create Portal's transition usage train detection entity")
    end
    global.tunnelPortals.transitionUsageDetectorEntityIdToPortal[transitionUsageDetectorEntity.unit_number] = portal
    portal.transitionUsageDetectorEntity = transitionUsageDetectorEntity
end

---@param portal Portal
TunnelPortals.RemoveTransitionUsageDetectionEntityFromPortal = function(portal)
    if portal.transitionUsageDetectorEntity ~= nil then
        if portal.transitionUsageDetectorEntity.valid then
            global.tunnelPortals.transitionUsageDetectorEntityIdToPortal[portal.transitionUsageDetectorEntity.unit_number] = nil
            portal.transitionUsageDetectorEntity.destroy()
        end
        portal.transitionUsageDetectorEntity = nil
    end
end

return TunnelPortals
