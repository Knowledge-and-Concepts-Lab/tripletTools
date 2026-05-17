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
