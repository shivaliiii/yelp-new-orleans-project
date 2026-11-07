# =============================================================================
# R/reviewers.R
# Step 7: ratings from all reviewers vs. reviewer-adjusted scores
#
# Run from the project root, after R/clean.R:
#   Rscript R/reviewers.R
#
# Idea: some reviewers give almost everything 5 stars, others rarely do.
# For each reviewer we compute their usual (baseline) rating across the
# breakfast & coffee restaurants they reviewed, and subtract it from each of
# their ratings. A normalized score of +0.6 means "this reviewer rated this
# place 0.6 stars above what they usually give". It is NOT a new Yelp rating.
# =============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(lubridate)
  library(ggplot2)
  library(ggrepel)
})
source("R/theme.R")

min_reviewer_reviews   <- 5    # a reviewer needs this many reviews to get a baseline
min_eligible_reviews   <- 10   # a restaurant needs this many eligible reviews to be ranked
thresholds_to_test     <- c(3, 5, 10)

selected_restaurants <- readRDS("data/new_orleans/selected_restaurants.rds")
category_reviews <- readRDS("data/new_orleans/selected_reviews.rds") |>
  mutate(review_date = ymd_hms(date), review_year = year(review_date))

# ---- All reviewers -----------------------------------------------------------

all_reviewer_summary <- category_reviews |>
  group_by(business_id) |>
  summarise(
    number_of_reviews_all_reviewers = n(),
    average_stars_all_reviewers     = mean(stars, na.rm = TRUE),
    median_stars_all_reviewers      = median(stars, na.rm = TRUE),
    .groups = "drop"
  )

# ---- Reviewer activity and baselines -------------------------------------------

reviewer_baselines <- category_reviews |>
  group_by(user_id) |>
  summarise(
    reviewer_mean         = mean(stars, na.rm = TRUE),
    reviewer_median       = median(stars, na.rm = TRUE),
    reviewer_review_count = n(),
    .groups = "drop"
  )

category_reviews_adjusted <- category_reviews |>
  left_join(reviewer_baselines, by = "user_id") |>
  mutate(
    normalized_mean_score   = stars - reviewer_mean,
    normalized_median_score = stars - reviewer_median
  )

# How many reviewers and reviews survive each activity threshold?
threshold_table <- tibble(min_reviews = thresholds_to_test) |>
  rowwise() |>
  mutate(
    reviewers_kept     = sum(reviewer_baselines$reviewer_review_count >= min_reviews),
    pct_of_reviewers   = round(100 * reviewers_kept / nrow(reviewer_baselines), 1),
    reviews_kept       = sum(category_reviews_adjusted$reviewer_review_count >= min_reviews),
    pct_of_reviews     = round(100 * reviews_kept / nrow(category_reviews_adjusted), 1),
    restaurants_ranked = category_reviews_adjusted |>
      filter(reviewer_review_count >= min_reviews) |>
      count(business_id) |>
      filter(n >= min_eligible_reviews) |>
      nrow()
  ) |>
  ungroup()

# Why the mean baseline: with whole-star ratings, the median baseline gives a
# normalized score of exactly 0 for a large share of reviews.
eligible_adjusted_reviews <- category_reviews_adjusted |>
  filter(reviewer_review_count >= min_reviewer_reviews)

baseline_check <- tibble(
  share_zero_with_median_baseline = round(mean(eligible_adjusted_reviews$normalized_median_score == 0), 3),
  share_zero_with_mean_baseline   = round(mean(abs(eligible_adjusted_reviews$normalized_mean_score) < 1e-9), 3),
  typical_reviewer_mean           = round(median(reviewer_baselines$reviewer_mean[reviewer_baselines$reviewer_review_count >= min_reviewer_reviews]), 2),
  reviewer_mean_5th_percentile    = round(quantile(reviewer_baselines$reviewer_mean[reviewer_baselines$reviewer_review_count >= min_reviewer_reviews], 0.05), 2),
  reviewer_mean_95th_percentile   = round(quantile(reviewer_baselines$reviewer_mean[reviewer_baselines$reviewer_review_count >= min_reviewer_reviews], 0.95), 2)
)

