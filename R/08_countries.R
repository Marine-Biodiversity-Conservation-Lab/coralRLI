# 08_countries.R ----
# For each country: its share of the world's cumulative fossil and industry CO2 (to 2024) and its share
# of the world's warm-water reef area.
#   - Countries are sovereign states. Overseas territories' reefs and emissions count with their
#     sovereign (e.g. French Polynesia with France).
#   - Each reef cell belongs to the EEZ or land territory that contains it (Marine Regions EEZ v12
#     unioned with land).
#   - Reefs in disputed areas (overlapping claims, joint regimes) go to the state named in
#     data/disputed_allocation.csv, or stay unallocated (no emissions) where that column is blank.
#   - Emissions exclude land-use change (Global Carbon Budget 2025, via Our World in Data).
# Writes data/country_shares.csv (one row per sovereign state) and data/map_units.csv (one row per
# Natural Earth map unit, with its sovereign and its own reef share, used to draw small islands as dots).

source("R/00_setup.R")

disputed <- "DSP"     # code for the unallocated disputed-areas unit

# 1. Territory -> sovereign lookup ----

countries <- st_read(file.path(dir_raw, "natural_earth", "ne_10m_admin_0_countries.shp"), quiet = TRUE) %>%
  st_drop_geometry() %>%
  transmute(iso3 = if_else(ISO_A3_EH == "-99", ADM0_A3, ISO_A3_EH), name = NAME, admin = ADMIN,
            sov_a3 = SOV_A3, sovereign = SOVEREIGNT, type = TYPE)

eez <- st_read(file.path(dir_raw, "eez", "eez_land.shp"), quiet = TRUE) %>% mutate(eez_id = row_number())

# Natural Earth links each dependency to its sovereign; EEZ v12 overrides it where both give one.
# A few units are set by hand to the sovereign that EEZ v12 gives their waters.
by_hand <- tribble(~iso3, ~sov_iso3,
                   "IOT", "MUS",    # Chagos Archipelago
                   "GIB", "GBR",    # Gibraltar
                   "FLK", "GBR",    # Falkland Islands
                   "SOL", "SOM")    # Somaliland
ne_sov <- countries %>%
  left_join(countries %>% filter(admin == sovereign) %>% distinct(sov_a3, sov_iso3 = iso3), by = "sov_a3") %>%
  mutate(sov_iso3 = if_else(admin == sovereign | type %in% c("Disputed", "Indeterminate") | is.na(sov_iso3),
                            iso3, sov_iso3)) %>%
  distinct(iso3, sov_iso3)
eez_sov <- eez %>%
  st_drop_geometry() %>%
  filter(pol_type == "Union EEZ and country", !is.na(iso_ter1), iso_ter1 != iso_sov1) %>%
  distinct(iso3 = iso_ter1, sov_iso3 = iso_sov1)

sov_lut <- bind_rows(by_hand, eez_sov, ne_sov) %>% distinct(iso3, .keep_all = TRUE)   # first source wins
to_sov  <- \(x) coalesce(sov_lut$sov_iso3[match(x, sov_lut$iso3)], x)

# 2. Reef area by country ----

cells <- read_csv(file.path(dir_work, "reef_cells.csv"), show_col_types = FALSE)

sf_use_s2(FALSE)
hit <- st_intersects(st_as_sf(cells, coords = c("lon", "lat"), crs = 4326), st_make_valid(eez))
sf_use_s2(TRUE)

allocation <- read_csv(file.path(dir_data, "disputed_allocation.csv"), col_types = cols(.default = "c")) %>%
  filter(!is.na(allocate_to)) %>%
  select(eez_name, allocate_to)

cells <- cells %>%
  mutate(eez_id = map_int(hit, \(h) if (length(h) > 0) h[1] else NA_integer_)) %>%
  left_join(st_drop_geometry(eez) %>% select(eez_id, eez_name = union, pol_type, iso_ter1, iso_sov1), by = "eez_id") %>%
  left_join(allocation, by = "eez_name") %>%
  mutate(is_disputed = pol_type %in% c("Overlapping claim", "Joint regime (EEZ)"),
         sov  = case_when(is_disputed & !is.na(allocate_to) ~ to_sov(allocate_to),
                          is_disputed ~ disputed, TRUE ~ to_sov(iso_sov1)),
         unit = case_when(is_disputed & !is.na(allocate_to) ~ allocate_to, is_disputed ~ disputed,
                          eez_name == "Chagos Archipelago" ~ "IOT", TRUE ~ iso_ter1))

stopifnot("reef cells outside every EEZ-or-land polygon" = !anyNA(cells$sov))
msg(round(100 * sum(cells$area_km2[cells$sov == disputed]) / sum(cells$area_km2), 2),
    "% of reef area lies in unallocated disputed areas")

reef_share <- \(key) cells %>% group_by(iso3 = .data[[key]]) %>%
  summarise(reef_share = 100 * sum(area_km2) / sum(cells$area_km2), .groups = "drop")

# 3. Cumulative emissions ----
# Territories with their own series (e.g. New Caledonia) are added to their sovereign

emis <- read_csv(file.path(dir_raw, "owid", "owid-co2-data.csv"), show_col_types = FALSE) %>%
  filter(year == emis_year, !is.na(iso_code), !str_starts(iso_code, "OWID")) %>%
  group_by(iso3 = to_sov(iso_code)) %>%
  summarise(co2_share = if (all(is.na(share_global_cumulative_co2))) NA_real_ else sum(share_global_cumulative_co2, na.rm = TRUE),
            .groups = "drop")

# 4. Join and write ----

sov_names <- countries %>%
  filter(iso3 == to_sov(iso3)) %>%
  arrange(desc(admin == sovereign)) %>%
  distinct(iso3, .keep_all = TRUE) %>%
  select(iso3, name)

country_shares <- sov_names %>%
  bind_rows(tibble(iso3 = disputed, name = "Disputed areas (unallocated)")) %>%
  left_join(emis, by = "iso3") %>%
  left_join(reef_share("sov"), by = "iso3") %>%
  mutate(reef_share = coalesce(reef_share, 0)) %>%
  arrange(desc(reef_share))

stopifnot("reef area lost in the join" = abs(sum(country_shares$reef_share) - 100) < 1e-6)

map_units <- countries %>%
  distinct(iso3) %>%
  mutate(sov_iso3 = to_sov(iso3)) %>%
  left_join(reef_share("unit") %>% rename(unit_reef_share = reef_share), by = "iso3") %>%
  mutate(unit_reef_share = coalesce(unit_reef_share, 0))

with(filter(country_shares, co2_share > 0, reef_share > 0),
     msg("Spearman correlation, CO2 share vs reef share: ", round(cor(co2_share, reef_share, method = "spearman"), 2)))

write_csv(country_shares %>% mutate(reef_share = round(reef_share, 4)), file.path(dir_data, "country_shares.csv"))
write_csv(map_units %>% mutate(unit_reef_share = round(unit_reef_share, 4)), file.path(dir_data, "map_units.csv"))
