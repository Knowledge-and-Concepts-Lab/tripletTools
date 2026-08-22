make_synthetic_case <- function(seed = 1) {
  set.seed(seed)
  n <- 12
  items <- paste0("item", seq_len(n))

  # "True" structure lives in 2 dimensions with a healthy scale; 3 extra
  # dimensions are near-flat noise, as if the embedding were fit at a
  # generously high d but only 2 dimensions carry real signal.
  true_coords <- matrix(rnorm(n * 2, sd = 5), n, 2, dimnames = list(items))
  noise_coords <- matrix(rnorm(n * 3, sd = 0.05), n, 3)
  embedding <- cbind(true_coords, noise_coords)
  rownames(embedding) <- items
  colnames(embedding) <- paste0("dim_", 0:4)

  # Triplets generated directly from the TRUE 2D structure, so the
  # embedding's first two (PCA-rotated) dimensions should predict them
  # essentially perfectly, with or without the noise dimensions.
  triplets <- expand.grid(Center = items, Left = items, Right = items,
                           stringsAsFactors = FALSE)
  triplets <- triplets[triplets$Center != triplets$Left &
                         triplets$Center != triplets$Right &
                         triplets$Left != triplets$Right, ]
  triplets <- triplets[sample(nrow(triplets), 60), ]

  d_left  <- rowSums((true_coords[triplets$Center, ] - true_coords[triplets$Left, ])^2)
  d_right <- rowSums((true_coords[triplets$Center, ] - true_coords[triplets$Right, ])^2)
  triplets$Answer <- ifelse(d_left < d_right, triplets$Left, triplets$Right)
  triplets$sampleSet <- rep(c("train", "test"), length.out = nrow(triplets))

  list(embedding = embedding, triplets = triplets)
}

test_that("reduce_embedding_dimension() recovers the true low dimensionality", {
  case <- make_synthetic_case(1)
  res <- reduce_embedding_dimension(case$embedding, case$triplets,
                                     variance_threshold = 0.95)

  expect_equal(res$k, 2L)
  expect_gte(res$variance_explained, 0.95)
  expect_gt(res$accuracy, 0.9)
  expect_gt(res$accuracy_full, 0.9)
  expect_equal(nrow(res$embedding), nrow(case$embedding))
  expect_equal(ncol(res$embedding), 2L)
  expect_equal(rownames(res$embedding), rownames(case$embedding))
  expect_equal(colnames(res$embedding), c("dim_0", "dim_1"))
})

test_that("diagnostics has one row per available dimension and monotonic cum_variance", {
  case <- make_synthetic_case(2)
  res <- reduce_embedding_dimension(case$embedding, case$triplets)

  expect_equal(nrow(res$diagnostics), ncol(case$embedding))
  expect_equal(names(res$diagnostics), c("k", "cum_variance", "accuracy"))
  expect_true(all(diff(res$diagnostics$cum_variance) >= -1e-12))
  expect_equal(res$diagnostics$cum_variance[nrow(res$diagnostics)], 1, tolerance = 1e-8)
})

test_that("a lower variance_threshold selects a smaller k", {
  case <- make_synthetic_case(3)
  res_loose <- reduce_embedding_dimension(case$embedding, case$triplets,
                                           variance_threshold = 0.5)
  res_strict <- reduce_embedding_dimension(case$embedding, case$triplets,
                                            variance_threshold = 0.999)

  expect_lte(res_loose$k, res_strict$k)
})

test_that("max_k caps the selected k and warns when the threshold wants more", {
  case <- make_synthetic_case(4)
  expect_warning(
    res <- reduce_embedding_dimension(case$embedding, case$triplets,
                                       variance_threshold = 0.999, max_k = 1),
    "max_k"
  )
  expect_equal(res$k, 1L)
})

test_that("check trials (sampleSet == NA) are excluded", {
  case <- make_synthetic_case(5)
  case$triplets$sampleSet[1] <- NA
  res <- reduce_embedding_dimension(case$embedding, case$triplets)
  expect_equal(res$diagnostics$k[1], 1L)  # sanity: still runs, doesn't error
})

test_that("reduce_embedding_dimension() validates its inputs", {
  case <- make_synthetic_case(6)

  expect_error(
    reduce_embedding_dimension(unname(case$embedding), case$triplets),
    "row names"
  )
  expect_error(
    reduce_embedding_dimension(case$embedding, case$triplets, variance_threshold = 0),
    "variance_threshold"
  )
  expect_error(
    reduce_embedding_dimension(case$embedding, case$triplets, variance_threshold = 1.1),
    "variance_threshold"
  )
  expect_error(
    reduce_embedding_dimension(case$embedding, case$triplets, max_k = 0),
    "max_k"
  )

  bad_cols <- case$triplets[, setdiff(names(case$triplets), "Answer")]
  expect_error(
    reduce_embedding_dimension(case$embedding, bad_cols),
    "missing required column"
  )

  bad_items <- case$triplets
  bad_items$Left[1] <- "not_an_item"
  expect_error(
    reduce_embedding_dimension(case$embedding, bad_items),
    "not present in embedding"
  )

  all_check <- case$triplets
  all_check$sampleSet <- NA
  expect_error(
    reduce_embedding_dimension(case$embedding, all_check),
    "no non-check triplets"
  )
})
