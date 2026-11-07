# =============================================================================
# R/charts.R
# Two summary charts for the report:
#   figures/category_chart.png   Step 3: where the selected categories sit
#   figures/top10_chart.png      The answer: top 10 by reviewer-adjusted score
#
# Run from the project root, after R/clean.R and R/reviewers.R:
#   Rscript R/charts.R
# =============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(ggplot2)
})
source("R/theme.R")

selected_categories <- c("Breakfast & Brunch", "Coffee & Tea", "Cafes", "Bakeries")

# ---- Category chart ----------------------------------------------------------

category_counts <- read.csv("data/new_orleans/category_counts.csv")
top_categories <- category_counts |>
  filter(!category %in% c("Restaurants", "Food")) |>
  filter(rank(-n, ties.method = "first") <= 14 | category %in% selected_categories) |>
  mutate(selected = category %in% selected_categories,
         category = reorder(category, n))

p_categories <- ggplot(top_categories, aes(n, category)) +
  geom_col(aes(fill = selected), width = 0.62) +
  geom_text(aes(label = n, color = selected), hjust = -0.25, family = plot_family,
            fontface = "bold", size = 3.6) +
  scale_fill_manual(values = c(`TRUE` = theme_cols$zcta[["deep"]], `FALSE` = theme_cols$tract[["fill"]]),
                    guide = "none") +
  scale_color_manual(values = c(`TRUE` = theme_cols$ink, `FALSE` = theme_cols$muted), guide = "none") +
  scale_x_continuous(expand = expansion(mult = c(0, 0.1))) +
  labs(
    title = "Breakfast & coffee: four categories, one morning",
    subtitle = "Most common categories among 2,261 New Orleans restaurants, plus Bakeries. Orange = the four chosen",
    x = "restaurants", y = NULL
  ) +
  theme_pastel() +
  theme(panel.grid.major.y = element_blank(),
        axis.text.y = element_text(color = theme_cols$ink, size = 11.5))

save_plot(p_categories, "figures/category_chart.png", width = 10, height = 6.2)

# ---- Top 10 chart ------------------------------------------------------------

top10 <- readRDS("data/new_orleans/top10.rds") |>
  left_join(readRDS("data/new_orleans/restaurant_areas.rds"), by = "business_id") |>
  mutate(
    label = paste0(top_rank, ".  ", business_name),
    label = reorder(label, -top_rank),
    was   = paste0("was #", rank_all_reviewers, " on plain stars"),
    where = paste0(neighborhood, ", ", zip)
  )

p_top10 <- ggplot(top10, aes(y = label)) +
  geom_segment(aes(x = 0, xend = average_normalized_score, yend = label),
               color = theme_cols$zcta[["fill"]], linewidth = 4.2, lineend = "round") +
  geom_point(aes(x = average_normalized_score), shape = 21, size = 6.4,
             fill = theme_cols$zcta[["deep"]], color = "white", stroke = 1.3) +
  geom_text(aes(x = average_normalized_score, label = sprintf("+%.2f", average_normalized_score)),
            hjust = -0.45, family = plot_family, fontface = "bold", color = theme_cols$ink, size = 4) +
  geom_text(aes(x = 0.02, label = where), vjust = 2.15, hjust = 0, family = plot_family,
            color = theme_cols$muted, size = 3.1) +
  geom_text(aes(x = 1.13, label = was), hjust = 1, family = plot_family,
            color = theme_cols$muted, size = 3.4) +
  annotate("text", x = 1.13, y = 10.75, hjust = 1, label = "before adjustment",
           family = plot_family, fontface = "bold", color = theme_cols$ink, size = 3.5) +
  scale_x_continuous(limits = c(0, 1.13), breaks = seq(0, 0.8, 0.2),
                     labels = function(x) ifelse(x == 0, "0", sprintf("+%.1f", x))) +
  coord_cartesian(clip = "off") +
  labs(
    title = "The top 10 breakfast & coffee spots",
    subtitle = "Stars above their usual rating that active reviewers gave each restaurant",
    x = "reviewer-adjusted score", y = NULL
  ) +
  theme_pastel() +
  theme(panel.grid.major.y = element_blank(),
        axis.text.y = element_text(color = theme_cols$ink, size = 12, face = "bold",
                                   margin = margin(r = 6)))

save_plot(p_top10, "figures/top10_chart.png", width = 10, height = 7)
message("Saved figures/category_chart.png and figures/top10_chart.png")
