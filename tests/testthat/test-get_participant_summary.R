test_that("Creation of participant summary file works.", {
  #Example data path
  fpath <- system.file("extdata", "icon_all_triplets.csv", package = "tripletTools")

  #Read example data
  trips <- get.combined(fpath)

  #compute summary
  part.summary <- get.participant.summary(trips)

  result <- part.summary[1,1]
  expected <- '3n7ggxph'

  expect_equal(result, expected)
})

test_that("trial-type counts (ncheck/nvalidation/ntrain/ntest) are correct", {
  fpath <- system.file("extdata", "icon_all_triplets.csv", package = "tripletTools")
  trips <- get.combined(fpath)
  part.summary <- get.participant.summary(trips)

  # Cross-check against a direct tabulation of the raw data for one participant
  sdat <- trips[[1]]
  row <- part.summary[part.summary$worker_id == sdat$worker_id[1], ]
  expect_equal(row$ncheck, sum(sdat$sampleAlg == "check", na.rm = TRUE))
  expect_equal(row$nvalidation, sum(sdat$sampleAlg == "validation", na.rm = TRUE))
  expect_equal(row$ntrain, sum(sdat$sampleSet == "train", na.rm = TRUE))
  expect_equal(row$ntest, sum(sdat$sampleSet == "test", na.rm = TRUE))

  # sampleSet is train/test for every trial *except* check trials, which are
  # excluded (sampleSet == NA, see the package's own is.na(sampleSet)
  # convention for identifying them) -- validation trials already carry a
  # real train/test sampleSet value (which side depends on
  # train_with_validation), so they're a subset of ntrain/ntest, not a
  # separate additive category. Confirmed against the real data: every
  # check trial has sampleSet == NA, no train/test trial is ever miscounted.
  expect_true(all(part.summary$ntrain + part.summary$ntest + part.summary$ncheck
                   == part.summary$ndat))
})

make_participant <- function(worker_id, n = 10, sampleAlg = "random", sampleSet = "train", ...) {
  extra <- list(...)
  items <- letters[1:5]
  cyc <- function(offset) items[((seq_len(n) - 1 + offset) %% length(items)) + 1]
  # Deterministically varying (not constant, and not random -- avoiding any
  # chance of an accidentally-constant column making this test flaky)
  # Center/Left/Right/Answer/rt across trials, matching real trial-level
  # data, where these genuinely differ row to row (unlike
  # sampleAlg/sampleSet/worker_id, which really are constant across an
  # entire participant's data in these test fixtures).
  base <- data.frame(
    worker_id = worker_id,
    Center = cyc(0),
    Left   = cyc(1),
    Right  = cyc(2),
    Answer = cyc(1),
    rt     = seq(800, by = 37, length.out = n),
    sampleAlg = sampleAlg,
    sampleSet = sampleSet,
    stringsAsFactors = FALSE
  )
  if (length(extra)) base <- cbind(base, as.data.frame(extra, stringsAsFactors = FALSE))
  base
}

test_that("a constant per-participant field (e.g. task) is carried through, varying between participants", {
  d <- list(
    p1 = make_participant("p1", n = 5, task = "kind"),
    p2 = make_participant("p2", n = 5, task = "size")
  )
  summ <- get.participant.summary(d, mintrial = 1)
  expect_true("task" %in% names(summ))
  expect_equal(summ$task[summ$worker_id == "p1"], "kind")
  expect_equal(summ$task[summ$worker_id == "p2"], "size")
})

test_that("a field that varies within one participant's own rows gives NA for that participant only", {
  p1 <- make_participant("p1", n = 5, task = "kind")
  p2 <- make_participant("p2", n = 5, task = "size")
  p2$task <- c("size", "size", "kind", "size", "size")  # not constant for p2

  summ <- get.participant.summary(list(p1 = p1, p2 = p2), mintrial = 1)
  expect_equal(summ$task[summ$worker_id == "p1"], "kind")
  expect_true(is.na(summ$task[summ$worker_id == "p2"]))
})

test_that("a field present for only one participant gives NA for the participant lacking it", {
  p1 <- make_participant("p1", n = 5, task = "kind")
  p2 <- make_participant("p2", n = 5)  # no task column at all

  summ <- get.participant.summary(list(p1 = p1, p2 = p2), mintrial = 1)
  expect_equal(summ$task[summ$worker_id == "p1"], "kind")
  expect_true(is.na(summ$task[summ$worker_id == "p2"]))
})

test_that("worker_id is not duplicated as an extra field", {
  d <- list(p1 = make_participant("p1", n = 5, task = "kind"))
  summ <- get.participant.summary(d, mintrial = 1)
  expect_equal(sum(names(summ) == "worker_id"), 1)
})

test_that("missing sampleAlg (legacy data with no check/validation trials) gives 0, not an error", {
  p1 <- make_participant("p1", n = 5, sampleSet = "train")
  p1$sampleAlg <- NULL  # simulate legacy data with no sampleAlg column at all

  summ <- get.participant.summary(list(p1 = p1), mintrial = 1)
  expect_equal(summ$ncheck, 0)
  expect_equal(summ$nvalidation, 0)
  expect_equal(summ$ntrain, 5)
  expect_equal(summ$cacc, 1.0)  # automatic pass, no check trials to assess
})

test_that("no extra columns are added when no field is constant per participant", {
  # A single-condition participant (one sampleAlg/sampleSet value for every
  # trial, as make_participant() defaults to) makes sampleAlg/sampleSet
  # themselves genuinely constant, and correctly picked up as extra fields
  # -- see the "trial-type counts" test above for that case. This test
  # instead uses realistically mixed trial types, under which sampleAlg/
  # sampleSet vary within the participant and should NOT be added.
  p1 <- make_participant("p1", n = 6)
  p1$sampleAlg <- c("random", "random", "random", "check", "validation", "random")
  p1$sampleSet <- c("train", "test", "train", NA, "train", "test")

  summ <- get.participant.summary(list(p1 = p1), mintrial = 1)
  expect_setequal(names(summ), c("tripfile", "worker_id", "ndat", "lrt", "cacc",
                                  "ncheck", "nvalidation", "ntrain", "ntest", "keep"))
})
