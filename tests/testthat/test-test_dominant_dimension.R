test_that("errors on too few participants or invalid arguments", {
  X <- matrix(runif(3 * 2), nrow = 3)
  expect_error(test_dominant_dimension(dist(X)), "at least 4 participants")

  X2 <- matrix(runif(10 * 2), nrow = 10)
  expect_error(test_dominant_dimension(dist(X2), n_simulations = 0),
               "n_simulations must be at least 1")
})

test_that("errors clearly when rank exceeds the candidate dimension pool", {
  set.seed(1)
  X <- matrix(rnorm(6 * 2), 6, 2)
  # n = 6 -> k_candidate at most n - 2 = 4
  expect_error(test_dominant_dimension(dist(X), rank = 10, n_simulations = 10),
               "exceeds the number of candidate dimensions")
})

test_that("p-value is not significant on pure noise (Type I error sanity check)", {
  set.seed(1)
  X <- matrix(runif(20 * 6), nrow = 20)
  res <- test_dominant_dimension(dist(X), n_simulations = 1000, seed = 1, verbose = FALSE)
  expect_gt(res$p_value, 0.05)
})

test_that("detects a strong genuine dominant dimension", {
  set.seed(1)
  dom <- rnorm(30, sd = 5)
  noise <- matrix(rnorm(30 * 5, sd = 1), 30, 5)
  X <- cbind(dom, noise)
  res <- test_dominant_dimension(dist(X), n_simulations = 1000, seed = 1, verbose = FALSE)
  expect_lt(res$p_value, 0.01)
})

test_that("does not falsely detect a weak/marginal dominant dimension", {
  # Variance ratio ~2 between the "signal" and noise dimensions -- too weak
  # to reliably distinguish from chance; the test should not overclaim here.
  set.seed(1)
  dom <- rnorm(30, sd = sqrt(2))
  noise <- matrix(rnorm(30 * 5, sd = 1), 30, 5)
  X <- cbind(dom, noise)
  res <- test_dominant_dimension(dist(X), n_simulations = 1000, seed = 1, verbose = FALSE)
  expect_gt(res$p_value, 0.05)
})

test_that("Type I error is approximately calibrated across repeated pure-noise draws", {
  # A lighter-weight version of the calibration check done during
  # development (verified there at 150+ reps and n_simulations in the
  # hundreds-to-thousands -- this just locks down that it's still in the
  # right ballpark, not a precise estimate of the true false-positive rate).
  n_reps <- 40
  pvals <- numeric(n_reps)
  for (r in seq_len(n_reps)) {
    set.seed(r)
    X <- matrix(rnorm(15 * 5), 15, 5)
    pvals[r] <- test_dominant_dimension(dist(X), n_simulations = 300, seed = r, verbose = FALSE)$p_value
  }
  # Nominal 10% false-positive rate; allow generous slack given only 40 reps.
  expect_lt(mean(pvals < 0.10), 0.30)
})

test_that("same seed gives identical results", {
  set.seed(1)
  X <- matrix(rnorm(20 * 4), 20, 4)
  r1 <- test_dominant_dimension(dist(X), n_simulations = 200, seed = 5, verbose = FALSE)
  r2 <- test_dominant_dimension(dist(X), n_simulations = 200, seed = 5, verbose = FALSE)
  expect_identical(r1, r2)
})

test_that("return value has the documented structure", {
  set.seed(1)
  X <- matrix(rnorm(15 * 4), 15, 4)
  res <- test_dominant_dimension(dist(X), n_simulations = 100, seed = 1, verbose = FALSE)
  expect_equal(res$rank, 1)
  expect_true(res$k_candidate >= 1)
  expect_length(res$null_proportion, 100)
  expect_true(res$observed_proportion > 0 && res$observed_proportion <= 1)
  expect_true(res$p_value >= 0 && res$p_value <= 1)
})
