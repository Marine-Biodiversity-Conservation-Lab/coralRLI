# 07_threats.R ----
# Level-1 threats (IUCN Threats Classification Scheme v3.3) coded for each of the 892 species:
#   - the share of species affected by each threat
#   - the exact combinations of threats, and how many species have each one
# Every coded threat counts, whatever its timing, scope or severity (almost all are "Ongoing, Low
# Impact"). Species with no threat coded form their own row.
# Writes data/threat_sets.csv and data/threat_combinations.csv (committed).

source("R/00_setup.R")

l1_names <- c(`1` = "Residential & commercial development", `2` = "Agriculture & aquaculture",
              `4` = "Transportation & service corridors", `5` = "Biological resource use",
              `6` = "Human intrusions & disturbance", `8` = "Invasive & other problematic species, genes & diseases",
              `9` = "Pollution", `11` = "Climate change & severe weather")

species <- read_csv(file.path(dir_work, "species.csv"), show_col_types = FALSE)
n_spp   <- nrow(species)

# Level-1 code is the part before the first underscore: "11_3" -> "11"
sets <- read_csv(file.path(dir_work, "threats.csv"), col_types = cols(.default = "c", sis_id = "i")) %>%
  filter(sis_id %in% species$sis_id) %>%
  distinct(sis_id, code = str_extract(code, "^[0-9]+"))

stopifnot("threat code not in l1_names" = all(sets$code %in% names(l1_names)))
scheme <- names(l1_names)[names(l1_names) %in% sets$code]       # scheme order

# 1. Share of species affected by each threat ----

threat_sets <- sets %>%
  count(code, name = "n") %>%
  mutate(threat = l1_names[code], pct = round(100 * n / n_spp, 2)) %>%
  arrange(match(code, scheme)) %>%
  select(code, threat, n, pct)

# 2. Combinations ----

threat_combinations <- sets %>%
  group_by(sis_id) %>%
  summarise(combination = paste(scheme[scheme %in% code], collapse = "|"), n_threats = n(), .groups = "drop") %>%
  right_join(select(species, sis_id), by = "sis_id") %>%
  mutate(combination = replace_na(combination, "none"), n_threats = replace_na(n_threats, 0L)) %>%
  count(combination, n_threats, name = "n") %>%
  arrange(combination == "none", desc(n)) %>%
  mutate(pct = round(100 * n / n_spp, 2))

print(threat_sets)
print(threat_combinations)

write_csv(threat_sets,         file.path(dir_data, "threat_sets.csv"))
write_csv(threat_combinations, file.path(dir_data, "threat_combinations.csv"))
