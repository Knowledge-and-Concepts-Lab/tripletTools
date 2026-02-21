#' Get prediction matrix
#'
#' This function takes a list of embeddings and a matched list of triplet
#' data and uses each embedding to predict responses on each triplet
#' dataset, returning the mean accuracy as a matrix.
#'
#' @param elist Named list of embeddings.
#' @param tlist Named list of triplet data.
#' @param ttype Type of trial to evaluate on, defaults to test trials
#'
#' @return A matrix. Each row is an embedding, each column a triplet dataset.
#'  Entries indicate how accurately the embedding predicts the triplet data
#'  for the trial type indicated.
#'
#' @details
#' Elements of the embedding and triplet lists should be named with the
#' participant ID, as in the format returned by `get_combined`. Ideally
#' these lists will contain the same participants in the same order.
#' The function expects files conform to naming conventions. It first
#' extracts trials of the indicated type, then uses `get.hoacc` to compute the
#' proportion of items for which the embedding predicts the correct response.
#' It loops through all embeddings and datasets, returning a matrix of the
#' corresponding prediction accuracies.
#'
#' Assuming the two lists contain the same participants in the same order,
#' the matrix diagonal will indicate how well a participant's own embedding
#' predicts their decisions on the test items (typically hold-out items not
#' used to compute the embedding).
#'
#' @export
#'
#' @examples
#' embpath <- system.file("extdata", "cfd36_embeddings_individual.csv", package = "tripletTools")
#' tripath <- system.file("extdata", "cfd36_triplets_individual.csv", package = "tripletTools")
#'
#' #Get first five participants
#' embs <- get.combined(embpath, eflag=TRUE)[1:5]
#' trips <- get.combined(tripath, eflag = FALSE)[1:5]
#'
#' pmat <- get.prediction.matrix(embs, trips, ttype="test")
#'
#' pmat
#'

get.prediction.matrix <- function(elist, tlist, ttype = "test"){

  nemb <- length(elist) #Number of embeddings
  ntrip <- length(tlist) #Number of triplet datasets

  o <- matrix(NA, nemb, ntrip) #Initialize output matrix
  row.names(o) <- names(elist)  #Name rows
  colnames(o) <- names(tlist)  #Name columns

  #Main loop
  for(i in c(1:nemb)){
    thisemb <- elist[[i]]
    for(j in c(1:ntrip)){
      thistrip <- subset(tlist[[j]], tlist[[j]]$sampleSet==ttype)
      o[j,i] <- get.hoacc(thisemb, thistrip, ttype)
    }
  }
  o
}
