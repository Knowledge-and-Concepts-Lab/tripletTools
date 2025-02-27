#' Z-score prediction matrix
#'
#' This  function takes a matrix of predictive accuracies as produced by
#' `get.prediction.matrix` and returns, for each subject, a zscore indicating
#' how predictive accuracy from a subject's own embedding relates to those
#' from other subjects/
#'
#' @param pmat An embedding-to-triplet prediction matrix of the kind returned
#'  by `get.prediction.matrix`.
#'
#' @returns The predictive accuracy of each participant's embedding in predicting
#'    their own triplet decisions relative to the accuracy of other embeddings
#'    in the matrix, computed as a z-score.
#'
#' @details
#' The matrix diagonal must contain accuracies for each participant's
#' own embedding when predicting their held-out triplet judgments. These
#' diagonal values will be z-scored against the distribution formed by all
#' other accuracies in the row, which reflect accuracies of _other_ embeddings
#' predicting that same participant's triplet data.
#'
#' If embeddings reflect true, reliable individual differences, a participant's
#' own embedding should predict her held-out judgments better than does another
#' random participant from the matrix. In this case the z-scored self-prediction
#' accuracy will be positive. If the z-score is reliably positive across the
#' whole group of participants, this indicates reliable individual differences in
#' representation.
#'
#' @export
#'
#' @examples
#' #Random prediction matrix
#' pmat <- matrix(runif(25),5,5)
#'
#' #Diagonal relatively high
#' diag(pmat) <- 1 - runif(5)/10
#'
#' #Zscore diagonal relative to other entries
#' z.pred.mat(pmat)

z.pred.mat <- function(pmat){

  nsjs <- dim(pmat)[1] #Number of subjects

  #Check matrix is symmetrical
  if(nsjs != dim(pmat)[2]) stop("Matrix isn't symmetrical!")

  o <- rep(NA, times= nsjs) #Initialize output vector

  for(i in c(1:nsjs)){
    sjacc <- pmat[i,i] #Accuracy from subject's own embedding
    s <- c(1:nsjs)!=i  #Selection vector for remaining accuracies
    otheracc <- pmat[i,s] #Other accuracies
    #Compute z-score
    o[i] <- (sjacc - mean(otheracc))/(sqrt(stats::var(otheracc)))
  }
  o
}
