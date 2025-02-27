#' Prediction accuracy by cluster
#'
#' This function computes how well a participant's held-out judgments are
#' predicted by their own embedding and embeddings from members of the same
#' or other clusters.
#'
#' @param pacc Participant-by-participant matrix of predictive accuracies of the
#'   kind returned by `get_prediction_matrix`.
#' @param clusts Vector indicating the cluster membership for each participant in
#'   `pacc`
#' @param samediff If TRUE, returns mean prediction accuracy for participants in
#'   same cluster vs mean from those in different cluster. Otherwise returns
#'   mean prediction accuracy from participants in each cluster.
#'
#' @returns A participant-by-cluster matrix indicating the mean accuracy predicting
#'   each participant's judgments from embeddings in each cluster.
#'
#' @details
#' Participants can be clustered based on their pairwise representational distances
#' as returned by `get.rep.dist`. This function will then compute how well, on
#' average, embeddings within a cluster predict each participant's held-out
#' (test) judgments. It also returns how well the participant's own embedding
#' predicts their held-out judgments. If clusters are useful, the
#' participant's judgments should be better-predicted by their cluster-mates
#' than by non-cluster-mates. If cluster-mates all share the same embedding,
#' same-cluster prediction should be as good a own-embedding prediction.
#'
#' The first column of the returned matrix is always prediction accuracy from the
#' participant's own embedding. If `samediff==TRUE` the returned matrix will
#' include mean prediction accuracy from the participant's own cluster and
#' from all participants not in the same cluster. If FALSE, the returned
#' matrix will include one column per cluster, and entries will indicate
#' mean prediction accuracy from the embeddings in that cluster.
#'
#' @export
#'
#' @examples
#' repdist <- get.rep.dist(cfd_embeddings) #Representational distances
#'
#' #Hierarchical cluster
#' hc <- hclust(as.dist(repdist), method = "ward.D")
#' clusts <- cutree(hc, 3) #Cut tree to yield three clusters
#'
#' pacc <- get.prediction.matrix(cfd_embeddings, cfd_triplets) #Prediction matrix
#' pbc <- pacc.by.cluster(pacc, clusts, samediff=TRUE)
#'
#' colMeans(pbc)

pacc.by.cluster <- function(pacc, clusts, samediff = TRUE){

  ## Check arguments
  #Check that pacc is or can be coerced to a numeric matrix
  pacc <- try({
    pacc <- as.matrix(pacc)
    if (!is.numeric(pacc)) stop("pacc should be a numeric matrix")
    pacc
  }, silent = TRUE)

  # Check if the coercion was successful
  if (inherits(pacc, "try-error")) {
    stop("Error: pacc must be a numeric matrix or coercible to one.")
  }

  #Check that m is or can be coerced to a numeric matrix
  clusts <- try({
    clusts <- as.numeric(clusts)
    if (!is.numeric(clusts)) stop("clusts should be a numeric vector")
    clusts
  }, silent = TRUE)

  # Check if the coercion was successful
  if (inherits(clusts, "try-error")) {
    stop("Error: clusts must be a numeric vector or coercible to one.")
  }

  # Get numbers and check they match
  nclusts <- length(unique(clusts)) #Number of clusters
  nsjs <- dim(pacc)[1] #Number of subjects

  if(nsjs != length(clusts)){
    stop("Length of clusts should be equal to dimension of pacc")
  }

  #Initialize output matrix
  if(samediff){
    o <- matrix(NA, nsjs, 3)
    colnames(o) <- c("self", "same","other")
  } else{
    o <- matrix(NA, nsjs, nclusts + 1)
    colnames(o) <- c("self", paste0("clust-", c(1:nclusts)))
  }
  #Name rows
  row.names(o) <- row.names(pacc)

  #Main loop
  for(i in c(1:nsjs)){
    sv <- pacc[i,] #subject vector
    o[i,1] <- sv[i] #Self-prediction accuracy
    currclust <- clusts[i] #Current subject's cluster

    #Selection vector for everyone but current sj
    s <- c(1:nsjs)[c(1:nsjs)!=i]

    #Remove current subject from data and clusters
    tmpclust <- clusts[s]
    sv <- sv[s]

    if(samediff){
      o[i,2] <- mean(sv[tmpclust==currclust]) #Same cluster
      o[i,3] <- mean(sv[tmpclust!=currclust]) #Other cluster
    } else{
      #Mean prediction accuracy for each cluster
      cmeans <- aggregate(sv[s], by = list(clusts[s]), FUN = "mean")
      o[i,2:(nclusts+1)] <- cmeans[,2] #Cluster mean prediction accuracy
    }
  }
  o #Return matrix
}
