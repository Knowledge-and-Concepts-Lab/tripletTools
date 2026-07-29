# Small synthetic triplet_list fixture, structured like icon_triplets, used
# across embedding-pipeline smoke tests to exercise the pipeline end to end
# -- not to check fit quality.
make_fake_triplet_list <- function(n_participants = 2L, n_items = 5L,
                                    n_trials = 30L, seed = 1L) {
  set.seed(seed)
  items <- paste0("item", seq_len(n_items))
  lapply(seq_len(n_participants), function(p) {
    center <- sample(items, n_trials, replace = TRUE)
    left   <- vapply(center, function(c) sample(setdiff(items, c), 1), character(1))
    right  <- mapply(function(c, l) sample(setdiff(items, c(c, l)), 1), center, left)
    answer <- ifelse(stats::runif(n_trials) < 0.5, left, right)
    data.frame(
      Center = center, Left = left, Right = right, Answer = answer,
      sampleSet = rep(c("train", "test"), length.out = n_trials),
      sampleAlg = "random",
      worker_id = paste0("p", p),
      stringsAsFactors = FALSE
    )
  })
}
