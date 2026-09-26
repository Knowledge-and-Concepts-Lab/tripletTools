#' Align multiple embeddings into one shared reference frame
#'
#' Iteratively Procrustes-aligns every embedding in \code{elist} onto a
#' common consensus configuration (Gower, 1975), rather than aligning pairs
#' of embeddings independently against each other. This is the natural
#' preprocessing step before averaging or otherwise directly comparing
#' coordinates across more than two embeddings, since plain pairwise
#' alignment (as used internally by \code{\link{get.rep.dist}}) only ever
#' produces a shared frame for one pair at a time.
#'
#' @param elist List of embeddings. Each element should be a matrix or data
#'   frame of coordinates for the same items in the same order, with the
#'   same dimensionality across all embeddings.
#' @param scale Logical. Allow rescaling each embedding's overall size
#'   during alignment (in addition to rotation/reflection/translation)?
#'   Default \code{TRUE}, matching \code{\link{get.rep.dist}}'s default
#'   Procrustes convention.
#' @param reflect Logical. Allow reflection during alignment? Default
#'   \code{TRUE} -- embeddings fit independently (e.g. one per participant)
#'   can come out mirror-flipped with no meaningful interpretation attached
#'   to the reflection itself.
#' @param max_iter Integer. Maximum number of alignment iterations. Default 100.
#' @param tol Numeric. Convergence tolerance: iteration stops once the
#'   consensus configuration's root-mean-square change between iterations
#'   drops below this value. Default \code{1e-6}.
#'
#' @details
#' Starting from an arbitrary initial reference (the first embedding in
#' \code{elist}), each embedding is Procrustes-aligned onto the current
#' consensus (\code{\link[vegan]{procrustes}}, target-based, not
#' \code{symmetric = TRUE} -- there is always a well-defined target here,
#' the running consensus, unlike a pairwise comparison between two
#' embeddings with no natural reference), the consensus is recomputed as
#' the mean of the newly-aligned embeddings, and this repeats until the
#' consensus stops changing (or \code{max_iter} is reached). Unlike
#' pairwise alignment, every embedding ends up in one shared coordinate
#' frame simultaneously, so coordinates can be directly compared, combined,
#' or averaged across any subset of embeddings -- exactly what
#' \code{\link{smooth_embedding_trajectory}} needs before it can average
#' coordinates across participants.
#'
#' @return A list with elements:
#' \describe{
#'   \item{\code{aligned}}{A list the same length and names as \code{elist},
#'     each embedding rotated/reflected/scaled onto the shared consensus
#'     frame.}
#'   \item{\code{consensus}}{The final consensus configuration (matrix, same
#'     dimensions as one embedding): the mean of \code{aligned}.}
#'   \item{\code{iterations}}{Number of iterations actually run.}
#'   \item{\code{converged}}{Logical: did the consensus change drop below
#'     \code{tol} before \code{max_iter} was reached?}
#' }
#'
#' @references Gower, J.C. (1975). Generalized Procrustes analysis.
#'   Psychometrika, 40(1), 33-51.
#'
#' @export
#'
#' @examples
#' \dontrun{
#' gpa <- generalized_procrustes(icon_emb_ind)
#' gpa$consensus
#' gpa$converged
#' }
generalized_procrustes <- function(elist, scale = TRUE, reflect = TRUE,
                                    max_iter = 100, tol = 1e-6) {
  if (!requireNamespace("vegan", quietly = TRUE)) {
    stop("The 'vegan' package is required. Install it with install.packages('vegan').")
  }
  n_embeds <- length(elist)
  if (n_embeds < 2) stop("elist must contain at least 2 embeddings.")
  if (max_iter < 1) stop("max_iter must be at least 1.")

  mats <- lapply(elist, as.matrix)
  dims <- unique(lapply(mats, dim))
  if (length(dims) > 1) {
    stop("All embeddings in elist must have the same dimensions (same items, same number of columns).")
  }

  ref_dimnames <- dimnames(mats[[1]])
  consensus <- mats[[1]]
  converged <- FALSE
  iterations <- 0L
  aligned <- mats

  for (iter in seq_len(max_iter)) {
    iterations <- iter
    aligned <- lapply(mats, function(mat) {
      vegan::procrustes(X = consensus, Y = mat, scale = scale, reflect = reflect)$Yrot
    })
    new_consensus <- Reduce(`+`, aligned) / n_embeds
    # When scale = TRUE, repeatedly rescaling every embedding to match the
    # *previous* consensus and then re-averaging is not scale-neutral:
    # verified empirically that without this renormalization, the
    # consensus's sum of squares decays geometrically toward exactly zero
    # (a consistent ~0.37x per iteration here), never stabilizing at any
    # meaningful nonzero size -- a known degeneracy of iterative GPA with
    # scaling, fixed the standard way (Gower, 1975) by rescaling the
    # consensus back to a fixed size after each iteration. Left out when
    # scale = FALSE: there, nothing rescales embeddings during alignment in
    # the first place, so there's no shrinkage to correct, and forcing a
    # fixed size would destroy genuine average-size information the caller
    # chose to keep by turning scaling off.
    if (scale) {
      cur_size <- sqrt(sum(new_consensus^2))
      if (cur_size > 0) new_consensus <- new_consensus / cur_size
    }
    change <- sqrt(mean((new_consensus - consensus)^2))
    consensus <- new_consensus
    if (change < tol) {
      converged <- TRUE
      break
    }
  }

  names(aligned) <- names(elist)
  dimnames(consensus) <- ref_dimnames
  for (i in seq_along(aligned)) dimnames(aligned[[i]]) <- ref_dimnames

  list(
    aligned = aligned,
    consensus = consensus,
    iterations = iterations,
    converged = converged
  )
}
