#' Find items whose relative position differs most between two embeddings
#'
#' Given two embeddings of the same items, ranks items by how much their
#' distance profile to every other item differs between the two spaces --
#' a way to find which specific items are placed most differently, without
#' needing to align the two embeddings first (unlike Procrustes-based
#' comparisons).
#'
#' @param embedding1,embedding2 Numeric matrices (or data frames coercible to
#'   one) of embedding coordinates, rows = items, columns = dimensions. Row
#'   names must identify items, and both embeddings must contain the same
#'   set of items (order may differ). Dimensionality may differ between the
#'   two embeddings -- this function never needs to align them, since it
#'   only ever compares distances computed within each embedding's own
#'   space.
#' @param k Number of most-discrepant items to return. Default \code{NULL}
#'   returns every item, ranked.
#' @param method Correlation method, passed to \code{\link[stats]{cor}}.
#'   Default \code{"spearman"} -- see \emph{Details} for why this is
#'   deliberately not \code{"pearson"}.
#'
#' @return A data frame with one row per item (or per the top \code{k}, if
#'   set), sorted by ascending correlation (most discrepant first), with
#'   columns \code{item} and \code{correlation}.
#'
#' @details
#' For each item, this compares its vector of distances to every other item
#' in \code{embedding1} against the same vector in \code{embedding2}, via
#' \code{\link[stats]{cor}}. A low correlation means that item's position
#' *relative to everything else* differs between the two embeddings --
#' regardless of any overall rotation, reflection, or rescaling difference
#' between the two spaces, since Euclidean distance is already invariant to
#' all of those. Unlike a Procrustes-based comparison, there is no
#' dimensionality padding/alignment step to worry about: distances are
#' computed within each embedding's own space, so the two embeddings can
#' have entirely different dimensionality.
#'
#' \strong{Use \code{method = "spearman"}, not \code{"pearson"}.} A single
#' badly-placed item corrupts one distance entry for every *other* item's
#' profile too (their distance to that one item) while leaving the rest of
#' each such profile untouched. Pearson correlation is highly sensitive to a
#' single extreme value and can be dragged down by that one corrupted entry
#' even when the other entries are perfectly preserved -- verified directly:
#' in a synthetic test with exactly one relocated item, Pearson correlation
#' ranked that item outside the overall bottom 5 entirely, while Spearman
#' correlation (which compresses a single extreme value's effect via
#' ranking rather than raw magnitude) ranked it a clear, decisive first,
#' with every other item's correlation far higher.
#'
#' This complements \code{\link{find_discriminating_triplets}} (which finds
#' *triplets* two embeddings disagree on) and is a more robust alternative
#' to inspecting per-item Procrustes residuals for finding discrepant
#' *items* directly. A Procrustes fit (as used by
#' \code{\link{procrustes_rank_ceiling}}/\code{\link{procrustes_spectral_ceiling}})
#' shares a single rotation/scale across every item, so one badly-placed
#' item can distort that shared fit enough to inflate *other*, unrelated
#' items' apparent residuals above the true outlier's own (verified in this
#' same synthetic test: Procrustes residuals ranked a different, unrelated
#' item first). This function has no shared fitting step -- each item's
#' score depends only on its own distances in each space, independent of
#' every other item's placement (aside from the much smaller contamination
#' described above, which \code{method = "spearman"} already resists).
#'
#' With very few items, per-item correlations are computed over few points
#' and become noisy -- treat rankings cautiously for small item sets.
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
#' find_discrepant_items(embedding1, embedding2, k = 5)
find_discrepant_items <- function(embedding1, embedding2, k = NULL,
                                   method = c("spearman", "pearson")) {

  method <- match.arg(method)

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

  if (n_items < 4L) {
    stop("Need at least 4 items.")
  }

  if (!is.null(k) && k < 1L) {
    stop("k must be at least 1.")
  }

  D1 <- as.matrix(stats::dist(embedding1))
  D2 <- as.matrix(stats::dist(embedding2))

  correlation <- vapply(seq_len(n_items), function(i) {
    stats::cor(D1[i, -i], D2[i, -i], method = method)
  }, numeric(1))

  result <- data.frame(
    item = items,
    correlation = correlation,
    stringsAsFactors = FALSE
  )
  result <- result[order(result$correlation), ]
  row.names(result) <- NULL

  if (!is.null(k)) {
    k <- min(k, n_items)
    result <- result[seq_len(k), ]
  }

  result
}
