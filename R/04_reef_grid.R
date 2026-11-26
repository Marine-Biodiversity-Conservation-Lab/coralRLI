# 04_reef_grid.R ----
# Global 0.05° grid of reef cells: every cell touched by a UNEP-WCMC v4.1 reef polygon or point.
# Each reef cell is assigned to the GCRMN ecoregion (and so region) it falls in; cells just outside
# the GCRMN polygons join the nearest ecoregion. Takes a few minutes.
# Writes data/work/reef_cells.csv.

source("R/00_setup.R")

template <- rast(ext(grid_ext), resolution = grid_res, crs = "EPSG:4326")

# 1. Rasterise the reefs ----

wcmc <- list.files(file.path(dir_raw, "wcmc_reefs"), pattern = "\\.shp$", recursive = TRUE, full.names = TRUE)
wcmc_py <- wcmc[str_detect(basename(wcmc), "_Py_")]
wcmc_pt <- wcmc[str_detect(basename(wcmc), "_Pt_")]
if (length(wcmc_py) != 1) stop("UNEP-WCMC reef polygons not found; run R/01_download_open_data.R", call. = FALSE)

reef <- rasterize(vect(wcmc_py), template, field = 1, touches = TRUE, background = NA) %>%
  cover(rasterize(vect(wcmc_pt), template, field = 1, background = NA))

reef_cells <- which(!is.na(values(reef, mat = FALSE)))
xy <- xyFromCell(template, reef_cells)

cells <- tibble(cell     = reef_cells,
                lon      = xy[, 1],
                lat      = xy[, 2],
                area_km2 = cellSize(template, unit = "km")[reef_cells][, 1])

msg(nrow(cells), " reef cells")

# 2. Assign GCRMN ecoregions ----

load(need(file.path(dir_raw, "gcrmn", "gcrmn_ecoregions.RData"), "Run R/01_download_open_data.R"))
eco <- data_gcrmn_ecoregions %>% st_make_valid() %>% mutate(eco_id = row_number())

cells$eco_id <- rasterize(vect(eco), template, field = "eco_id", touches = TRUE)[cells$cell][, 1]

# Reef cells outside every GCRMN polygon (the polygons follow EEZ and MEOW lines, so some coastal reef
# falls just outside) join the nearest ecoregion
out <- which(is.na(cells$eco_id))
msg(length(out), " reef cells outside the GCRMN polygons join the nearest ecoregion")
cells$eco_id[out] <- eco$eco_id[st_nearest_feature(st_as_sf(cells[out, ], coords = c("lon", "lat"), crs = 4326), eco)]

cells <- cells %>%
  left_join(st_drop_geometry(eco) %>% select(eco_id, region, ecoregion), by = "eco_id") %>%
  select(-eco_id)

print(cells %>% group_by(region) %>% summarise(cells = n(), reef_km2 = round(sum(area_km2))), n = Inf)

write_csv(cells, file.path(dir_work, "reef_cells.csv"))
