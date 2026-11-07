# =============================================================================
# R/compare_systems.R
# Step 6 (continued): compare ZIP/ZCTA and census tracts on area size and
# average business rating, using the summaries saved by R/analysis.R.
#
# Run from the project root, after R/analysis.R:
#   Rscript R/compare_systems.R
# =============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(ggplot2)
})

min_restaurants <- 5   # areas below this are mapped but not ranked

zcta_summary  <- readRDS("data/new_orleans/zcta_summary.rds")  |> mutate(system = "ZIP/ZCTA")
tract_summary <- readRDS("data/new_orleans/tract_summary.rds") |> mutate(system = "Census tract")

areas <- bind_rows(zcta_summary, tract_summary) |>
  filter(!is.na(area_id)) |>
  mutate(system = factor(system, levels = c("ZIP/ZCTA", "Census tract")))

# ---- Table: area size and rating by geographic system -----------------------

system_ratings <- areas |>
  group_by(system) |>
  summarise(
    number_of_areas            = n(),
    median_restaurants_per_area = median(number_of_restaurants),
    areas_under_5              = sum(number_of_restaurants < min_restaurants),
    pct_areas_under_5          = round(100 * mean(number_of_restaurants < min_restaurants)),
    restaurants_in_areas_under_5 = sum(number_of_restaurants[number_of_restaurants < min_restaurants]),
    lowest_area_avg_stars      = round(min(average_business_stars[number_of_restaurants >= min_restaurants]), 2),
    highest_area_avg_stars     = round(max(average_business_stars[number_of_restaurants >= min_restaurants]), 2),
    .groups = "drop"
  )

print(as.data.frame(system_ratings))
write.csv(system_ratings, "data/new_orleans/system_ratings_comparison.csv", row.names = FALSE)

# ZIP-level table for the README (areas with enough restaurants to compare)
zcta_table <- zcta_summary |>
  filter(number_of_restaurants >= min_restaurants) |>
  transmute(zip = area_id, restaurants = number_of_restaurants,
            average_business_stars = round(average_business_stars, 2)) |>
  arrange(desc(restaurants))
write.csv(zcta_table, "data/new_orleans/zcta_ratings.csv", row.names = FALSE)

# ---- Plot: restaurants per area vs. average rating, both systems ------------

p_compare <- ggplot(areas, aes(number_of_restaurants, average_business_stars)) +
  annotate("rect", xmin = 0.8, xmax = min_restaurants - 0.5, ymin = -Inf, ymax = Inf,
           fill = "grey90") +
  geom_point(aes(color = system), alpha = 0.7, size = 2.2, show.legend = FALSE) +
  scale_x_log10(breaks = c(1, 2, 5, 10, 25, 50, 100)) +
  scale_color_manual(values = c("ZIP/ZCTA" = "#2a6f97", "Census tract" = "#c8553d")) +
  facet_wrap(~ system) +
  labs(
    title = "Census tracts split the same restaurants into many tiny areas",
    subtitle = paste0("Each point is one area. Grey band = fewer than ", min_restaurants,
                      " restaurants, too few for a reliable average."),
    x = "Breakfast & coffee restaurants in the area (log scale)",
    y = "Average business stars"
  ) +
  theme_minimal(base_size = 12)

ggsave("figures/geographic_system_comparison.png", p_compare, width = 9, height = 4.8, dpi = 150)
message("Saved figures/geographic_system_comparison.png and data/new_orleans/system_ratings_comparison.csv, zcta_ratings.csv")
