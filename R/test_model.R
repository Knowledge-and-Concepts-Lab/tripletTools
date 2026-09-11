#' Test embedding model predictions.
#'
#' This function generates predicted responses on a set of triplet items given
#' an embedding of the items, and appends the model prediction as an additional
#' column to the triplet data file, named after the embedding argument itself
#' by default (see \code{pred_name} below).
#'
#' @importFrom stats dist
#'
#' @param m An embedding of the stimuli or matrix of distances among stimuli.
#'  Rows must have names that correspond with the triplet data.
#' @param vdat Data frame containing triplet data. Must include columns
#'  named Center, Left and Right, and names here must match row names of model.
#' @param isemb Is model an embedding? If T (default), compute Euclidean distance
#'  matrix; otherwise just treat model as the distance matrix
#' @param pred_name Character or \code{NULL} (default). Name of the appended
#'  prediction column. When \code{NULL}, this is derived automatically from
#'  the expression passed as \code{m} -- e.g. \code{test.model(icon3d, valsum)}
#'  names the column \code{icon3d} -- sanitized with \code{\link{make.names}}
#'  so it's always a valid column name (this matters most when \code{m} is
#'  passed as something other than a plain variable name, e.g.
#'  \code{test.model(embeddings[[1]], valsum)}, where the derived name will be
#'  the sanitized deparsed expression rather than something meaningful). Set
#'  this explicitly for a predictable name regardless of how \code{m} is
#'  passed, e.g. when calling \code{test.model} from inside another function.
#'
#' @return Returns the triplet dataframe with the prediction column added,
#'  which contains the predicted triplet response given the embedding/distance
#'  matrix.
#'
#' @details
#' The returned object will be a data frame with an added field (named per
#' \code{pred_name} above) that contains the predicted response for the
#' triplet given the embedding. This response will be whichever of the two
#' choice items (Left or Right) has the smallest Euclidean distance to the
#' target item (Center) in the embedding space.
#'
#' If the triplet dataframe
#' also includes a field labelled `Answer` that contains the true, human-generated
#' answer for the triplet, then the model predictions can be easily converted to
#' a proportion correct score as follows:
#'
#' `mean(output$ModPred==output$Answer)`
#'
#' ...where `output` is the dataframe returned by the function, and `ModPred`
#' is replaced by whatever `pred_name` was used (see above).
#'
#' @export
#'
#' @examples
#' toy_embedding <- data.frame(
#'   x=c(1,1.1,2,2.1),
#'   y=c(1.25,1.75,1.25,2.75))
#'
#' row.names(toy_embedding) <- c("cat","dog","car","boat")
#'
#' toy_embedding <- as.matrix(toy_embedding)
#'
#' tr <- data.frame(
#'    Center=c("cat", "car"),
#'    Left = c("dog", "boat"),
#'    Right= c("car", "dog"))
#'
#' # Appends a column named "toy_embedding"
#' test.model(toy_embedding, tr, isemb=TRUE)
#'
#' # Appends a column named "ModPred" instead
#' test.model(toy_embedding, tr, isemb=TRUE, pred_name = "ModPred")

test.model <- function(m, vdat, isemb = TRUE, pred_name = NULL){
  ### Determine the name of the predicted-response column to append. Captured
  ### here, before `m` is reassigned below, because substitute() only sees the
  ### caller's original expression while `m` is still an unevaluated promise --
  ### capturing it after `m <- as.matrix(m)` would just return "m" itself.
  if (is.null(pred_name)) {
    pred_name <- make.names(deparse(substitute(m)))
  }

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
    names(out)[dim(out)[2]]<-pred_name
  }
  out
}
