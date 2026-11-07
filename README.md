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
│   ├── analysis.R           # Steps 5-6: spatial join + geographic comparison
│   └── compare_systems.R    # Step 6: area size and rating comparison plot
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

**Qualifying restaurants:** 575, spanning 25 postal ZIP codes (24 Census ZCTAs) — well above the assignment's minimum of 10 restaurants across 7 areas.

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

Two geographic systems were compared for dividing up the area: ZIP Code Tabulation Areas (ZCTAs, from `tigris::zctas()`) and census tracts (Orleans Parish, from `tigris::tracts()`). Each restaurant point was assigned to an area with `st_join(..., join = st_within)`.

| Geographic system | Number of areas | Restaurants assigned | Unmatched restaurants | Smallest area count | Largest area count |
|---|---:|---:|---:|---:|---:|
| ZIP/ZCTA | 24 | 575 | 0 | 1 | 143 |
| Census tract | 103 | 564 | 11 | 1 | 117 |

The 11 unmatched tract restaurants are the same 11 that fall just outside the city limits (Step 5). Only Orleans Parish tracts were loaded, so they have no tract to land in.

**Area size and ratings.** Averages are only shown for areas with at least 5 restaurants.

| Geographic system | Median restaurants per area | Areas with fewer than 5 restaurants | Range of area average stars |
|---|---:|---:|---:|
| ZIP/ZCTA | 6.5 | 9 of 24 (38%) | 2.30 – 4.11 |
| Census tract | 2 | 75 of 103 (73%) | 3.25 – 4.50 |

![Restaurants per area vs. average rating, ZIP/ZCTA and census tracts](figures/geographic_system_comparison.png)

**Selected system: ZIP/ZCTA.** ZIP codes are easy for a general reader to understand (unlike census tract numbers), and every restaurant was matched to one. Most importantly, they leave enough restaurants per area to compare. Census tracts split the same restaurants into 103 areas, and nearly three-quarters of them have fewer than 5 restaurants. In those tracts, one or two restaurants decide the "average," which is why tract averages swing from 1.5 to 5 stars in the plot above.

ZIP codes are not perfect either. They are postal areas, not neighborhoods, and they vary a lot in size: 9 ZIP codes have fewer than 5 qualifying restaurants (17 restaurants in total). Those ZIP codes will be shown on maps but not ranked.

![Breakfast & coffee restaurant counts by ZIP code](figures/zcta_restaurant_count_map.png)

**ZIP codes with at least 5 breakfast & coffee restaurants:**

| ZIP | Restaurants | Average business stars |
|---|---:|---:|
| 70130 | 143 | 3.76 |
| 70115 | 74 | 3.99 |
| 70116 | 62 | 3.98 |
| 70119 | 58 | 3.83 |
| 70112 | 56 | 3.66 |
| 70117 | 40 | 4.11 |
| 70118 | 38 | 3.82 |
| 70124 | 20 | 3.80 |
| 70113 | 18 | 3.94 |
| 70122 | 13 | 3.50 |
| 70125 | 13 | 3.38 |
| 70114 | 7 | 3.93 |
| 70126 | 6 | 2.67 |
| 70128 | 5 | 2.30 |
| 70131 | 5 | 3.10 |

ZIP 70130 has by far the most breakfast & coffee options (143), but not the highest average rating. Among the larger ZIP codes, 70117 (4.11) and 70115 (3.99) rate highest. Whether that holds up after adjusting for reviewer habits is the question for Step 7.

Code: [`R/analysis.R`](R/analysis.R) and [`R/compare_systems.R`](R/compare_systems.R). Tables: [`geographic_comparison.csv`](data/new_orleans/geographic_comparison.csv), [`system_ratings_comparison.csv`](data/new_orleans/system_ratings_comparison.csv), [`zcta_ratings.csv`](data/new_orleans/zcta_ratings.csv).
