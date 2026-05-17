test_that("group list mean works", {
  repdist <- get.rep.dist(icon_emb_ind)
  hc <- hclust(as.dist(repdist), method = "ward.D")
  clusts <- cutree(hc, 2)

  grpmeans <- get.group.list.mean(icon_emb_ind, clusts)
  grp1 <- grpmeans[[1]]

  result <- round(grp1[1,], 2)
  expected <- c(-0.16, 0.03, -0.01)

  expect_equal(result, expected)

})
