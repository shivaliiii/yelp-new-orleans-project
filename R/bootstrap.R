# =============================================================================
# R/bootstrap.R
# How sure is the top 10? Bootstrap confidence intervals and top-10 chances.
#
# Run from the project root, after R/clean.R (uses the same rules as
# R/reviewers.R):
#   Rscript R/bootstrap.R
#
# Idea: each restaurant's adjusted score is an average of only 10 to a few
# hundred reviews. If a different set of active reviewers had happened to
# visit, the score would come out a little different. The bootstrap imitates
# that: for every ranked restaurant it draws a new sample of its reviews
# (same size, with replacement), recomputes the score, and re-ranks all
# restaurants. Doing this 2,000 times gives
#   * a 95% interval for each restaurant's score, and
#   * how often each restaurant lands in the top 10.
# Reviewer baselines are held fixed; only which reviews a restaurant got is
# resampled.
#
# Output:
#   data/new_orleans/top10_bootstrap.csv
#   figures/top10_bootstrap.png
# =============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(ggplot2)
})
source("R/theme.R")

set.seed(167)
n_boot               <- 2000
min_reviewer_reviews <- 5    # same rules as R/reviewers.R
min_eligible_reviews <- 10

selected_restaurants <- readRDS("data/new_orleans/selected_restaurants.rds")
category_reviews     <- readRDS("data/new_orleans/selected_reviews.rds")

# ---- Adjusted scores (same as R/reviewers.R) ---------------------------------

reviewer_baselines <- category_reviews |>
  group_by(user_id) |>
  summarise(reviewer_mean = mean(stars), reviewer_review_count = n(), .groups = "drop")

eligible <- category_reviews |>
  left_join(reviewer_baselines, by = "user_id") |>
  filter(reviewer_review_count >= min_reviewer_reviews) |>
  mutate(score = stars - reviewer_mean)

ranked_ids <- eligible |>
  count(business_id) |>
  filter(n >= min_eligible_reviews) |>
  pull(business_id)

scores_by_restaurant <- eligible |>
  filter(business_id %in% ranked_ids) |>
  group_by(business_id) |>
  summarise(scores = list(score), .groups = "drop")

observed <- scores_by_restaurant |>
  mutate(n_reviews = lengths(scores),
         average_normalized_score = vapply(scores, mean, numeric(1))) |>
  arrange(desc(average_normalized_score)) |>
  mutate(rank_adjusted = row_number())

top10_ids <- observed$business_id[1:10]

# ---- Bootstrap ---------------------------------------------------------------

# One row per restaurant, one column per bootstrap sample
boot_scores <- t(vapply(
  observed$scores,
  function(s) colMeans(matrix(sample(s, length(s) * n_boot, replace = TRUE), nrow = length(s))),
  numeric(n_boot)
))

# Rank within each bootstrap sample (1 = best)
boot_ranks <- apply(-boot_scores, 2, rank, ties.method = "first")

bootstrap_summary <- observed |>
  select(business_id, n_reviews, average_normalized_score, rank_adjusted) |>
  mutate(
    ci_low        = apply(boot_scores, 1, quantile, 0.025),
    ci_high       = apply(boot_scores, 1, quantile, 0.975),
    pct_in_top10  = round(100 * rowMeans(boot_ranks <= 10)),
    rank_low      = apply(boot_ranks, 1, quantile, 0.025),
    rank_high     = apply(boot_ranks, 1, quantile, 0.975)
  ) |>
  left_join(selected_restaurants |> select(business_id, business_name), by = "business_id")

top10_boot <- bootstrap_summary |>
  filter(business_id %in% top10_ids) |>
  arrange(rank_adjusted)

# Restaurants outside the top 10 that still make it often
challengers <- bootstrap_summary |>
  filter(!business_id %in% top10_ids) |>
  arrange(desc(pct_in_top10)) |>
  slice_head(n = 3)

write.csv(
  bind_rows(top10_boot, challengers) |>
    transmute(rank_adjusted, business_name, n_reviews,
              adjusted_score = round(average_normalized_score, 2),
              ci_low = round(ci_low, 2), ci_high = round(ci_high, 2),
              pct_in_top10, rank_low = round(rank_low), rank_high = round(rank_high)),
  "data/new_orleans/top10_bootstrap.csv", row.names = FALSE
)

# ---- Does the area answer hold up? -------------------------------------------

