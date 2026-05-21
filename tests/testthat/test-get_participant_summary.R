test_that("Creation of participant summary file works.", {
  #Example data path
  fpath <- system.file("extdata", "icon_all_triplets.csv", package = "tripletTools")

  #Read example data
  trips <- get.combined(fpath)

  #compute summary
  part.summary <- get.participant.summary(trips)

  result <- part.summary[1,1]
  expected <- '3n7ggxph'

  expect_equal(result, expected)
})
