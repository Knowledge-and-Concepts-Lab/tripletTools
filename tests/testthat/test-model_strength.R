test_that("Model strength computation works.", {

  emb <- cfd_embeddings[[10]] # Embedding from participant 10
  trips <- cfd_triplets[[10]] #Triplet judgments from participant 10

  #Validation trials only:
  vdat <- subset(trips, trips$sampleAlg=="validation")

  mstrength <- model.strength(emb, vdat)

  result <- round(mstrength[1], 2)
  expected <- 0.67

  expect_equal(result, expected)
})
