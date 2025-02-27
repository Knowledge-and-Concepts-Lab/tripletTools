#' Get group list mean
#'
#' From a list of embeddings and a vector indicating to which group
#' each embedding belongs, this function aligns embeddings within each
#' group, then computes the mean embedding across members of the group.
#'
#' @param elist List of embeddings.
#' @param grps Vector indicating to which group each individual in `elist` belongs.
#'   Elements must be in the same order as in elist.
#'
#' @returns List containing mean embedding for each group.
#'
#' @details
#' This function is useful for visualizing the mean embedding for different
#' groups without having to recompute it from scratch. Note that the average
#' of the aligned embeddings returned by this function will necessarily be
#' the same as what is found if the embeddings _are_ computed from scratch
#' from the same participants.
#'
#' @export
#'
#' @examples
#' repdist <- get.rep.dist(cfd_embeddings) #Representational distances
#' hc <- hclust(as.dist(repdist), method = "ward.D") #Cluster tree
#' clusts <- cutree(hc, 4) #Cut into 4 clusters
#'
#' mn.by.clust <- get.group.list.mean(cfd_embeddings, clusts)
#' plot_pics(mn.by.clust[[1]], cfd_pics)

get.group.list.mean <- function(elist, grps){

  nitems <- length(elist)
  gid <- unique(grps) #Group IDs
  ngps <- length(gid) #Number of groups

  o <- list() #Initialize output

  for(i in c(1:ngps)){
    #get items in group:
    thisgroup <- elist[grps==gid[i]]
    thisgroup <- align.embeddings(thisgroup) #Align within group
    gpmn <- thisgroup[[1]] #Seed mean with first element

    #Add others if there are more in group
    if(length(thisgroup) > 1){
      for(j in c(2: length(thisgroup))) gpmn <- gpmn + thisgroup[[j]]
    }
    #Divide by number of embeddings in group
    gpmn <- gpmn/length(thisgroup)

    #To rotate so first dimension is largest component, etc:
    s <- svd(gpmn) #SVD of matrix
    o[[i]] <- s$u %*% diag(s$d) #reconstruct from U and eigen values
  }
  names(o) <- paste0("group-", gid)
  o
}
