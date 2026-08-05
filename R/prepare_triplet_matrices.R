#' Build train/test triplet matrices from a list of participant data frames
#'
#' Collects and sorts all unique item names across participants, converts
#' each participant's \code{Center}/\code{Left}/\code{Right}/\code{Answer}
#' columns to zero-based \code{head}/\code{winner}/\code{loser} integer
#' indices, and splits into \code{X_train}/\code{X_test} matrices.
#'
#' @section Item indexing:
#' All unique item names in \code{Center}, \code{Left}, and \code{Right}
#' across all participants are collected and sorted alphabetically; this
#' sorted order defines the zero-based integer indices used in the returned
#' matrices, and is also returned as \code{all_items} so callers can restore
#' item names on a fitted embedding afterward.
#'
#' @section Filtering:
#' Trials with \code{NA} in the \code{sampleSet} column (attention-check
#' trials) are excluded before splitting. The \code{sampleSet} column
#' (\code{"train"} / \code{"test"}) defines the split. If no \code{sampleSet}
#' column is present, or all its values are \code{NA}, a 70/30 random
#' train/test split is used instead, controlled by \code{seed}.
#'
#' @param triplet_list A named list of data frames, one per participant, as
#'   returned by \code{\link{get.combined}}. Each data frame must contain
#'   columns \code{Center}, \code{Left}, \code{Right}, \code{Answer}, and
#'   \code{sampleSet}.
#' @param seed Integer seed for the fallback random 70/30 split. Only used
#'   when \code{sampleSet} is absent or entirely \code{NA}. Default \code{1L}.
#'
#' @return A named list with three elements:
#' \describe{
#'   \item{\code{X_train}}{Integer matrix of shape
#'     \eqn{n_{\text{train}} \times 3} with columns \code{head}, \code{winner},
#'     \code{loser}.}
#'   \item{\code{X_test}}{Integer matrix in the same format as \code{X_train}.}
#'   \item{\code{all_items}}{Character vector of item names, sorted
#'     alphabetically -- row \code{i} (1-based) of this vector is the item
#'     at zero-based index \code{i - 1} in \code{X_train}/\code{X_test}.}
#' }
#'
#' @export
#'
#' @examples
#' \dontrun{
#' mats <- prepare_triplet_matrices(icon_triplets, seed = 1L)
#' dim(mats$X_train)
#' head(mats$all_items)
#' }
prepare_triplet_matrices <- function(triplet_list, seed = 1L) {
  all_items <- sort(unique(unlist(lapply(triplet_list, function(df) {
    c(df$Center, df$Left, df$Right)
  }))))

  # Build head/winner/loser rows for *every* trial first, before any
  # sampleSet-based filtering -- deciding whether real train/test labels
  # exist has to happen against the unfiltered data, otherwise the
  # entirely-absent/all-NA sampleSet case (meant to trigger the random
  # 70/30 fallback below) would filter every row out before the fallback
  # ever saw them.
  combined <- do.call(rbind, lapply(triplet_list, function(df) {
    winner <- ifelse(df$Answer == df$Left, df$Left, df$Right)
    loser  <- ifelse(df$Answer == df$Left, df$Right, df$Left)
    data.frame(
      head      = match(df$Center, all_items) - 1L,
      winner    = match(winner,    all_items) - 1L,
      loser     = match(loser,     all_items) - 1L,
      sampleSet = if (is.null(df$sampleSet)) NA_character_ else df$sampleSet,
      stringsAsFactors = FALSE
    )
  }))

  train_rows <- !is.na(combined$sampleSet) & combined$sampleSet == "train"
  test_rows  <- !is.na(combined$sampleSet) & combined$sampleSet == "test"

  if (!any(train_rows) || !any(test_rows)) {
    set.seed(seed)
    shuffled  <- combined[sample(nrow(combined)), ]
    split_idx <- floor(0.7 * nrow(shuffled))
    X_train <- as.matrix(shuffled[seq_len(split_idx), c("head", "winner", "loser")])
    X_test  <- as.matrix(shuffled[seq(split_idx + 1L, nrow(shuffled)), c("head", "winner", "loser")])
  } else {
    X_train <- as.matrix(combined[train_rows, c("head", "winner", "loser")])
    X_test  <- as.matrix(combined[test_rows,  c("head", "winner", "loser")])
  }

  list(X_train = X_train, X_test = X_test, all_items = all_items)
}
