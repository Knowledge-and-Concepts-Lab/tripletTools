make_trip_row <- function(worker_id, center, left, right, answer = left,
                           sampleAlg = "random") {
  data.frame(worker_id = worker_id, Center = center, Left = left, Right = right,
             Answer = answer, sampleAlg = sampleAlg, stringsAsFactors = FALSE)
}

test_that("find_frequent_triplets() counts distinct participants, not raw rows", {
  # Triplet A-B-C judged by 3 different participants (once each) -- Left/Right
  # swapped on one of them, which should NOT create a second triplet.
  p1 <- make_trip_row("p1", "A", "B", "C")
  p2 <- make_trip_row("p2", "A", "C", "B")  # left/right swapped
  p3 <- make_trip_row("p3", "A", "B", "C")
  # A different, unrelated singleton triplet.
  p3 <- rbind(p3, make_trip_row("p3", "X", "Y", "Z"))

  triplet_list <- list(p1 = p1, p2 = p2, p3 = p3)
  res <- find_frequent_triplets(triplet_list, n = 10)

  expect_s3_class(res, "data.frame")
  expect_equal(names(res), c("triplet", "Center", "Left", "Right", "n_participants", "n_trials"))

  abc <- res[res$Center == "A", ]
  expect_equal(nrow(abc), 1L)  # left/right swap collapsed into one row
  expect_equal(abc$n_participants, 3L)
  expect_equal(abc$n_trials, 3L)

  xyz <- res[res$Center == "X", ]
  expect_equal(xyz$n_participants, 1L)
  expect_equal(xyz$n_trials, 1L)

  # Most frequent first.
  expect_equal(res$triplet[1], abc$triplet)
})

test_that("a repeated trial by the same participant inflates n_trials but not n_participants", {
  p1 <- rbind(make_trip_row("p1", "A", "B", "C"),
              make_trip_row("p1", "A", "C", "B"))  # same participant, same triplet, swapped sides
  p2 <- make_trip_row("p2", "A", "B", "C")

  res <- find_frequent_triplets(list(p1 = p1, p2 = p2), n = 10)
  expect_equal(nrow(res), 1L)
  expect_equal(res$n_participants, 2L)
  expect_equal(res$n_trials, 3L)
})

test_that("same three items with a different Center counts as a different triplet", {
  p1 <- make_trip_row("p1", "A", "B", "C")
  p2 <- make_trip_row("p2", "B", "A", "C")  # same 3 items, different reference item

  res <- find_frequent_triplets(list(p1 = p1, p2 = p2), n = 10)
  expect_equal(nrow(res), 2L)
  expect_true(all(res$n_participants == 1L))
})

test_that("exclude_check drops check trials by default", {
  p1 <- rbind(make_trip_row("p1", "A", "B", "C", sampleAlg = "check"),
              make_trip_row("p1", "D", "E", "F"))
  p2 <- make_trip_row("p2", "A", "B", "C", sampleAlg = "check")

  res <- find_frequent_triplets(list(p1 = p1, p2 = p2), n = 10)
  expect_false("A" %in% res$Center)
  expect_true("D" %in% res$Center)

  res_kept <- find_frequent_triplets(list(p1 = p1, p2 = p2), n = 10, exclude_check = FALSE)
  expect_true("A" %in% res_kept$Center)
  expect_equal(res_kept[res_kept$Center == "A", "n_participants"], 2L)
})

test_that("n and min_participants control how many rows are returned", {
  p1 <- make_trip_row("p1", "A", "B", "C")
  p2 <- make_trip_row("p2", "A", "B", "C")
  p3 <- make_trip_row("p3", "D", "E", "F")

  res_n1 <- find_frequent_triplets(list(p1 = p1, p2 = p2, p3 = p3), n = 1)
  expect_equal(nrow(res_n1), 1L)
  expect_equal(res_n1$Center, "A")

  res_thresh <- find_frequent_triplets(list(p1 = p1, p2 = p2, p3 = p3), n = 10,
                                        min_participants = 2)
  expect_equal(nrow(res_thresh), 1L)
  expect_equal(res_thresh$Center, "A")
})

test_that("find_frequent_triplets() validates its inputs", {
  p1 <- make_trip_row("p1", "A", "B", "C")
  expect_error(find_frequent_triplets(p1), "list")
  expect_error(find_frequent_triplets(list(p1 = p1), n = 0), "n must be at least 1")
  expect_error(find_frequent_triplets(list(p1 = p1), min_participants = 0),
               "min_participants must be at least 1")

  no_worker <- p1
  no_worker$worker_id <- NULL
  expect_error(find_frequent_triplets(list(a = no_worker)), "worker_id")
})

test_that("find_frequent_triplets() recovers icon_triplets' known repeated validation triplets", {
  combined <- do.call(rbind, icon_triplets)
  val_rows <- subset(combined, sampleAlg == "validation")
  val_rows$tripname <- make.tripnames(val_rows)
  tbl <- table(val_rows$tripname)
  max_n <- max(tbl)
  known_top <- sort(names(tbl[tbl == max_n]))

  res <- find_frequent_triplets(icon_triplets, n = length(known_top))
  expect_equal(sort(res$triplet), known_top)
  expect_true(all(res$n_participants == max_n))
})
