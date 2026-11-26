# 09_figure.R ----
# Draws the three-panel figure from the summary tables in data/:
#   a  Level-1 threats to reef-building corals (UpSet plot)       data/threat_sets.csv, threat_combinations.csv
#   b  Range-weighted Red List Index by GCRMN region              data/rli_regions.csv
#   c  Share of cumulative CO2 and of reef area by country        data/country_shares.csv, map_units.csv
# Panel b also needs the reef grid (R/04_reef_grid.R) and both maps need the open map layers
# (R/01_download_open_data.R).
# Writes outputs/figure.pdf and outputs/figure.png (180 mm wide).

source("R/00_setup.R")
source("R/functions/basemap.R")
source("R/functions/placement.R")
source("R/functions/sparkline.R")

title_theme <- theme(plot.title = element_text(size = 9, face = "bold", margin = margin(0, 0, 3, 0)))

# a. Threats ----------------------------------------------------------------------------------------

threat_sets  <- read_csv(file.path(dir_data, "threat_sets.csv"), col_types = cols(code = "c"))
threat_combs <- read_csv(file.path(dir_data, "threat_combinations.csv"), show_col_types = FALSE)

# Percentages from the counts (the combinations add up to all 892 species), not the rounded columns
n_species    <- sum(threat_combs$n)
threat_sets  <- mutate(threat_sets, pct = 100 * n / n_species)
threat_combs <- mutate(threat_combs, pct = 100 * n / n_species)

# Short column heads and one colour per threat (red is kept for Critically Endangered)
threat_short <- c(`1` = "Residential & commercial", `4` = "Transport & corridors", `5` = "Biological resource use",
                  `6` = "Human disturbance", `8` = "Invasives & disease", `9` = "Pollution", `11` = "Climate change")
threat_col   <- c(`1` = "#e2c044", `4` = "#8c6d46", `5` = "#33708a", `6` = "#86b5d1",
                  `8` = "#5e9c4e", `9` = "#8e5a9e", `11` = "#e08a1e")

bar_mm <- 40      # height of the threat bars
row_mm <- 4.6     # height of one combination row

# White or dark text, whichever reads better on the bar colour
ink <- \(col) { m <- col2rgb(col) / 255; if_else(0.299 * m[1, ] + 0.587 * m[2, ] + 0.114 * m[3, ] > 0.62, "grey15", "white") }

