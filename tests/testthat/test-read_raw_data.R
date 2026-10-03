make_valid_raw_csv <- function(path, worker_id = "p1", n = 10) {
  items <- paste0("item", seq_len(4))
  set.seed(1)
  head_vals <- sample(items, n, replace = TRUE)
  choice_pairs <- lapply(head_vals, function(h) sample(setdiff(items, h), 2))
  choices <- vapply(choice_pairs, function(p) paste0("[\"", p[1], "\",\"", p[2], "\"]"), character(1))
  d <- data.frame(
    trial_index    = seq_len(n),
    rt             = sample(400:900, n, replace = TRUE),
    stimulus       = head_vals,
    choices        = choices,
    response       = sample(c("arrowleft", "arrowright"), n, replace = TRUE),
    trial_category = "random",
    worker_id      = worker_id,
    stringsAsFactors = FALSE
  )
  readr::write_csv(d, path)
}

make_stray_embeddings_csv <- function(path) {
  d <- data.frame(
    dim_0 = rnorm(4), dim_1 = rnorm(4),
    item = paste0("item", 1:4), worker_id = "p1"
  )
  readr::write_csv(d, path)
}

test_that("a stray non-trial CSV is skipped with a warning, not a hard error", {
  tmp_dir <- tempfile("raw_data_")
  dir.create(tmp_dir)
  valid_file <- file.path(tmp_dir, "valid_export.csv")
  stray_file <- file.path(tmp_dir, "embeddings_all_prolific.csv")
  make_valid_raw_csv(valid_file)
  make_stray_embeddings_csv(stray_file)

  expect_warning(
    res <- read_raw_data(data_dir = tmp_dir, output_df = NULL, output_levels = NULL,
                          min_trials = 0, min_mean_rt_ms = 0, max_prop_wrong = 1.0),
    "embeddings_all_prolific.csv"
  )

  expect_equal(nrow(res$trials), 10)
  expect_true(all(res$trials$worker_id == "p1"))
})

test_that("an all-stray directory gives a clear error instead of a cryptic downstream failure", {
  tmp_dir <- tempfile("raw_data_all_stray_")
  dir.create(tmp_dir)
  make_stray_embeddings_csv(file.path(tmp_dir, "embeddings_only.csv"))

  expect_error(
    suppressWarnings(read_raw_data(data_dir = tmp_dir, output_df = NULL, output_levels = NULL)),
    "No CSV files in .* contained a recognized trial-category column"
  )
})

test_that("a directory with only valid files reads with no warning", {
  tmp_dir <- tempfile("raw_data_clean_")
  dir.create(tmp_dir)
  make_valid_raw_csv(file.path(tmp_dir, "valid_export.csv"))

  expect_no_warning(
    res <- read_raw_data(data_dir = tmp_dir, output_df = NULL, output_levels = NULL,
                          min_trials = 0, min_mean_rt_ms = 0, max_prop_wrong = 1.0)
  )
  expect_equal(nrow(res$trials), 10)
})
