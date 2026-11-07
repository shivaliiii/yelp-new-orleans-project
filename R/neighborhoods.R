# =============================================================================
# R/neighborhoods.R
# Step 6 (third system): Neighborhood Statistical Areas (NSAs), the City of
# New Orleans' own planning neighbourhoods. Also rebuilds the geographic
# comparison table with all three systems.
#
# Run from the project root, after R/analysis.R and R/boundaries.R:
#   Rscript R/neighborhoods.R
# =============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(sf)
})
sf_use_s2(FALSE)

selected_restaurants <- readRDS("data/new_orleans/selected_restaurants.rds")
restaurant_points <- selected_restaurants |>
  filter(!is.na(longitude), !is.na(latitude)) |>
  st_as_sf(coords = c("longitude", "latitude"), crs = 4326, remove = FALSE)

nsa  <- st_read("data/boundaries/nsa_new_orleans.geojson", quiet = TRUE)
zcta <- st_read("data/boundaries/zcta_new_orleans.geojson", quiet = TRUE)

# Assign every restaurant to a ZIP code and a neighbourhood
restaurant_areas <- restaurant_points |>
  st_join(zcta, join = st_within, left = TRUE) |>
  rename(zip = area_id) |>
  st_join(nsa, join = st_within, left = TRUE) |>
  st_drop_geometry() |>
  select(business_id, zip, neighborhood)
saveRDS(restaurant_areas, "data/new_orleans/restaurant_areas.rds")

nsa_summary <- restaurant_points |>
  st_drop_geometry() |>
  left_join(restaurant_areas, by = "business_id") |>
  group_by(area_id = neighborhood) |>
  summarise(
    number_of_restaurants  = n(),
    average_business_stars = mean(stars, na.rm = TRUE),
    .groups = "drop"
  ) |>
  arrange(desc(number_of_restaurants))
saveRDS(nsa_summary, "data/new_orleans/nsa_summary.rds")

# ---- Comparison table with all three systems --------------------------------

summarise_system <- function(summary, label) {
  matched <- summary |> filter(!is.na(area_id))
  tibble(
    geographic_system     = label,
    number_of_areas       = nrow(matched),
    restaurants_assigned  = sum(matched$number_of_restaurants),
    unmatched_restaurants = sum(summary$number_of_restaurants[is.na(summary$area_id)]),
    smallest_area_count   = min(matched$number_of_restaurants),
    largest_area_count    = max(matched$number_of_restaurants)
  )
}

geographic_comparison <- bind_rows(
  summarise_system(readRDS("data/new_orleans/zcta_summary.rds"),  "ZIP/ZCTA"),
  summarise_system(readRDS("data/new_orleans/tract_summary.rds"), "Census tract"),
  summarise_system(nsa_summary, "Neighborhood Statistical Area")
)
print(as.data.frame(geographic_comparison))
print(head(as.data.frame(nsa_summary), 12))
write.csv(geographic_comparison, "data/new_orleans/geographic_comparison.csv", row.names = FALSE)
message("Saved restaurant_areas.rds, nsa_summary.rds, geographic_comparison.csv")
