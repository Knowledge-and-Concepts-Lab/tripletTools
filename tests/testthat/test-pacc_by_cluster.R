test_that("prediction by cluster works", {
  pmat <- get.prediction.matrix(icon_emb_ind, icon_triplets) #Prediction matrix

  #Manual cluster assignments (3 in cluster 1, 2 in cluster 2):
  clusts <- c(1, 1, 1, 2, 2)

  pbc <- pacc.by.cluster(pmat, clusts, samediff=TRUE)

  result <- round(colMeans(pbc),2)
  expected <- c(.79, .72, .68)
  names(expected) <-c("self","same","other")

  expect_equal(result, expected)
})
