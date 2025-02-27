test_that("making triplet names works", {
  trips <- cfd_triplets[[10]] #Triplet data for participant 10
  tnames <- make.tripnames(trips) #Make triplet names

  result <- tnames[1] #First triplet name
  expected <- "CFD-WF-026-008-A_CFD-WM-023-012-A_CFD-WM-033-014-A"
  expect_equal(result, expected)
})
