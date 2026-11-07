# =============================================================================
# R/analysis.R
# Step 5: spatial join to an official city boundary (tigris::places)
# Step 6: compare two geographic systems (ZCTA vs. Census tract) and pick one
#
# Run from the project root, after R/clean.R:
#   Rscript R/analysis.R
# =============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(sf)
  library(tigris)
  library(ggplot2)
  library(viridis)
})

options(tigris_use_cache = TRUE)
dir.create("figures", showWarnings = FALSE, recursive = TRUE)

selected_restaurants <- readRDS("data/new_orleans/selected_restaurants.rds")

restaurant_points <- selected_restaurants |>
  filter(!is.na(longitude), !is.na(latitude)) |>
  st_as_sf(coords = c("longitude", "latitude"), crs = 4326, remove = FALSE)

# ---- Step 5: spatial join to the official New Orleans place boundary -------

louisiana_places <- tigris::places(state = "LA", cb = TRUE, year = 2024, class = "sf") |>
  st_transform(4326)

restaurants_with_place <- restaurant_points |>
  st_join(
    louisiana_places |> select(GEOID, place_name = NAME),
    join = st_within,
    left = TRUE
  )

message("Yelp city label vs. official place boundary:")
city_vs_place <- restaurants_with_place |>
  st_drop_geometry() |>
  count(city, place_name, sort = TRUE)
print(as.data.frame(head(city_vs_place, 15)))

new_orleans_boundary <- louisiana_places |> filter(NAME == "New Orleans")
new_orleans_map_data <- restaurants_with_place |> filter(place_name == "New Orleans")

p_boundary <- ggplot() +
  geom_sf(data = new_orleans_boundary, fill = "grey95", color = "grey35") +
  geom_sf(data = new_orleans_map_data, aes(color = stars), alpha = 0.7, size = 1.5) +
  scale_color_viridis_c(option = "C", limits = c(1, 5)) +
  labs(
    title = "Breakfast & Coffee Spots Within the New Orleans City Boundary",
    color = "Business\nstars"
  ) +
  theme_minimal()

ggsave("figures/new_orleans_boundary_map.png", p_boundary, width = 7, height = 6, dpi = 150)

# ---- Step 6: compare two geographic systems ---------------------------------

# System 1: ZIP Code Tabulation Areas (ZCTA)
zctas_la <- tigris::zctas(state = "LA", cb = FALSE, year = 2010, class = "sf") |>
  select(area_id = ZCTA5CE10) |>
  st_transform(4326)

restaurants_by_zcta <- restaurant_points |>
  st_join(zctas_la, join = st_within, left = TRUE)

zcta_summary <- restaurants_by_zcta |>
  st_drop_geometry() |>
  group_by(area_id) |>
  summarise(
    number_of_restaurants = n(),
    average_business_stars = mean(stars, na.rm = TRUE),
    .groups = "drop"
  ) |>
  arrange(desc(number_of_restaurants))

# System 2: Census tracts (Orleans Parish)
tracts_orleans <- tigris::tracts(state = "LA", county = "Orleans", cb = TRUE, year = 2024, class = "sf") |>
  select(area_id = TRACTCE) |>
  st_transform(4326)

restaurants_by_tract <- restaurant_points |>
  st_join(tracts_orleans, join = st_within, left = TRUE)

tract_summary <- restaurants_by_tract |>
  st_drop_geometry() |>
  group_by(area_id) |>
  summarise(
    number_of_restaurants = n(),
    average_business_stars = mean(stars, na.rm = TRUE),
    .groups = "drop"
  ) |>
  arrange(desc(number_of_restaurants))

summarise_system <- function(df, label, n_areas_total) {
  matched <- df |> filter(!is.na(area_id))
  unmatched_n <- sum(is.na(df$area_id))
  tibble(
    geographic_system = label,
    number_of_areas = n_distinct(matched$area_id),
    restaurants_assigned = nrow(matched),
    unmatched_restaurants = unmatched_n,
    smallest_area_count = min(matched |> count(area_id) |> pull(n)),
    largest_area_count = max(matched |> count(area_id) |> pull(n))
  )
}

geographic_comparison <- bind_rows(
  summarise_system(st_drop_geometry(restaurants_by_zcta), "ZIP/ZCTA"),
  summarise_system(st_drop_geometry(restaurants_by_tract), "Census tract")
)

message("\nGeographic system comparison:")
print(as.data.frame(geographic_comparison))

write.csv(geographic_comparison, "data/new_orleans/geographic_comparison.csv", row.names = FALSE)
saveRDS(zcta_summary, "data/new_orleans/zcta_summary.rds")
saveRDS(tract_summary, "data/new_orleans/tract_summary.rds")

# Map of restaurant counts per ZCTA (the system this project selects -- see
# README for the justification).
zcta_map_data <- zctas_la |> left_join(zcta_summary, by = "area_id")

p_zcta <- ggplot() +
  geom_sf(data = zcta_map_data, aes(fill = number_of_restaurants), color = "white", size = 0.1) +
  geom_sf(data = new_orleans_boundary, fill = NA, color = "black", linewidth = 0.6) +
  coord_sf(xlim = st_bbox(new_orleans_boundary)[c("xmin", "xmax")],
           ylim = st_bbox(new_orleans_boundary)[c("ymin", "ymax")]) +
  scale_fill_viridis_c(option = "C", na.value = "grey90") +
  labs(
    title = "Breakfast & Coffee Restaurants per ZIP Code (ZCTA)",
    fill = "Restaurant\ncount"
  ) +
  theme_minimal()

ggsave("figures/zcta_restaurant_count_map.png", p_zcta, width = 7, height = 6, dpi = 150)

message("\nSaved figures/new_orleans_boundary_map.png, figures/zcta_restaurant_count_map.png")
message("Saved data/new_orleans/geographic_comparison.csv, zcta_summary.rds, tract_summary.rds")
