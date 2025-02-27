test_that("Z-scoring prediction matrix works", {
  pmat <- matrix(
          c(.9,.2,.25,.3,
            .15, .95, .2,.25,
            .3, .25, .85, .1,
            .22, .22, .25, .8),
          4, 4, byrow = TRUE)

  z.pmat <- z.pred.mat(pmat)

  result <- z.pmat[1]
  expected <- 13.00

  expect_equal(result, expected)
})
