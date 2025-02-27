test_that("Reading a combined data file works", {

  fpath <- system.file("extdata", "cfd36_embeddings_individual.csv", package="tripletTools")
  tmp <- get.combined(fpath, eflag=TRUE)
  tmp <- tmp[[1]]
  result <- round(tmp[1,1],2)
  expect_equal(result,0.39)
})
