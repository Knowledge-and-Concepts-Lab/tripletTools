test_that("Hold-out prediction error works.", {
  m <- data.frame(
    x=c(1,1.1,2,2.1),
    y=c(1.25,1.75,1.25,1.75))

  row.names(m) <- c("cat","dog","car","boat")

  m <- as.matrix(m)

  tr <- data.frame(
    Center=c("cat", "car", "dog", "boat"),
    Left = c("dog", "boat", "car", "cat"),
    Right= c("car", "dog", "boat", "car"),
    Answer=c("dog", "boat", "car", "car"),
    sampleSet=c("test","test","test", "test"))

  response <- get.hoacc(m, tr, isemb=TRUE)
  expected <- 0.75
  expect_equal(response, expected)
})
