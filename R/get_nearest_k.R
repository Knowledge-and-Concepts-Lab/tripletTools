#' Get nearest k
#'
#' This function takes a distance matrix and an item name and returns
#' the `k` nearest neighbors to the specified item.
#'
#' @param dmat Data matrix; rows must be named.
#' @param item String indicating the item for which nearest neighbors will be returned
#' @param k How many neighbors to return.
#'
#' @returns A character vector containing the `k` nearest neighbors in order
#'   of proximity to the target item.
#'
#' @details
#' `dmat` must be a matrix with named rows, and `item` must match the name of one
#' row.
#'
#' This function is useful for understanding local similarity structure in a higher-
#' dimensional embedding, and for creating a k-nearest-neighbor graph of such structure.
#'
#' @export
#'
#' @examples
#'
#' emb <- cfd_embeddings[[10]] #Embedding for participant 10
#' fdists <- as.matrix(dist(emb)) #Compute pairwise distance matrix
#' target <- "CFD-BF-002-004-HO"  #Name of target items
#'
#' #Return 5 items nearest to target:
#' get.nearest.k(fdists, target, 5)


get.nearest.k <- function(dmat, item, k = 5)
{
  ### Check arguments
  #Check that dmat can be coerced to a numeric matrix
  dmat <- try({
    dmat <- as.matrix(dmat)
    if (!is.numeric(dmat)) stop("dmat should be a numeric matrix")
    dmat
  }, silent = TRUE)

  # Check if the coercion was successful
  if (inherits(dmat, "try-error")) {
    stop("Error: dmat must be a numeric matrix or coercible to one.")
  }

  #Check matrix is symmetric
  if(dim(dmat)[1] != dim(dmat)[2]) stop("dmat should be a symmetric distance matrix.")

  #Check item matches a row names in dmat
  rno <- match(item, row.names(dmat))
  if(is.na(rno)) stop("item not found in distance matrix")

  #Return nearest k in order of distance:
  row.names(dmat)[order(dmat[item, ])[2:(k+1)]]

  #Note we take `2:(k+1)` because the closest match is always the item itself.
}
