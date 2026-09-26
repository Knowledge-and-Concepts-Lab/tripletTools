test_that("query_points defaults to n_query evenly-spaced points spanning positions", {
  set.seed(1)
  pos <- c(-2, -1, 0, 1, 2, 3)
  traj <- smooth_embedding_trajectory(icon_emb_ind, pos, n_query = 7)
  expect_length(traj$query_points, 7)
  expect_equal(min(traj$query_points), min(pos))
  expect_equal(max(traj$query_points), max(pos))
})

test_that("bandwidth defaults to bw.nrd0(positions) when not supplied", {
  pos <- c(-2, -1, 0, 1, 2, 3)
  traj <- smooth_embedding_trajectory(icon_emb_ind, pos, n_query = 5)
  expect_equal(traj$bandwidth, stats::bw.nrd0(pos))
})

test_that("a tiny bandwidth at a participant's own position recovers that participant's own GPA-aligned embedding", {
  pos <- c(-2, -1, 0, 1, 2, 3)
  gpa <- generalized_procrustes(icon_emb_ind)
  traj <- smooth_embedding_trajectory(icon_emb_ind, pos, query_points = pos[1],
                                       bandwidth = 1e-8, kernel = "epanechnikov")
  expect_equal(unname(traj$embeddings[[1]]), unname(gpa$aligned[[1]]), tolerance = 1e-6)
})

test_that("effective_n is n when weights are equal, and less than n otherwise", {
  pos <- c(-2, -1, 0, 1, 2, 3)
  # a bandwidth much larger than the spread of positions -> ~equal weights
  traj_wide <- smooth_embedding_trajectory(icon_emb_ind, pos, query_points = 0,
                                            bandwidth = 1000)
  expect_equal(traj_wide$effective_n, 6, tolerance = 1e-3)

  # a narrow bandwidth concentrates weight on nearby participants -> lower effective_n
  traj_narrow <- smooth_embedding_trajectory(icon_emb_ind, pos, query_points = 0,
                                              bandwidth = 0.3)
  expect_lt(traj_narrow$effective_n, 6)
})

test_that("embeddings have the right shape and dimnames", {
  pos <- c(-2, -1, 0, 1, 2, 3)
  traj <- smooth_embedding_trajectory(icon_emb_ind, pos, n_query = 4)
  for (emb in traj$embeddings) {
    expect_equal(dim(emb), dim(icon_emb_ind[[1]]))
    expect_equal(rownames(emb), rownames(icon_emb_ind[[1]]))
  }
})

test_that("errors on mismatched lengths or invalid arguments", {
  pos_bad <- c(-2, -1, 0)
  expect_error(smooth_embedding_trajectory(icon_emb_ind, pos_bad),
               "positions must have the same length as elist")

  pos <- c(-2, -1, 0, 1, 2, 3)
  expect_error(smooth_embedding_trajectory(icon_emb_ind, pos, bandwidth = -1),
               "bandwidth must be positive")
  expect_error(smooth_embedding_trajectory(icon_emb_ind, pos, n_query = 0),
               "n_query must be at least 1")
})

test_that("warns and returns NA for a query point with no meaningful weight", {
  pos <- c(-2, -1, 0, 1, 2, 3)
  expect_warning(
    traj <- smooth_embedding_trajectory(icon_emb_ind, pos, query_points = 1000,
                                         bandwidth = 0.01, kernel = "epanechnikov"),
    "meaningful weight"
  )
  expect_true(all(is.na(traj$embeddings[[1]])))
  expect_equal(traj$effective_n, 0)
})

test_that("same seed/inputs give identical results (deterministic)", {
  pos <- c(-2, -1, 0, 1, 2, 3)
  r1 <- smooth_embedding_trajectory(icon_emb_ind, pos, n_query = 5)
  r2 <- smooth_embedding_trajectory(icon_emb_ind, pos, n_query = 5)
  expect_identical(r1, r2)
})
