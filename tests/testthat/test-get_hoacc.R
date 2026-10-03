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

test_that("trialtype = 'validation' selects via sampleAlg, not sampleSet", {
  m <- as.matrix(data.frame(
    x = c(1, 1.1, 2, 2.1),
    y = c(1.25, 1.75, 1.25, 1.75),
    row.names = c("cat", "dog", "car", "boat")
  ))

  # Validation trials excluded from training (sampleSet = NA, the
  # "holdout" treatment) -- sampleSet never literally equals "validation",
  # so trialtype = "validation" must fall back to sampleAlg.
  tr <- data.frame(
    Center    = c("cat", "car", "dog", "boat"),
    Left      = c("dog", "boat", "car", "cat"),
    Right     = c("car", "dog", "boat", "car"),
    Answer    = c("dog", "boat", "car", "car"),
    sampleSet = c(NA, NA, "train", "train"),
    sampleAlg = c("validation", "validation", "random", "random")
  )

  response <- get.hoacc(m, tr, trialtype = "validation", isemb = TRUE)
  expect_equal(response, 1.0)
})

test_that("trialtype = 'validation' errors clearly when sampleAlg is missing", {
  m <- as.matrix(data.frame(x = 1, y = 1, row.names = "cat"))
  tr <- data.frame(Center = "cat", Left = "cat", Right = "cat",
                    Answer = "cat", sampleSet = "train")
  expect_error(
    get.hoacc(m, tr, trialtype = "validation", isemb = TRUE),
    "sampleAlg"
  )
})
