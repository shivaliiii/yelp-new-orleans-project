# =============================================================================
# R/maps.R
# All maps in the README, plus the ZIP-level reviewer-adjusted summary.
#
#   figures/new_orleans_boundary_map.png   Step 5: restaurants inside the city
#   figures/zcta_restaurant_count_map.png  Step 6: restaurants per ZIP code
#   figures/top10_map.png                  Final answer: top 10 + ZIP scores
#
# Run from the project root, after R/boundaries.R, R/neighborhoods.R and
# R/reviewers.R:
#   Rscript R/maps.R
# =============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(sf)
  library(ggplot2)
  library(ggrepel)
})
source("R/theme.R")
sf_use_s2(FALSE)

min_ranked_per_zip <- 10   # ZIPs need this many ranked restaurants to get a score

zcta <- st_read("data/boundaries/zcta_new_orleans.geojson", quiet = TRUE)
nsa  <- st_read("data/boundaries/nsa_new_orleans.geojson", quiet = TRUE)
city <- st_union(nsa) |> st_sf()             # NSAs tile the whole city

selected_restaurants <- readRDS("data/new_orleans/selected_restaurants.rds")
restaurant_areas     <- readRDS("data/new_orleans/restaurant_areas.rds")
ranked               <- readRDS("data/new_orleans/ranked_restaurants.rds") |>
  left_join(restaurant_areas, by = "business_id")
top10                <- readRDS("data/new_orleans/top10.rds") |>
  left_join(restaurant_areas, by = "business_id")

points <- selected_restaurants |>
  st_as_sf(coords = c("longitude", "latitude"), crs = 4326, remove = FALSE)
points_in_city <- points[lengths(st_within(points, city)) > 0, ]

zcta_city <- st_intersection(zcta, city)     # ZIP shapes clipped to the city
zip_centers <- st_point_on_surface(zcta_city)

map_theme <- theme_pastel() +
  theme(axis.text = element_blank(), axis.text.x = element_blank(), axis.text.y = element_blank(),
        axis.title = element_blank(),
        panel.grid.major = element_blank(), legend.position = "right",
        legend.title = element_text(color = theme_cols$ink, size = 11),
        legend.text = element_text(color = theme_cols$muted))

# ---- ZIP-level reviewer-adjusted summary -------------------------------------

zip_adjusted <- ranked |>
  group_by(zip) |>
  summarise(
    ranked_restaurants       = n(),
    pct_above_usual          = round(100 * mean(average_normalized_score > 0)),
    in_top_10                = sum(business_id %in% top10$business_id),
    in_top_50                = sum(rank_adjusted <= 50),
    average_stars_all        = mean(average_stars_all_reviewers),
    average_normalized_score = mean(average_normalized_score),
    .groups = "drop"
  ) |>
  arrange(desc(average_normalized_score))
write.csv(zip_adjusted |> mutate(across(c(average_stars_all, average_normalized_score), ~ round(.x, 2))),
          "data/new_orleans/zip_adjusted_scores.csv", row.names = FALSE)
print(as.data.frame(zip_adjusted))

# ---- Map 1: restaurants inside the city boundary (Step 5) --------------------

p_boundary <- ggplot() +
  geom_sf(data = city, fill = "#FBF8F5", color = theme_cols$ink, linewidth = 0.4) +
  geom_sf(data = points_in_city |> arrange(stars), aes(fill = stars),
          shape = 21, color = "white", stroke = 0.3, size = 2.4) +
  scale_fill_gradient(low = "#F8D3B3", high = "#9A3F12", limits = c(1, 5),
                      name = "Yelp stars") +
  coord_sf(xlim = c(-90.14, -89.90), ylim = c(29.90, 30.06), expand = FALSE) +
  labs(title = "Breakfast & coffee spots cluster along the river",
       subtitle = paste0(nrow(points_in_city), " restaurants inside the official city boundary, ",
                         "coloured by Yelp stars")) +
  map_theme

save_plot(p_boundary, "figures/new_orleans_boundary_map.png", width = 10, height = 6.6)

# ---- Map 2: restaurants per ZIP code (Step 6) --------------------------------

