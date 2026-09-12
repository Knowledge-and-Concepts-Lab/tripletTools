skip_if_not_installed("mclust")

test_that("no evidence of clusters in uniform random data", {
  # n = 60: at smaller n (e.g. 20), BIC-based G-selection has a nontrivial
  # false-positive rate on pure null data (~35% in a 20-seed simulation
  # during development, vs 0% for the Hopkins-based check at the same n) --
  # a real, documented limitation of BIC search over many models at small
  # sample sizes, not something a single test should paper over by picking
  # a lucky seed at a fragile sample size. Hopkins is the more reliable
  # check here and is asserted unconditionally; best_g is checked too since
  # n = 60 brings its false-positive rate down to ~5%, verified stable for
  # this specific seed.
  set.seed(1)
  X <- matrix(runif(60 * 4), nrow = 60)
  res <- test_for_clusters(dist(X), max_clusters = 4, seed = 1, verbose = FALSE)

  expect_gt(res$hopkins_p_value, 0.05)
  expect_equal(res$best_g, 1)
  expect_equal(names(res$bic), paste0("G=", 1:4))
})

test_that("clear evidence of two clusters in well-separated blobs", {
  set.seed(1)
  X <- rbind(
    matrix(rnorm(15 * 4, mean = 0), nrow = 15),
    matrix(rnorm(15 * 4, mean = 12), nrow = 15)
  )
  res <- test_for_clusters(dist(X), max_clusters = 4, seed = 1, verbose = FALSE)

  expect_lt(res$hopkins_p_value, 0.05)
  expect_equal(res$best_g, 2)
})

test_that("errors on too few participants or max_clusters >= n", {
  X <- matrix(runif(3 * 2), nrow = 3)
  expect_error(test_for_clusters(dist(X)), "at least 4 participants")

  X2 <- matrix(runif(10 * 2), nrow = 10)
  expect_error(test_for_clusters(dist(X2), max_clusters = 10),
               "must be less than the number of participants")
})

test_that("same seed gives identical results", {
  set.seed(2)
  X <- matrix(runif(15 * 3), nrow = 15)
  d <- dist(X)
  r1 <- test_for_clusters(d, max_clusters = 3, seed = 5, verbose = FALSE)
  r2 <- test_for_clusters(d, max_clusters = 3, seed = 5, verbose = FALSE)
  expect_identical(r1, r2)
})
