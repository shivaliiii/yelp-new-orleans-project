# =============================================================================
# R/clean.R
# Step 3: select a related category group (breakfast & coffee)
# Step 4: join businesses to reviews for just that category group
#
# Run from the project root, after R/import.R:
#   Rscript R/clean.R
# =============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(stringr)
  library(tidyr)
})

business <- readRDS("data/new_orleans/business_new_orleans.rds")
reviews  <- readRDS("data/new_orleans/reviews_new_orleans.rds")

dir.create("data/new_orleans", showWarnings = FALSE, recursive = TRUE)

# ---- Step 3: category selection --------------------------------------------

# One row per business-category combination, cleaned up.
restaurant_categories <- business |>
  select(business_id, categories) |>
  separate_rows(categories, sep = ",") |>
  mutate(category = str_squish(categories)) |>
  select(business_id, category)

category_counts <- restaurant_categories |>
  count(category, sort = TRUE)

write.csv(category_counts, "data/new_orleans/category_counts.csv", row.names = FALSE)

# Theme: breakfast & coffee. These four categories are all places New Orleans
# residents/visitors go for a morning meal or a coffee break, so they support
# one focused question: "Where can someone find the best breakfast and coffee
# in New Orleans, and which area is best for finding it?"
selected_categories <- c("Breakfast & Brunch", "Coffee & Tea", "Cafes", "Bakeries")

# Co-occurrence among the selected categories (how often they overlap on the
# same business) -- evidence that they form one coherent group rather than
# four unrelated ones.
category_pairs <- restaurant_categories |>
  filter(category %in% selected_categories) |>
  inner_join(
    restaurant_categories |> filter(category %in% selected_categories),
    by = "business_id",
    relationship = "many-to-many"
  ) |>
  filter(category.x < category.y) |>
  count(category.x, category.y, sort = TRUE)

message("Category counts for the selected group:")
print(category_counts |> filter(category %in% selected_categories))
message("\nCo-occurrence between selected categories:")
print(category_pairs)

# Inclusion rule: a restaurant qualifies if it has AT LEAST ONE of the four
# selected categories.
selected_restaurant_ids <- restaurant_categories |>
  filter(category %in% selected_categories) |>
  distinct(business_id) |>
  pull(business_id)

selected_restaurants <- business |>
  filter(business_id %in% selected_restaurant_ids)

n_areas <- n_distinct(selected_restaurants$postal_code, na.rm = TRUE)

message(
  "\nQualifying restaurants: ", nrow(selected_restaurants),
  " across ", n_areas, " ZIP codes (requirement: >= 10 restaurants, >= 7 areas)"
)
stopifnot(nrow(selected_restaurants) >= 10, n_areas >= 7)

saveRDS(selected_restaurants, "data/new_orleans/selected_restaurants.rds")

# ---- Step 4: join reviews to the selected restaurants only -----------------

selected_reviews <- reviews |>
  semi_join(selected_restaurants, by = "business_id")

message(
  "\nReviews for selected (breakfast & coffee) restaurants: ",
  nrow(selected_reviews), " out of ", nrow(reviews), " total New Orleans reviews"
)

saveRDS(selected_reviews, "data/new_orleans/selected_reviews.rds")

message("\nSaved data/new_orleans/selected_restaurants.rds, selected_reviews.rds, category_counts.csv")
