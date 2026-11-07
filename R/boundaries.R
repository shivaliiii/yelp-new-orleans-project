# =============================================================================
# R/boundaries.R
# Saves small copies of the boundary shapes used in the maps, so the maps can
# be redrawn without downloading Census files every time.
#
#   data/boundaries/zcta_new_orleans.geojson     2010 ZIP Code Tabulation Areas
#                                                 around New Orleans (same
#                                                 vintage as R/analysis.R)
#   data/boundaries/nsa_new_orleans.geojson      Neighborhood Statistical Areas
#                                                 (City of New Orleans planning
#                                                 neighbourhoods); their union is
#                                                 the city outline
#
# Run from the project root (needs internet the first time):
#   Rscript R/boundaries.R
#
# Sources: ZCTAs are the 2010 Census TIGER/Line shapes (the committed copy was
# built from the OpenDataDE GitHub mirror of that file; tigris gives the same
# shapes). Neighborhood Statistical Areas come from the City of New Orleans
# (Data.NOLA.gov), read here from the blackmad/neighborhoods GitHub mirror.
# =============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(sf)
  library(tigris)
  library(stringr)
})
options(tigris_use_cache = TRUE)
sf_use_s2(FALSE)
dir.create("data/boundaries", recursive = TRUE, showWarnings = FALSE)

study_box <- st_as_sfc(st_bbox(c(xmin = -90.30, ymin = 29.85, xmax = -89.60, ymax = 30.20),
                               crs = st_crs(4326)))

zctas <- tigris::zctas(state = "LA", cb = FALSE, year = 2010, class = "sf") |>
  st_transform(4326) |>
  select(area_id = ZCTA5CE10)
zctas <- zctas[lengths(st_intersects(zctas, study_box)) > 0, ] |>
  st_simplify(dTolerance = 0.0002, preserveTopology = TRUE)

nsa_url <- "https://raw.githubusercontent.com/blackmad/neighborhoods/master/new-orleans.geojson"
nsa <- st_read(nsa_url, quiet = TRUE) |>
  st_make_valid() |>
  st_transform(4326) |>
  transmute(neighborhood = str_squish(name))

st_write(zctas, "data/boundaries/zcta_new_orleans.geojson", delete_dsn = TRUE, quiet = TRUE)
st_write(nsa, "data/boundaries/nsa_new_orleans.geojson", delete_dsn = TRUE, quiet = TRUE)
message("Saved data/boundaries/zcta_new_orleans.geojson and nsa_new_orleans.geojson")
