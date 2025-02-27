test_that("Prediction matrix is correctly generated", {
  embpath <- system.file("extdata", "cfd36_embeddings_individual.csv", package = "tripletTools")
  tripath <- system.file("extdata", "cfd36_triplets_individual.csv", package = "tripletTools")

  #Get first five participants
  embs <- get.combined(embpath, eflag=TRUE)[1:5]
  trips <- get.combined(tripath, eflag = FALSE)[1:5]

  pmat <- get.prediction.matrix(embs, trips, ttype="test")

  result <- round(pmat[1,1], 2)
  expected <- 0.83
  expect_equal(result, expected)
})
