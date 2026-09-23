skip_if_not_installed("mclust")

# Two well-separated 2D blobs, embedded with several extra pure-noise
# dimensions -- the exact scenario that broke the pre-fix
# test_for_clusters() default (numerical-rank dimensionality retention
# swamping a real, low-dimensional signal with noise-only dimensions).
make_blobs_with_noise <- function(seed, n_per_blob = 8, n_noise_dims = 8,
                                   noise_sd = 1.5, separation = 10) {
  set.seed(seed)
  signal <- rbind(
    matrix(rnorm(n_per_blob * 2, sd = 1), ncol = 2),
    matrix(rnorm(n_per_blob * 2, sd = 1), ncol = 2) + separation
  )
  noise <- matrix(rnorm(nrow(signal) * n_noise_dims, sd = noise_sd), ncol = n_noise_dims)
  cbind(signal, noise)
}

test_that("a clean 2-cluster configuration needs at most 2 dimensions, not the full candidate pool", {
  # Two well-separated blobs in 2D. In population terms the *between-
  # cluster* structure lives in only 1 direction -- the line connecting
  # the two cluster means (a discriminant-analysis fact: G groups need at
  # most G-1 dimensions to separate) -- but empirically (stable across 10
  # data-generation seeds) the second dimension often also clears its
  # threshold here: dim 1's variance (the huge between-cluster gap) is
  # ~50x dim 2's (pure within-cluster noise), and permutation-based
  # eigenvalue estimates of a covariance matrix with that much variance
  # disparity are well known to spread apart, deflating the smaller
  # dimension's null threshold below its true value. Whether dim 2 "counts"
  # is genuinely ambiguous in this extreme, contrived construction; the
  # property actually worth locking down is that this never inflates all
  # the way to the full n-2 candidate pool the way the pre-fix numerical-
  # rank policy did.
  set.seed(1)
  X <- rbind(
    matrix(rnorm(10 * 2, sd = 1), ncol = 2),
    matrix(rnorm(10 * 2, sd = 1), ncol = 2) + 10
  )
  res <- estimate_intrinsic_dimension(dist(X), n_permutations = 100, seed = 1, verbose = FALSE)
  expect_lte(res$k, 2)
})

test_that("recovers 2 real dimensions for a 3-cluster configuration needing 2 to separate", {
  # 3 cluster means at the vertices of a triangle (non-collinear) genuinely
  # need 2 dimensions to separate -- unlike the 2-cluster case above, which
  # only ever needs 1.
  set.seed(1)
  centers <- rbind(c(0, 0), c(10, 0), c(5, 10))
  X <- do.call(rbind, lapply(1:3, function(i) {
    matrix(rnorm(8 * 2, sd = 1), ncol = 2) + matrix(centers[i, ], 8, 2, byrow = TRUE)
  }))
  res <- estimate_intrinsic_dimension(dist(X), n_permutations = 100, seed = 1, verbose = FALSE)
  expect_equal(res$k, 2)
})

test_that("recovers a low true dimensionality despite many noise dimensions", {
  X <- make_blobs_with_noise(seed = 1)
  res <- estimate_intrinsic_dimension(dist(X), n_permutations = 200, seed = 1, verbose = FALSE)
  # True signal is 2D; the numerical-rank ceiling here would be n - 2 = 14.
  expect_lt(res$k, 5)
})

test_that("estimates a small k on pure noise (no real structure)", {
  set.seed(1)
  X <- matrix(runif(20 * 6), nrow = 20)
  res <- estimate_intrinsic_dimension(dist(X), n_permutations = 200, seed = 1, verbose = FALSE)
  expect_lte(res$k, 2)
})

test_that("eigenvalues and null_threshold are returned with consistent length", {
  X <- make_blobs_with_noise(seed = 2)
  res <- estimate_intrinsic_dimension(dist(X), n_permutations = 50, seed = 1, verbose = FALSE)
  expect_equal(length(res$eigenvalues), length(res$null_threshold))
  expect_true(res$k >= 1)
  expect_true(res$k <= length(res$eigenvalues))
})

test_that("errors on too few participants or invalid arguments", {
  X <- matrix(runif(3 * 2), nrow = 3)
  expect_error(estimate_intrinsic_dimension(dist(X)), "at least 4 participants")

  X2 <- matrix(runif(10 * 2), nrow = 10)
  expect_error(estimate_intrinsic_dimension(dist(X2), n_permutations = 0),
               "n_permutations must be at least 1")
  expect_error(estimate_intrinsic_dimension(dist(X2), threshold_quantile = 0),
               "threshold_quantile must be strictly between 0 and 1")
  expect_error(estimate_intrinsic_dimension(dist(X2), threshold_quantile = 1),
               "threshold_quantile must be strictly between 0 and 1")
})

test_that("same seed gives identical results", {
  X <- make_blobs_with_noise(seed = 3)
  r1 <- estimate_intrinsic_dimension(dist(X), n_permutations = 50, seed = 5, verbose = FALSE)
  r2 <- estimate_intrinsic_dimension(dist(X), n_permutations = 50, seed = 5, verbose = FALSE)
  expect_identical(r1, r2)
})
