test_that("Alignment of embeddings works", {
  s1 <- data.frame(
         x = c(1:10) + runif(10)/10,
         y = c(1:10) + runif(10)/10
         )

  s2 <- s1 * 2 + 4 #Double and shift s1 data
  s2[,1] <- -1 * s2[,1] #Reflect along one dimension

  unaligned <- list(s1,s2)
  aligned <- align.embeddings(unaligned, baseno = 1)

  result1 <- round(aligned[[1]], 2)
  result2 <- round(aligned[[2]],2)

  expect_equal(result1, result2)
})
