test_that("Prediction matrix is correctly generated", {
  pmat <- get.prediction.matrix(icon_emb_ind, icon_triplets, ttype="test")

  result <- round(pmat[1,1], 2)
  expected <- 0.69
  expect_equal(result, expected)
})