zip_counts <- readRDS("data/new_orleans/zcta_summary.rds")
zcta_count_map <- zcta_city |> left_join(zip_counts, by = "area_id")
count_labels <- zip_centers |>
  left_join(zip_counts, by = "area_id") |>
  filter(number_of_restaurants >= 10)

p_zcta <- ggplot() +
  geom_sf(data = zcta_count_map, aes(fill = number_of_restaurants), color = "white", linewidth = 0.5) +
  geom_sf(data = city, fill = NA, color = theme_cols$ink, linewidth = 0.4) +
  geom_sf_text(data = count_labels, aes(label = paste0(area_id, "\n", number_of_restaurants)),
               family = plot_family, size = 3, color = theme_cols$ink, lineheight = 0.9,
               fontface = "bold") +
  scale_fill_gradient(low = "#FFF1E5", high = "#D9844F", na.value = "#F4F1EE",
                      name = "Breakfast &\ncoffee spots") +
  coord_sf(xlim = c(-90.14, -89.90), ylim = c(29.90, 30.06), expand = FALSE) +
  labs(title = "One downtown ZIP code has a quarter of all spots",
       subtitle = "Breakfast & coffee restaurants per ZIP code (labels for ZIPs with 10 or more)") +
  map_theme

save_plot(p_zcta, "figures/zcta_restaurant_count_map.png", width = 10, height = 6.6)

# ---- Map 3: the answer - top 10 and ZIP-level adjusted scores ----------------

zip_score_map <- zcta_city |>
  left_join(zip_adjusted, by = c("area_id" = "zip")) |>
  mutate(score = ifelse(ranked_restaurants >= min_ranked_per_zip, average_normalized_score, NA))

score_labels <- zip_centers |>
  left_join(zip_adjusted, by = c("area_id" = "zip")) |>
  filter(ranked_restaurants >= min_ranked_per_zip)

top10_points <- top10 |>
  st_as_sf(coords = c("longitude", "latitude"), crs = 4326, remove = FALSE)

view <- list(x = c(-90.135, -90.02), y = c(29.915, 30.03))

p_top10 <- ggplot() +
  geom_sf(data = zip_score_map, aes(fill = score), color = "white", linewidth = 0.6) +
  geom_sf(data = city, fill = NA, color = theme_cols$ink, linewidth = 0.4) +
  geom_sf(data = points_in_city, shape = 16, size = 0.9, color = alpha(theme_cols$ink, 0.25)) +
  geom_sf_text(data = score_labels, aes(label = area_id), family = plot_family,
               size = 3, color = alpha(theme_cols$ink, 0.55), fontface = "bold",
               nudge_y = -0.004) +
  geom_sf(data = top10_points, shape = 21, size = 6.5, fill = theme_cols$zcta[["deep"]],
          color = "white", stroke = 1.1) +
  geom_sf_text(data = top10_points, aes(label = top_rank), family = plot_family,
               size = 3.1, color = "white", fontface = "bold") +
  geom_label_repel(data = top10, aes(longitude, latitude, label = business_name),
                   family = plot_family, size = 3.2, color = theme_cols$ink,
                   fill = alpha("white", 0.9), label.size = 0, label.padding = 0.18,
                   box.padding = 0.7, point.padding = 0.6, min.segment.length = 0,
                   segment.color = theme_cols$muted, max.overlaps = Inf, seed = 10) +
  scale_fill_gradient2(low = theme_cols$below[["deep"]], mid = "#F2EEEA",
                       high = theme_cols$above[["deep"]], midpoint = 0,
                       limits = c(-0.25, 0.25), oob = scales::squish, na.value = "#FAF8F6",
                       name = "ZIP average\nnormalized score",
                       breaks = c(-0.2, 0, 0.2), labels = c("-0.2 (below usual)", "0", "+0.2 (above usual)")) +
  coord_sf(xlim = view$x, ylim = view$y, expand = FALSE) +
  labs(title = "The top 10 breakfast & coffee spots",
       subtitle = paste0("ZIP colour = average reviewer-adjusted score (ZIPs with ", min_ranked_per_zip,
                         "+ ranked restaurants). Grey dots = all other spots")) +
  map_theme

save_plot(p_top10, "figures/top10_map.png", width = 11, height = 8.4)
message("Saved figures/new_orleans_boundary_map.png, zcta_restaurant_count_map.png, top10_map.png")
