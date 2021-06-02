--local Events = require("utility/events")
--local Interfaces = require("utility/interfaces")
local Utils = require("utility/utils")
local TunnelCommon = {}

-- Make the entity lists.
TunnelCommon.tunnelSegmentPlacedEntityNames, TunnelCommon.tunnelSegmentPlacementEntityNames, TunnelCommon.tunnelPortalPlacedEntityNames, TunnelCommon.tunnelPortalPlacementEntityNames = {}, {}, {}, {}
for _, coreName in pairs({"railway_tunnel-tunnel_segment_surface", "railway_tunnel-tunnel_segment_surface_rail_crossing"}) do
    TunnelCommon.tunnelSegmentPlacedEntityNames[coreName .. "-placed"] = coreName .. "-placed"
    TunnelCommon.tunnelSegmentPlacementEntityNames[coreName .. "-placement"] = coreName .. "-placement"
end
TunnelCommon.tunnelSegmentPlacedPlacementEntityNames = Utils.TableMerge({TunnelCommon.tunnelSegmentPlacedEntityNames, TunnelCommon.tunnelSegmentPlacementEntityNames})
for _, coreName in pairs({"railway_tunnel-tunnel_portal_surface"}) do
    TunnelCommon.tunnelPortalPlacedEntityNames[coreName .. "-placed"] = coreName .. "-placed"
    TunnelCommon.tunnelPortalPlacementEntityNames[coreName .. "-placement"] = coreName .. "-placement"
end
TunnelCommon.tunnelPortalPlacedPlacementEntityNames = Utils.TableMerge({TunnelCommon.tunnelPortalPlacedEntityNames, TunnelCommon.tunnelPortalPlacementEntityNames})
TunnelCommon.tunnelSegmentAndPortalPlacedEntityNames = Utils.TableMerge({TunnelCommon.tunnelSegmentPlacedEntityNames, TunnelCommon.tunnelPortalPlacedEntityNames})
TunnelCommon.tunnelSegmentAndPortalPlacedPlacementEntityNames = Utils.TableMerge({TunnelCommon.tunnelSegmentPlacedEntityNames, TunnelCommon.tunnelSegmentPlacementEntityNames, TunnelCommon.tunnelPortalPlacedEntityNames, TunnelCommon.tunnelPortalPlacementEntityNames})

TunnelCommon.CheckTunnelPartsInDirection = function(startingTunnelPart, startingTunnelPartPoint, tunnelPortals, tunnelSegments, checkingDirection, placer)
    local orientation = Utils.DirectionToOrientation(checkingDirection)
    local continueChecking = true
    local nextCheckingPos = startingTunnelPartPoint
    while continueChecking do
        nextCheckingPos = Utils.ApplyOffsetToPosition(nextCheckingPos, Utils.RotatePositionAround0(orientation, {x = 0, y = 2}))
        local connectedTunnelEntities = startingTunnelPart.surface.find_entities_filtered {position = nextCheckingPos, name = TunnelCommon.tunnelSegmentAndPortalPlacedEntityNames, force = startingTunnelPart.force, limit = 1}
        if #connectedTunnelEntities == 0 then
            continueChecking = false
        else
            local connectedTunnelEntity = connectedTunnelEntities[1]
            if connectedTunnelEntity.position.x ~= startingTunnelPart.position.x and connectedTunnelEntity.position.y ~= startingTunnelPart.position.y then
                TunnelCommon.EntityErrorMessage(placer, "Tunnel parts must be in a straight line", connectedTunnelEntity.surface, connectedTunnelEntity.position)
                continueChecking = false
            elseif TunnelCommon.tunnelSegmentPlacedEntityNames[connectedTunnelEntity.name] then
                if connectedTunnelEntity.direction == startingTunnelPart.direction or connectedTunnelEntity.direction == Utils.LoopDirectionValue(startingTunnelPart.direction + 4) then
                    table.insert(tunnelSegments, connectedTunnelEntity)
                else
                    TunnelCommon.EntityErrorMessage(placer, "Tunnel segments must be in the same direction; horizontal or vertical", connectedTunnelEntity.surface, connectedTunnelEntity.position)
                    continueChecking = false
                end
            elseif TunnelCommon.tunnelPortalPlacedEntityNames[connectedTunnelEntity.name] then
                continueChecking = false
                if connectedTunnelEntity.direction == Utils.LoopDirectionValue(checkingDirection + 4) then
                    table.insert(tunnelPortals, connectedTunnelEntity)
                    return true
                else
                    TunnelCommon.EntityErrorMessage(placer, "Tunnel portal facing wrong direction", connectedTunnelEntity.surface, connectedTunnelEntity.position)
                end
            else
                error("unhandled railway_tunnel entity type")
            end
        end
    end
    return false
end

TunnelCommon.UndoInvalidPlacement = function(placementEntity, placer, mine)
    if placer ~= nil then
        TunnelCommon.EntityErrorMessage(placer, "Tunnel must be placed on the rail grid", placementEntity.surface, placementEntity.position)
        if mine then
            local result
            if placer.is_player() then
                result = placer.mine_entity(placementEntity, true)
            else
                -- Is construction bot
                result = placementEntity.mine({inventory = placer.get_inventory(defines.inventory.robot_cargo), force = true, raise_destroyed = false, ignore_minable = true})
            end
            if result ~= true then
                error("couldn't mine invalidly placed tunnel entity")
            end
        else
            placementEntity.destroy()
        end
    end
end

TunnelCommon.EntityErrorMessage = function(entityDoingInteraction, text, surface, position)
    local textAudience = Utils.GetRenderPlayersForcesFromActioner(entityDoingInteraction)
    rendering.draw_text {text = text, surface = surface, target = position, time_to_live = 180, players = textAudience.players, forces = textAudience.forces, color = {r = 1, g = 0, b = 0, a = 1}, scale_with_zoom = true}
end

TunnelCommon.DestroyCarriagesOnRailEntityList = function(railEntityList, killForce, killerCauseEntity)
    if Utils.IsTableEmpty(railEntityList) then
        return
    end
    local refEntity, railEntityCollisionBoxList = Utils.GetFirstTableValue(railEntityList), {}
    for _, railEntity in pairs(railEntityList) do
        if railEntity.valid then
            table.insert(railEntityCollisionBoxList, railEntity.bounding_box) -- Only supports straight track by design.
        end
    end
    local searchArea = Utils.CalculateBoundingBoxToIncludeAllBoundingBoxs(railEntityCollisionBoxList)
    local carriagesFound = refEntity.surface.find_entities_filtered {area = searchArea, type = {"locomotive", "cargo-wagon", "fluid-wagon", "artillery-wagon"}}
    for _, carriage in pairs(carriagesFound) do
        Utils.EntityDie(carriage, killForce, killerCauseEntity)
    end
end

return TunnelCommon
