#' Successor representation of a weighted adjacency matrix
#'
#' Converts a weighted adjacency (transition-weight) matrix into a Successor
#' Representation: a discounted sum of expected future visitation, in the
#' style of reinforcement-learning successor-representation models.
#'
#' @param W Square numeric matrix (or object coercible to one) of
#'   non-negative transition weights, rows = "from" items, columns = "to"
#'   items.
#' @param gamma Discount factor, \code{0 <= gamma < 1}. Larger values weight
#'   longer-range paths more heavily. Default \code{0.5}.
#' @param pseudocount Non-negative constant added to every entry of \code{W}
#'   before row-normalizing, to avoid zero-weight rows or to smooth sparse
#'   graphs. Default \code{0} (no smoothing).
#'
#' @return A named list with two elements:
#' \describe{
#'   \item{\code{successor}}{The successor matrix \code{S = (1 - gamma) *
#'     solve(diag(n) - gamma * P)}, with row and column names taken from
#'     \code{W}.}
#'   \item{\code{transition}}{The row-normalized transition matrix \code{P}
#'     used to compute \code{S}.}
#' }
#'
#' @details
#' \code{W} is first row-normalized (after adding \code{pseudocount}) to a
#' transition matrix \code{P}, so that each row of \code{P} sums to 1. The
#' successor matrix \code{S} then gives, for each pair of items, the
#' discounted expected number of times item \code{j} would be visited
#' starting a random walk from item \code{i} and following \code{P}, summed
#' over an infinite horizon and weighted by \code{gamma} per step:
#' \code{S = (1 - gamma) * sum_t gamma^t P^t}. At \code{gamma = 0} only the
#' \code{t = 0} term survives and \code{S} is the identity matrix (no
#' diffusion beyond an item itself); as \code{gamma} increases, \code{S}
#' incorporates progressively longer paths through the graph, and as
#' \code{gamma} approaches 1 every row of \code{S} converges toward the
#' graph's stationary distribution, reflecting global rather than local
#' structure.
#'
#' Turning a similarity or adjacency graph into a successor matrix is one way
#' to derive an embedding-like representation that captures multi-step
#' relational structure rather than only direct pairwise similarity.
#'
#' @export
#'
#' @examples
#' # A small weighted graph over four items
#' W <- matrix(
#'   c(0, 1, 1, 0,
#'     1, 0, 0, 1,
#'     1, 0, 0, 1,
#'     0, 1, 1, 0),
#'   nrow = 4, byrow = TRUE,
#'   dimnames = list(letters[1:4], letters[1:4])
#' )
#' result <- successor_matrix(W, gamma = 0.5)
#' result$successor
successor_matrix <- function(W, gamma = 0.5, pseudocount = 0) {

  if (!is.matrix(W))
    W <- as.matrix(W)

  if (nrow(W) != ncol(W))
    stop("W must be a square adjacency matrix.")

  if (gamma < 0 || gamma >= 1)
    stop("gamma must satisfy 0 <= gamma < 1.")

  W <- W + pseudocount

  row_sums <- rowSums(W)

  if (any(row_sums == 0))
    stop("One or more rows have zero outgoing weight.")

  P <- W / row_sums

  n <- nrow(P)

  S <- (1 - gamma) *
       solve(diag(n) - gamma * P)

  rownames(S) <- rownames(W)
  colnames(S) <- colnames(W)

  return(list(
    successor = S,
    transition = P
  ))
}
