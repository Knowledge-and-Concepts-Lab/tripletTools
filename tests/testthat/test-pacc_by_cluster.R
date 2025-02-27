test_that("prediction by cluster works", {
  repdist <- get.rep.dist(cfd_embeddings) #Representational distances

  #Hierarchical cluster
  hc <- hclust(as.dist(repdist), method = "ward.D")
  clusts <- cutree(hc, 3) #Cut tree to yield three clusters

  pacc <- get.prediction.matrix(cfd_embeddings, cfd_triplets) #Prediction matrix
  pbc <- pacc.by.cluster(pacc, clusts, samediff=TRUE)

  result <- round(colMeans(pbc),2)
  expected <- c(.77, .67, .59)
  names(expected) <-c("self","same","other")

  expect_equal(result, expected)
})
