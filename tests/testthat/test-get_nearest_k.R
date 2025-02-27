test_that("get nearest k works", {

  emb <- cfd_embeddings[[10]] #Embedding for participant 10
  fdists <- as.matrix(dist(emb)) #Compute pairwise distance matrix
  target <- "CFD-BF-002-004-HO"  #Name of target items

  #Return 3 items nearest to target:
  result <- get.nearest.k(fdists, target, 3)[1]
  expected <- "CFD-BM-009-003-HO"

  expect_equal(result, expected)
})
