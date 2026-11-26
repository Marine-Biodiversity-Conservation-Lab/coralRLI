# 06_rli.R ----
# Red List Index (Butchart et al. 2007) for the world and for each GCRMN region, pre-1998, 2008, 2024.
#
#   RLI   = 1 - sum(W_s) / (5 * N)                  W: LC 0, NT 1, VU 2, EN 3, CR 4, EX/EW 5
#   RLI_w = 1 - sum(W_s * p_s) / (5 * sum(p_s))     p_s = share of species s's reef range in the region
#
# RLI_w is the range-weighted (disaggregated) RLI of Rodrigues et al. (2014), shown in the figure: a
# species counts in a region in proportion to how much of its reef range lies there. Data Deficient
# species are left out (no back-cast), leaving 774 species.
# 95% confidence intervals: 1,000 bootstrap resamples of species; each resample scores all three years
# from the same draw of species.
# Writes data/rli_regions.csv (committed).

source("R/00_setup.R")

species <- read_csv(file.path(dir_work, "species.csv"), show_col_types = FALSE)

status <- species %>%
  filter(!is.na(cat_1998), !is.na(cat_2008), category != "DD") %>%
  transmute(sis_id, `1998` = cat_1998, `2008` = cat_2008, `2024` = category) %>%
  pivot_longer(-sis_id, names_to = "year", values_to = "cat") %>%
  mutate(year = as.integer(year), w = unname(rli_weight[cat]))

stopifnot("unknown category in RLI input" = !anyNA(status$w))
msg(n_distinct(status$sis_id), " species with categories in all three years")

# 1. RLI for one set of species ----

rli <- function(w, p = rep(1, length(w))) 1 - sum(w * p) / (5 * sum(p))

rli_unit <- function(d) {
  # d: one row per species x year with columns sis_id, year, w, p
  wide <- pivot_wider(d, id_cols = c(sis_id, p), names_from = year, values_from = w)
  w    <- as.matrix(wide[, as.character(rli_years)])
  n    <- nrow(w)
  boot <- replicate(n_boot, {
    i <- sample.int(n, n, replace = TRUE)
    c(apply(w[i, , drop = FALSE], 2, rli), apply(w[i, , drop = FALSE], 2, rli, p = wide$p[i]))
  })
  k <- length(rli_years)
  q <- \(rows, pr) apply(boot[rows, , drop = FALSE], 1, quantile, pr)
  tibble(year = rli_years, n = n,
         rli   = apply(w, 2, rli),            rli_lo   = q(1:k, 0.025),     rli_hi   = q(1:k, 0.975),
         rli_w = apply(w, 2, rli, p = wide$p), rli_w_lo = q(k + 1:k, 0.025), rli_w_hi = q(k + 1:k, 0.975))
}

# 2. World, then regions ----

set.seed(2026)

global <- status %>%
  mutate(p = 1) %>%
  rli_unit() %>%
  mutate(region = "Global", .before = 1)

regions <- read_csv(file.path(dir_work, "species_region.csv"), show_col_types = FALSE) %>%
  select(sis_id, region, p = prop_of_range) %>%
  inner_join(status, by = "sis_id", relationship = "many-to-many") %>%
  group_by(region) %>%
  group_modify(\(d, key) rli_unit(d)) %>%
  ungroup()

rli_all <- bind_rows(global, regions)

print(rli_all %>% select(region, year, n, rli_w) %>% pivot_wider(names_from = year, values_from = rli_w) %>%
        mutate(across(where(is.double), \(x) round(x, 2))), n = Inf)

write_csv(rli_all %>% mutate(across(starts_with("rli"), \(x) round(x, 4))), file.path(dir_data, "rli_regions.csv"))
