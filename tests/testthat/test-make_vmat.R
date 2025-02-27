test_that("make validation matrix works", {

  vmat <- make.vmat(cfd_triplets)

  result <- round(vmat[[1]][1,3],2)
  expected <- 0.59
  expect_equal(result, expected)
})
