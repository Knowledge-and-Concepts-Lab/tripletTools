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

  result <- test.model(m, tr, isemb=TRUE, pred_name = "ModPred")
  expect_equal(result$ModPred, c("dog","boat"))
})

test_that("Prediction column defaults to the embedding argument's own name", {
  toy_embedding <- data.frame(
    x=c(1,1.1,2,2.1),
    y=c(1.25,1.75,1.25,1.75))
  row.names(toy_embedding) <- c("cat","dog","car","boat")
  toy_embedding <- as.matrix(toy_embedding)

  tr <- data.frame(
    Center=c("cat", "car"),
    Left = c("dog", "boat"),
    Right= c("car", "dog"))

  result <- test.model(toy_embedding, tr, isemb=TRUE)
  expect_equal(result$toy_embedding, c("dog","boat"))
})