panel_threats <- function(tag) {
  sz <- threat_sets %>%
    mutate(x = row_number(), name = str_wrap(threat_short[code], 12), inside = pct >= 15, ink = ink(threat_col[code]))
  nx <- nrow(sz); ny <- nrow(threat_combs)
  rows <- threat_combs %>% mutate(y = ny - row_number() + 1)               # most common combination on top
  dots <- rows %>%
    filter(combination != "none") %>%
    mutate(code = str_split(combination, fixed("|"))) %>%
    unnest(code) %>%
    left_join(select(sz, code, x), by = "code")
  links <- dots %>% group_by(y) %>% summarise(x0 = min(x), x1 = max(x), .groups = "drop")
  theme_up <- theme_void(base_size = 7) + theme(plot.margin = margin(0, 0, 0, 0))

  # Top: % of species affected by each threat
  bars <- ggplot(sz, aes(x, pct)) +
    geom_col(aes(fill = code), width = 0.78, colour = "grey25", linewidth = 0.2) +
    geom_text(data = filter(sz, inside), aes(y = pct - 3, label = sprintf("%.0f%%", pct)),
              vjust = 1, colour = filter(sz, inside)$ink, size = 2.4, fontface = "bold") +
    geom_text(data = filter(sz, !inside), aes(y = pct + 2, label = sprintf("%.1f%%", pct)), vjust = 0, size = 2.4) +
    geom_text(aes(y = pct + if_else(inside, 3, 9), label = name), vjust = 0, size = 2.1, lineheight = 0.9) +
    annotate("segment", x = 0.25, xend = 0.25, y = 0, yend = 100, linewidth = 0.25, colour = "grey40") +
    annotate("segment", x = 0.25, xend = 0.1, y = c(0, 50, 100), yend = c(0, 50, 100), linewidth = 0.25, colour = "grey40") +
    annotate("text", x = 0.05, y = c(0, 50, 100), label = c(0, 50, 100), hjust = 1, size = 2, colour = "grey30") +
    annotate("text", x = -0.9, y = 50, label = "Percent of species affected", angle = 90, size = 2.3, colour = "grey30") +
    scale_fill_manual(values = threat_col, guide = "none") +
    coord_cartesian(xlim = c(-1.2, nx + 0.5), ylim = c(0, 100), expand = FALSE, clip = "off") +
    labs(title = paste0(tag, "   Level 1 threats to reef-building corals")) +
    theme_up + theme(plot.title = element_text(size = 9, face = "bold", margin = margin(0, 0, 22, 0)))

  # Bottom: each row is one exact combination of threats (coloured circles joined by a line)
  matrix <- ggplot() +
    geom_point(data = expand_grid(x = seq_len(nx), y = seq_len(ny)), aes(x, y), colour = "grey80", size = 2) +
    geom_segment(data = links, aes(x = x0, xend = x1, y = y, yend = y), linewidth = 0.6, colour = "black") +
    geom_point(data = dots, aes(x, y, colour = code), size = 2) +
    annotate("segment", x = 0.25, xend = 0.25, y = 0.6, yend = ny + 0.4, linewidth = 0.3, colour = "grey50") +
    annotate("segment", x = 0.25, xend = 0.45, y = c(0.6, ny + 0.4), yend = c(0.6, ny + 0.4), linewidth = 0.3, colour = "grey50") +
    annotate("text", x = -0.3, y = (ny + 1) / 2, angle = 90, size = 2.1, colour = "grey30", lineheight = 0.9,
             label = "Combinations of threats\n(connecting lines & coloured circles)") +
    scale_colour_manual(values = threat_col, guide = "none") +
    coord_cartesian(xlim = c(-1.2, nx + 0.5), ylim = c(0.4, ny + 0.6), expand = FALSE, clip = "off") +
    theme_up

  # Right: number and % of species with each combination
  rows <- rows %>% mutate(lab = case_when(row_number() == 1 ~ sprintf("%d species, %.1f%%", n, pct),
                                          combination == "none" ~ sprintf("%d, %.1f%% (no threat coded)", n, pct),
                                          TRUE ~ sprintf("%d, %.1f%%", n, pct)))
  combo_bars <- ggplot(rows, aes(y = y)) +
    geom_rect(aes(xmin = 0, xmax = pct, ymin = y - 0.32, ymax = y + 0.32), fill = "grey95", colour = "grey40", linewidth = 0.2) +
    geom_text(aes(x = pct + 3, label = lab), hjust = 0, size = 2, colour = "grey25") +
    annotate("segment", x = 0, xend = 100, y = ny + 0.75, yend = ny + 0.75, linewidth = 0.25, colour = "grey40") +
    annotate("segment", x = c(0, 50, 100), xend = c(0, 50, 100), y = ny + 0.75, yend = ny + 0.95, linewidth = 0.25, colour = "grey40") +
    annotate("text", x = c(0, 50, 100), y = ny + 1.1, label = c(0, 50, 100), vjust = 0, size = 2, colour = "grey30") +
    annotate("text", x = 0, y = ny + 2, hjust = 0, vjust = 0, size = 2.3, colour = "grey30", lineheight = 0.9,
             label = "Number and percent of species with\nunique & combined threats") +
    coord_cartesian(xlim = c(0, 100), ylim = c(0.4, ny + 0.6), expand = FALSE, clip = "off") +
    theme_up + theme(plot.margin = margin(0, 32, 0, 6))

  (bars + plot_spacer() + matrix + combo_bars) +
    plot_layout(ncol = 2, widths = c(nx, 3.2), heights = unit(c(bar_mm, ny * row_mm), "mm"))
}

h_threats <- 22 + bar_mm + nrow(threat_combs) * row_mm

# b. Range-weighted RLI by GCRMN region ---------------------------------------------------------------

rli <- read_csv(file.path(dir_data, "rli_regions.csv"), show_col_types = FALSE) %>% filter(region != "Global")

rli_lim <- c(floor(min(c(rli$rli, rli$rli_w)) * 10) / 10, 1)
rli_col <- scales::col_numeric(viridisLite::viridis(256, direction = -1), domain = rli_lim)

