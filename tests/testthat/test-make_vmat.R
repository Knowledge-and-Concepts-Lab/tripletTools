test_that("make validation matrix works", {

  vmat <- make.vmat(icon_triplets)

  result <- round(vmat[[1]][1,3],2)
  expected <- 1
  expect_equal(result, expected)
})

test_that("make.vmat() reports n/nmaj/p/sig consistently", {
  vmat <- make.vmat(icon_triplets)
  majority <- vmat$majority

  expect_true(all(c("n", "nmaj", "p", "sig") %in% names(majority)))
  expect_true(all(majority$nmaj <= majority$n))
  expect_equal(majority$pmaj, majority$nmaj / majority$n)
  expect_equal(majority$sig, majority$p < 0.05)

  # p is the one-sided P(X >= nmaj) under Binomial(n, 0.5) -- cross-check
  # directly against stats::binom.test() for a representative row, not just
  # against the function's own internal pbinom() call.
  i <- which.max(majority$n)
  expected_p <- binom.test(majority$nmaj[i], majority$n[i], p = 0.5,
                            alternative = "greater")$p.value
  expect_equal(majority$p[i], expected_p)

  # A triplet with every judgment agreeing (nmaj == n) should be the most
  # significant available, and one with only a single judgment can never be
  # significant (p >= 0.5) regardless of how it's cast, since Binomial(1, 0.5)
  # can't distinguish agreement from chance.
  single_judgment <- majority[majority$n == 1, ]
  if (nrow(single_judgment) > 0) {
    expect_true(all(single_judgment$p >= 0.5 - 1e-8))
    expect_true(all(!single_judgment$sig))
  }
})
