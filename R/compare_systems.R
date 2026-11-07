# =============================================================================
# R/compare_systems.R
# Step 6 (continued): compare ZIP/ZCTA, census tracts and Neighborhood
# Statistical Areas on area size and average business rating, using the
# summaries saved by R/analysis.R and R/neighborhoods.R.
# Also draws the headline chart for the README.
#
# Run from the project root, after R/neighborhoods.R:
#   Rscript R/compare_systems.R
# =============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(ggplot2)
})
source("R/theme.R")

min_restaurants <- 5   # areas below this are mapped but not ranked

selected_restaurants <- readRDS("data/new_orleans/selected_restaurants.rds")
city_average <- mean(selected_restaurants$stars, na.rm = TRUE)

zcta_summary  <- readRDS("data/new_orleans/zcta_summary.rds")  |> mutate(system = "ZIP codes")
tract_summary <- readRDS("data/new_orleans/tract_summary.rds") |> mutate(system = "Census tracts")
nsa_summary   <- readRDS("data/new_orleans/nsa_summary.rds")   |> mutate(system = "Neighborhoods (NSAs)")

system_levels <- c("ZIP codes", "Neighborhoods (NSAs)", "Census tracts")
areas <- bind_rows(zcta_summary, tract_summary, nsa_summary) |>
  filter(!is.na(area_id)) |>
  mutate(system = factor(system, levels = system_levels))

# ---- Table: area size and rating by geographic system -----------------------

system_ratings <- areas |>
  group_by(system) |>
  summarise(
    number_of_areas              = n(),
    median_restaurants_per_area  = median(number_of_restaurants),
    areas_under_5                = sum(number_of_restaurants < min_restaurants),
    pct_areas_under_5            = round(100 * mean(number_of_restaurants < min_restaurants)),
    restaurants_in_areas_under_5 = sum(number_of_restaurants[number_of_restaurants < min_restaurants]),
    lowest_area_avg_stars        = round(min(average_business_stars[number_of_restaurants >= min_restaurants]), 2),
    highest_area_avg_stars       = round(max(average_business_stars[number_of_restaurants >= min_restaurants]), 2),
    .groups = "drop"
  )
print(as.data.frame(system_ratings))
write.csv(system_ratings, "data/new_orleans/system_ratings_comparison.csv", row.names = FALSE)

# ---- ZIP-level table (areas with enough restaurants to compare) -------------

# Main neighborhoods in each ZIP code, for readable labels
zip_neighborhoods <- c(
  "70112" = "CBD & Tulane-Gravier",      "70113" = "Central City",
  "70114" = "Algiers Point",             "70115" = "Uptown & Garden District",
  "70116" = "French Quarter & Marigny",  "70117" = "Bywater & St. Roch",
  "70118" = "Carrollton & Audubon",      "70119" = "Mid-City",
  "70122" = "Gentilly",                  "70124" = "Lakeview",
  "70125" = "Broadmoor & Freret",        "70126" = "New Orleans East",
  "70128" = "New Orleans East",          "70130" = "Warehouse District & upper Quarter",
  "70131" = "Algiers"
)

zcta_table <- zcta_summary |>
  filter(number_of_restaurants >= min_restaurants) |>
  transmute(zip = area_id,
            neighborhoods = unname(zip_neighborhoods[area_id]),
            restaurants = number_of_restaurants,
            average_business_stars = round(average_business_stars, 2)) |>
  arrange(desc(restaurants))
write.csv(zcta_table, "data/new_orleans/zcta_ratings.csv", row.names = FALSE)

# ---- Headline chart: average stars by ZIP vs. the city average --------------

hero <- zcta_table |>
  mutate(
    label    = paste0(zip, "  ", neighborhoods),
    label    = reorder(label, average_business_stars),
    better   = average_business_stars >= city_average,
    deep     = ifelse(better, theme_cols$above[["deep"]], theme_cols$below[["deep"]]),
    pastel   = ifelse(better, theme_cols$above[["fill"]], theme_cols$below[["fill"]]),
    value    = sprintf("%.2f", average_business_stars),
    count    = paste0(restaurants, " spots")
  )

p_hero <- ggplot(hero, aes(y = label)) +
  geom_vline(xintercept = city_average, linetype = "22", color = theme_cols$ink, linewidth = 0.6) +
  annotate("text", x = city_average, y = Inf, vjust = -0.5, label = "city average",
           family = plot_family, fontface = "bold", color = theme_cols$ink, size = 3.8, hjust = 0.5) +
  geom_segment(aes(x = city_average, xend = average_business_stars, yend = label, color = pastel),
               linewidth = 3.2, lineend = "round") +
  geom_point(aes(x = average_business_stars, fill = deep), shape = 21, color = "white",
             size = 5, stroke = 1.2) +
  geom_text(aes(x = average_business_stars, label = value,
                hjust = ifelse(better, -0.55, 1.55)),
            family = plot_family, fontface = "bold", color = theme_cols$ink, size = 3.9) +
  geom_text(aes(x = 4.62, label = count), family = plot_family, color = theme_cols$muted,
            size = 3.5, hjust = 1) +
  scale_color_identity() +
  scale_fill_identity() +
  scale_x_continuous(limits = c(2.05, 4.62), breaks = seq(2.5, 4.5, 0.5)) +
  coord_cartesian(clip = "off") +
  labs(
    title = "Most spots downtown, best ratings in Bywater",
    subtitle = "Average Yelp stars of breakfast & coffee restaurants, ZIP codes with at least 5 of them",
    x = "average business stars", y = NULL
  ) +
  theme_pastel() +
  theme(panel.grid.major.y = element_blank())

save_plot(p_hero, "figures/zip_ratings_chart.png", width = 10, height = 6.4)

# ---- Comparison plot: restaurants per area vs. average rating ---------------

system_colors <- c("ZIP codes" = theme_cols$zcta[["deep"]], "Census tracts" = theme_cols$tract[["deep"]],
                   "Neighborhoods (NSAs)" = theme_cols$nsa[["deep"]])

p_compare <- ggplot(areas, aes(number_of_restaurants, average_business_stars)) +
  annotate("rect", xmin = 0.8, xmax = min_restaurants - 0.5, ymin = -Inf, ymax = Inf,
           fill = theme_cols$band) +
  annotate("text", x = 2, y = 5.35, label = "too few to trust", family = plot_family,
           fontface = "bold", color = theme_cols$muted, size = 3.6) +
  geom_hline(yintercept = city_average, linetype = "22", color = theme_cols$ink, linewidth = 0.5) +
  geom_point(aes(fill = system), shape = 21, color = "white", size = 3.4, stroke = 0.8, alpha = 0.9,
             show.legend = FALSE) +
  scale_fill_manual(values = system_colors) +
  scale_x_log10(breaks = c(1, 2, 5, 10, 25, 50, 100)) +
  scale_y_continuous(limits = c(1.4, 5.45), breaks = 1:5) +
  facet_wrap(~ system) +
  labs(
    title = "Smaller areas mean shakier averages",
    subtitle = paste0("Each dot is one area. Areas with fewer than ", min_restaurants,
                      " restaurants (shaded) swing wildly; dashed line = city average"),
    x = "breakfast & coffee restaurants in the area (log scale)",
    y = "average business stars"
  ) +
  theme_pastel()

save_plot(p_compare, "figures/geographic_system_comparison.png", width = 12, height = 5)

message("Saved figures/zip_ratings_chart.png, figures/geographic_system_comparison.png, ",
        "data/new_orleans/system_ratings_comparison.csv, zcta_ratings.csv")