# Colour key in the bottom-left corner of the map (fractions of the panel); boxes keep clear of it
key_npc  <- c(left = 0.005, right = 0.24, bottom = 0.005, top = 0.20)
keep_out <- tibble(xmin = xlim[1] + key_npc[["left"]] * diff(xlim),   xmax = xlim[1] + key_npc[["right"]] * diff(xlim),
                   ymin = ylim[1] + key_npc[["bottom"]] * diff(ylim), ymax = ylim[1] + key_npc[["top"]] * diff(ylim))

# Place the sparkline boxes; the three stacked over Africa share one left edge
left_column <- c("ROPME", "RSGA", "WIO")
boxes <- rli %>%
  filter(year == 2024) %>%
  transmute(unit = region, size = n, gw = spark_box_w, gh = spark_box_h) %>%
  place_glyphs(keep_out) %>%
  mutate(x = if_else(unit %in% left_column, min(x[unit %in% left_column]), x)) %>%
  left_join(targets, by = "unit")

panel_rli <- function(tag) {
  fill_2024 <- rli %>% filter(year == 2024) %>% select(unit = region, value = rli_w)
  p <- base_map(fill_2024) +
    scale_fill_viridis_c(direction = -1, limits = rli_lim, na.value = "#e8f1f6", name = "Range-weighted RLI (2024)",
                         guide = guide_colourbar(barheight = unit(2, "mm"), barwidth = unit(30, "mm"),
                                                 title.position = "top", direction = "horizontal")) +
    geom_segment(data = spark_leaders(boxes), aes(x = sx, y = sy, xend = tx, yend = ty),
                 colour = "grey20", linewidth = 0.25, inherit.aes = FALSE) +
    theme(legend.position        = "inside",
          legend.position.inside = c(key_npc[["left"]] + 0.005, key_npc[["bottom"]] + 0.01),
          legend.justification   = c(0, 0),
          legend.title           = element_text(size = 6),
          legend.text            = element_text(size = 5.5),
          legend.background      = element_rect(fill = "white", colour = NA),
          legend.margin          = margin(3, 5, 3, 5))
  p <- add_sparklines(p, boxes, rename(rli, unit = region), "rli_w", rli_col, rli_lim[1] - 0.04)
  wrap_elements(p) +
    labs(title = paste0(tag, "   Range-weighted Red List Index of reef-building corals by GCRMN region")) + title_theme
}

# c. CO2 and reef area by country -------------------------------------------------------------------

# 3 x 3 classes: CO2 share (< 0.1%, 0.1-1%, >= 1%) by reef share (none, < 1%, >= 1%)
biv_pal <- c("1-1" = "#e8e8e8", "2-1" = "#ace4e4", "3-1" = "#5ac8c8",
             "1-2" = "#dfb0d6", "2-2" = "#a5add3", "3-2" = "#5698b9",
             "1-3" = "#be64ac", "2-3" = "#8c62aa", "3-3" = "#3b4994")
small_km2 <- 30000    # reef-holding map units smaller than this are also drawn as dots

shares <- read_csv(file.path(dir_data, "country_shares.csv"), show_col_types = FALSE) %>%
  mutate(co2_class  = case_when(is.na(co2_share) ~ NA_integer_, co2_share < 0.1 ~ 1L, co2_share < 1 ~ 2L, TRUE ~ 3L),
         reef_class = case_when(reef_share <= 0 ~ 1L, reef_share < 1 ~ 2L, TRUE ~ 3L),
         biv        = if_else(is.na(co2_class), NA_character_, paste(reef_class, co2_class, sep = "-")))

sf_use_s2(FALSE)

# Each Natural Earth unit takes its sovereign's class
world <- st_read(file.path(dir_raw, "natural_earth", "ne_10m_admin_0_countries.shp"), quiet = TRUE) %>%
  transmute(iso3 = if_else(ISO_A3_EH == "-99", ADM0_A3, ISO_A3_EH)) %>%
  st_make_valid() %>%
  st_crop(xmin = -180, xmax = 180, ymin = -60, ymax = 85) %>%
  left_join(read_csv(file.path(dir_data, "map_units.csv"), show_col_types = FALSE), by = "iso3") %>%
  left_join(select(shares, sov_iso3 = iso3, biv), by = "sov_iso3")

