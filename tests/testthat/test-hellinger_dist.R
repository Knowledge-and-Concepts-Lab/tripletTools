test_that("hellinger_dist() gives zero distance between identical rows", {
  P <- matrix(c(0.7, 0.3, 0.7, 0.3), nrow = 2, byrow = TRUE)
  d <- as.matrix(hellinger_dist(P))
  expect_equal(d[1, 2], 0, tolerance = 1e-8)
})

test_that("hellinger_dist() gives the maximal distance of 1 between disjoint profiles", {
  P <- matrix(c(1, 0, 0, 1), nrow = 2, byrow = TRUE)
  d <- as.matrix(hellinger_dist(P))
  expect_equal(d[1, 2], 1, tolerance = 1e-8)
})

test_that("hellinger_dist() renormalizes rows that don't already sum to 1", {
  P <- matrix(c(7, 3, 70, 30), nrow = 2, byrow = TRUE)
  d <- as.matrix(hellinger_dist(P))
  expect_equal(d[1, 2], 0, tolerance = 1e-8)
})

test_that("hellinger_dist() rejects negative values", {
  P <- matrix(c(0.5, -0.5, 0.5, 0.5), nrow = 2, byrow = TRUE)
  expect_error(hellinger_dist(P), "negative")
})
