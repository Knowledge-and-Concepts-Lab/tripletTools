test_that("making triplet names works", {
  trips <- icon_triplets[[1]] #Triplet data for participant 1
  tnames <- make.tripnames(trips) #Make triplet names

  result <- tnames[1] #First triplet name
  expected <- "pnhns_pdcos_pncnb"
  expect_equal(result, expected)
})
