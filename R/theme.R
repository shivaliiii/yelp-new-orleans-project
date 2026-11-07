# =============================================================================
# R/theme.R
# Shared plot style (same soft pastel look as my Monte Carlo CLT project).
# Every colour has a pastel FILL for bars/segments and a deeper version for
# points and lines, so marks stay readable on white.
# =============================================================================

theme_cols <- list(
  ink    = "#4A3F55",   # soft plum-charcoal: titles, labels, reference lines
  muted  = "#9A8FA6",   # axes, secondary text
  grid   = "#F3EBE6",   # gridlines
  band   = "#FDF3EA",   # soft cream highlight band
  above  = c(deep = "#3E9C83", fill = "#A8E0CC"),   # mint: better than average
  below  = c(deep = "#C9577F", fill = "#F8B5CC"),   # pink: worse than average
  zcta   = c(deep = "#D9844F", fill = "#FFCBA8"),   # peach: ZIP codes
  tract  = c(deep = "#6C63C7", fill = "#C9C5FF")    # lavender: census tracts
)

# DM Sans if it is installed, otherwise the default sans-serif font.
installed_fonts <- if (requireNamespace("systemfonts", quietly = TRUE)) {
  unique(systemfonts::system_fonts()$family)
} else character()
plot_family <- intersect(c("DM Sans", "DM Sans 9pt"), installed_fonts)[1]
if (is.na(plot_family)) plot_family <- "sans"

theme_pastel <- function(base_size = 13) {
  ggplot2::theme_minimal(base_size = base_size, base_family = plot_family) +
    ggplot2::theme(
      plot.title         = ggplot2::element_text(face = "bold", color = theme_cols$ink, size = base_size * 1.45),
      plot.subtitle      = ggplot2::element_text(color = theme_cols$muted, margin = ggplot2::margin(b = 12)),
      plot.title.position = "plot",
      axis.text          = ggplot2::element_text(color = theme_cols$muted),
      axis.text.y        = ggplot2::element_text(color = theme_cols$ink),
      axis.title         = ggplot2::element_text(color = theme_cols$ink),
      panel.grid.major   = ggplot2::element_line(color = theme_cols$grid, linewidth = 0.6),
      panel.grid.minor   = ggplot2::element_blank(),
      strip.text         = ggplot2::element_text(face = "bold", color = theme_cols$ink, size = base_size),
      plot.background    = ggplot2::element_rect(fill = "white", color = NA),
      plot.margin        = ggplot2::margin(16, 20, 12, 16)
    )
}

save_plot <- function(plot, file, width, height) {
  device <- if (requireNamespace("ragg", quietly = TRUE)) ragg::agg_png else "png"
  ggplot2::ggsave(file, plot, width = width, height = height, dpi = 150, device = device, bg = "white")
}
