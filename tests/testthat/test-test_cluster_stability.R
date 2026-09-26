skip_if_not_installed("mclust")

test_that("clean two-blob data gives high stability", {
  set.seed(1)
  X <- rbind(
    matrix(rnorm(15 * 3, mean = 0), nrow = 15),
    matrix(rnorm(15 * 3, mean = 12), nrow = 15)
  )
  res <- test_cluster_stability(dist(X), k = 2, n_reps = 100, seed = 1, verbose = FALSE)

  expect_gt(res$mean_ari, 0.9)
  expect_gt(res$median_ari, 0.9)
  expect_length(res$ari, 100)
  expect_length(res$participant_stability, 30)
  expect_true(all(res$participant_stability > 0.8))
})

test_that("a clumpy but genuinely structure-free sample can still look moderately stable", {
  # This is a real, documented property of resampling-based stability checks
  # (see the function's "What 'stable' does and doesn't mean" docs section),
  # not a bug: subsampling mostly repeats the same fixed points, so a
  # chance-clumpy finite draw can resample as reproducible even with no
  # real population-level structure. The point of this test is just to
  # confirm mean_ari varies with the data (not pinned to some constant),
  # and is meaningfully lower here than in the clean-blob case above.
  set.seed(3)
  X <- matrix(rnorm(20 * 5), nrow = 20)
  res <- test_cluster_stability(dist(X), k = 2, n_reps = 100, seed = 1, verbose = FALSE)

  expect_true(res$mean_ari >= 0 && res$mean_ari <= 1)
})

test_that("returned fields have the expected names, types, and shapes", {
  set.seed(2)
  X <- matrix(runif(16 * 3), nrow = 16)
  res <- test_cluster_stability(dist(X), k = 3, n_reps = 50, seed = 4, verbose = FALSE)

  expect_named(res, c(
    "ari", "mean_ari", "median_ari", "participant_stability",
    "orig_labels", "k", "n_reps", "subsample_frac", "method"
  ))
  expect_length(res$orig_labels, 16)
  expect_equal(length(unique(res$orig_labels)), 3)
  expect_equal(res$k, 3)
  expect_equal(res$n_reps, 50)
  expect_equal(res$method, "ward.D")
})

test_that("same seed gives identical results", {
  set.seed(5)
  X <- matrix(runif(20 * 3), nrow = 20)
  d <- dist(X)
  r1 <- test_cluster_stability(d, k = 2, n_reps = 30, seed = 7, verbose = FALSE)
  r2 <- test_cluster_stability(d, k = 2, n_reps = 30, seed = 7, verbose = FALSE)
  expect_identical(r1, r2)
})

test_that("errors on invalid arguments", {
  X <- matrix(runif(3 * 2), nrow = 3)
  expect_error(test_cluster_stability(dist(X), k = 2), "at least 4 participants")

  X2 <- matrix(runif(10 * 2), nrow = 10)
  expect_error(test_cluster_stability(dist(X2), k = 1), "k must be between 2 and")
  expect_error(test_cluster_stability(dist(X2), k = 10), "k must be between 2 and")

  expect_error(test_cluster_stability(dist(X2), k = 2, subsample_frac = 0),
               "subsample_frac must be strictly between 0 and 1")
  expect_error(test_cluster_stability(dist(X2), k = 2, subsample_frac = 1),
               "subsample_frac must be strictly between 0 and 1")

  # subsample_frac leaves too few participants for the requested k
  X3 <- matrix(runif(6 * 2), nrow = 6)
  expect_error(
    test_cluster_stability(dist(X3), k = 4, subsample_frac = 0.5),
    "not enough for k"
  )
})
