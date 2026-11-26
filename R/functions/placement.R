# placement.R ----
# Places the RLI sparkline boxes (panel b) in open space automatically, so no box sits on reef.
# Candidate box centres lie on a 100 km grid. A candidate is ruled out if its box leaves the map,
# overlaps a box already placed (with a 100 km gap) or the colour key, or lies more than max_dist from
# its region. Of the rest, those covering at most 2% reef cells (with a ~40 km halo) are kept where any
# exist, and the cheapest is chosen:
#   cost = w_reef   * share of the box over reef cells
#        + w_region * share of the box over GCRMN regions
#        + w_dist   * distance to the region's leader-line target (per 1,000 km)
#        + w_cross  * number of crossings (leader lines vs boxes, and leader vs leader)
# Boxes are placed one at a time, largest region (most species) first; the layout is also built for 11
# random orders (fixed seed) and the order with the lowest total cost is kept.
# Requires basemap.R (regions, reef_pts, xlim, ylim, targets).

occ_res   <- 4e4    # occupancy grid resolution (m)
cand_step <- 1e5    # candidate grid spacing (m)
reef_tol  <- 0.02
w_reef    <- 30
w_region  <- 12
w_dist    <- 1
w_cross   <- 15
n_orders  <- 12
gap       <- 1e5    # minimum clearance between boxes (m)
max_dist  <- 6e6    # boxes stay within this distance of their target (relaxed if nothing fits)

# 1. Occupancy grids (summed-area tables, so the cover of any rectangle is four look-ups) ----

sat <- function(m) {
  m[is.na(m)] <- 0
  s <- t(apply(apply(m, 2, cumsum), 1, cumsum))
  rbind(0, cbind(0, s))
}

occ_template <- rast(xmin = xlim[1], xmax = xlim[2], ymin = ylim[1], ymax = ylim[2],
                     resolution = occ_res, crs = map_crs)

occ_reef <- rasterize(vect(reef_pts), occ_template, field = 1, background = 0) %>%
  focal(w = 3, fun = "max", fillvalue = 0)                             # ~40 km halo round reef cells
occ_region <- rasterize(vect(regions), occ_template, field = 1, touches = TRUE, background = 0)

sat_reef   <- sat(as.matrix(occ_reef, wide = TRUE))
sat_region <- sat(as.matrix(occ_region, wide = TRUE))
occ_nr     <- nrow(occ_template)
occ_nc     <- ncol(occ_template)

# Share of each rectangle covered (rows run from ylim[2] downwards)
rect_share <- function(S, xmin, xmax, ymin, ymax) {
  c1 <- pmin(pmax(floor((xmin - xlim[1]) / occ_res) + 1, 1), occ_nc)
  c2 <- pmin(pmax(ceiling((xmax - xlim[1]) / occ_res), 1), occ_nc)
  r1 <- pmin(pmax(floor((ylim[2] - ymax) / occ_res) + 1, 1), occ_nr)
  r2 <- pmin(pmax(ceiling((ylim[2] - ymin) / occ_res), 1), occ_nr)
  tot <- S[cbind(r2 + 1, c2 + 1)] - S[cbind(r1, c2 + 1)] - S[cbind(r2 + 1, c1)] + S[cbind(r1, c1)]
  list(sum = tot, n = (r2 - r1 + 1) * (c2 - c1 + 1))
}

# 2. Geometry helpers ----

box_rect <- \(item, x, y) tibble(xmin = x - item$gw / 2, xmax = x + item$gw / 2,
                                 ymin = y - item$gh / 2, ymax = y + item$gh / 2)

overlaps <- function(a, b, pad = gap) {
  !(a$xmax + pad < b$xmin | a$xmin - pad > b$xmax | a$ymax + pad < b$ymin | a$ymin - pad > b$ymax)
}

# Does segment (x0, y0)-(x1, y1) cross the rectangle? (Liang-Barsky; arguments recycle)
seg_hits_rect <- function(x0, y0, x1, y1, xmin, xmax, ymin, ymax) {
  n  <- max(length(x0), length(xmin))
  x0 <- rep_len(x0, n); y0 <- rep_len(y0, n); x1 <- rep_len(x1, n); y1 <- rep_len(y1, n)
  xmin <- rep_len(xmin, n); xmax <- rep_len(xmax, n); ymin <- rep_len(ymin, n); ymax <- rep_len(ymax, n)
  dx <- x1 - x0; dy <- y1 - y0
  p <- cbind(-dx, dx, -dy, dy)
  q <- cbind(x0 - xmin, xmax - x0, y0 - ymin, ymax - y0)
  t0 <- rep(0, n); t1 <- rep(1, n); hit <- rep(TRUE, n)
  for (k in 1:4) {
    pk <- p[, k]; qk <- q[, k]
    par <- pk == 0
    hit[par & qk < 0] <- FALSE
    tk  <- qk / pk
    neg <- !par & pk < 0; pos <- !par & pk > 0
    t0[neg] <- pmax(t0[neg], tk[neg]); t1[pos] <- pmin(t1[pos], tk[pos])
  }
  hit & t0 <= t1
}

