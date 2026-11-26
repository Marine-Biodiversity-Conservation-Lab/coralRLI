# 02_species.R ----
# Species table for the 892 reef-building corals: 2024 Red List category from the IUCN range
# polygons, plus the back-cast pre-1998 and 2008 categories and the ocean realm from Obura et al.
# (2026) Supplementary Dataset 1. Only attribute tables are read here; 05_species_regions.R reads the
# polygons themselves.
# Writes data/work/species.csv and data/work/range_index.csv (species-level; not committed).

source("R/00_setup.R")

# 1. IUCN range polygons ----

if (length(list.files(dir_iucn, pattern = "\\.shp$")) == 0) {
  need(path_iucn_zip, "Download the reef-building coral range polygons from the IUCN Red List (README, step 2).")
  unzip(path_iucn_zip, exdir = dir_iucn)
}

shp_files <- list.files(dir_iucn, pattern = "\\.shp$", full.names = TRUE)   # the download comes in parts

attrs <- map_dfr(shp_files, \(f) foreign::read.dbf(sub("\\.shp$", ".dbf", f), as.is = TRUE) %>%
                   rename_with(tolower) %>%
                   mutate(shp_file = f, shp_row = row_number()))

# Keep extant or probably extant (presence 1-2), native or reintroduced (origin 1-2) parts
polys <- attrs %>%
  mutate(sis_id = as.integer(id_no)) %>%
  filter(presence %in% c(1, 2), origin %in% c(1, 2))

msg(nrow(polys), " range polygons for ", n_distinct(polys$sis_id), " species")

write_csv(select(polys, sis_id, shp_file, shp_row), file.path(dir_work, "range_index.csv"))

species <- polys %>%
  group_by(sis_id) %>%
  summarise(scientific_name = str_squish(first(sci_name)),
            category        = as_iucn_code(first(category)),
            .groups         = "drop")

# 2. Back-cast categories (Obura et al. 2026, Supplementary Dataset 1) ----
# The authors re-assessed every species for pre-1998 and 2008 with the 2024 methods and knowledge, so
# changes between years are genuine changes in status, as the Red List Index requires.

path_si <- need(file.path(dir_obura, "41586_2026_11263_MOESM3_ESM.xlsx"),
                "Download Supplementary Dataset 1 of Obura et al. 2026 (README, step 3).")

first_code <- \(x) str_extract(str_trim(x), "^(CR|EN|VU|NT|LC|DD|EX|EW)")

si <- readxl::read_excel(path_si, sheet = "Supplementary Dataset 1 ") %>%
  transmute(name      = str_squish(`Species Name`),
            name_2008 = str_squish(`(2008) Species Name`),
            cat_2008  = first_code(`RLI (2008)`),
            cat_1998  = first_code(`RLI (pre-1998)`),
            realm     = Realm)

# Match on the current name, else on the 2008 name
si <- si %>%
  mutate(name = if_else(name %in% species$scientific_name, name, name_2008)) %>%
  select(-name_2008)

species <- left_join(species, si, by = c("scientific_name" = "name"))

msg("back-cast categories matched for ", sum(!is.na(species$cat_2008)), " of ", nrow(species), " species")

write_csv(species, file.path(dir_work, "species.csv"))
print(count(species, category))
