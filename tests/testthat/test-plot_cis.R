test_that("Calculation of column means is correct", {
  dm <- matrix(1:12,4,3)
  mn <- plot_cis(dm)
  expect_equal(mn[1,], colMeans(dm))
})