zip_of <- selected_restaurants$postal_code[match(observed$business_id, selected_restaurants$business_id)]
top10_zips <- apply(boot_ranks, 2, function(r) zip_of[r <= 10])

area_check <- tibble(
  check = c("Mid-City (70119) + Bywater & Marigny (70117) hold at least half of the top 10",
            "70119 has the most top-10 spots (ties included)",
            "70117 has the most top-10 spots (ties included)",
            "Downtown 70130 has the most top-10 spots (ties included)"),
  pct_of_resamples = round(100 * c(
    mean(apply(top10_zips, 2, function(z) sum(z %in% c("70119", "70117")) >= 5)),
    mean(apply(top10_zips, 2, function(z) { t <- table(z); "70119" %in% names(t)[t == max(t)] })),
    mean(apply(top10_zips, 2, function(z) { t <- table(z); "70117" %in% names(t)[t == max(t)] })),
    mean(apply(top10_zips, 2, function(z) { t <- table(z); "70130" %in% names(t)[t == max(t)] }))
  ))
)
write.csv(area_check, "data/new_orleans/area_bootstrap.csv", row.names = FALSE)
print(as.data.frame(area_check))

# ---- Chart -------------------------------------------------------------------

plot_data <- top10_boot |>
  mutate(
    label = paste0(rank_adjusted, ".  ", business_name),
    label = reorder(label, -rank_adjusted),
    sure  = pct_in_top10 >= 50
  )

tenth_score <- observed$average_normalized_score[10]

p_boot <- ggplot(plot_data, aes(y = label)) +
  geom_vline(xintercept = 0, color = theme_cols$muted, linewidth = 0.5) +
  geom_vline(xintercept = tenth_score, color = theme_cols$muted, linetype = "dashed", linewidth = 0.5) +
  geom_segment(aes(x = ci_low, xend = ci_high, yend = label, color = sure),
               linewidth = 4.2, lineend = "round", alpha = 0.55) +
  geom_point(aes(x = average_normalized_score, fill = sure), shape = 21, size = 5.6,
             color = "white", stroke = 1.2) +
  geom_text(aes(x = 1.75, label = paste0(pct_in_top10, "%")), hjust = 1,
            family = plot_family, fontface = "bold", color = theme_cols$ink, size = 4) +
  geom_text(aes(x = ci_low, label = paste0(n_reviews, " reviews")), hjust = 1.12,
            family = plot_family, color = theme_cols$muted, size = 3.1) +
  annotate("text", x = tenth_score, y = 10.7, label = "10th place", hjust = 1.08,
           family = plot_family, color = theme_cols$muted, size = 3.3) +
  annotate("text", x = 1.75, y = 10.7, hjust = 1, label = "in top 10",
           family = plot_family, fontface = "bold", color = theme_cols$ink, size = 3.5) +
  scale_color_manual(values = c(`TRUE` = theme_cols$above[["fill"]], `FALSE` = theme_cols$zcta[["fill"]]),
                     guide = "none") +
  scale_fill_manual(values = c(`TRUE` = theme_cols$above[["deep"]], `FALSE` = theme_cols$zcta[["deep"]]),
                    guide = "none") +
  scale_x_continuous(limits = c(-0.45, 1.75), breaks = seq(-0.2, 1.4, 0.2),
                     labels = function(x) ifelse(abs(x) < 1e-9, "0", sprintf("%+.1f", x))) +
  coord_cartesian(clip = "off") +
  labs(
    title = "How sure is each top-10 spot?",
    subtitle = paste0("Bars: 95% bootstrap interval for the adjusted score (", format(n_boot, big.mark = ","),
                      " resamples). Right: share of resamples in the top 10.\n",
                      "Green = in the top 10 more often than not. Review counts are reviews from active reviewers"),
    x = "reviewer-adjusted score", y = NULL
  ) +
  theme_pastel() +
  theme(panel.grid.major.y = element_blank(),
        axis.text.y = element_text(color = theme_cols$ink, size = 12, face = "bold",
                                   margin = margin(r = 6)))

save_plot(p_boot, "figures/top10_bootstrap.png", width = 10, height = 7)

print(as.data.frame(read.csv("data/new_orleans/top10_bootstrap.csv")))
message("Saved figures/top10_bootstrap.png and data/new_orleans/top10_bootstrap.csv")
