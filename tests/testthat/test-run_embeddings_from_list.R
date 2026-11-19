skip_if_not_installed("reticulate")
skip_if(
  inherits(tryCatch(.get_compute_py(), error = function(e) e), "error"),
  "Python embedding backend not available"
)

# Regression test for a real bug: when worker_id values are purely numeric
# (e.g. "87059", as in real jsPsych worker IDs -- not "p1"-style labels),
# pandas infers an int64 dtype for the per-worker chunks' worker_id column,
# but the group chunk's worker_id is the string 'group'. Concatenating an
# int-typed column with a str-typed one forces pandas to an object dtype
# holding genuinely mixed int/str values; reticulate's as.data.frame() then
# can't coerce that to one atomic R type and falls back to an R *list*
# column. Comparing a list column with == (as the per-worker split does)
# returns NA -- not FALSE -- for every row whose value doesn't coerce to
# the comparison type, and indexing a data frame with a logical selector
# containing NA inserts a bogus all-NA row for each one, which was
# silently doubling every individual participant's returned embedding with
# NA rows (confirmed against a real 36-item motion-triplets dataset during
# diagnosis). make_fake_triplet_list()'s default "p1"/"p2" worker IDs are
# already strings and do NOT trigger this -- numeric-looking IDs are
# required to reproduce it, so they're set explicitly below.
numeric_worker_trips <- make_fake_triplet_list(n_participants = 3L, n_items = 5L, n_trials = 30L, seed = 1L)
numeric_worker_trips <- lapply(seq_along(numeric_worker_trips), function(i) {
  df <- numeric_worker_trips[[i]]
  df$worker_id <- 1000L + i
  df
})
names(numeric_worker_trips) <- vapply(numeric_worker_trips, function(df) as.character(df$worker_id[1]), character(1))

test_that("individual embeddings have no bogus NA rows with numeric-looking worker IDs", {
  out_dir <- tempfile("run_embeddings_numeric_")
  res <- run_embeddings_from_list(
    triplet_list = numeric_worker_trips,
    output_dir   = out_dir,
    d            = 2L, max_epochs = 20L, tol_window = 10L, seed = 1L
  )

  all_item_names <- sort(unique(unlist(lapply(numeric_worker_trips, function(df) {
    c(df$Center, df$Left, df$Right)
  }))))

  expect_length(res$individual, 3L)
  for (nm in names(res$individual)) {
    emb <- res$individual[[nm]]
    expect_equal(nrow(emb), length(all_item_names))
    expect_equal(sort(rownames(emb)), all_item_names)
    expect_false(any(apply(emb, 1, function(r) all(is.na(r)))))
  }
  expect_equal(nrow(res$group), length(all_item_names))
  expect_false(any(apply(res$group, 1, function(r) all(is.na(r)))))
})

test_that("same seed reproduces identical individual and group embeddings", {
  # Regression test for a real bug: seed never actually controlled numpy/
  # torch's random_state for the Python fits (only Python's unused built-in
  # random module), so two calls with identical arguments -- including the
  # same seed -- produced different embeddings. Confirmed directly before
  # this fix: two back-to-back calls below with identical arguments gave
  # FALSE for every participant.
  trips <- make_fake_triplet_list(n_participants = 3L, n_items = 8L, n_trials = 60L, seed = 7L)

  res_a <- run_embeddings_from_list(
    trips, tempfile("seed_a_"),
    d = 2L, max_epochs = 30L, tol_window = 15L, seed = 99L
  )
  res_b <- run_embeddings_from_list(
    trips, tempfile("seed_b_"),
    d = 2L, max_epochs = 30L, tol_window = 15L, seed = 99L
  )

  for (nm in names(res_a$individual)) {
    expect_identical(res_a$individual[[nm]], res_b$individual[[nm]])
  }
  expect_identical(res_a$group, res_b$group)
})

test_that("a different seed gives a different embedding (not a degenerate fixed point)", {
  trips <- make_fake_triplet_list(n_participants = 2L, n_items = 8L, n_trials = 60L, seed = 8L)

  res_a <- run_embeddings_from_list(
    trips, tempfile("seed_diff_a_"),
    d = 2L, max_epochs = 30L, tol_window = 15L, seed = 1L
  )
  res_b <- run_embeddings_from_list(
    trips, tempfile("seed_diff_b_"),
    d = 2L, max_epochs = 30L, tol_window = 15L, seed = 2L
  )

  expect_false(identical(res_a$individual[[1]], res_b$individual[[1]]))
})

