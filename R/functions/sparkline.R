# sparkline.R ----
# RLI sparkline boxes for panel b: a rounded white box, the region name in bold above the data, points
# for pre-1998, 2008 and 2024 on a grey line, and the 2024 value just right of the last point. Box size
# is in map units (metres).

spark_years   <- c(1991, 2039)   # x limits; the left margin keeps the name clear of the box edge
spark_label_x <- 1994            # left edge of the region name
spark_label_y <- 1.33            # top of the region name (RLI units)
spark_top     <- 1.41            # y limit above the name
spark_value_dx <- 2.6            # gap (years) between the last point and the 2024 value
spark_box_w   <- 3.6e6           # 75 km per year, as before the margins were widened
spark_box_h   <- 2.0e6           # 2,000 km per RLI unit

# df: one region's rows (year, value column); point_fill: function from RLI to colour; y_min: lower
# y limit (RLI)
make_spark_grob <- function(df, value, unit_name, point_fill, y_min) {
  df   <- df %>% arrange(year) %>% mutate(v = .data[[value]])
  last <- df[nrow(df), ]
  gg <- ggplot(df, aes(x = year, y = v)) +
    geom_line(colour = "grey45", linewidth = 0.4) +
    geom_point(aes(fill = point_fill(pmin(v, 1))), shape = 21, colour = "grey20", stroke = 0.25, size = 1.3) +
    scale_fill_identity() +
    annotate("text", x = spark_label_x, y = spark_label_y, hjust = 0, vjust = 1, size = 1.75, fontface = "bold",
             label = unit_name) +
    annotate("text", x = last$year + spark_value_dx, y = last$v, hjust = 0, vjust = 0.5, size = 1.6,
             label = sprintf("%.2f", last$v)) +
    scale_x_continuous(limits = spark_years, expand = c(0, 0)) +
    scale_y_continuous(limits = c(y_min, spark_top), expand = c(0, 0)) +
    theme_void() +
    theme(panel.background = element_rect(fill = NA, colour = NA),
          plot.background  = element_rect(fill = NA, colour = NA),
          plot.margin      = margin(0, 0, 0, 0))
  box <- grid::roundrectGrob(r = unit(1.2, "mm"),
                             gp = grid::gpar(fill = alpha("white", 0.85), col = "grey15", lwd = 0.7))
  grid::grobTree(box, ggplotGrob(gg))
}

# Leader lines run from the box edge to the region's target, only where the target lies outside the box
spark_leaders <- function(boxes, hw = spark_box_w / 2, hh = spark_box_h / 2) {
  boxes %>%
    filter(!is.na(tx), abs(tx - x) > hw | abs(ty - y) > hh) %>%
    mutate(dx = tx - x, dy = ty - y,
           t  = pmin(ifelse(dx == 0, Inf, hw / abs(dx)), ifelse(dy == 0, Inf, hh / abs(dy)), 1),
           sx = x + t * dx, sy = y + t * dy)
}

add_sparklines <- function(p, boxes, data, value, point_fill, y_min) {
  for (i in seq_len(nrow(boxes))) {
    p <- p + annotation_custom(make_spark_grob(filter(data, unit == boxes$unit[i]), value, boxes$unit[i], point_fill, y_min),
                               xmin = boxes$x[i] - spark_box_w / 2, xmax = boxes$x[i] + spark_box_w / 2,
                               ymin = boxes$y[i] - spark_box_h / 2, ymax = boxes$y[i] + spark_box_h / 2)
  }
  p
}