# ---- Restaurant-level comparison ---------------------------------------------

adjusted_summary <- eligible_adjusted_reviews |>
  group_by(business_id) |>
  summarise(
    number_of_reviews_eligible_reviewers = n(),
    average_stars_eligible_reviewers     = mean(stars, na.rm = TRUE),
    average_normalized_score             = mean(normalized_mean_score, na.rm = TRUE),
    median_normalized_score              = median(normalized_mean_score, na.rm = TRUE),
    average_normalized_median_score      = mean(normalized_median_score, na.rm = TRUE),
    .groups = "drop"
  )

restaurant_summary <- selected_restaurants |>
  select(business_id, business_name, address, postal_code, latitude, longitude,
         yelp_stars = stars, categories) |>
  left_join(all_reviewer_summary, by = "business_id") |>
  left_join(adjusted_summary, by = "business_id") |>
  arrange(desc(average_normalized_score))

ranked <- restaurant_summary |>
  filter(number_of_reviews_eligible_reviewers >= min_eligible_reviews) |>
  mutate(
    rank_all_reviewers = min_rank(desc(average_stars_all_reviewers)),
    rank_adjusted      = min_rank(desc(average_normalized_score)),
    rank_change        = rank_all_reviewers - rank_adjusted   # positive = moves up
  )

# ---- Top 10 ------------------------------------------------------------------

top10 <- ranked |>
  arrange(desc(average_normalized_score)) |>
  slice_head(n = 10) |>
  mutate(top_rank = row_number())

# Robustness: does the top 10 change with other choices?
top10_with <- function(min_rev, min_elig, score = "average_normalized_score") {
  category_reviews_adjusted |>
    filter(reviewer_review_count >= min_rev) |>
    group_by(business_id) |>
    summarise(n = n(),
              average_normalized_score = mean(normalized_mean_score),
              average_normalized_median_score = mean(normalized_median_score),
              .groups = "drop") |>
    filter(n >= min_elig) |>
    arrange(desc(.data[[score]])) |>
    slice_head(n = 10) |>
    pull(business_id)
}
robustness <- tibble(
  version = c("Reviewers with 3+ reviews", "Reviewers with 10+ reviews",
              "Restaurants need 20+ eligible reviews", "Median baseline instead of mean",
              "Plain average stars (all reviewers)"),
  ids = list(top10_with(3, min_eligible_reviews), top10_with(10, min_eligible_reviews),
             top10_with(min_reviewer_reviews, 20),
             top10_with(min_reviewer_reviews, min_eligible_reviews, "average_normalized_median_score"),
             ranked |> arrange(desc(average_stars_all_reviewers)) |> slice_head(n = 10) |> pull(business_id))
) |>
  mutate(top10_restaurants_kept = sapply(ids, function(x) sum(x %in% top10$business_id))) |>
  select(-ids)

# Biggest movers among ranked restaurants
movers <- bind_rows(
  ranked |> arrange(desc(rank_change)) |> slice_head(n = 5) |> mutate(direction = "up"),
  ranked |> arrange(rank_change) |> slice_head(n = 5) |> mutate(direction = "down")
) |>
  select(direction, business_name, postal_code, number_of_reviews_all_reviewers,
         average_stars_all_reviewers, number_of_reviews_eligible_reviewers,
         average_stars_eligible_reviewers, average_normalized_score,
         rank_all_reviewers, rank_adjusted, rank_change)

# ---- Save --------------------------------------------------------------------

saveRDS(restaurant_summary, "data/new_orleans/restaurant_summary.rds")
write.csv(threshold_table, "data/new_orleans/reviewer_thresholds.csv", row.names = FALSE)
write.csv(baseline_check, "data/new_orleans/baseline_check.csv", row.names = FALSE)
write.csv(robustness, "data/new_orleans/top10_robustness.csv", row.names = FALSE)
write.csv(movers |> mutate(across(where(is.double), ~ round(.x, 2))),
          "data/new_orleans/rank_movers.csv", row.names = FALSE)
