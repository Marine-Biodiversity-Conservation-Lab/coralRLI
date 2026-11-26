# basemap.R ----
# Base map for panel b: Pacific-centred Equal Earth land, GCRMN regions and reef cells, the plot window,
# and a leader-line target for each region. Requires 00_setup.R.

cells <- read_csv(need(file.path(dir_work, "reef_cells.csv"), "Run R/04_reef_grid.R"), show_col_types = FALSE)

to_map_xy <- function(d) {
  xy <- d %>%
    mutate(lon = ((lon + 180) %% 360) - 180) %>%
    st_as_sf(coords = c("lon", "lat"), crs = 4326) %>%
    st_transform(map_crs) %>%
    st_coordinates()
  d %>% mutate(x = xy[, 1], y = xy[, 2])
}

# 1. Layers ----

sf_use_s2(FALSE)

land <- st_read(file.path(dir_raw, "natural_earth", "ne_10m_land.shp"), quiet = TRUE) %>%
  st_crop(xmin = -180, xmax = 180, ymin = map_lat[1] - 15, ymax = map_lat[2] + 15) %>%
  st_break_antimeridian(lon_0 = map_lon0) %>%
  st_transform(map_crs)

load(file.path(dir_raw, "gcrmn", "gcrmn_regions.RData"))  # data_gcrmn_regions

# The source polygons are cut at 180°; each region is dissolved in map space so the Pacific has no
# seam (buffer out 20 km, union, buffer back in)
regions <- data_gcrmn_regions %>%
  st_make_valid() %>%
  st_break_antimeridian(lon_0 = map_lon0) %>%
  st_transform(map_crs) %>%
  st_buffer(2e4) %>%
  group_by(region) %>%
  summarise(.groups = "drop") %>%
  st_buffer(-2e4)

sf_use_s2(TRUE)

reef_pts <- cells %>% st_as_sf(coords = c("lon", "lat"), crs = 4326) %>% st_transform(map_crs)

# Plot window: the full longitude span at map_lon0, latitudes map_lat
lims <- to_map_xy(tibble(lon = c(map_lon0 - 179.9, map_lon0 + 179.9, map_lon0, map_lon0), lat = c(0, 0, map_lat)))
xlim <- range(lims$x[1:2])
ylim <- range(lims$y[3:4])

# 2. Leader-line targets ----
# The reef-area-weighted centre of each region; the Pacific uses the centre of its polygon instead,
# because its reef area is concentrated in Papua New Guinea, which pulls the weighted centre far west.

targets <- cells %>%
  mutate(lon = shift_lon(lon)) %>%
  group_by(unit = region) %>%
  summarise(lon = weighted.mean(lon, area_km2), lat = weighted.mean(lat, area_km2), .groups = "drop") %>%
  to_map_xy() %>%
  select(unit, tx = x, ty = y)

sf_use_s2(FALSE)
pacific <- st_coordinates(st_centroid(st_geometry(filter(regions, region == "Pacific"))))
sf_use_s2(TRUE)
targets <- rows_update(targets, tibble(unit = "Pacific", tx = pacific[, 1], ty = pacific[, 2]), by = "unit")

# 3. Map ----
# region_fill: tibble(unit, value) used to shade the regions (add a fill scale)

base_map <- function(region_fill) {
  ggplot() +
    geom_sf(data = left_join(regions, region_fill, by = c("region" = "unit")), aes(fill = value),
            colour = "#9bb8c9", linewidth = 0.25) +
    geom_sf(data = land, fill = "#d9d9d6", colour = NA) +
    geom_sf(data = reef_pts, colour = "#1f4e5f", size = 0.15) +
    coord_sf(crs = map_crs, xlim = xlim, ylim = ylim, expand = FALSE, default_crs = NULL) +
    theme_void(base_size = 7) +
    theme(panel.background = element_rect(fill = "white", colour = "grey40", linewidth = 0.3),
          legend.position  = "bottom",
          legend.key.size  = unit(3, "mm"),
          plot.margin      = margin(4, 4, 4, 4))
}
