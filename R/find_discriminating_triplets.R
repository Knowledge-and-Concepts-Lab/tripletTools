# Internal helpers for find_discriminating_triplets(). Not exported.

# CKL win-probability that the winner is closer to the head than the loser,
# from squared Euclidean distances -- same formula/convention as this
# package's vendored Python CKL noise model (inst/python/salmon/.../
# _noise_models.py), including its mu=0.05 default.
ckl_prob <- function(d_win, d_lose, mu) {
  num <- mu + d_lose
  num / (num + mu + d_win)
}

# Symmetric KL divergence between two Bernoulli(p) distributions, i.e.
# KL(p1||p2) + KL(p2||p1). Closed form: (p1-p2)*(logit(p1)-logit(p2)).
# Zero iff p1 == p2 -- unlike a plain cross-entropy sum, this has no
# "floor" from shared ambiguity (p1 == p2 == 0.5 correctly scores 0).
symmetric_kl_bernoulli <- function(p1, p2) {
  logit <- function(p) log(p) - log(1 - p)
  (p1 - p2) * (logit(p1) - logit(p2))
}


#' Find triplets where two embeddings make discrepant predictions
#'
#' Given two embeddings of the same items, finds triplets (a head item and
#' two options) for which the embeddings imply very different answers about
#' which option is closer to the head -- useful for designing a follow-up
#' study to test which embedding better matches human similarity judgments.
#'
#' @param embedding1,embedding2 Numeric matrices (or data frames coercible to
#'   one) of embedding coordinates, rows = items, columns = dimensions. Row
#'   names must identify items, and both embeddings must contain the same
#'   set of items (order may differ; dimensionality may differ between the
#'   two embeddings).
#' @param k Number of triplets to return. Default \code{10L}.
#' @param mu CKL model constant, matching the crowd kernel noise model this
#'   package's embedding pipeline is fit under (see \emph{Details}). Default
#'   \code{0.05}.
#' @param n_candidates Number of candidate triplets to sample and score
#'   before selecting the top \code{k}. Default \code{200000L}. Half are
#'   drawn uniformly at random; half are drawn with items weighted by how
#'   much their distance-to-other-items profile differs between the two
#'   embeddings (see \emph{Details}), concentrating search on items likely
#'   to matter without excluding any item outright. For small item sets, a
#'   large enough value effectively covers every distinct triplet
#'   (duplicates are removed automatically), approximating exhaustive search
#'   without a separate code path for it.
#' @param max_per_item Maximum number of returned triplets any single item
#'   may appear in (as head or either option). Default \code{Inf} (no cap).
#'   Useful when a handful of items are placed very differently between the
#'   two embeddings and would otherwise dominate the results.
#' @param seed Optional integer random seed for reproducible candidate
#'   sampling. Default \code{NULL} (no seed set).
#'
#' @return A data frame with one row per selected triplet, sorted by
#'   decreasing discrepancy, with columns:
#' \describe{
#'   \item{\code{head}, \code{option1}, \code{option2}}{Item names.}
#'   \item{\code{embedding1_predicts}, \code{embedding2_predicts}}{Which
#'     option (\code{option1} or \code{option2}) each embedding predicts is
#'     closer to the head.}
#'   \item{\code{p_embedding1}, \code{p_embedding2}}{Each embedding's CKL
#'     probability that \code{option1} is the closer option.}
#'   \item{\code{discrepancy}}{The symmetric KL divergence between the two
#'     embeddings' predicted probabilities for this triplet -- see
#'     \emph{Details}.}
#' }
#' If fewer than \code{k} triplets with positive discrepancy can be
#' selected from the sampled candidates -- because \code{max_per_item} is
#' restrictive, or because the two embeddings simply agree on everything
#' else sampled -- a warning reports how many were found and the returned
#' data frame has fewer than \code{k} rows.
#'
#' @details
#' For a triplet with head \code{h} and options \code{A}/\code{B}, each
#' embedding's CKL probability that \code{A} is closer than \code{B} is
#' \code{p = (mu + d(h,B)) / (2*mu + d(h,A) + d(h,B))}, where \code{d} is
#' squared Euclidean distance within that embedding's own coordinates --
#' the same probability model (including the \code{mu} constant) used by
#' this package's embedding-fitting backend. Calling \code{p1}/\code{p2} the
#' two embeddings' probabilities for a triplet, \code{discrepancy} is the
#' symmetric KL divergence between \code{Bernoulli(p1)} and
#' \code{Bernoulli(p2)}. This is zero exactly when the embeddings agree
#' (\code{p1 == p2}), including when both are highly uncertain
#' (\code{p1 == p2 == 0.5}) -- a plain sum of cross-entropies would instead
#' score such genuinely-ambiguous-but-agreeing triplets as artificially
#' "discrepant," since cross-entropy has an entropy floor even between
#' identical distributions.
#'
#' Because the number of possible triplets grows as
#' \code{n*(n-1)*(n-2)/2}, exhaustive search is not attempted; candidates
#' are sampled instead (see \code{n_candidates}). Half of every candidate
#' pool is drawn uniformly at random; the other half is drawn with items
#' weighted by \code{1 - } their distance-profile Spearman correlation (the
#' same measure used by \code{\link{find_discrepant_items}}): for each
#' item, its vector of distances to every other item is compared between
#' \code{embedding1} and \code{embedding2}, and items whose relative
#' position differs more between the two embeddings get a larger weight and
#' are sampled more often. This is a soft bias on candidate *generation*
#' only: every item retains nonzero sampling probability (a small floor is
#' added to the weights), and the final ranking always comes from the exact
#' \code{discrepancy} score above, so a misleading weight can cost search
#' efficiency but never correctness. An earlier version of this function
#' weighted items by their residual from a Procrustes alignment of
#' \code{embedding1} onto \code{embedding2} instead; that was replaced
#' because a single strong outlier item can distort the *global* rotation/
#' scale a Procrustes fit uses to minimize total residual, inflating the
#' apparent residual of other, unchanged items enough that they outrank the
#' true outlier (verified: on a 20-item synthetic example with exactly one
#' item relocated, the Procrustes residual ranked that item only 3rd, with a
#' weight barely distinguishable from the top-ranked item, while the
#' Spearman-based weight used here ranks it 1st with more than 3x the
#' next-highest item's weight). The distance-profile approach has no shared
#' fitting step, so it does not share this failure mode; the 50/50 uniform
#' component is retained regardless, as a general hedge against any
#' remaining imperfection in the weighting heuristic.
#'
#' Selection among scored candidates is a greedy pass in decreasing order
#' of \code{discrepancy}, skipping any candidate that would push one of its
#' three items over \code{max_per_item}, and skipping candidates with
#' \code{discrepancy <= 0} outright -- such a candidate means the two
#' embeddings agree on that triplet, which is never useful for the stated
#' purpose regardless of how many triplets have already been selected.
#' This selection is an approximation, not a globally optimal selection
#' under the \code{max_per_item} constraint, but one consistent with only
#' needing "good enough" triplets rather than a provably best set.
#'
#' @export
#'
#' @examples
#' set.seed(1)
#' n <- 20
#' embedding1 <- matrix(rnorm(n * 3), n, 3, dimnames = list(paste0("item", 1:n)))
#' embedding2 <- embedding1
#' embedding2["item1", ] <- embedding2["item1", ] + 10   # one item moved far away
#'
#' find_discriminating_triplets(embedding1, embedding2, k = 5)
#'
#' # Cap how often any single item (e.g. the one moved above) can appear
#' find_discriminating_triplets(embedding1, embedding2, k = 5, max_per_item = 2)
find_discriminating_triplets <- function(
    embedding1,
    embedding2,
    k = 10L,
    mu = 0.05,
    n_candidates = 200000L,
    max_per_item = Inf,
    seed = NULL
) {

  embedding1 <- as.matrix(embedding1)
  embedding2 <- as.matrix(embedding2)

  if (is.null(rownames(embedding1)) || is.null(rownames(embedding2))) {
    stop("Both embeddings must have row names identifying items.")
  }

  if (!setequal(rownames(embedding1), rownames(embedding2))) {
    stop("embedding1 and embedding2 must contain the same set of items.")
  }

  items <- rownames(embedding1)
  embedding2 <- embedding2[items, , drop = FALSE]
  n_items <- length(items)

  if (n_items < 3L) {
    stop("Need at least 3 items.")
  }

  if (k < 1L) {
    stop("k must be at least 1.")
  }

  if (mu <= 0) {
    stop("mu must be positive.")
  }

  if (!is.null(seed)) {
    set.seed(seed)
  }

  D1 <- as.matrix(stats::dist(embedding1))^2
  D2 <- as.matrix(stats::dist(embedding2))^2

  # Per-item discrepancy, used only to bias candidate *sampling* (see
  # @details) -- never affects CKL discrepancy scoring or final ranking.
  # Spearman correlation between each item's row of D1/D2 -- squaring
  # preserves rank order for non-negative distances, so these already-
  # computed squared distances give the same Spearman correlation as raw
  # distances would, with no extra computation needed. This is markedly
  # more robust to a single badly-placed item than a Procrustes residual
  # (which this replaced): verified on a single-relocated-item synthetic
  # test that Procrustes residuals rank that item only 3rd, with a weight
  # barely distinguishable from the top (unrelated) item, while this
  # correlation-based weight ranks it 1st with more than 3x the next-highest
  # item's weight -- see find_discrepant_items()'s documentation, which
  # uses the same underlying signal for a related but distinct purpose
  # (ranking items directly, rather than biasing a sampling distribution).
  spearman_corr <- vapply(seq_len(n_items), function(i) {
    stats::cor(D1[i, -i], D2[i, -i], method = "spearman")
  }, numeric(1))
  discrepancy <- 1 - spearman_corr
  # The additive floor is usually scaled to the typical discrepancy, but
  # when the two embeddings are identical (or coincidentally rank-identical)
  # every item's discrepancy is exactly zero, which would otherwise zero out
  # every sampling weight -- add a small absolute floor too so sample.int()
  # always has strictly positive probabilities to work with.
  weights <- discrepancy + 0.01 * mean(discrepancy) + 1e-8

  n_uniform <- ceiling(n_candidates / 2)
  n_weighted <- n_candidates - n_uniform

  idx_uniform <- matrix(
    sample.int(n_items, n_uniform * 3L, replace = TRUE),
    ncol = 3L
  )
  idx_weighted <- matrix(
    sample.int(n_items, n_weighted * 3L, replace = TRUE, prob = weights),
    ncol = 3L
  )
  idx <- rbind(idx_uniform, idx_weighted)

  valid <- idx[, 1L] != idx[, 2L] & idx[, 2L] != idx[, 3L] & idx[, 1L] != idx[, 3L]
  idx <- idx[valid, , drop = FALSE]

  # Dedupe: option order doesn't affect the (symmetric) score.
  key <- paste(idx[, 1L], pmin(idx[, 2L], idx[, 3L]), pmax(idx[, 2L], idx[, 3L]))
  idx <- idx[!duplicated(key), , drop = FALSE]

  h <- idx[, 1L]; a <- idx[, 2L]; b <- idx[, 3L]

  d1_ha <- D1[cbind(h, a)]; d1_hb <- D1[cbind(h, b)]
  d2_ha <- D2[cbind(h, a)]; d2_hb <- D2[cbind(h, b)]

  p1 <- ckl_prob(d1_ha, d1_hb, mu)
  p2 <- ckl_prob(d2_ha, d2_hb, mu)

  discrepancy <- symmetric_kl_bernoulli(p1, p2)

  ord <- order(discrepancy, decreasing = TRUE)
  h <- h[ord]; a <- a[ord]; b <- b[ord]
  p1 <- p1[ord]; p2 <- p2[ord]; discrepancy <- discrepancy[ord]

  # Greedy selection respecting max_per_item.
  usage <- integer(n_items)
  selected <- integer(0)

  for (i in seq_along(h)) {
    if (length(selected) >= k) break
    if (discrepancy[i] <= 0) break  # discrepancy is sorted descending; none after this help
    triple <- c(h[i], a[i], b[i])
    if (all(usage[triple] < max_per_item)) {
      selected <- c(selected, i)
      usage[triple] <- usage[triple] + 1L
    }
  }

  if (length(selected) < k) {
    warning(sprintf(
      "Only found %d of the requested %d triplets (either exhausted candidates with positive discrepancy, or max_per_item = %s was too restrictive) among %d sampled candidates. Increase n_candidates or relax max_per_item.",
      length(selected), k, format(max_per_item), length(h)
    ))
  }

  data.frame(
    head                = items[h[selected]],
    option1             = items[a[selected]],
    option2             = items[b[selected]],
    embedding1_predicts = ifelse(p1[selected] > 0.5, items[a[selected]], items[b[selected]]),
    embedding2_predicts = ifelse(p2[selected] > 0.5, items[a[selected]], items[b[selected]]),
    p_embedding1        = p1[selected],
    p_embedding2        = p2[selected],
    discrepancy         = discrepancy[selected],
    stringsAsFactors    = FALSE
  )
}
