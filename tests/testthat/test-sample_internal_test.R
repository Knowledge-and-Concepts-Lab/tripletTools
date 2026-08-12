# A small matrix with a unique row id in a 4th column, so partition
# correctness (no duplicated/missing rows) can be checked directly, without
# relying on head/winner/loser values happening to be unique.
make_id_matrix <- function(n = 40L) {
  m <- matrix(c(seq_len(n), seq_len(n), seq_len(n), seq_len(n)), ncol = 4L)
  colnames(m) <- c("head", "winner", "loser", "id")
  m
}

test_that("sample_internal_test partitions rows without loss or duplication", {
  X <- make_id_matrix(40L)
  split <- sample_internal_test(X, frac = 0.25, seed = 1L)

  expect_equal(nrow(split$X_internal_test), floor(0.25 * 40))
  expect_equal(nrow(split$X_fit) + nrow(split$X_internal_test), nrow(X))
  expect_equal(sort(c(split$X_fit[, "id"], split$X_internal_test[, "id"])), X[, "id"])
})

test_that("sample_internal_test is deterministic given the same seed", {
  X <- make_id_matrix(40L)
  a <- sample_internal_test(X, frac = 0.2, seed = 42L)
  b <- sample_internal_test(X, frac = 0.2, seed = 42L)

  expect_equal(a$X_fit, b$X_fit)
  expect_equal(a$X_internal_test, b$X_internal_test)
})

test_that("sample_internal_test differs across seeds", {
  X <- make_id_matrix(40L)
  a <- sample_internal_test(X, frac = 0.2, seed = 1L)
  b <- sample_internal_test(X, frac = 0.2, seed = 2L)

  expect_false(identical(a$X_internal_test[, "id"], b$X_internal_test[, "id"]))
})

test_that("sample_internal_test validates frac", {
  X <- make_id_matrix(40L)
  expect_error(sample_internal_test(X, frac = 0, seed = 1L), "frac")
  expect_error(sample_internal_test(X, frac = 1, seed = 1L), "frac")
  expect_error(sample_internal_test(X, frac = -0.1, seed = 1L), "frac")
  expect_error(sample_internal_test(X, frac = 1.1, seed = 1L), "frac")
  expect_error(sample_internal_test(X, frac = NA_real_, seed = 1L), "frac")
})

test_that("sample_internal_test errors when X_train is too small to split", {
  X <- make_id_matrix(5L)
  # frac = 0.1 -> floor(0.5) = 0 internal_test rows: not a valid split
  expect_error(sample_internal_test(X, frac = 0.1, seed = 1L), "too few rows")
})
