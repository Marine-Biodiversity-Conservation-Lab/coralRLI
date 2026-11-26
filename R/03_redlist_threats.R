# 03_redlist_threats.R ----
# Threats coded in each species' latest global Red List assessment, from the IUCN Red List API v4.
# Needs a free API token (https://api.iucnredlist.org) saved as IUCN_REDLIST_KEY in ~/.Renviron.
# About 45 minutes the first time (two calls per species, paced at one per second). Each species'
# reply is cached in data/raw/redlist_api/, so an interrupted run carries on where it stopped.
# Writes data/work/threats.csv (species-level; not committed).

source("R/00_setup.R")
library(rredlist)
library(jsonlite)

if (!nzchar(Sys.getenv("IUCN_REDLIST_KEY"))) stop("IUCN_REDLIST_KEY is not set (README, step 4)", call. = FALSE)

dir_cache <- file.path(dir_raw, "redlist_api")
dir.create(dir_cache, showWarnings = FALSE)

ids <- read_csv(file.path(dir_work, "species.csv"), show_col_types = FALSE)$sis_id

# 1. Polite API calls: pause between calls, back off and retry when the server is busy ----

rl_call <- function(fun, id, tries = 6) {
  for (k in seq_len(tries)) {
    out <- tryCatch(fun(id), error = \(e) e)
    if (!inherits(out, "error")) { Sys.sleep(1); return(out) }
    busy <- str_detect(conditionMessage(out), "(?i)429|too many|rate|50[0-9]|timeout|timed out|connection")
    if (!busy || k == tries) stop("API call failed for ", id, ": ", conditionMessage(out))
    Sys.sleep(5 * 2^(k - 1))
  }
}

# 2. Fetch and cache ----

is_global <- \(a) any(map_chr(a$scopes, \(s) s$description$en %||% "") == "Global")

todo <- ids[!file.exists(file.path(dir_cache, paste0(ids, ".json")))]
msg(length(ids) - length(todo), " species cached, ", length(todo), " to fetch")

for (i in seq_along(todo)) {
  if (i %% 25 == 0) msg("  ", i, " / ", length(todo))
  id     <- todo[i]
  sis    <- fromJSON(rl_call(rl_sis_, id), simplifyVector = FALSE)
  latest <- keep(sis$assessments, \(a) is_global(a) && isTRUE(a$latest))
  assess <- if (length(latest) > 0) fromJSON(rl_call(rl_assessment_, latest[[1]]$assessment_id), simplifyVector = FALSE)
  write_json(list(sis_id = id, latest = assess), file.path(dir_cache, paste0(id, ".json")),
             auto_unbox = TRUE, null = "null")
}

# 3. Threats table ----
# One row per species x threat; code is the IUCN Threats Classification Scheme v3.3 code, e.g. "11_3"

threats <- map_dfr(ids, \(id) {
  x <- fromJSON(file.path(dir_cache, paste0(id, ".json")), simplifyVector = FALSE)
  map_dfr(x$latest$threats, \(z) tibble(sis_id = id, code = z$code))
})

msg(nrow(threats), " threat records for ", n_distinct(threats$sis_id), " species")
write_csv(threats, file.path(dir_work, "threats.csv"))
