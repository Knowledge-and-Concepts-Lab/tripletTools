skip_if_not_installed("reticulate")
skip_if(
  inherits(tryCatch(.get_compute_py(), error = function(e) e), "error"),
  "Python embedding backend not available"
)

n_items <- 6
items <- paste0("item", seq_len(n_items))
true_coords <- matrix(cbind(seq_len(n_items), 0), n_items, 2,
                       dimnames = list(items, c("x", "y")))

# Same fixture convention as test-estimate_group_alpha.R: a fixed
# sampleAlg == "validation" block (sampleSet = NA, the package's holdout
# convention), internally consistent with true_coords, appended to every
# participant's data frame.
add_validation_block <- function(trips, true_coords, n_val = 20L, seed = 99L) {
  items <- rownames(true_coords)
  set.seed(seed)
  center <- sample(items, n_val, replace = TRUE)
  left   <- vapply(center, function(c) sample(setdiff(items, c), 1), character(1))
  right  <- mapply(function(c, l) sample(setdiff(items, c(c, l)), 1), center, left)
  d_left  <- sqrt(rowSums((true_coords[center, , drop = FALSE] - true_coords[left, , drop = FALSE])^2))
  d_right <- sqrt(rowSums((true_coords[center, , drop = FALSE] - true_coords[right, , drop = FALSE])^2))
  answer <- ifelse(d_left < d_right, left, right)
  val_block <- data.frame(
    Center = center, Left = left, Right = right, Answer = answer,
    sampleSet = NA_character_, sampleAlg = "validation",
    stringsAsFactors = FALSE
  )
  lapply(trips, function(df) {
    val_block$worker_id <- df$worker_id[1]
    rbind(df, val_block)
  })
}

trips_novval <- make_structured_triplet_list(true_coords, n_participants = 4, n_trials = 80, seed = 1)
names(trips_novval) <- paste0("p", 1:4)

trips <- add_validation_block(trips_novval, true_coords)

test_that("errors clearly for geometry = sphere with refit_alpha = TRUE", {
  # estimate_group_alpha() (step 3) does not currently support spherical
  # geometry -- this must be refused up front, before any (expensive)
  # fitting happens, rather than silently refitting a Euclidean embedding
  # when a spherical one was requested.
  expect_error(
    run_group_embedding_workflow(trips, dims = 1:2, geometry = "sphere", refit_alpha = TRUE),
    "sphere"
  )
})

# Epoch/restart/iteration counts here are as small as possible while still
# exercising the full three-step chain end to end -- this checks that the
# wrapper runs correctly and returns well-formed, consistent structure, not
# that it converges to a scientifically meaningful dimension/alpha (dimension
# selection and the joint alpha/embedding refit are each validated on their
# own, more realistic terms by estimate_dimensionality()'s and
# estimate_group_alpha()'s own test suites).
test_that("runs end to end with refit_alpha = TRUE and returns well-formed output", {
  out <- run_group_embedding_workflow(
    trips,
    dims = 1:2, n_restarts_dim = 2L, n_restarts_final = 2L,
    max_epochs = 50L, tol_window = 20L, seed = 1L,
    max_outer = 2L, verbose = FALSE
  )

  expect_true(out$best_d %in% 1:2)
  expect_true(all(c("results", "summary") %in% names(out$dimensionality)))
  expect_true(any(out$dimensionality$summary$best_d))

  expect_equal(ncol(out$final_fit$embedding), out$best_d)
  expect_equal(sort(rownames(out$final_fit$embedding)), sort(items))
  expect_true(is.finite(out$final_fit$loss))

  expect_false(is.null(out$refit))
  expect_equal(sort(rownames(out$refit$embedding)), sort(items))
  expect_equal(ncol(out$refit$embedding), out$best_d)
  expect_true(is.finite(out$refit$alpha) && out$refit$alpha > 0)
  expect_length(out$refit$ci, 2L)
})

test_that("refit_alpha = FALSE skips step 3 and works without validation trials", {
  # trips_novval has no sampleAlg == "validation" trials at all -- this must
  # still succeed, since step 3 is skipped entirely.
  out <- run_group_embedding_workflow(
    trips_novval,
    dims = 1:2, n_restarts_dim = 2L, n_restarts_final = 1L,
    max_epochs = 50L, tol_window = 20L, seed = 1L,
    refit_alpha = FALSE, verbose = FALSE
  )
  expect_null(out$refit)
  expect_false(is.null(out$final_fit))
  expect_equal(sort(rownames(out$final_fit$embedding)), sort(items))
})

test_that("multiple final-fit restarts keep the lowest test loss", {
  # A direct check that the restart loop's selection rule actually works:
  # running the same workflow with n_restarts_final = 1 vs. several restarts
  # should never produce a *worse* (higher) kept test loss on average when
  # more restarts are tried, since the single-restart case is one of the
  # candidates the multi-restart case also considers (same seed for restart
  # 1 in both cases).
  out1 <- run_group_embedding_workflow(
    trips_novval,
    dims = 1L, n_restarts_dim = 1L, n_restarts_final = 1L,
    max_epochs = 50L, tol_window = 20L, seed = 5L,
    refit_alpha = FALSE, verbose = FALSE
  )
  out3 <- run_group_embedding_workflow(
    trips_novval,
    dims = 1L, n_restarts_dim = 1L, n_restarts_final = 3L,
    max_epochs = 50L, tol_window = 20L, seed = 5L,
    refit_alpha = FALSE, verbose = FALSE
  )
  expect_lte(out3$final_fit$loss, out1$final_fit$loss)
})
