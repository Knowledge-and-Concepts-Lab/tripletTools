## code to prepare `animal_triplet_embedding` and `animal_adjacency_matrix`
## datasets: a 6D triplet-based embedding of 213 animal words, alongside a
## verbal-fluency co-occurrence graph over a broader 295-word vocabulary
## (which contains all 213 triplet-embedded animals plus 82 additional
## words -- superordinate terms, synonyms, and other species that appeared
## in fluency lists but weren't part of the curated triplet stimulus set).
##
## Bundled as example data for an upcoming vignette section on estimating
## similarity from verbal-fluency data via successor_matrix() +
## hellinger_dist(), and comparing the resulting distances to a
## triplet-based embedding of the same items.

adj_raw  <- read.csv("data-raw/animals_min5_adjacency_matrix.csv",
                      check.names = FALSE, row.names = 1)
trip_raw <- read.csv("data-raw/animals_min5_triplet_embedding.csv",
                      stringsAsFactors = FALSE)

animal_adjacency_matrix <- as.matrix(adj_raw)

stopifnot(
  identical(rownames(animal_adjacency_matrix), colnames(animal_adjacency_matrix)),
  !anyNA(animal_adjacency_matrix),
  all(trip_raw$item %in% rownames(animal_adjacency_matrix)),
  !anyDuplicated(trip_raw$item),
  !anyNA(trip_raw)
)

animal_triplet_embedding <- trip_raw[, grepl("^dim_", names(trip_raw))]
row.names(animal_triplet_embedding) <- trip_raw$item

usethis::use_data(animal_adjacency_matrix, overwrite = TRUE)
usethis::use_data(animal_triplet_embedding, overwrite = TRUE)
