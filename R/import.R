# =============================================================================
# R/import.R
# Yelp Open Dataset -> New Orleans restaurants + their reviews (compressed RDS)
#
# Run from the project root (the folder that contains README.md):
#   Rscript R/import.R
# or open the project in RStudio and source("R/import.R").
#
# Input  (put ONE of these in data/raw/):
#   - Yelp-JSON.zip                        (the file Yelp gives you), or
#   - yelp_dataset.tar                     (what is inside the zip), or
#   - yelp_academic_dataset_business.json  and
#     yelp_academic_dataset_review.json    (already extracted)
#
# Output (data/new_orleans/):
#   - business_new_orleans.rds      New Orleans restaurants (one row per business)
#   - reviews_new_orleans.rds       every review of those restaurants, no text
#   - review_text_new_orleans.rds   review_id + text (kept separate: large file)
#   - import_log.txt                row counts, timings, file sizes
#
# Design notes (for the "large-data management" section of the report):
#   * Both JSON files are read with jsonlite::stream_in() and a handler, so only
#     one page of records is in memory at a time. Each page is reduced to the
#     needed columns (and, for reviews, to New Orleans restaurants) before the
#     next page is read. The ~5 GB review file never has to fit in RAM.
#   * Only the two needed JSON files are pulled out of the tar archive.
#   * Outputs are saved with xz compression.
# =============================================================================

suppressPackageStartupMessages({
  library(jsonlite)
  library(dplyr)
  library(stringr)
})

# ---- Settings ---------------------------------------------------------------

raw_dir <- "data/raw"
out_dir <- "data/new_orleans"

# Set to TRUE to delete the raw JSON / tar / zip files after the RDS files have
# been written and successfully read back. Leave FALSE until you are sure.
delete_raw_files <- FALSE

# Records read per page. Lower it (e.g. 25000) if your computer runs out of memory.
page_size <- 1e5

business_file <- file.path(raw_dir, "yelp_academic_dataset_business.json")
review_file   <- file.path(raw_dir, "yelp_academic_dataset_review.json")

