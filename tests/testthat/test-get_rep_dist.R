test_that("Representational distance works", {
  #Subject 1 data
  s1 <- matrix(
    c(1,1,
      2,2,
      3,3,
      4,4,
      5,5), 5,2,byrow = T)

  #Subject 2 is scaled, shifted variant of s1
  s2 <- s1 * 1.1 + .1

  #Subject 3 is different:
  s3 <- matrix(
    c(1,2,
      3,4,
      4,3,
      2,1,
      5,2), 5,2,byrow = T)

  slist <- list(s1,s2,s3)

  sdist <- get.rep.dist(slist)
  result <- round(sdist[2,1], 2)
  expected <- 0.0

  expect_equal(result, expected)
})
