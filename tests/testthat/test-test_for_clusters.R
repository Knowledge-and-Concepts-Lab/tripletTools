skip_if_not_installed("mclust")

test_that("no evidence of clusters in uniform random data", {
  # n = 60: at smaller n (e.g. 20), BIC-based G-selection has a nontrivial
  # false-positive rate on pure null data (~35% in a 20-seed simulation
  # during development, vs 0% for the Hopkins-based check at the same n) --
  # a real, documented limitation of BIC search over many models at small
  # sample sizes, not something a single test should paper over by picking
  # a lucky seed at a fragile sample size. Hopkins is the more reliable
  # check here and is asserted unconditionally; best_g is checked too since
  # n = 60 brings its false-positive rate down to ~5%, verified stable for
  # this specific seed.
  set.seed(1)
  X <- matrix(runif(60 * 4), nrow = 60)
  res <- test_for_clusters(dist(X), max_clusters = 4, seed = 1, verbose = FALSE)

  expect_gt(res$hopkins_p_value, 0.05)
  expect_equal(res$best_g, 1)
  expect_equal(names(res$bic), paste0("G=", 1:4))
})

test_that("clear evidence of two clusters in well-separated blobs", {
  set.seed(1)
  X <- rbind(
    matrix(rnorm(15 * 4, mean = 0), nrow = 15),
    matrix(rnorm(15 * 4, mean = 12), nrow = 15)
  )
  res <- test_for_clusters(dist(X), max_clusters = 4, seed = 1, verbose = FALSE)

  expect_lt(res$hopkins_p_value, 0.05)
  expect_equal(res$best_g, 2)

  expect_type(res$model_name, "character")
  expect_length(res$model_name, 1)
  expect_length(res$classification, 30)
  expect_equal(sort(unique(res$classification)), 1:2)
  # the two true 15-member blobs should come back as two clean 15/15 groups
  expect_equal(sort(as.vector(table(res$classification))), c(15, 15))
})

test_that("report_classification_for returns extra G classifications consistent with bic", {
  set.seed(1)
  X <- rbind(
    matrix(rnorm(15 * 4, mean = 0), nrow = 15),
    matrix(rnorm(15 * 4, mean = 12), nrow = 15)
  )
  res <- test_for_clusters(dist(X), max_clusters = 4, seed = 1, verbose = FALSE,
                            report_classification_for = c(1, 3))

  expect_named(res$alt_classifications, c("G=1", "G=3"))
  expect_length(res$alt_classifications[["G=1"]]$classification, 30)
  expect_equal(length(unique(res$alt_classifications[["G=1"]]$classification)), 1)
  # forcing G=3 on genuinely 2-cluster data can legitimately leave one of
  # the 3 components unpopulated in the MAP assignment -- just check the
  # classification is well-formed, not that all 3 labels are necessarily used
  expect_length(res$alt_classifications[["G=3"]]$classification, 30)
  expect_true(length(unique(res$alt_classifications[["G=3"]]$classification)) <= 3)

  # NULL when not requested
  res2 <- test_for_clusters(dist(X), max_clusters = 4, seed = 1, verbose = FALSE)
  expect_null(res2$alt_classifications)
})

test_that("report_classification_for validates its range", {
  X <- matrix(runif(15 * 3), nrow = 15)
  expect_error(
    test_for_clusters(dist(X), max_clusters = 3, report_classification_for = 5, verbose = FALSE),
    "report_classification_for must be between 1 and max_clusters"
  )
})

test_that("errors on too few participants or max_clusters >= n", {
  X <- matrix(runif(3 * 2), nrow = 3)
  expect_error(test_for_clusters(dist(X)), "at least 4 participants")

  X2 <- matrix(runif(10 * 2), nrow = 10)
  expect_error(test_for_clusters(dist(X2), max_clusters = 10),
               "must be less than the number of participants")
})

test_that("same seed gives identical results", {
  set.seed(2)
  X <- matrix(runif(15 * 3), nrow = 15)
  d <- dist(X)
  r1 <- test_for_clusters(d, max_clusters = 3, seed = 5, verbose = FALSE)
  r2 <- test_for_clusters(d, max_clusters = 3, seed = 5, verbose = FALSE)
  expect_identical(r1, r2)
})