# Do segments a and b cross? (shared end points don't count)
seg_cross <- function(ax0, ay0, ax1, ay1, bx0, by0, bx1, by1) {
  orient <- \(px, py, qx, qy, rx, ry) sign((qx - px) * (ry - py) - (qy - py) * (rx - px))
  o1 <- orient(ax0, ay0, ax1, ay1, bx0, by0); o2 <- orient(ax0, ay0, ax1, ay1, bx1, by1)
  o3 <- orient(bx0, by0, bx1, by1, ax0, ay0); o4 <- orient(bx0, by0, bx1, by1, ax1, ay1)
  o1 * o2 < 0 & o3 * o4 < 0
}

# 3. Place ----
# items: unit, size (sets the default order), gw, gh (box width and height, m)

place_glyphs <- function(items, keep_out) {
  items <- items %>% left_join(targets, by = "unit") %>% arrange(desc(size))
  set.seed(1)
  orders  <- c(list(seq_len(nrow(items))), map(seq_len(n_orders - 1), \(k) sample.int(nrow(items))))
  layouts <- map(orders, \(o) place_once(items[o, ], keep_out))
  layouts[[which.min(map_dbl(layouts, \(l) sum(l$cost)))]]
}

place_once <- function(items, keep_out) {

  cand <- expand_grid(x = seq(xlim[1], xlim[2], by = cand_step), y = seq(ylim[1], ylim[2], by = cand_step))

  placed_rects <- keep_out
  placed_segs  <- tibble(x0 = numeric(), y0 = numeric(), x1 = numeric(), y1 = numeric())
  out <- list()

  for (i in seq_len(nrow(items))) {

    it <- items[i, ]
    gx1 <- cand$x - it$gw / 2; gx2 <- cand$x + it$gw / 2
    gy1 <- cand$y - it$gh / 2; gy2 <- cand$y + it$gh / 2

    ok <- gx1 >= xlim[1] + 2e4 & gx2 <= xlim[2] - 2e4 & gy1 >= ylim[1] + 2e4 & gy2 <= ylim[2] - 2e4
    for (k in seq_len(nrow(placed_rects))) {
      ok <- ok & !overlaps(list(xmin = gx1, xmax = gx2, ymin = gy1, ymax = gy2), placed_rects[k, ])
    }
    if (!any(ok)) {                                    # this order fails; another may fit
      out[[i]] <- tibble(unit = it$unit, x = NA_real_, y = NA_real_, cost = 1e6)
      next
    }

    dist <- sqrt((cand$x - it$tx)^2 + (cand$y - it$ty)^2)
    if (any(ok & dist <= max_dist)) ok <- ok & dist <= max_dist

    reef <- rect_share(sat_reef, gx1, gx2, gy1, gy2)
    reg  <- rect_share(sat_region, gx1, gx2, gy1, gy2)

    cross <- 0
    for (k in seq_len(nrow(placed_rects))) {
      pr <- placed_rects[k, ]
      cross <- cross + seg_hits_rect(cand$x, cand$y, it$tx, it$ty, pr$xmin, pr$xmax, pr$ymin, pr$ymax)
    }
    for (k in seq_len(nrow(placed_segs))) {
      ps <- placed_segs[k, ]
      cross <- cross + seg_hits_rect(ps$x0, ps$y0, ps$x1, ps$y1, gx1, gx2, gy1, gy2) +
        seg_cross(cand$x, cand$y, it$tx, it$ty, ps$x0, ps$y0, ps$x1, ps$y1)
    }

    reef_share <- reef$sum / reef$n
    if (any(ok & reef_share <= reef_tol)) ok <- ok & reef_share <= reef_tol

    cost <- w_reef * reef_share + w_region * reg$sum / reef$n + w_dist * dist / 1e6 + w_cross * cross
    cost[!ok] <- Inf

    j <- which.min(cost)
    out[[i]] <- tibble(unit = it$unit, x = cand$x[j], y = cand$y[j], cost = cost[j])
    placed_rects <- bind_rows(placed_rects, box_rect(it, cand$x[j], cand$y[j]))
    placed_segs  <- bind_rows(placed_segs, tibble(x0 = cand$x[j], y0 = cand$y[j], x1 = it$tx, y1 = it$ty))
  }

  bind_rows(out)
}