world_proj <- world %>% st_break_antimeridian(lon_0 = map_lon0) %>% st_transform(map_crs)

# Small islands that hold reef themselves, drawn as a dot on their largest part
area_km2 <- \(g) as.numeric(st_area(st_transform(g, "+proj=eqearth"))) / 1e6
small <- world %>%
  mutate(area_km2 = area_km2(geometry)) %>%
  group_by(iso3, biv, unit_reef_share) %>%
  summarise(area_km2 = sum(area_km2), geometry = st_union(geometry), .groups = "drop") %>%
  filter(unit_reef_share > 0, area_km2 < small_km2, !is.na(biv)) %>%
  st_cast("POLYGON", warn = FALSE) %>%
  mutate(part_area = area_km2(geometry)) %>%
  group_by(iso3) %>%
  slice_max(part_area, n = 1, with_ties = FALSE) %>%
  ungroup() %>%
  st_point_on_surface() %>%
  st_transform(map_crs)

sf_use_s2(TRUE)

globe <- st_sfc(st_multipoint(rbind(c(map_lon0 - 179.9, 0), c(map_lon0 + 179.9, 0), c(map_lon0, -60), c(map_lon0, 85))),
                crs = 4326) %>% st_transform(map_crs) %>% st_coordinates()

biv_key <- ggplot(expand_grid(reef = 1:3, co2 = 1:3), aes(reef, co2, fill = paste(reef, co2, sep = "-"))) +
  geom_tile(colour = "white", linewidth = 0.4) +
  scale_fill_manual(values = biv_pal, guide = "none") +
  scale_x_continuous(breaks = 1:3, labels = c("none", "<1%", "≥1%"), expand = c(0, 0)) +
  scale_y_continuous(breaks = 1:3, labels = c("<0.1%", "0.1–1%", "≥1%"), expand = c(0, 0)) +
  labs(x = "Share of reef area →", y = "Share of CO₂ →") +
  coord_fixed() +
  theme_minimal(base_size = 5.5) +
  theme(panel.grid = element_blank(), axis.title = element_text(size = 5.5),
        plot.background = element_rect(fill = "white", colour = NA))

# Country borders: a hairline in the PDF; thinner in the 300 dpi PNG, where a hairline fills a whole pixel
panel_emissions <- function(tag, border_lw) {
  map <- ggplot() +
    geom_sf(data = filter(world_proj, !is.na(biv)), aes(fill = biv), colour = "white", linewidth = border_lw) +
    geom_sf(data = filter(world_proj, is.na(biv)), fill = "white", colour = "grey55", linewidth = 0.12) +
    geom_sf(data = small, aes(fill = biv), shape = 21, size = 1.4, colour = "grey25", stroke = 0.2) +
    scale_fill_manual(values = biv_pal, na.value = "white", guide = "none") +
    coord_sf(crs = map_crs, xlim = range(globe[1:2, 1]), ylim = range(globe[3:4, 2]), expand = FALSE, default_crs = NULL) +
    theme_void(base_size = 7) +
    theme(panel.background = element_rect(fill = "#f7fafb", colour = "grey60", linewidth = 0.3))
  map <- map + inset_element(biv_key, left = 0.005, right = 0.14, bottom = -0.03, top = 0.36, align_to = "panel")
  wrap_elements(map) +
    labs(title = paste0(tag, "   Share of cumulative CO₂ emissions and of warm-water reef area by country")) + title_theme
}

# Compose and save ------------------------------------------------------------------------------------

heights <- c(h_threats, 62 + 6, 82 + 6)     # mm
figure  <- \(border_lw) wrap_plots(list(wrap_elements(panel_threats("a")), panel_rli("b"), panel_emissions("c", border_lw)),
                                   ncol = 1, heights = heights)

ggsave(file.path(dir_out, "figure.pdf"), figure(0.08), width = 180, height = sum(heights) + 6, units = "mm", device = cairo_pdf)
ggsave(file.path(dir_out, "figure.png"), figure(0.03), width = 180, height = sum(heights) + 6, units = "mm", dpi = 300, bg = "white")
msg("saved ", file.path(dir_out, "figure.{pdf,png}"))
