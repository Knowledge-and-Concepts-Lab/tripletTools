make_trip_row <- function(worker_id, center, left, right, answer = left,
                           sampleAlg = "random") {
  data.frame(worker_id = worker_id, Center = center, Left = left, Right = right,
             Answer = answer, sampleAlg = sampleAlg, stringsAsFactors = FALSE)
}

test_that("promotes rows matching candidate triplets, left/right-independent", {
  p1 <- rbind(make_trip_row("p1", "A", "B", "C"),
              make_trip_row("p1", "X", "Y", "Z"))
  p2 <- make_trip_row("p2", "A", "C", "B")  # same triplet as p1's first row, swapped

  triplet_list <- list(p1 = p1, p2 = p2)
  freq <- find_frequent_triplets(triplet_list, n = 10, min_participants = 2)

  res <- assign_validation_from_frequency(triplet_list, freq, verbose = FALSE)

  expect_equal(res$p1$sampleAlg, c("validation", "random"))
  expect_equal(res$p2$sampleAlg, "validation")
})

test_that("check trials are never promoted even if they match a candidate", {
  p1 <- make_trip_row("p1", "A", "B", "C", sampleAlg = "check")
  p2 <- make_trip_row("p2", "A", "B", "C")

  triplet_list <- list(p1 = p1, p2 = p2)
  # Force the candidate through directly (as if found with exclude_check = FALSE)
  freq <- data.frame(triplet = "A_B_C", Center = "A", Left = "B", Right = "C",
                      n_participants = 2L, n_trials = 2L, stringsAsFactors = FALSE)

  res <- assign_validation_from_frequency(triplet_list, freq, verbose = FALSE)
  expect_equal(res$p1$sampleAlg, "check")
  expect_equal(res$p2$sampleAlg, "validation")
})

test_that("max_per_participant caps distinct triplets, prioritized by freq_triplets row order", {
  p1 <- rbind(make_trip_row("p1", "A", "B", "C"),
              make_trip_row("p1", "D", "E", "F"),
              make_trip_row("p1", "G", "H", "I"))
  triplet_list <- list(p1 = p1)

  # freq_triplets lists A_B_C first, then D_E_F, then G_H_I -- cap of 2
  # should keep the first two and drop the third.
  freq <- data.frame(
    triplet = c("A_B_C", "D_E_F", "G_H_I"),
    Center = c("A", "D", "G"), Left = c("B", "E", "H"), Right = c("C", "F", "I"),
    n_participants = c(3L, 2L, 1L), n_trials = c(3L, 2L, 1L),
    stringsAsFactors = FALSE
  )

  res <- assign_validation_from_frequency(triplet_list, freq, max_per_participant = 2,
                                           verbose = FALSE)
  expect_equal(res$p1$sampleAlg, c("validation", "validation", "random"))
})

test_that("a repeated trial of the same triplet is kept or dropped together, never split", {
  p1 <- rbind(make_trip_row("p1", "A", "B", "C"),
              make_trip_row("p1", "A", "C", "B"),  # same triplet, repeated
              make_trip_row("p1", "D", "E", "F"))
  triplet_list <- list(p1 = p1)

  freq <- data.frame(triplet = c("A_B_C", "D_E_F"), Center = c("A", "D"),
                      Left = c("B", "E"), Right = c("C", "F"),
                      n_participants = c(1L, 1L), n_trials = c(2L, 1L),
                      stringsAsFactors = FALSE)

  # Cap of 1 distinct triplet -- A_B_C is first in freq, so both of its rows
  # should be promoted together, and D_E_F should not be promoted at all.
  res <- assign_validation_from_frequency(triplet_list, freq, max_per_participant = 1,
                                           verbose = FALSE)
  expect_equal(res$p1$sampleAlg, c("validation", "validation", "random"))
})

test_that("a participant with no matching trials is returned unchanged", {
  p1 <- make_trip_row("p1", "A", "B", "C")
  p2 <- make_trip_row("p2", "X", "Y", "Z")
  triplet_list <- list(p1 = p1, p2 = p2)

  freq <- find_frequent_triplets(triplet_list, n = 1, min_participants = 1)  # only one of the two
  res <- assign_validation_from_frequency(triplet_list, freq, verbose = FALSE)

  n_val <- sapply(res, function(df) sum(df$sampleAlg == "validation"))
  expect_equal(sum(n_val), 1L)
  expect_equal(sum(n_val == 0), 1L)
})

test_that("sampleSet and other columns are left untouched", {
  p1 <- make_trip_row("p1", "A", "B", "C")
  p1$sampleSet <- "train"
  p1$extra_col <- "keep me"
  p2 <- make_trip_row("p2", "A", "B", "C")
  p2$sampleSet <- "train"
  p2$extra_col <- "keep me too"

  triplet_list <- list(p1 = p1, p2 = p2)
  freq <- find_frequent_triplets(triplet_list, n = 10, min_participants = 2)
  res <- assign_validation_from_frequency(triplet_list, freq, verbose = FALSE)

  expect_equal(res$p1$sampleSet, "train")
  expect_equal(res$p1$extra_col, "keep me")
})

test_that("assign_validation_from_frequency() validates its inputs", {
  p1 <- make_trip_row("p1", "A", "B", "C")
  freq <- data.frame(triplet = "A_B_C")

  expect_error(assign_validation_from_frequency(p1, freq), "list")
  expect_error(assign_validation_from_frequency(list(p1 = p1), data.frame(x = 1)), "triplet")
  expect_error(assign_validation_from_frequency(list(p1 = p1), freq, max_per_participant = 0),
               "max_per_participant must be at least 1")

  no_alg <- p1
  no_alg$sampleAlg <- NULL
  expect_error(assign_validation_from_frequency(list(a = no_alg), freq), "sampleAlg")
})

test_that("end-to-end: promoted trials work correctly with set_validation_behavior() and get.hoacc()", {
  set.seed(1)
  items <- LETTERS[1:6]
  make_p <- function(id) {
    rows <- lapply(1:20, function(i) {
      trio <- sample(items, 3)
      make_trip_row(id, trio[1], trio[2], trio[3], trio[2])
    })
    df <- do.call(rbind, rows)
    df$sampleSet <- "train"
    df
  }
  triplet_list <- lapply(paste0("p", 1:5), make_p)
  names(triplet_list) <- paste0("p", 1:5)

  freq <- find_frequent_triplets(triplet_list, n = Inf, min_participants = 2)
  skip_if(nrow(freq) == 0, "no overlapping triplets in this random draw")

  res <- assign_validation_from_frequency(triplet_list, freq, verbose = FALSE)
  res_holdout <- set_validation_behavior(res, mode = "holdout")

  for (df in res_holdout) {
    is_val <- df$sampleAlg == "validation"
    expect_true(all(is.na(df$sampleSet[is_val])))
    expect_true(all(!is.na(df$sampleSet[!is_val])))
  }

  emb <- matrix(rnorm(length(items) * 2), length(items), 2,
                dimnames = list(items, NULL))
  acc <- get.hoacc(emb, res_holdout[[1]], trialtype = "validation")
  expect_true(is.numeric(acc) && acc >= 0 && acc <= 1)
})
