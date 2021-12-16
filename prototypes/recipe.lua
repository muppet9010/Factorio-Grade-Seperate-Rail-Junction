data:extend(
    {
        {
            type = "recipe",
            name = "railway_tunnel-portal_end",
            enabled = false,
            ingredients = {
                {"concrete", 30},
                {"steel-plate", 30},
                {"rail", 3},
                {"rail-signal", 2}
            },
            result = "railway_tunnel-portal_end-placement",
            result_count = 1
        },
        {
            type = "recipe",
            name = "railway_tunnel-portal_segment-straight",
            enabled = false,
            ingredients = {
                {"concrete", 10},
                {"steel-plate", 10},
                {"rail", 1}
            },
            result = "railway_tunnel-portal_segment-straight-placement",
            result_count = 1
        },
        {
            type = "recipe",
            name = "railway_tunnel-underground_segment-straight",
            enabled = false,
            ingredients = {
                {"concrete", 10},
                {"steel-plate", 10},
                {"rail", 1},
                {"landfill", 1}
            },
            result = "railway_tunnel-underground_segment-straight-placement",
            result_count = 1
        },
        {
            type = "recipe",
            name = "railway_tunnel-underground_segment-straight-rail_crossing",
            enabled = false,
            ingredients = {
                {"concrete", 10},
                {"rail", 3},
                {"railway_tunnel-underground_segment-straight-placement", 1}
            },
            result = "railway_tunnel-underground_segment-straight-rail_crossing-placement",
            result_count = 1
        }
    }
)