write.csv(top10 |>
            transmute(top_rank, business_name, address, postal_code,
                      reviews_all = number_of_reviews_all_reviewers,
                      avg_stars_all = round(average_stars_all_reviewers, 2),
                      reviews_eligible = number_of_reviews_eligible_reviewers,
                      avg_stars_eligible = round(average_stars_eligible_reviewers, 2),
                      avg_normalized_score = round(average_normalized_score, 2),
                      rank_all_reviewers),
          "data/new_orleans/top10_restaurants.csv", row.names = FALSE)
saveRDS(top10, "data/new_orleans/top10.rds")
saveRDS(ranked, "data/new_orleans/ranked_restaurants.rds")

print(threshold_table); print(baseline_check); print(robustness)
print(as.data.frame(movers |> mutate(across(where(is.double), ~ round(.x, 2)))))
print(as.data.frame(top10 |> select(top_rank, business_name, postal_code,
                                    number_of_reviews_all_reviewers, average_stars_all_reviewers,
                                    number_of_reviews_eligible_reviewers, average_normalized_score,
                                    rank_all_reviewers)))

# ---- Plot: raw vs. adjusted --------------------------------------------------

mover_names <- c(movers$business_name[movers$direction == "up"][1:2],
                 movers$business_name[movers$direction == "down"][1:2])
plot_data <- ranked |>
  mutate(group = case_when(
    business_id %in% top10$business_id ~ "top10",
    business_name %in% mover_names     ~ "mover",
    TRUE                               ~ "other"
  ))
top_labels   <- plot_data |> filter(group == "top10") |>
  left_join(top10 |> select(business_id, top_rank), by = "business_id")
mover_labels <- plot_data |> filter(group == "mover")

p_adjusted <- ggplot(plot_data, aes(average_stars_all_reviewers, average_normalized_score)) +
  geom_hline(yintercept = 0, linetype = "22", color = theme_cols$ink, linewidth = 0.5) +
  geom_point(data = filter(plot_data, group == "other"), shape = 21, size = 2.6,
             fill = theme_cols$tract[["fill"]], color = "white", stroke = 0.4) +
  geom_point(data = mover_labels, shape = 21, size = 3.6,
             fill = theme_cols$below[["deep"]], color = "white", stroke = 0.8) +
  geom_point(data = top_labels, shape = 21, size = 4.2,
             fill = theme_cols$zcta[["deep"]], color = "white", stroke = 0.8) +
  geom_text_repel(data = top_labels, aes(label = top_rank), family = plot_family,
                  fontface = "bold", color = theme_cols$ink, size = 3.4,
                  min.segment.length = 0.2, segment.color = theme_cols$muted,
                  box.padding = 0.25, point.padding = 0.15, max.overlaps = Inf, seed = 167) +
  geom_label_repel(data = mover_labels,
                   aes(label = paste0(business_name, "\n", rank_all_reviewers, "th \u2192 ", rank_adjusted, "th")),
                   family = plot_family, color = theme_cols$ink, size = 3.2, label.size = 0,
                   fill = alpha("white", 0.85), lineheight = 0.95, min.segment.length = 0,
                   segment.color = theme_cols$muted, box.padding = 0.6, nudge_y = 0.25, seed = 167) +
  annotate("text", x = 1.15, y = 0.85, hjust = 0, label = "rated higher than\nreviewers usually rate",
           family = plot_family, color = theme_cols$muted, size = 3.4, lineheight = 0.9) +
  annotate("text", x = 1.15, y = -1.5, hjust = 0, label = "rated lower than\nreviewers usually rate",
           family = plot_family, color = theme_cols$muted, size = 3.4, lineheight = 0.9) +
  scale_x_continuous(limits = c(1.1, 5), breaks = 1:5) +
  labs(
    title = "Adjusting for reviewer habits mostly agrees with Yelp",
    subtitle = paste0(nrow(ranked), " restaurants with ", min_eligible_reviews,
                      "+ reviews from active reviewers. Orange = top 10, pink = biggest rank changes"),
    x = "average stars from all reviewers",
    y = "average normalized score"
  ) +
  theme_pastel()

save_plot(p_adjusted, "figures/raw_vs_adjusted.png", width = 10, height = 6.6)
message("Saved Step 7 tables in data/new_orleans/ and figures/raw_vs_adjusted.png")
