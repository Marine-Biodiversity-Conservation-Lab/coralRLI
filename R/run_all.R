# run_all.R ----
# Rebuilds everything from the raw downloads:  Rscript R/run_all.R
# Each script runs in its own R process, exactly as when run alone. Skip 01-05 to redraw the figure from
# the committed summary tables (see README, "Quick start").

scripts <- c("R/01_download_open_data.R",   # open data, no login (~300 MB)
             "R/02_species.R",              # needs the IUCN polygons and Obura et al. 2026 SI
             "R/03_redlist_threats.R",      # needs an IUCN API token; ~45 min the first time
             "R/04_reef_grid.R",
             "R/05_species_regions.R",      # ~8 min
             "R/06_rli.R",
             "R/07_threats.R",
             "R/08_countries.R",
             "R/09_figure.R")

for (s in scripts) {
  message("\n==== ", s, " ====")
  if (system2("Rscript", s) != 0) stop("failed: ", s)
}