dir.create(raw_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

log_lines <- character()
log_msg <- function(...) {
  line <- paste0(format(Sys.time(), "%H:%M:%S"), "  ", paste0(...))
  message(line)
  log_lines <<- c(log_lines, line)
}
fmt <- function(x) format(x, big.mark = ",", scientific = FALSE)
mb <- function(path) sprintf("%.1f MB", file.size(path) / 1024^2)

# ---- Step 1: unzip / untar (only if the JSON files are not there yet) -------

needed_json <- basename(c(business_file, review_file))

if (!all(file.exists(c(business_file, review_file)))) {

  tar_file <- list.files(raw_dir, pattern = "\\.tar$", full.names = TRUE,
                         recursive = TRUE)[1]

  if (is.na(tar_file)) {
    zip_file <- list.files(raw_dir, pattern = "\\.zip$", full.names = TRUE)[1]
    if (is.na(zip_file)) {
      stop("No Yelp files found in ", raw_dir, ". See README.md for download steps.")
    }
    log_msg("Unzipping ", basename(zip_file), " (", mb(zip_file), ")")
    zip_members <- unzip(zip_file, list = TRUE)$Name
    tar_member  <- grep("\\.tar$", zip_members, value = TRUE)[1]
    if (is.na(tar_member)) {
      # Some copies of the zip hold the JSON files directly
      json_members <- zip_members[basename(zip_members) %in% needed_json]
      unzip(zip_file, files = json_members, exdir = raw_dir, junkpaths = TRUE)
    } else {
      unzip(zip_file, files = tar_member, exdir = raw_dir, junkpaths = TRUE)
      tar_file <- file.path(raw_dir, basename(tar_member))
    }
  }

  if (!is.na(tar_file) && file.exists(tar_file)) {
    log_msg("Extracting business + review JSON from ", basename(tar_file),
            " (", mb(tar_file), ")")
    tar_members  <- untar(tar_file, list = TRUE)
    json_members <- tar_members[basename(tar_members) %in% needed_json]
    untar(tar_file, files = json_members, exdir = raw_dir)
    # Move to data/raw/ in case the tar stores them inside a sub-folder
    for (m in json_members) {
      from <- file.path(raw_dir, m)
      to   <- file.path(raw_dir, basename(m))
      if (normalizePath(from) != normalizePath(to, mustWork = FALSE)) file.rename(from, to)
    }
  }

  if (!all(file.exists(c(business_file, review_file)))) {
    stop("Could not find both JSON files after extraction. Check ", raw_dir, ".")
  }
}

log_msg("Business JSON: ", mb(business_file), " | Review JSON: ", mb(review_file))

# Helper: keep the listed columns from a page, adding any that are missing
keep_cols <- function(df, cols) {
  for (col in setdiff(cols, names(df))) df[[col]] <- NA
  df[, cols, drop = FALSE]
}

# ---- Step 2: import businesses (streamed) -----------------------------------

business_cols <- c("business_id", "name", "address", "city", "state",
                   "postal_code", "latitude", "longitude", "stars",
                   "review_count", "categories")

t0 <- Sys.time()
business_pages <- list()
business_total <- 0

stream_in(
  file(business_file),
  handler = function(df) {
    business_total <<- business_total + nrow(df)
    df <- keep_cols(df, business_cols)
    # Keep Louisiana only at this stage; New Orleans is decided below
    business_pages[[length(business_pages) + 1]] <<- df[df$state %in% "LA", ]
  },
  pagesize = page_size,
  verbose = FALSE
)

business_la <- bind_rows(business_pages)
rm(business_pages); invisible(gc())

log_msg("Businesses read: ", fmt(business_total),
        " | in Louisiana: ", fmt(nrow(business_la)),
        " | ", round(difftime(Sys.time(), t0, units = "secs")), " s")

# ---- Step 3: filter to New Orleans restaurants ------------------------------

# How is "New Orleans" spelled in the city field? (useful for the report)
city_spellings <- business_la |>
  filter(str_detect(str_to_lower(city), "new\\s*orleans")) |>
  count(city, sort = TRUE)
message("\nCity labels containing 'New Orleans':")
print(as.data.frame(city_spellings), row.names = FALSE)

new_orleans_restaurants <- business_la |>
  filter(
    state == "LA",
    str_to_lower(str_squish(city)) == "new orleans",
    !is.na(categories),
    str_detect(categories, regex("Restaurants", ignore_case = TRUE))
  ) |>
  mutate(
    city          = str_squish(city),
    postal_code   = na_if(postal_code, ""),
    categories    = str_squish(categories),
    business_name = str_squish(name)
  ) |>
  distinct(business_id, .keep_all = TRUE)

rm(business_la); invisible(gc())

log_msg("New Orleans restaurants: ",
        fmt(nrow(new_orleans_restaurants)))

print(
  new_orleans_restaurants |>
    summarise(
      number_of_restaurants = n(),
      missing_latitude   = sum(is.na(latitude)),
      missing_longitude  = sum(is.na(longitude)),
      missing_categories = sum(is.na(categories)),
      missing_postal     = sum(is.na(postal_code))
    )
)

# ---- Step 4: import reviews for those restaurants only (streamed) -----------

review_cols <- c("review_id", "business_id", "user_id", "stars", "date",
                 "text", "useful", "funny", "cool")
nola_ids <- new_orleans_restaurants$business_id

t0 <- Sys.time()
review_pages <- list()
review_total <- 0

stream_in(
  file(review_file),
  handler = function(df) {
    review_total <<- review_total + nrow(df)
    df <- df[df$business_id %in% nola_ids, , drop = FALSE]
    if (nrow(df) > 0) {
      review_pages[[length(review_pages) + 1]] <<- keep_cols(df, review_cols)
    }
    if (review_total %% 1e6 < page_size) {
      message("  ...", fmt(review_total), " reviews scanned")
    }
  },
  pagesize = page_size,
  verbose = FALSE
)

reviews_all_cols <- bind_rows(review_pages)
rm(review_pages); invisible(gc())

log_msg("Reviews scanned: ", fmt(review_total),
        " | kept for New Orleans restaurants: ",
        fmt(nrow(reviews_all_cols)),
        " | ", round(difftime(Sys.time(), t0, units = "mins"), 1), " min")

# Split the review text off: it is most of the file size and is not needed for
# the ratings analysis. review_id links the two tables if you need the text.
new_orleans_reviews <- reviews_all_cols |> select(-text)
new_orleans_review_text <- reviews_all_cols |> select(review_id, business_id, text)
rm(reviews_all_cols); invisible(gc())

# ---- Step 5: save as compressed RDS and verify ------------------------------

out_business <- file.path(out_dir, "business_new_orleans.rds")
out_reviews  <- file.path(out_dir, "reviews_new_orleans.rds")
out_text     <- file.path(out_dir, "review_text_new_orleans.rds")

saveRDS(new_orleans_restaurants, out_business, compress = "xz")
saveRDS(new_orleans_reviews,     out_reviews,  compress = "xz")
saveRDS(new_orleans_review_text, out_text,     compress = "xz")

check_business <- readRDS(out_business)
check_reviews  <- readRDS(out_reviews)
check_text     <- readRDS(out_text)
stopifnot(
  identical(dim(check_business), dim(new_orleans_restaurants)),
  identical(dim(check_reviews),  dim(new_orleans_reviews)),
  identical(dim(check_text),     dim(new_orleans_review_text))
)

log_msg("Saved ", basename(out_business), " (", mb(out_business), "), ",
        basename(out_reviews), " (", mb(out_reviews), "), ",
        basename(out_text), " (", mb(out_text), ")")

if (file.size(out_text) > 95 * 1024^2) {
  log_msg("NOTE: ", basename(out_text), " is over GitHub's 100 MB limit; ",
          "it is listed in .gitignore and stays on your computer.")
}

message("\nglimpse(business):"); glimpse(new_orleans_restaurants)
message("\nglimpse(reviews):");  glimpse(new_orleans_reviews)

# ---- Step 6: optionally delete the raw files --------------------------------

if (delete_raw_files) {
  raw_files <- list.files(raw_dir, pattern = "\\.(json|tar|zip)$",
                          full.names = TRUE, recursive = TRUE)
  freed <- sum(file.size(raw_files)) / 1024^3
  file.remove(raw_files)
  log_msg("Deleted ", length(raw_files), " raw files, freed ",
          sprintf("%.1f GB", freed))
}

writeLines(log_lines, file.path(out_dir, "import_log.txt"))
message("\nDone. Load the data later with:\n",
        "  new_orleans_restaurants <- readRDS(\"", out_business, "\")\n",
        "  new_orleans_reviews     <- readRDS(\"", out_reviews, "\")")
