test_that("strsplit1() splits a string", {
  expect_equal(strsplit1("a,b,c", ","), c("a","b","c"))
})
