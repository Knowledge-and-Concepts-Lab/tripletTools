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
