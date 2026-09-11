#' Get representational distances
#'
#' Given a list of embeddings, this function computes the procrustes
#' distance between each pair and returns this as a distance matrix.
#'
#' @param elist List of embeddings.
#' @param metric Character. Which distance to compute from the Procrustes
#'   fit between each pair, one of:
#'   \describe{
#'     \item{\code{"sqrt_ss"}}{(default) \code{sqrt(ss)}, the standard
#'       Procrustes distance used in the shape-analysis literature. Unlike
#'       \code{"corr_dist"} below, this corresponds to an actual Euclidean
#'       distance between the two optimally aligned (rotated, reflected, and
#'       scaled) configurations, so it is the recommended choice for
#'       distance-based methods like hierarchical clustering, k-medoids, or
#'       MDS.}
#'     \item{\code{"corr_dist"}}{\code{1 - sqrt(1 - ss)}, i.e. one minus the
#'       Procrustes "correlation" \code{sqrt(1 - ss)}. This was this
#'       function's only behavior before the \code{metric} argument was
#'       added (then selected via \code{rootflag = TRUE}); kept for backward
#'       compatibility and for contexts that specifically want "1 minus a
#'       correlation-like similarity" rather than a proper distance -- it is
#'       not guaranteed to satisfy the triangle inequality.}
#'     \item{\code{"ss"}}{The raw normalized sum of squares (equivalently
#'       \code{sqrt_ss^2}), i.e. this behaves like a *squared* distance.
#'       Rank-based clustering methods (e.g. single/complete linkage) give
#'       identical results whether they're fed \code{"ss"} or
#'       \code{"sqrt_ss"}, since one is a monotonic transform of the other,
#'       but methods that use the actual metric values (Ward's linkage,
#'       k-medoids, MDS) should use \code{"sqrt_ss"} instead.}
#'   }
#'   This argument replaces the previous \code{rootflag} argument
#'   (\code{rootflag = TRUE} corresponded to \code{metric = "corr_dist"},
#'   and \code{rootflag = FALSE} to \code{metric = "ss"}).
#'
#' @return A matrix of distances between each pair of embeddings.
#'
#' @details
#' Each element of the list should contain a matrix of embedding coordinates
#' from one participant. Each embedding should contain the same items in
#' the same order, and should be of the same dimension.
#'
#' All three metrics are computed from \code{ss}, the normalized sum of
#' squares from a symmetric Procrustes alignment (rotation, reflection, and
#' scaling) between each pair, and are already bounded in \eqn{[0,1]} -- no
#' further normalization is needed before using them for clustering.
#'
#' @export
#'
#' @examples
#' #Subject 1 data
#' s1 <- matrix(
#'       c(1,1,
#'       2,2,
#'       3,3,
#'       4,4,
#'       5,5), 5,2,byrow = TRUE)
#'
#' #Subject 2 is noisy version of subject 1
#' s2 <- s1 + runif(10) / 10
#'
#' #Subject 3 is different:
#' s3 <- matrix(
#'       c(1,2,
#'       3,4,
#'       4,3,
#'       2,1,
#'       5,2), 5,2,byrow = TRUE)
#'
#' slist <- list(s1,s2,s3)
#'
#' sdist <- get.rep.dist(slist)
#'
#' head(sdist)
#'
#' #Cluster participants using the recommended default metric:
#' hclust(as.dist(sdist), method = "ward.D")
get.rep.dist <- function (elist, metric = c("sqrt_ss", "corr_dist", "ss"))
{
  metric <- match.arg(metric)

  nembeds <- length(elist) #Number of embeddings
  o <- matrix(NA, nembeds, nembeds) #Initialize outmput matrix

  #loop filling matrix
  for (i in c(1:(nembeds-1))) {
    for (j in c((i+1):nembeds)) {
      #Procrustes align
      thisp <- vegan::procrustes(elist[[i]], elist[[j]],
                                 reflect = TRUE,
                                 symmetric = TRUE,
                                 scale = TRUE)

      #Compute procrustes distance. ss is clamped to [0, 1] before use: for a
      #near-perfect (or near-total-mismatch) fit it can land a hair outside
      #that range (e.g. -2e-16 or 1 + 2e-16) from floating-point roundoff,
      #which would otherwise silently produce NaN in sqrt(ss) or sqrt(1-ss)
      #despite ss being mathematically guaranteed to lie in [0, 1].
      ss <- min(max(thisp$ss, 0), 1)
      thiso <- switch(metric,
        sqrt_ss   = sqrt(ss),
        corr_dist = 1 - sqrt(1 - ss),
        ss        = ss
      )
      o[i, j] <- thiso #Put in output matrix
      o[j,i] <- thiso
    }
  }
  diag(o) <- 0 #Zero distance on diagonal
  o
}
