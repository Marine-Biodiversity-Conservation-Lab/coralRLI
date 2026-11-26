# 00_setup.R ----
# Packages, folders and settings shared by every script. Each script sources this file first.
# Run all scripts from the repository root.

suppressPackageStartupMessages({
  library(sf)
  library(terra)
  library(dplyr)
  library(tidyr)
  library(readr)
  library(stringr)
  library(purrr)
  library(ggplot2)
  library(patchwork)
})

# 1. Folders ----

dir_data <- "data"                        # committed summary tables (what the figure is drawn from)
dir_raw  <- file.path("data", "raw")      # downloaded inputs (not committed)
dir_work <- file.path("data", "work")     # intermediate tables (not committed; some are species-level)
dir_out  <- "outputs"

for (d in c(dir_raw, dir_work, dir_out)) dir.create(d, recursive = TRUE, showWarnings = FALSE)

# Inputs you download by hand (see README, "Data")
path_iucn_zip <- file.path(dir_raw, "iucn", "REEF_FORMING_CORALS.zip")    # IUCN range polygons
dir_iucn      <- file.path(dir_raw, "iucn", "REEF_FORMING_CORALS")
dir_obura     <- file.path(dir_raw, "obura2026")                          # Obura et al. 2026 supplementary data

# 2. Settings ----

grid_res  <- 0.05                 # reef grid resolution, degrees (about 5.5 km at the equator)
grid_ext  <- c(-180, 180, -50, 50)

rli_years  <- c(1998, 2008, 2024) # 1998 stands for "pre-1998"
rli_weight <- c(LC = 0, NT = 1, VU = 2, EN = 3, CR = 4, EW = 5, EX = 5)
n_boot     <- 1000                # bootstrap resamples for the RLI confidence intervals

emis_year <- 2024                 # cumulative CO2 up to and including this year

# Map: Equal Earth (equal-area) centred on 150°E, so the Indo-Pacific is not split
map_lon0 <- 150
map_crs  <- paste0("+proj=eqearth +lon_0=", map_lon0, " +datum=WGS84 +units=m +no_defs")
map_lat  <- c(-42, 42)

# 3. IUCN categories ----

iucn_levels <- c("EX", "EW", "CR", "EN", "VU", "NT", "LC", "DD")
threatened  <- c("CR", "EN", "VU")

iucn_lookup <- c("Extinct" = "EX", "Extinct in the Wild" = "EW",
                 "Critically Endangered" = "CR", "Endangered" = "EN", "Vulnerable" = "VU",
                 "Near Threatened" = "NT", "Least Concern" = "LC", "Data Deficient" = "DD")

as_iucn_code <- function(x) {
  x   <- str_trim(as.character(x))
  out <- unname(iucn_lookup[x])
  out[is.na(out) & x %in% iucn_levels] <- x[is.na(out) & x %in% iucn_levels]
  out
}

# 4. Helpers ----

# Shift longitudes into the window centred on map_lon0
shift_lon <- function(lon, lon0 = map_lon0) ((lon - (lon0 - 180)) %% 360) + (lon0 - 180)

msg <- function(...) message(format(Sys.time(), "%H:%M:%S"), " | ", ...)

# Stop with a pointer to the README when an input is missing
need <- function(path, how) {
  if (!file.exists(path)) stop("missing ", path, "\n  ", how, call. = FALSE)
  invisible(path)
}
