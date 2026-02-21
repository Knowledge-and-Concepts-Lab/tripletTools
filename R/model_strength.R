#' Get model strength
#'
#' This function assesses how well the similarities expressed in an embedding
#' or distance model explain the triad choices contained in vdat by computing
#' the distance of the furthest option divided by the sum of both distances.
#'
#' @param model An embedding model.
#' @param vdat A matrix of triplet data.
#' @param isemb Flag indicating whether model is an embedding; if FALSE, model is treated as a distance matrix.
#'
#' @returns Vector containing the prediction strength metric for each triplet
#'  in `vdat`
#'
#' @details
#' If `isemb==FALSE` function assumes `model` is a distance matrix.
#'
#' The prediction-strength metric has a floor of 0.5 (both equally distant) and
#' increases to approach 1.0 when one option is very close and the other very far,
#' that is, when the answer should be obvious. If the embedding is good,
#' people should make reliably consistent decisions for triplets where this
#' 'strength' is high and less consistent decisions when it is low.
#'
#' This measure can be especially useful when computed for validation trials
#' where the proportion of participants agreeing with the majority vote on
#' a trial has been computed. If most participants agree with the majority
#' decision on the triplet, this means decisions are highly reliable across
#' participants. If the embedding is good, such items will also have a high
#' prediction-strength score. Thus the correlation between prediction strength
#' and inter-subject agreement tells you something about the quality of the
#' embedding.
#'
#' @export
#'
#' @examples
#' emb <- cfd_embeddings[[2]] #Embedding for participant 1
#' trips <- cfd_triplets[[2]] #Triplets for participant 1
#'
#' #Get validation trials only
#' vdat <- subset(trips, trips$sampleAlg=="validation")
#'
#' pstrength <- model.strength(emb, vdat)


model.strength <- function(model, vdat, isemb=TRUE){

  if(isemb){ #If model is an embedding
    dmat<-as.matrix(dist(model))
  } else{
    dmat <- as.matrix(model)
    if(dim(model)[1] != dim(model)[2]){
      stop("Model is flagged as distance matrix but is not symmetric")
    }
  }

  ntriads<-dim(vdat)[1] #Number of triads
  nitems<-dim(dmat)[1]  #Number of items in embedding
  out<-rep(NA, times = ntriads) #Initialize output vector
  items<-row.names(dmat)  #Names of items

  #Pull out key items
  sample<-match(vdat$Center, items)
  option1<-match(vdat$Left, items)
  option2<-match(vdat$Right, items)

  if(is.na(sum(sample+option1+option2))){ #Check if there are missing items
    print("####Items not found in model####")
    out<-vdat$Target[is.na(sample)]
    out<-c(out, vdat$Option1[is.na(option1)])
    out<-c(out, vdat$Option2[is.na(option2)])
    out<-unique(out)
  } else
  {
    for(i1 in c(1:ntriads)){

      d1<-dmat[sample[i1], option1[i1]]
      d2<-dmat[sample[i1], option2[i1]]

      out[i1] <- max(c(d1,d2))/(d1+d2)
    }
  }
  out #Return vector
}
