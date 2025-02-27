test_that("Embedding prediction works", {
  m <- data.frame(
    x=c(1,1.1,2,2.1),
    y=c(1.25,1.75,1.25,1.75))

  row.names(m) <- c("cat","dog","car","boat")

  m <- as.matrix(m)

  tr <- data.frame(
    Center=c("cat", "car"),
    Left = c("dog", "boat"),
    Right= c("car", "dog"))

  result <- test.model(m, tr, isemb=TRUE)
  expect_equal(result$ModPred, c("dog","boat"))
})
