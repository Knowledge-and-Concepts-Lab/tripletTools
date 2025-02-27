test_that("group list mean works", {
  repdist <- get.rep.dist(cfd_embeddings)
  hc <- hclust(as.dist(repdist), method = "ward.D")
  clusts <- cutree(hc, 4)

  grpmeans <- get.group.list.mean(cfd_embeddings, clusts)
  grp1 <- grpmeans[[1]]

  result <- round(grp1[1,], 2)
  expected <- c(-0.06, -.02)

  expect_equal(result, expected)

})
