test_that("matrix_rank() detects full rank", {
  set.seed(1)
  M <- matrix(rnorm(40), nrow = 20, ncol = 2)
  expect_equal(matrix_rank(M), 2L)
})

test_that("matrix_rank() detects rank deficiency from a linear combination", {
  set.seed(1)
  a <- rnorm(20)
  b <- rnorm(20)
  M <- cbind(a, b, 2 * a - b)
  expect_equal(matrix_rank(M), 2L)
})

test_that("matrix_rank() ignores a constant column after centering", {
  set.seed(1)
  M <- cbind(rnorm(20), rep(5, 20))
  expect_equal(matrix_rank(M), 1L)
})
