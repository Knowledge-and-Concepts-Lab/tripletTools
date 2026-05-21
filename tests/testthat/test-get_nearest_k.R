test_that("get nearest k works", {

  emb <- icon_emb_ind[[1]] #Embedding for participant 1
  fdists <- as.matrix(dist(emb)) #Compute pairwise distance matrix
  target <- "fdfob"  #Name of target item

  #Return 3 items nearest to target:
  result <- get.nearest.k(fdists, target, 3)[1]
  expected <- "fdfyw"

  expect_equal(result, expected)
})
