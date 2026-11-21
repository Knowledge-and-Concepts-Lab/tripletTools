test_that("round-trips through get.combined()", {
  out <- tempfile(fileext = ".csv")
  write_triplet_list(icon_triplets, out)

  combined <- do.call(rbind, icon_triplets)
  rebuilt <- get.combined(out, eflag = FALSE)

  expect_setequal(names(rebuilt), unique(combined$worker_id))
  expect_equal(sum(vapply(rebuilt, nrow, integer(1))), nrow(combined))
  expect_equal(
    sort(rebuilt[[names(rebuilt)[1]]]$Center),
    sort(icon_triplets[[names(rebuilt)[1]]]$Center)
  )
})

test_that("works on an unnamed triplet_list (e.g. make_fake_triplet_list() fixtures)", {
  trips <- make_fake_triplet_list(n_participants = 3L, n_items = 5L, n_trials = 10L, seed = 1L)
  expect_null(names(trips))

  out <- tempfile(fileext = ".csv")
  write_triplet_list(trips, out)

  rebuilt <- get.combined(out, eflag = FALSE)
  expect_setequal(names(rebuilt), c("p1", "p2", "p3"))
  expect_equal(nrow(rebuilt[["p2"]]), 10)
})

test_that("participants with mismatched columns are combined via bind_rows, not rbind", {
  trips <- make_fake_triplet_list(n_participants = 2L, n_items = 5L, n_trials = 5L, seed = 2L)
  trips[[1]]$rt <- seq_len(5)  # only participant 1 has a 'rt' column

  out <- tempfile(fileext = ".csv")
  write_triplet_list(trips, out)

  written <- read.csv(out)
  expect_true("rt" %in% names(written))
  expect_true(all(is.na(written$rt[written$worker_id == "p2"])))
  expect_false(any(is.na(written$rt[written$worker_id == "p1"])))
})

test_that("errors clearly on malformed input", {
  expect_error(write_triplet_list(list(), tempfile()), "empty")
  expect_error(write_triplet_list(icon_triplets[[1]], tempfile()), "list of per-participant")
  expect_error(write_triplet_list(list(1:3), tempfile()), "data frame")

  no_worker_id <- icon_triplets[[1]]
  no_worker_id$worker_id <- NULL
  expect_error(write_triplet_list(list(no_worker_id), tempfile()), "worker_id")
})

test_that("returns the file path invisibly", {
  out <- tempfile(fileext = ".csv")
  result <- withVisible(write_triplet_list(icon_triplets, out))
  expect_equal(result$value, out)
  expect_false(result$visible)
})
