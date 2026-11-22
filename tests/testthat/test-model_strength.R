test_that("Model strength computation works.", {

  emb <- icon_emb_ind[[1]] #Embedding from participant 1
  trips <- icon_triplets[[1]] #Triplet judgments from participant 1

  #Validation trials only:
  vdat <- subset(trips, trips$sampleAlg=="validation")

  mstrength <- model.strength(emb, vdat)

  result <- round(mstrength[1], 2)
  expected <- 0.5

  expect_equal(result, expected)
})

test_that("model.strength with alpha returns the TSTE choice-model probability of the predicted winner", {

  emb <- icon_emb_ind[[1]]
  trips <- icon_triplets[[1]]
  vdat <- subset(trips, trips$sampleAlg == "validation")

  pwin <- model.strength(emb, vdat, alpha = 1)

  # Always the probability of whichever option is predicted to win, so
  # always >= 0.5 and <= 1.
  expect_true(all(pwin >= 0.5 & pwin <= 1))
  expect_equal(length(pwin), nrow(vdat))

  # Hand-computed check against the vendored TSTE formula for one row.
  dmat <- as.matrix(dist(emb))
  items <- rownames(dmat)
  i <- 1
  d1 <- dmat[match(vdat$Center[i], items), match(vdat$Left[i], items)]
  d2 <- dmat[match(vdat$Center[i], items), match(vdat$Right[i], items)]
  alpha <- 1
  pwr <- -(alpha + 1) / 2
  t1 <- (1 + d1^2 / alpha)^pwr
  t2 <- (1 + d2^2 / alpha)^pwr
  p1 <- t1 / (t1 + t2)
  expected <- max(p1, 1 - p1)

  expect_equal(pwin[i], expected)

  # alpha = NULL (default) must reproduce the original distance-ratio metric
  # exactly -- the new argument shouldn't change existing behavior.
  mstrength <- model.strength(emb, vdat)
  expect_equal(model.strength(emb, vdat, alpha = NULL), mstrength)
})
