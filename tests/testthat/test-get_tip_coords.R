test_that("Extracting tip coordinates works", {
  dmat <- matrix(
    c(1, .5,  1, 0,   0,  0,
      .1, 1,  1, 0,   0,  0,
      1,  1, .8, 0,   0,  0,
      0,  0,  0, 1.1, 1,  1,
      0,  0,  0, 1,  .5,  1,
      0,  0,  0, 1,   1, .2
    ),6,6)

  #Cluster analysis
  hc <- stats::hclust(stats::dist(dmat))
  #Phylo-tree
  pt <- ape::as.phylo(hc)

  plot(pt, show.tip.label=FALSE)

  tpts <- get.tip.coords()

  result <- as.numeric(tpts[1,2])
  expected <- 4

  expect_equal(result, expected)
})
