# =============================================================================
# R/theme.R
# Shared plot style: bright pastels with rounded, playful fonts.
# Every colour has a pastel FILL for bars/segments and a deeper version for
# points and lines, so marks stay readable on white.
# =============================================================================

theme_cols <- list(
  ink    = "#3D3553",   # deep plum: titles, labels, reference lines
  muted  = "#9A8CB0",   # axes, secondary text
  grid   = "#F1ECFA",   # gridlines
  band   = "#FFF6D6",   # butter-yellow highlight band
  above  = c(deep = "#2FB38A", fill = "#BDF0DE"),   # mint: better than average
  below  = c(deep = "#F0608E", fill = "#FFC9DA"),   # bubblegum pink: worse than average
  zcta   = c(deep = "#8B6CF0", fill = "#DCD0FF"),   # lavender: ZIP codes, main colour
  tract  = c(deep = "#4FA3E3", fill = "#CDE6FF"),   # sky blue: census tracts
  nsa    = c(deep = "#F28C5B", fill = "#FFD9C4")    # peach: neighbourhoods
)

# Fonts: Nunito for text and Fredoka for titles. They ship with the project
# (assets/fonts/ttf), so the charts look the same on any computer. If they
# can't be loaded, the default sans-serif font is used instead.
plot_family  <- "sans"
title_family <- "sans"
font_dir <- "assets/fonts/ttf"
if (requireNamespace("systemfonts", quietly = TRUE) && dir.exists(font_dir)) {
  ok <- tryCatch({
    systemfonts::register_font(
      name   = "Nunito",
      plain  = file.path(font_dir, "nunito-latin-400-normal.ttf"),
      bold   = file.path(font_dir, "nunito-latin-700-normal.ttf"),
      italic = file.path(font_dir, "nunito-latin-400-italic.ttf")
    )
    systemfonts::register_font(
      name  = "Fredoka",
      plain = file.path(font_dir, "fredoka-latin-600-normal.ttf"),
      bold  = file.path(font_dir, "fredoka-latin-700-normal.ttf")
    )
    TRUE
  }, error = function(e) FALSE)
  if (ok) { plot_family <- "Nunito"; title_family <- "Fredoka" }
}

theme_pastel <- function(base_size = 13) {
  ggplot2::theme_minimal(base_size = base_size, base_family = plot_family) +
    ggplot2::theme(
      plot.title         = ggplot2::element_text(family = title_family, color = theme_cols$ink, size = base_size * 1.55),
      plot.subtitle      = ggplot2::element_text(color = theme_cols$muted, margin = ggplot2::margin(b = 12)),
      plot.title.position = "plot",
      axis.text          = ggplot2::element_text(color = theme_cols$muted),
      axis.text.y        = ggplot2::element_text(color = theme_cols$ink),
      axis.title         = ggplot2::element_text(color = theme_cols$ink),
      panel.grid.major   = ggplot2::element_line(color = theme_cols$grid, linewidth = 0.6),
      panel.grid.minor   = ggplot2::element_blank(),
      strip.text         = ggplot2::element_text(family = title_family, color = theme_cols$ink, size = base_size * 1.1),
      plot.background    = ggplot2::element_rect(fill = "white", color = NA),
      plot.margin        = ggplot2::margin(16, 20, 12, 16)
    )
}

save_plot <- function(plot, file, width, height) {
  device <- if (requireNamespace("ragg", quietly = TRUE)) ragg::agg_png else "png"
  ggplot2::ggsave(file, plot, width = width, height = height, dpi = 150, device = device, bg = "white")
}
