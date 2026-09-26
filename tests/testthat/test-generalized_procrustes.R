make_rotated_list <- function(seed, n_embeds = 5, n_items = 8, n_dim = 2, noise_sd = 0) {
  set.seed(seed)
  base <- matrix(rnorm(n_items * n_dim), n_items, n_dim)
  lapply(seq_len(n_embeds), function(i) {
    theta <- runif(1, 0, 2 * pi)
    R <- matrix(c(cos(theta), sin(theta), -sin(theta), cos(theta)), 2, 2)
    scale_factor <- runif(1, 0.5, 2)
    shift <- rnorm(n_dim, sd = 5)
    noisy <- base + matrix(rnorm(n_items * n_dim, sd = noise_sd), n_items, n_dim)
    sweep(noisy %*% R * scale_factor, 2, shift, `+`)
  })
}

test_that("recovers a shared configuration from noiselessly rotated/scaled/shifted copies", {
  elist <- make_rotated_list(seed = 1, noise_sd = 0)
  gpa <- generalized_procrustes(elist)

  expect_true(gpa$converged)
  # every aligned embedding should now closely match every other one
  pairwise_diffs <- sapply(2:length(gpa$aligned), function(i) {
    max(abs(gpa$aligned[[i]] - gpa$aligned[[1]]))
  })
  expect_true(all(pairwise_diffs < 1e-4))
})

test_that("consensus does not collapse to (near-)zero size when scale = TRUE", {
  # Regression test for a real bug: without renormalizing the consensus
  # each iteration, its sum of squares decayed geometrically toward exactly
  # zero (never stabilizing), so every aligned embedding came out at
  # ~1e-6 magnitude regardless of the actual data.
  gpa <- generalized_procrustes(icon_emb_ind)
  expect_gt(sum(gpa$consensus^2), 1e-3)
  for (a in gpa$aligned) expect_gt(sum(a^2), 1e-3)
})

test_that("scale = FALSE does not force a fixed size", {
  elist <- make_rotated_list(seed = 2, noise_sd = 0)
  gpa <- generalized_procrustes(elist, scale = FALSE)
  expect_true(gpa$converged)
  expect_gt(sum(gpa$consensus^2), 1e-3)
})

test_that("aligned embeddings and consensus preserve item dimnames", {
  gpa <- generalized_procrustes(icon_emb_ind)
  expect_equal(rownames(gpa$consensus), rownames(icon_emb_ind[[1]]))
  expect_equal(colnames(gpa$consensus), colnames(icon_emb_ind[[1]]))
  for (nm in names(icon_emb_ind)) {
    expect_equal(rownames(gpa$aligned[[nm]]), rownames(icon_emb_ind[[1]]))
  }
  expect_equal(names(gpa$aligned), names(icon_emb_ind))
})

test_that("same input gives identical results (deterministic, no randomness)", {
  r1 <- generalized_procrustes(icon_emb_ind)
  r2 <- generalized_procrustes(icon_emb_ind)
  expect_identical(r1, r2)
})

test_that("errors on too few embeddings or mismatched dimensions", {
  expect_error(generalized_procrustes(icon_emb_ind[1]), "at least 2 embeddings")

  bad <- icon_emb_ind
  bad[[1]] <- bad[[1]][, 1:2]
  expect_error(generalized_procrustes(bad), "same dimensions")
})
