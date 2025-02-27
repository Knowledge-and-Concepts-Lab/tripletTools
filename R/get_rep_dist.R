#' Get representational distances
#'
#' Given a list of embeddings, this function computes the procrustes
#' distance between each pair and returns this as a distance matrix.
#'
#' @param elist List of embeddings.
#' @param rootflag Computer square root of distance? Defaults to TRUE
#'
#' @return A matrix of distances between each pair of embeddings.
#'
#' @details
#' Each element of the list should contain a matrix of embedding coordinates
#' from one participant. Each embedding should contain the same items in
#' the same order, and should be of the same dimension.
#'
#' By default the distance metric is the procrustes equivalent of Pearon's
#' correlation, that is `1 - sqrt(1 - ss)` where `ss` is the normalized
#' sum of squares from the aligned embeddings. If `rootflag=FALSE`, the normalized
#' sum of squares is used as the distance metric.
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

get.rep.dist <- function (elist, rootflag = TRUE)
{
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

      #Compute procrustes distance
      if(rootflag) thiso <- 1 - sqrt(1 - thisp$ss) else thiso <- thisp$ss
      o[i, j] <- thiso #Put in output matrix
      o[j,i] <- thiso
    }
  }
  diag(o) <- 0 #Zero distance on diagonal
  o
}
