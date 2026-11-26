# 05_species_regions.R ----
# Where each species occurs on reef: every range polygon is rasterised onto the reef grid, and only the
# cells that are also reef cells are kept. This "reef mask" matters because the IUCN ranges are drawn
# as a coastal buffer (100 km offshore, 200 m deep), not as reef. The reef area of each species is then
# summed by GCRMN region. About 8 minutes.
# Writes data/work/species_region.csv (species-level; not committed).

source("R/00_setup.R")

range_index <- read_csv(file.path(dir_work, "range_index.csv"), show_col_types = FALSE)
cells       <- read_csv(file.path(dir_work, "reef_cells.csv"), show_col_types = FALSE)
species     <- read_csv(file.path(dir_work, "species.csv"), show_col_types = FALSE)
template    <- rast(ext(grid_ext), resolution = grid_res, crs = "EPSG:4326")

# Row of the reef cell table for each grid cell (0 = not reef)
cell_row <- integer(ncell(template))
cell_row[cells$cell] <- seq_len(nrow(cells))

# 1. Grid cells touched by one range polygon ----
# Rasterising with terra avoids repairing the polygons' invalid rings, which is impractically slow

range_cells <- function(v) {
  e <- terra::intersect(ext(v), ext(template))
  if (is.null(e)) return(integer(0))
  sub <- crop(template, e, snap = "out")
  r   <- rasterize(v, sub, field = 1, touches = TRUE, background = NA)
  cellFromXY(template, xyFromCell(sub, which(!is.na(values(r, mat = FALSE)))))
}

hits <- list()
for (f in unique(range_index$shp_file)) {
  msg("reading ", basename(f))
  v    <- vect(f)
  rows <- filter(range_index, shp_file == f)
  for (j in seq_len(nrow(rows))) {
    hits[[length(hits) + 1]] <- tibble(sis_id = rows$sis_id[j], cell = range_cells(v[rows$shp_row[j]]))
  }
  rm(v); gc(verbose = FALSE)
}

# 2. Reef area of each species by region ----

species_reef <- bind_rows(hits) %>%
  distinct() %>%                                   # a species' polygons may overlap
  mutate(row = cell_row[cell]) %>%
  filter(row > 0) %>%                              # reef cells only
  mutate(region = cells$region[row], area_km2 = cells$area_km2[row])

no_reef <- setdiff(species$sis_id, species_reef$sis_id)
msg(length(no_reef), " species touch no reef cell and are left out of the regional results")

# Ocean-basin rule: Atlantic species count only in the Caribbean and Brazil, Indo-Pacific species only
# elsewhere. Rasterising with touches = TRUE can otherwise carry a range across a narrow isthmus
# (e.g. a Pacific range touching a Caribbean reef cell at Panama).
atlantic_regions <- c("Caribbean", "Brazil")

species_region <- species_reef %>%
  left_join(select(species, sis_id, realm), by = "sis_id") %>%
  filter(is.na(realm) | (realm == "Atlantic") == (region %in% atlantic_regions)) %>%
  group_by(sis_id, region) %>%
  summarise(reef_km2 = sum(area_km2), .groups = "drop_last") %>%
  mutate(prop_of_range = reef_km2 / sum(reef_km2)) %>%     # share of the species' reef range in the region
  ungroup()

msg(n_distinct(species_region$sis_id), " species placed in GCRMN regions")
write_csv(species_region, file.path(dir_work, "species_region.csv"))
