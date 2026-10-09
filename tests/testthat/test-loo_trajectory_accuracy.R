test_that("runs on real bundled data and returns the documented structure", {
  repdist <- get.rep.dist(icon_emb_ind)
  res <- loo_trajectory_accuracy(repdist, icon_emb_ind, icon_triplets, n_query = 5, verbose = FALSE)

  n <- length(icon_emb_ind)
  expect_equal(dim(res$accuracy), c(n, 5))
  expect_equal(dim(res$query_points), c(n, 5))
  expect_equal(dim(res$effective_n), c(n, 5))
  expect_length(res$full_sample_position, n)
  expect_identical(rownames(res$accuracy), names(icon_emb_ind))
  expect_true(all(res$accuracy >= 0 & res$accuracy <= 1, na.rm = TRUE))
})

test_that("errors on mismatched lengths or invalid n_query", {
  repdist <- get.rep.dist(icon_emb_ind)
  expect_error(
    loo_trajectory_accuracy(repdist, icon_emb_ind[-1], icon_triplets, n_query = 5),
    "elist must have the same length"
  )
  expect_error(
    loo_trajectory_accuracy(repdist, icon_emb_ind, icon_triplets[-1], n_query = 5),
    "triplet_list must have the same length"
  )
  expect_error(
    loo_trajectory_accuracy(repdist, icon_emb_ind, icon_triplets, n_query = 0),
    "n_query must be at least 1"
  )
})

test_that("errors when elist and triplet_list are named but in a different order", {
  repdist <- get.rep.dist(icon_emb_ind)
  shuffled_triplets <- icon_triplets[rev(names(icon_triplets))]
  expect_error(
    loo_trajectory_accuracy(repdist, icon_emb_ind, shuffled_triplets, n_query = 5),
    "not in the same order"
  )
})

test_that("no spurious crossover on synthetic data with zero true shared structure", {
  # Regression test for the real leakage bug this function was built to fix:
  # smooth_embedding_trajectory(), used directly without leave-one-out
  # exclusion, produced a strong "significant"-looking crossover pattern
  # (R-squared 0.27, p = 0.003) on this exact kind of data -- participants
  # with fully independent, unrelated true embeddings, so zero real shared
  # structure by construction -- purely because each participant's own
  # embedding contributes to the same smoothed query-point embeddings later
  # evaluated against them. This function fixes that by fully excluding each
  # participant, including from the 1-D axis itself, before computing the
  # trajectory evaluated against them.
  set.seed(1)
  n_participants <- 20
  n_items <- 12
  items <- paste0("item", 1:n_items)
  d_emb <- 3

  true_embs <- lapply(seq_len(n_participants), function(i) {
    m <- matrix(rnorm(n_items * d_emb), n_items, d_emb)
    rownames(m) <- items
    colnames(m) <- paste0("dim_", 0:(d_emb - 1))
    m
  })
  names(true_embs) <- paste0("p", seq_len(n_participants))

  mu <- 1
  n_trials <- 60
  make_triplets <- function(emb) {
    rows <- lapply(seq_len(n_trials), function(t) {
      idx <- sample(n_items, 3)
      center <- items[idx[1]]; a <- items[idx[2]]; b <- items[idx[3]]
      da <- sum((emb[center, ] - emb[a, ])^2)
      db <- sum((emb[center, ] - emb[b, ])^2)
      p_a <- ckl_prob(da, db, mu)
      answer <- if (runif(1) < p_a) a else b
      data.frame(Center = center, Left = a, Right = b, Answer = answer,
                 sampleAlg = "validation", sampleSet = NA_character_,
                 stringsAsFactors = FALSE)
    })
    do.call(rbind, rows)
  }
  triplets <- lapply(true_embs, make_triplets)
  names(triplets) <- names(true_embs)

  repdist <- get.rep.dist(true_embs)
  res <- loo_trajectory_accuracy(repdist, true_embs, triplets, n_query = 10, verbose = FALSE)

  diff_endpoints <- res$accuracy[, 1] - res$accuracy[, 10]
  m <- lm(diff_endpoints ~ res$full_sample_position)
  expect_gt(summary(m)$coefficients[2, 4], 0.05)
})
