test_that("find_discriminating_triplets() returns expected structure", {
  set.seed(2)
  n <- 20
  emb_a <- matrix(rnorm(n * 3), n, 3, dimnames = list(paste0("item", 1:n)))
  emb_b <- matrix(rnorm(n * 3), n, 3, dimnames = list(paste0("item", 1:n)))

  res <- find_discriminating_triplets(emb_a, emb_b, k = 8, n_candidates = 5000, seed = 3)

  expect_s3_class(res, "data.frame")
  expect_equal(nrow(res), 8L)
  expect_true(all(c("head", "option1", "option2", "embedding1_predicts",
                     "embedding2_predicts", "p_embedding1", "p_embedding2",
                     "discrepancy") %in% names(res)))
  expect_true(all(res$discrepancy > 0))
  expect_true(is.unsorted(-res$discrepancy) == FALSE)  # sorted descending
  expect_true(all(res$p_embedding1 >= 0 & res$p_embedding1 <= 1))
})

test_that("identical embeddings yield zero discriminating triplets", {
  set.seed(1)
  n <- 15
  emb <- matrix(rnorm(n * 3), n, 3, dimnames = list(paste0("item", 1:n)))

  expect_warning(
    res <- find_discriminating_triplets(emb, emb, k = 5, n_candidates = 3000, seed = 1),
    "Only found 0"
  )
  expect_equal(nrow(res), 0L)
})

test_that("a single relocated item dominates the results without a cap", {
  set.seed(1)
  n <- 20
  emb1 <- matrix(rnorm(n * 3), n, 3, dimnames = list(paste0("item", 1:n)))
  emb2 <- emb1
  emb2["item1", ] <- emb2["item1", ] + 10

  res <- find_discriminating_triplets(emb1, emb2, k = 5, n_candidates = 5000, seed = 1)
  expect_true(all(res$head == "item1" | res$option1 == "item1" | res$option2 == "item1"))
})

test_that("max_per_item caps usage and never pads with zero-discrepancy filler", {
  set.seed(1)
  n <- 20
  emb1 <- matrix(rnorm(n * 3), n, 3, dimnames = list(paste0("item", 1:n)))
  emb2 <- emb1
  emb2["item1", ] <- emb2["item1", ] + 10

  expect_warning(
    res <- find_discriminating_triplets(emb1, emb2, k = 5, n_candidates = 5000,
                                         seed = 1, max_per_item = 2),
    "Only found"
  )

  item_counts <- table(c(res$head, res$option1, res$option2))
  expect_true(all(item_counts <= 2))
  expect_true(all(res$discrepancy > 0))
  # Only item1-involving triplets have any discrepancy in this synthetic
  # setup, so capping item1's usage at 2 must yield fewer than 5 rows.
  expect_lt(nrow(res), 5L)
})

test_that("find_discriminating_triplets() works with mismatched dimensionality", {
  set.seed(4)
  n <- 15
  emb_lo <- matrix(rnorm(n * 3), n, 3, dimnames = list(paste0("item", 1:n)))
  emb_hi <- matrix(rnorm(n * 10), n, 10, dimnames = list(paste0("item", 1:n)))

  res <- suppressWarnings(
    find_discriminating_triplets(emb_lo, emb_hi, k = 5, n_candidates = 3000, seed = 4)
  )
  expect_equal(nrow(res), 5L)
})

test_that("find_discriminating_triplets() is invariant to row order", {
  set.seed(2)
  n <- 20
  emb_a <- matrix(rnorm(n * 3), n, 3, dimnames = list(paste0("item", 1:n)))
  emb_b <- matrix(rnorm(n * 3), n, 3, dimnames = list(paste0("item", 1:n)))
  emb_b_shuffled <- emb_b[sample(rownames(emb_b)), ]

  res1 <- find_discriminating_triplets(emb_a, emb_b, k = 8, n_candidates = 5000, seed = 3)
  res2 <- find_discriminating_triplets(emb_a, emb_b_shuffled, k = 8, n_candidates = 5000, seed = 3)

  expect_equal(res1, res2)
})

test_that("find_discriminating_triplets() validates its inputs", {
  set.seed(1)
  n <- 15
  emb_a <- matrix(rnorm(n * 3), n, 3, dimnames = list(paste0("item", 1:n)))
  emb_b_mismatched <- emb_a[1:10, ]

  expect_error(
    find_discriminating_triplets(emb_a, emb_b_mismatched, k = 3),
    "same set of items"
  )
  expect_error(
    find_discriminating_triplets(unname(emb_a), emb_a, k = 3),
    "row names"
  )
  expect_error(
    find_discriminating_triplets(emb_a, emb_a, k = 0),
    "k must be at least 1"
  )
  expect_error(
    find_discriminating_triplets(emb_a, emb_a, k = 3, mu = -1),
    "mu must be positive"
  )
})
