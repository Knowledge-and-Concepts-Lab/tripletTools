test_that("successor_matrix() reduces to the identity matrix when gamma = 0", {
  W <- matrix(c(0, 1, 1, 0, 0, 1, 1, 1, 0), nrow = 3, byrow = TRUE)
  result <- successor_matrix(W, gamma = 0)
  expect_equal(unname(result$successor), diag(3), tolerance = 1e-8)
})

test_that("successor_matrix() rows sum to 1 for any valid gamma", {
  set.seed(1)
  W <- matrix(runif(16), nrow = 4)
  result <- successor_matrix(W, gamma = 0.7)
  expect_equal(unname(rowSums(result$successor)), rep(1, 4), tolerance = 1e-8)
  expect_equal(unname(rowSums(result$transition)), rep(1, 4), tolerance = 1e-8)
})

test_that("successor_matrix() preserves dimnames", {
  W <- matrix(c(0, 1, 1, 0), nrow = 2,
              dimnames = list(c("a", "b"), c("a", "b")))
  result <- successor_matrix(W, gamma = 0.5)
  expect_equal(rownames(result$successor), c("a", "b"))
  expect_equal(colnames(result$successor), c("a", "b"))
})

test_that("successor_matrix() validates its inputs", {
  expect_error(successor_matrix(matrix(1:6, nrow = 2)), "square")
  expect_error(successor_matrix(matrix(c(0, 1, 1, 0), 2), gamma = 1), "gamma")
  expect_error(successor_matrix(matrix(c(0, 0, 1, 0), 2)), "zero outgoing weight")
})
