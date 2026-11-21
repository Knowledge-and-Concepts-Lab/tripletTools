skip_if_not_installed("reticulate")
skip_if(
  inherits(tryCatch(.get_compute_py(), error = function(e) e), "error"),
  "Python embedding backend not available"
)

n_items <- 6
items <- paste0("item", seq_len(n_items))
true_coords <- matrix(cbind(seq_len(n_items), 0), n_items, 2,
                       dimnames = list(items, c("x", "y")))

# A sampleSet = NA block (check trials and, historically, holdout-validation
# trials both look like this) -- still useful here to exercise the
# NA-sampleSet regression (see below), even though estimate_group_alpha()
# no longer reads sampleAlg at all.
add_na_sampleset_block <- function(trips, true_coords, n_block = 20L, seed = 99L) {
  items <- rownames(true_coords)
  set.seed(seed)
  center <- sample(items, n_block, replace = TRUE)
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

trips <- add_na_sampleset_block(trips_novval, true_coords)

test_that("errors clearly when warm_start has no row names", {
  warm_start <- matrix(rnorm(n_items * 2), n_items, 2)
  expect_error(
    estimate_group_alpha(trips, warm_start = warm_start, max_outer = 1L),
    "warm_start"
  )
})

test_that("runs end to end without any sampleAlg == 'validation' trials", {
  # This used to be the error case (no validation trials found); now alpha
  # is profiled from a split of the test pool instead, so no validation
  # trials are required at all.
  grp <- run_group_embedding_from_list(trips_novval, d = 2L, max_epochs = 50L, tol_window = 20L, seed = 1L)
  joint <- estimate_group_alpha(
    trips_novval, warm_start = grp$embedding,
    max_epochs = 50L, tol_window = 20L, max_outer = 2L, seed = 1L, verbose = FALSE
  )
  expect_equal(sort(rownames(joint$embedding)), sort(items))
  expect_true(is.finite(joint$alpha) && joint$alpha > 0)
})

# Epoch/iteration counts here are as small as possible while still
# exercising the real fitting loop -- this checks that the procedure runs
# correctly end to end and returns sane, finite structure, not that it
# converges to a scientifically meaningful alpha (that was validated
# separately against real and simulated data with a known generating
# alpha, outside the test suite).
test_that("estimate_group_alpha() runs end to end and returns well-formed output", {
  grp <- run_group_embedding_from_list(trips, d = 2L, max_epochs = 50L, tol_window = 20L, seed = 1L)

  # Regression check: a previous version of this function computed
  # train/test row selection as `combined$sampleSet == "train"`/`"test"`
  # directly, without first excluding sampleSet == NA rows (check trials
  # and, in this fixture, an extra NA-sampleSet block) -- `NA == "train"` is
  # `NA`, not `FALSE`, and subsetting a data frame with a logical vector
  # containing NA inserts an all-NA row, which crashed the Python call
  # with an out-of-bounds index once cast to int32. This fixture's extra
  # block (sampleSet = NA) exercises exactly that path.
  joint <- estimate_group_alpha(
    trips, warm_start = grp$embedding,
    max_epochs = 50L, tol_window = 20L, max_outer = 2L, seed = 1L, verbose = FALSE
  )

  expect_equal(sort(rownames(joint$embedding)), sort(items))
  expect_equal(ncol(joint$embedding), 2L)
  expect_false(anyNA(joint$embedding))

  expect_true(is.finite(joint$alpha) && joint$alpha > 0)
  expect_length(joint$ci, 2L)
  expect_true(all(is.finite(joint$ci)))
  expect_lte(joint$ci[1], joint$ci[2])

  expect_true(nrow(joint$history) >= 1L && nrow(joint$history) <= 2L)
  expect_true(all(joint$history$alpha > 0))
  expect_true(all(is.finite(joint$history$ll_alpha_test)))
  expect_true(all(joint$history$acc_alpha_test >= 0 & joint$history$acc_alpha_test <= 1))
  expect_true(all(joint$history$delta_log_alpha >= 0))
})

test_that("alpha_test_frac splits the test pool into disjoint sub-pools of the expected sizes", {
  grp <- run_group_embedding_from_list(trips_novval, d = 2L, max_epochs = 50L, tol_window = 20L, seed = 1L)

  n_test_total <- sum(do.call(rbind, trips_novval)$sampleSet == "test", na.rm = TRUE)

  joint_half <- estimate_group_alpha(
    trips_novval, warm_start = grp$embedding,
    max_epochs = 50L, tol_window = 20L, max_outer = 1L, seed = 1L,
    alpha_test_frac = 0.5, verbose = FALSE
  )
  expect_equal(joint_half$n_test_fit + joint_half$n_alpha_test, n_test_total)
  expect_equal(joint_half$n_alpha_test, floor(0.5 * n_test_total))

  joint_small <- estimate_group_alpha(
    trips_novval, warm_start = grp$embedding,
    max_epochs = 50L, tol_window = 20L, max_outer = 1L, seed = 1L,
    alpha_test_frac = 0.2, verbose = FALSE
  )
  expect_equal(joint_small$n_test_fit + joint_small$n_alpha_test, n_test_total)
  expect_equal(joint_small$n_alpha_test, floor(0.2 * n_test_total))
  expect_lt(joint_small$n_alpha_test, joint_half$n_alpha_test)
})

test_that("alpha_test_rows reports real positions of alpha-test rows in do.call(rbind, triplet_list)", {
  grp <- run_group_embedding_from_list(trips_novval, d = 2L, max_epochs = 50L, tol_window = 20L, seed = 1L)
  joint <- estimate_group_alpha(
    trips_novval, warm_start = grp$embedding,
    max_epochs = 50L, tol_window = 20L, max_outer = 1L, seed = 1L,
    alpha_test_frac = 0.3, verbose = FALSE
  )

  expect_length(joint$alpha_test_rows, joint$n_alpha_test)
  expect_equal(length(unique(joint$alpha_test_rows)), joint$n_alpha_test)  # no duplicates

  combined <- do.call(rbind, trips_novval)
  expect_true(all(joint$alpha_test_rows >= 1L & joint$alpha_test_rows <= nrow(combined)))
  # Every reported position really was sampleSet == "test" beforehand, and
  # none of them is a check/NA-sampleSet row.
  expect_true(all(combined$sampleSet[joint$alpha_test_rows] == "test"))
})
