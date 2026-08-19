test_that("procrustes_rank_ceiling() reaches 1 when k covers all nonzero dimensions", {
  set.seed(1)
  target <- cbind(rnorm(20, sd = 5), rnorm(20, sd = 3), rnorm(20, sd = 1))
  expect_equal(procrustes_rank_ceiling(target, k = 3), 1, tolerance = 1e-8)
  # k larger than the number of columns is silently clamped
  expect_equal(procrustes_rank_ceiling(target, k = 10), 1, tolerance = 1e-8)
})

test_that("procrustes_rank_ceiling() is close to 1 when variance is concentrated", {
  set.seed(1)
  target <- cbind(rnorm(20, sd = 5), rnorm(20, sd = 0.01))
  expect_gt(procrustes_rank_ceiling(target, k = 1), 0.99)
})

test_that("procrustes_rank_ceiling() validates its inputs", {
  target <- matrix(rnorm(20), nrow = 10)
  expect_error(procrustes_rank_ceiling(target, k = 0), "k must be at least 1")
  target_na <- target
  target_na[1, 1] <- NA
  expect_error(procrustes_rank_ceiling(target_na, k = 1), "missing values")
})
