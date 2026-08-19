test_that("procrustes_spectral_ceiling() returns 1 for identical spectra", {
  set.seed(1)
  M <- cbind(rnorm(20, sd = 4), rnorm(20, sd = 1))
  expect_equal(procrustes_spectral_ceiling(M, M), 1, tolerance = 1e-8)
})

test_that("procrustes_spectral_ceiling() handles differing dimensionality", {
  set.seed(1)
  candidate <- cbind(rnorm(20, sd = 4), rnorm(20, sd = 1))
  target    <- cbind(rnorm(20, sd = 5), rnorm(20, sd = 1.2), rnorm(20, sd = 0.1))
  result <- procrustes_spectral_ceiling(candidate, target)
  expect_true(is.numeric(result) && length(result) == 1L)
  expect_gte(result, 0)
  expect_lte(result, 1)
})
