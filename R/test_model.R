#' Test embedding model predictions.
#'
#' This function generates predicted responses on a set of triplet items given
#' an embedding of the items, and appends the model prediction as an additional
#' column named ModPred to the triplet data file.
#'
#' @importFrom stats dist
#'
#' @param m An embedding of the stimuli or matrix of distances among stimuli.
#'  Rows must have names that correspond with the triplet data.
#' @param vdat Data frame containing triplet data. Must include columns
#'  named Center, Left and Right, and names here must match row names of model.
#' @param isemb Is model an embedding? If T (default), compute Euclidean distance
#'  matrix; otherwise just treat model as the distance matrix
#'
#' @return Returns the triplet dataframe with the column ModPred added, which contains
#'  the predicted triplet response given the embedding/distance matrix.
#'
#' @details
#' The returned object will be a data frame with an added field `ModPred` that
#' contains the predicted response for the triplet given the embedding. This response
#' will be whichever of the two choice items (Left or Right) has the smallest Euclidean
#' distance to the target item (Center) in the embedding space.
#'
#' If the triplet dataframe
#' also includes a field labelled `Answer` that contains the true, human-generated
#' answer for the triplet, then the model predictions can be easily converted to
#' a proportion correct score as follows:
#'
#' `mean(output$ModPred==output$Answer)`
#'
#' ...where `output` is the dataframe returned by the function.
#'
#' @export
#'
#' @examples
#' m <- data.frame(
#'   x=c(1,1.1,2,2.1),
#'   y=c(1.25,1.75,1.25,2.75))
#'
#' row.names(m) <- c("cat","dog","car","boat")
#'
#' m <- as.matrix(m)
#'
#' tr <- data.frame(
#'    Center=c("cat", "car"),
#'    Left = c("dog", "boat"),
#'    Right= c("car", "dog"))
#'
#' test.model(m, tr, isemb=TRUE)

test.model <- function(m, vdat, isemb = TRUE){
  ### Check arguments
  #Check that m can be coerced to a numeric matrix
  m <- try({
    m <- as.matrix(m)
    if (!is.numeric(m)) stop("m should be a numberic matrix")
    m
  }, silent = TRUE)

  # Check if the coercion was successful
  if (inherits(m, "try-error")) {
    stop("Error: m must be a numeric matrix or coercible to one.")
  }

  #Check that vdat is or can be coerced to a data frame
  vdat <- try({
    vdat <- as.data.frame(vdat)
  }, silent = TRUE)

  # Check if the coercion was successful
  if (inherits(vdat, "try-error")) {
    stop("Error: vdat must be a data frame or coercible to one.")
  }

  #Check for necessary column names
  tst <- match(c("Center","Left","Right"), names(vdat))
  if(is.na(sum(tst))){
    stop("Triplet data must contain columns named Center, Left and Right")
  }

  ## Start computation
  # Compute distances if it is an embedding
  if(isemb) dmat<-as.matrix(stats::dist(m)) else dmat <- m
  ntriads<-dim(vdat)[1] #Number of triads
  nitems<-dim(dmat)[1]  #Number of items
  out<-rep("NA", times = ntriads) #Initialize output
  items<-row.names(dmat)  #Names of items

  #Check if there are missing items in distance matrix
  center<-match(vdat$Center, items)
  option1<-match(vdat$Left, items)
  option2<-match(vdat$Right, items)

  if(is.na(sum(center+option1+option2))){ #Some items not found
    print("####Items not found in model####")
    #Indicate which were not found
    out<-vdat$Center[is.na(center)]
    out<-c(out, vdat$Left[is.na(option1)])
    out<-c(out, vdat$Right[is.na(option2)])
    out<-unique(out)
  } else
  { #If all items are found
    for(i1 in c(1:ntriads)){

      d1<-dmat[center[i1], option1[i1]]
      d2<-dmat[center[i1], option2[i1]]

      if(d1<d2)out[i1]<-items[option1[i1]] else out[i1]<-items[option2[i1]]
    }
    out<-cbind(vdat,out)
    names(out)[dim(out)[2]]<-"ModPred"
  }
  out
}
