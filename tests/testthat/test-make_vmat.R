test_that("make validation matrix works", {

  vmat <- make.vmat(icon_triplets)

  result <- round(vmat[[1]][1,3],2)
  expected <- 1
  expect_equal(result, expected)
})