test_that("the compute_group flag no longer perturbs individual embeddings (same seed)", {
  trips <- make_fake_triplet_list(n_participants = 3L, n_items = 8L, n_trials = 60L, seed = 9L)

  res_true <- run_embeddings_from_list(
    trips, tempfile("cg_rep_true_"),
    d = 2L, max_epochs = 30L, tol_window = 15L, seed = 42L, compute_group = TRUE
  )
  res_false <- run_embeddings_from_list(
    trips, tempfile("cg_rep_false_"),
    d = 2L, max_epochs = 30L, tol_window = 15L, seed = 42L, compute_group = FALSE
  )

  for (nm in names(res_true$individual)) {
    expect_identical(res_true$individual[[nm]], res_false$individual[[nm]])
  }
})

test_that("compute_group = FALSE skips the group embedding entirely", {
  trips <- make_fake_triplet_list(n_participants = 3L, n_items = 5L, n_trials = 30L, seed = 3L)
  out_dir <- tempfile("run_embeddings_no_group_")
  res <- run_embeddings_from_list(
    triplet_list  = trips,
    output_dir    = out_dir,
    d             = 2L, max_epochs = 20L, tol_window = 10L, seed = 1L,
    compute_group = FALSE
  )

  expect_null(res$group)
  expect_length(res$individual, 3L)
  expect_false("group" %in% res$history$worker_id)
  expect_false(file.exists(file.path(out_dir, "embeddings_group.csv")))

  all_item_names <- sort(unique(unlist(lapply(trips, function(df) {
    c(df$Center, df$Left, df$Right)
  }))))
  for (nm in names(res$individual)) {
    emb <- res$individual[[nm]]
    expect_equal(nrow(emb), length(all_item_names))
    expect_false(any(apply(emb, 1, function(r) all(is.na(r)))))
  }
})

test_that("a leading-zero numeric-looking worker_id is not silently truncated", {
  # Regression test for a real bug: process_all_workers() read its input CSV
  # via pd.read_csv(input_file) with no dtype hint, so pandas infers an
  # int64 dtype for an all-digit worker_id column -- silently dropping any
  # leading zero (e.g. "0080102887" read back as the integer 80102887, then
  # str()'d to "80102887") even though the CSV text itself, written by R,
  # has the leading zero intact. This is the same bug class already fixed
  # on the R-reading side in get.combined() (colClasses forcing worker_id to
  # character), but here on the Python-reading side that feeds this
  # per-worker loop -- confirmed to matter downstream in practice: the
  # condor_joint_manifold_workflow.py orchestrator intersects triplet-file
  # worker_ids against embedding-file worker_ids, and a worker_id corrupted
  # this way in the embeddings output no longer matches its own correct,
  # zero-padded worker_id in the (separately-written) triplet file, so that
  # participant is silently dropped from the whole workflow.
  # The whole worker_id column must be all-digit for pandas to infer int64
  # in the first place -- a mix with non-numeric IDs (e.g. "p1") keeps the
  # column as object dtype and never triggers the bug, so every participant
  # here gets a purely numeric-looking worker_id, not just the one with a
  # leading zero.
  lz_trips <- make_fake_triplet_list(n_participants = 2L, n_items = 5L, n_trials = 30L, seed = 4L)
  lz_trips[[1]]$worker_id <- "0012345678"
  names(lz_trips)[1] <- "0012345678"
  lz_trips[[2]]$worker_id <- "9988776655"
  names(lz_trips)[2] <- "9988776655"

  out_dir <- tempfile("run_embeddings_leading_zero_")
  res <- run_embeddings_from_list(
    triplet_list = lz_trips,
    output_dir   = out_dir,
    d            = 2L, max_epochs = 20L, tol_window = 10L, seed = 1L
  )

  expect_true("0012345678" %in% names(res$individual))
  expect_false(any(grepl("^12345678$", names(res$individual))))
})

test_that("string worker IDs (unaffected by the dtype bug) still work", {
  trips <- make_fake_triplet_list(n_participants = 2L, n_items = 5L, n_trials = 30L, seed = 2L)
  out_dir <- tempfile("run_embeddings_string_")
  res <- run_embeddings_from_list(
    triplet_list = trips,
    output_dir   = out_dir,
    d            = 2L, max_epochs = 20L, tol_window = 10L, seed = 1L
  )

  all_item_names <- sort(unique(unlist(lapply(trips, function(df) {
    c(df$Center, df$Left, df$Right)
  }))))

  for (nm in names(res$individual)) {
    emb <- res$individual[[nm]]
    expect_equal(nrow(emb), length(all_item_names))
    expect_false(any(apply(emb, 1, function(r) all(is.na(r)))))
  }
})
