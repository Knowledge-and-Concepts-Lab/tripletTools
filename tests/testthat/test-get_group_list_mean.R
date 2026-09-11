test_that("group list mean works", {
  # metric fixed explicitly: this test's expected values were computed from
  # the clustering that "corr_dist" (this function's original, only
  # behavior) produces, and Ward's-method clustering is sensitive to which
  # metric is used, not just its rank order.
  repdist <- get.rep.dist(icon_emb_ind, metric = "corr_dist")
  hc <- hclust(as.dist(repdist), method = "ward.D")
  clusts <- cutree(hc, 2)

  grpmeans <- get.group.list.mean(icon_emb_ind, clusts)
  grp1 <- grpmeans[[1]]

  result <- round(grp1[1,], 2)
  expected <- c(-0.16, 0.03, -0.01)

  expect_equal(result, expected)

})
