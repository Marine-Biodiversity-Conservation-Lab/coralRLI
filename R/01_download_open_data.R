# 01_download_open_data.R ----
# Downloads every input that needs no login (about 300 MB), pinned to the versions used for the figure:
#   - GCRMN regions and ecoregions               github.com/GCRMN/gcrmn_regions, commit e435ab4
#   - UNEP-WCMC warm-water coral reefs v4.1      WCMC-008
#   - Natural Earth 1:10m land and countries
#   - Marine Regions EEZ v12 unioned with land   (only needed by 07_countries.R)
#   - Global Carbon Budget 2025 via Our World in Data, commit 382ee6c (only needed by 07_countries.R)
# Files already present are not downloaded again.

source("R/00_setup.R")

options(timeout = 3600)

get <- function(url, dest, unzip_to = NULL) {
  dir.create(dirname(dest), recursive = TRUE, showWarnings = FALSE)
  if (file.exists(dest) && file.size(dest) > 0) {
    msg("already have ", dest)
  } else {
    msg("downloading ", url)
    download.file(url, dest, mode = "wb", quiet = TRUE)
  }
  if (!is.null(unzip_to)) {                       # extract only if something is missing
    inside <- unzip(dest, list = TRUE)$Name
    if (!all(file.exists(file.path(unzip_to, inside)))) unzip(dest, exdir = unzip_to)
  }
  invisible(dest)
}

# 1. GCRMN regions and ecoregions ----

gcrmn <- "https://raw.githubusercontent.com/GCRMN/gcrmn_regions/e435ab4043b6bf4dfd01362460faf5d46f4afc79/data/gcrmn-regions"
for (f in c("gcrmn_regions", "gcrmn_ecoregions")) {
  get(file.path(gcrmn, paste0(f, ".RData")), file.path(dir_raw, "gcrmn", paste0(f, ".RData")))
}

# 2. UNEP-WCMC warm-water coral reefs v4.1 ----

get("https://datadownload-production.s3.amazonaws.com/WCMC008_CoralReefs2021_v4_1.zip",
    file.path(dir_raw, "wcmc_reefs", "WCMC008_CoralReefs2021_v4_1.zip"),
    unzip_to = file.path(dir_raw, "wcmc_reefs"))

# 3. Natural Earth 1:10m land and countries ----

get("https://naciscdn.org/naturalearth/10m/physical/ne_10m_land.zip",
    file.path(dir_raw, "natural_earth", "ne_10m_land.zip"), unzip_to = file.path(dir_raw, "natural_earth"))
get("https://naciscdn.org/naturalearth/10m/cultural/ne_10m_admin_0_countries.zip",
    file.path(dir_raw, "natural_earth", "ne_10m_admin_0_countries.zip"), unzip_to = file.path(dir_raw, "natural_earth"))

# 4. Marine Regions EEZ v12 unioned with land ----
# The land union also catches reef cells landward of the EEZ baseline (lagoons, reef flats)

get(paste0("https://geo.vliz.be/geoserver/MarineRegions/wfs?service=WFS&version=1.0.0",
           "&request=GetFeature&typeName=MarineRegions:eez_land&outputFormat=SHAPE-ZIP"),
    file.path(dir_raw, "eez", "eez_land_v12.zip"), unzip_to = file.path(dir_raw, "eez"))

# 5. Cumulative CO2 (Global Carbon Budget 2025, via Our World in Data) ----
# Pinned to the last commit before the Global Carbon Budget 2026 update (10 Nov 2026)

get("https://raw.githubusercontent.com/owid/co2-data/382ee6c662b0ece26e111f263b44c029afad7787/owid-co2-data.csv",
    file.path(dir_raw, "owid", "owid-co2-data.csv"))

msg("open data ready in ", dir_raw)
