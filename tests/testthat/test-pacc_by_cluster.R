test_that("prediction by cluster works", {
  pmat <- get.prediction.matrix(icon_emb_ind, icon_triplets) #Prediction matrix

  #Cluster assignments derived from get.rep.dist(icon_emb_ind) +
  #hclust(..., method = "ward.D") + cutree(hc, 2): a tight 4-participant
  #cluster (3n7ggxph, b5wma4no, d8mmm1qn, jn7bbjc0) and a separate
  #2-participant cluster (pbby694o, sc2xbd6w), matching the row order of
  #icon_emb_ind/icon_triplets.
  clusts <- c(1, 1, 1, 1, 2, 2)

  pbc <- pacc.by.cluster(pmat, clusts, samediff=TRUE)

  result <- round(colMeans(pbc),2)
  expected <- c(.78, .78, .60)
  names(expected) <-c("self","same","other")

  expect_equal(result, expected)
})
