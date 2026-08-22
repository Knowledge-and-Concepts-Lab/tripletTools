test_that("find_discrepant_items() returns expected structure", {
  set.seed(2)
  n <- 20
  emb_a <- matrix(rnorm(n * 3), n, 3, dimnames = list(paste0("item", 1:n)))
  emb_b <- matrix(rnorm(n * 3), n, 3, dimnames = list(paste0("item", 1:n)))

  res <- find_discrepant_items(emb_a, emb_b)
  expect_s3_class(res, "data.frame")
  expect_equal(nrow(res), n)
  expect_equal(names(res), c("item", "correlation"))
  expect_true(all(res$correlation >= -1 - 1e-8 & res$correlation <= 1 + 1e-8))
  expect_true(!is.unsorted(res$correlation))  # ascending: most discrepant first

  res_top <- find_discrepant_items(emb_a, emb_b, k = 5)
  expect_equal(nrow(res_top), 5L)
  expect_equal(res_top, res[1:5, ])
})

test_that("spearman correctly identifies a single relocated item; pearson does not", {
  set.seed(1)
  n <- 20
  emb1 <- matrix(rnorm(n * 3), n, 3, dimnames = list(paste0("item", 1:n)))
  emb2 <- emb1
  emb2["item1", ] <- emb2["item1", ] + 10

  res_spearman <- find_discrepant_items(emb1, emb2, method = "spearman")
  expect_equal(res_spearman$item[1], "item1")
  # item1's correlation should be far below every other item's
  expect_true(res_spearman$correlation[1] < res_spearman$correlation[2] - 0.3)

  res_pearson <- find_discrepant_items(emb1, emb2, method = "pearson")
  expect_false(res_pearson$item[1] == "item1")
  expect_true("item1" %in% res_pearson$item[-(1:5)])
})

test_that("find_discrepant_items() handles mismatched dimensionality", {
  set.seed(4)
  n <- 15
  emb_lo <- matrix(rnorm(n * 3), n, 3, dimnames = list(paste0("item", 1:n)))
  emb_hi <- matrix(rnorm(n * 10), n, 10, dimnames = list(paste0("item", 1:n)))

  res <- find_discrepant_items(emb_lo, emb_hi)
  expect_equal(nrow(res), n)
})

test_that("find_discrepant_items() is invariant to row order", {
  set.seed(2)
  n <- 20
  emb_a <- matrix(rnorm(n * 3), n, 3, dimnames = list(paste0("item", 1:n)))
  emb_b <- matrix(rnorm(n * 3), n, 3, dimnames = list(paste0("item", 1:n)))
  emb_b_shuffled <- emb_b[sample(rownames(emb_b)), ]

  res1 <- find_discrepant_items(emb_a, emb_b)
  res2 <- find_discrepant_items(emb_a, emb_b_shuffled)
  expect_equal(res1, res2)
})

test_that("k larger than the number of items is silently clamped", {
  set.seed(2)
  n <- 10
  emb_a <- matrix(rnorm(n * 3), n, 3, dimnames = list(paste0("item", 1:n)))
  emb_b <- matrix(rnorm(n * 3), n, 3, dimnames = list(paste0("item", 1:n)))

  res <- find_discrepant_items(emb_a, emb_b, k = 1000L)
  expect_equal(nrow(res), n)
})

test_that("find_discrepant_items() validates its inputs", {
  set.seed(2)
  n <- 10
  emb_a <- matrix(rnorm(n * 3), n, 3, dimnames = list(paste0("item", 1:n)))
  emb_b_mismatched <- emb_a[1:8, ]
  emb_tiny <- emb_a[1:3, ]

  expect_error(find_discrepant_items(unname(emb_a), emb_a), "row names")
  expect_error(find_discrepant_items(emb_a, emb_b_mismatched), "same set of items")
  expect_error(find_discrepant_items(emb_tiny, emb_tiny), "at least 4 items")
  expect_error(find_discrepant_items(emb_a, emb_a, k = 0L), "k must be at least 1")
})
