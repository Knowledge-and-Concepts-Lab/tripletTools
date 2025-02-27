#' Align embeddings across participants
#'
#' This function takes a list of embeddings, one per participant,
#' and procrustes-aligns each to a reference embedding.
#'
#' @importFrom vegan procrustes protest
#'
#' @param emb List of embeddings; each element is one participant.
#' @param baseno Integer indicating which list element to use as the base.
#'
#' @return A list with each participant's embedding aligned to the base embedding.
#'
#' @details
#' Each element of the list should contain embedding data from one participant,
#' as returned by the function `get.combined`. Each embedding must contain the
#' same items in the same order, and must be of the same dimension. The function
#' will procrustes-align each participant's embedding to the base participant,
#' specified by the `baseno` argument. The procrustes alignment permits rotation,
#' translation, scaling and reflection.
#'
#' @export
#'
#' @examples
#'
#' #Example data for subject 1
#' s1 <- data.frame(
#'       x = c(1:10) + runif(10)/10,
#'       y = c(1:10) + runif(10)/10
#'       )
#'
#' s2 <- s1 * 2 + 4 #Double and shift s1 data
#' s2[,1] <- -1 * s2[,1] #Reflect along one dimension
#'
#' unaligned <- list(s1,s2)
#' aligned <- align.embeddings(unaligned)

align.embeddings <- function (emb, baseno = 1)
{

  o <- list() #Initialize output list
  n <- length(emb) #Number of participants
  baseemb <- emb[[baseno]] #base embedding

  for (i in c(1:n)){
    o[[i]] <- vegan::procrustes(baseemb,
                                emb[[i]],
                                symmetric = TRUE,
                                reflect = TRUE,
                                scale = TRUE)$Yrot
  }
  o
}
