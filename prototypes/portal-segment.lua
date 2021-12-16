local Utils = require("utility/utils")

--[[
    The entities shouldn't appear twice in any player list. Placements shouldn't appear in decon planner lists. As the placed is always the selected entity by the player.
]]
local portalSegmentStraightPlacement = {
    type = "simple-entity-with-owner",
    name = "railway_tunnel-portal_segment-straight-placement",
    icon = "__railway_tunnel__/graphics/icon/portal_segment-straight/railway_tunnel-portal_segment-straight-placement.png",
    icon_size = 32,
    localised_name = {"item-name.railway_tunnel-portal_segment-straight-placement"},
    localised_description = {"item-description.railway_tunnel-portal_segment-straight-placement"},
    collision_box = {{-2.9, -0.9}, {2.9, 0.9}},
    collision_mask = {"item-layer", "object-layer", "player-layer", "water-tile"},
    max_health = 1000,
    resistances = {
        {
            type = "fire",
            percent = 100
        },
        {
            type = "acid",
            percent = 100
        }
    },
    flags = {"player-creation", "not-on-map", "not-deconstructable"},
    picture = {
        north = {
            filename = "__railway_tunnel__/graphics/entity/portal_segment-straight/portal_segment-straight-placement-northsouth.png",
            height = 64,
            width = 192
        },
        east = {
            filename = "__railway_tunnel__/graphics/entity/portal_segment-straight/portal_segment-straight-placement-eastwest.png",
            height = 192,
            width = 64
        },
        south = {
            filename = "__railway_tunnel__/graphics/entity/portal_segment-straight/portal_segment-straight-placement-northsouth.png",
            height = 64,
            width = 192
        },
        west = {
            filename = "__railway_tunnel__/graphics/entity/portal_segment-straight/portal_segment-straight-placement-eastwest.png",
            height = 192,
            width = 64
        }
    },
    minable = {
        mining_time = 0.5,
        result = "railway_tunnel-portal_segment-straight-placement",
        count = 1
    },
    placeable_by = {
        item = "railway_tunnel-portal_segment-straight-placement",
        count = 1
    }
}

local portalSegmentPlaced = Utils.DeepCopy(portalSegmentStraightPlacement)
portalSegmentPlaced.name = "railway_tunnel-portal_segment-straight-placed"
portalSegmentPlaced.flags = {"player-creation", "not-on-map"}
portalSegmentPlaced.render_layer = "ground-tile"
portalSegmentPlaced.selection_box = portalSegmentPlaced.collision_box
portalSegmentPlaced.corpse = "railway_tunnel-portal_segment-straight-remnant"

local portalSegmentRemnant = {
    type = "corpse",
    name = "railway_tunnel-portal_segment-straight-remnant",
    icon = portalSegmentStraightPlacement.icon,
    icon_size = portalSegmentStraightPlacement.icon_size,
    icon_mipmaps = portalSegmentStraightPlacement.icon_mipmaps,
    flags = {"placeable-neutral", "not-on-map"},
    subgroup = "remnants",
    order = "d[remnants]-b[rail]-z[portal]",
    selection_box = portalSegmentStraightPlacement.selection_box,
    selectable_in_game = false,
    time_before_removed = 60 * 60 * 15, -- 15 minutes
    final_render_layer = "remnants",
    remove_on_tile_placement = false,
    animation = {
        filename = "__railway_tunnel__/graphics/entity/portal_segment-straight/portal_segment-straight-remnant.png",
        line_length = 1,
        width = 192,
        height = 192,
        frame_count = 1,
        direction_count = 2
    }
}

local portalSegmentStraightPlacementItem = {
    type = "item",
    name = "railway_tunnel-portal_segment-straight-placement",
    icon = "__railway_tunnel__/graphics/icon/portal_segment-straight/railway_tunnel-portal_segment-straight-placement.png",
    icon_size = 32,
    subgroup = "train-transport",
    order = "a[train-system]-a[rail]a",
    stack_size = 10,
    place_result = "railway_tunnel-portal_segment-straight-placement"
}

data:extend(
    {
        portalSegmentStraightPlacement,
        portalSegmentPlaced,
        portalSegmentRemnant,
        portalSegmentStraightPlacementItem
    }
)
