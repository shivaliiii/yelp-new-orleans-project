# Yelp New Orleans Restaurant Analysis

**Research question:** Where can someone find the best breakfast and coffee in New Orleans, and which ZIP-code area is best for finding it?

*Work in progress (through Project 2, Step 6 — Homework 6).* Reviewer-adjusted scores and the final top-10 writeup are still to come.

## Project structure

```text
yelp-new-orleans-project/
├── README.md
├── R/
│   ├── import.R            # Step 1: unzip, stream-import, filter to New Orleans, save RDS
│   ├── clean.R              # Steps 3-4: select categories, join to reviews
│   └── analysis.R           # Steps 5-6: spatial join + geographic comparison
├── data/
│   ├── raw/                # Yelp JSON files go here (not committed to GitHub)
│   └── new_orleans/        # filtered, compressed outputs
└── figures/
```

## Getting the data

The raw Yelp files are not in this repository. They are several gigabytes, which is more than GitHub allows. To reproduce the data:

1. Go to the [Yelp Open Dataset page](https://business.yelp.com/data/resources/open-dataset/), accept the terms, and download the **JSON** version (`Yelp-JSON.zip`, about 4 GB).
2. Put `Yelp-JSON.zip` in `data/raw/`. You don't need to unzip it. The script also works if you have already extracted `yelp_dataset.tar` or the two JSON files.
3. From the project folder, run:

   ```bash
   Rscript R/import.R
   ```

   Or run `source("R/import.R")` in RStudio. It needs the `jsonlite`, `dplyr` and `stringr` packages.

The script writes these files to `data/new_orleans/`:

| File | Contents |
|---|---|
| `business_new_orleans.rds` | New Orleans restaurants (`state == "LA"`, city is "New Orleans", categories include "Restaurants") |
| `reviews_new_orleans.rds` | All Yelp reviews of those restaurants, without the review text |
| `review_text_new_orleans.rds` | `review_id` and review text. Kept separate because it is large; not committed |
| `import_log.txt` | Row counts, run times and file sizes from the import |

After the RDS files are saved, you can delete the raw files. To have the script do it, set `delete_raw_files <- TRUE` at the top of `R/import.R`.

## How the large files are handled

- **Streaming import.** Both JSON files are read with `jsonlite::stream_in()` and a handler function, 100,000 records at a time. Each page is cut down to the needed columns, and the reviews are cut down to New Orleans restaurants, before the next page is read. The roughly 5 GB review file never has to fit in memory. If memory is tight, lower `page_size`.
- **Selective extraction.** Only the business and review JSON files are pulled out of the archive.
- **Compression.** Outputs are saved with `xz` compression. Review text goes in its own file so the main review table stays small.
- Streaming through all ~7 million reviews in the file to find the ones for New Orleans restaurants took about 6 minutes locally. The full `review.json` file is ~5 GB, and loading it without streaming was not attempted since it would likely exceed available memory.

## Step 3: Selected category group — Breakfast & Coffee

Of the 2,261 New Orleans restaurants, the category field was split into one row per business/category and counted. Four categories were chosen because they all describe places someone would go for a morning meal or a coffee break, directly supporting the research question above:

| Category | Restaurants |
|---|---:|
| Breakfast & Brunch | 367 |
| Coffee & Tea | 208 |
| Cafes | 173 |
| Bakeries | 81 |

**Co-occurrence** (how often two of these categories appear on the same business) confirms they form one coherent group rather than four unrelated ones:

| Category pair | Shared restaurants |
|---|---:|
| Breakfast & Brunch + Coffee & Tea | 85 |
| Cafes + Coffee & Tea | 75 |
| Breakfast & Brunch + Cafes | 65 |
| Bakeries + Coffee & Tea | 37 |
| Bakeries + Breakfast & Brunch | 32 |
| Bakeries + Cafes | 16 |

**Inclusion rule:** a restaurant qualifies if it has *at least one* of the four categories above.

**Qualifying restaurants:** 575, spanning 24 ZIP codes — well above the assignment's minimum of 10 restaurants across 7 areas.

Code: [`R/clean.R`](R/clean.R). Full category counts: [`data/new_orleans/category_counts.csv`](data/new_orleans/category_counts.csv).

## Step 4: Joining reviews

Reviews were filtered to only the 575 selected restaurants before any further analysis, rather than carrying all 476,565 New Orleans restaurant reviews forward. This left **159,552 reviews** for the breakfast & coffee group.

## Step 5: Official city boundary (spatial join)

Each restaurant's latitude/longitude was converted to a spatial point and joined (`st_within`) to the official New Orleans city boundary from `tigris::places()`. Comparing Yelp's own `city` text field to this independently-constructed boundary:

| Yelp city | Official place | Restaurants |
|---|---|---:|
| New Orleans | New Orleans | 564 |
| New Orleans | Elmwood | 2 |
| New Orleans | Harahan | 2 |
| New Orleans | Jefferson | 2 |
| New Orleans | Metairie | 2 |
| New Orleans | Terrytown | 2 |
| New Orleans | Kenner | 1 |

11 restaurants that Yelp labels `city = "New Orleans"` actually fall just outside the official city limits, in nearby Jefferson Parish towns — a postal-city vs. incorporated-city mismatch, not a data error. They're kept in the analysis since they're real, nearby options for the same question.

![Breakfast & coffee restaurants within the New Orleans boundary, colored by rating](figures/new_orleans_boundary_map.png)

## Step 6: Geographic system comparison

Two geographic systems were compared for dividing up the area:

| Geographic system | Number of areas | Restaurants assigned | Unmatched restaurants | Smallest area count | Largest area count |
|---|---:|---:|---:|---:|---:|
| ZIP/ZCTA | 24 | 575 | 0 | 1 | 143 |
| Census tract | 103 | 564 | 11 | 1 | 117 |

**Selected system: ZIP/ZCTA.** ZIP codes are immediately understandable to a general audience (unlike census tract numbers), matched every single restaurant with zero unmatched points, and — with only 24 areas instead of 103 — keep enough restaurants per area for the counts and ratings to be meaningful. Census tracts fragment the same 575 restaurants into more than four times as many areas, several with very few restaurants, which would make area-to-area comparisons noisy.

ZIP codes are not perfect either. They are postal areas, not neighborhoods, and they vary a lot in size: the smallest has only 1 qualifying restaurant while the largest has 143. ZIP codes with fewer than 5 qualifying restaurants will be shown on maps but not ranked, since one or two restaurants can't support a reliable area average.

![Breakfast & coffee restaurant counts by ZIP code](figures/zcta_restaurant_count_map.png)

One ZCTA (the French Quarter / CBD area) clearly stands out with the most breakfast & coffee options — this will be explored further in the final writeup once reviewer-adjusted scores (Step 7) are added.

Code: [`R/analysis.R`](R/analysis.R). Full comparison table: [`data/new_orleans/geographic_comparison.csv`](data/new_orleans/geographic_comparison.csv).
