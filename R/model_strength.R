# TSTE/Student-t choice-model win probability that the option at squared
# distance d1_sq is judged closer to the head than the option at squared
# distance d2_sq, given a fixed alpha -- same formula as the vendored Python
# TSTE noise model (inst/python/salmon/.../_noise_models.py's TSTE._probs()),
# which is what estimate_group_alpha()/fit_group_embedding_restarts_at_alpha()
# actually fit (alpha = 1 is exactly crowd-kernel mu = 1). Symmetric under
# swapping the two arguments and 1-complemented, so it works regardless of
# which option is labeled "winner". Distinct from the CKL mu-parameterized
# formula in find_discriminating_triplets.R's ckl_prob() -- a different
# (though closely related) choice-model family.
tste_closer_prob <- function(d1_sq, d2_sq, alpha) {
  pwr <- -(alpha + 1) / 2
  t1 <- (1 + d1_sq / alpha)^pwr
  t2 <- (1 + d2_sq / alpha)^pwr
  t1 / (t1 + t2)
}

#' Get model strength
#'
#' This function assesses how well the similarities expressed in an embedding
#' or distance model explain the triad choices contained in vdat by computing
#' the distance of the furthest option divided by the sum of both distances.
#'
#' @param model An embedding model.
#' @param vdat A matrix of triplet data.
#' @param isemb Flag indicating whether model is an embedding; if FALSE, model is treated as a distance matrix.
#' @param alpha Optional choice-model alpha (the same parameter fit by
#'   \code{estimate_group_alpha()}/\code{fit_group_embedding_restarts_at_alpha()},
#'   where \eqn{\alpha = 1} is exactly crowd-kernel \eqn{\mu = 1}). If `NULL`
#'   (default), the function's original distance-ratio behavior is
#'   unchanged. If set, the function instead returns, for each triplet, the
#'   TSTE/Student-t choice-model probability of whichever option is
#'   predicted to win (the one closer to `Center`) -- always the larger of
#'   the two win-probabilities, so always \eqn{\ge 0.5}.
#'
#' @returns Vector containing, for each triplet in `vdat`, either the
#'  prediction-strength metric (`alpha = NULL`) or the choice-model
#'  probability of the predicted winner (`alpha` set)
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
#' Setting `alpha` ties this same "how easy should this triplet be" idea
#' directly to the choice model actually used to fit the embedding, rather
#' than to the raw distance ratio -- useful for checking, e.g., whether the
#' empirical probability of an accurate response on a set of fully held-out
#' triplets tracks the model-implied probability of its predicted winner.
#'
#' @export
#'
#' @examples
#' emb <- icon_emb_ind[[1]] #Embedding for participant 1
#' trips <- icon_triplets[[1]] #Triplets for participant 1
#'
#' #Get validation trials only
#' vdat <- subset(trips, trips$sampleAlg=="validation")
#'
#' pstrength <- model.strength(emb, vdat)
#'
#' #Same triplets, but as a choice-model probability at alpha = 1
#' pwin <- model.strength(emb, vdat, alpha = 1)


model.strength <- function(model, vdat, isemb=TRUE, alpha=NULL){

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

      if (is.null(alpha)) {
        out[i1] <- max(c(d1,d2))/(d1+d2)
      } else {
        p1 <- tste_closer_prob(d1^2, d2^2, alpha)
        out[i1] <- max(p1, 1 - p1)
      }
    }
  }
  out #Return vector
}
