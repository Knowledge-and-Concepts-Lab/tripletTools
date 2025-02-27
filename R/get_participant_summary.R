#' Get participant summary
#'
#' This function takes a list of triplet data of the kind returned by
#' `get_combined` and from it generates a dataframe summarizing information about
#' each participant in the study.
#'
#' @param d List of triplet data. Each element is data from one participant.
#' @param irange Vector indicating which elements of the list to include. Default is all.
#' @param mintrial Minimum number of trials needed to count as a complete record.
#' @param accthresh Accuracy threshould for check trials to pass quality check
#' @param rtthresh Threshold of log RT to pass quality check
#'
#' @return Data frame containing information about each participant in the study.
#'
#' @details
#' The summary will include participant ID, number of completed trials, mean
#' accuracy on check trials, and mean log(RT) across all trials. The arguments
#' `accthresh` and `rtthresh` set criteria for assessing the participant's data
#' quality. A mean log RT of 0 or less means participant was responding in under
#' one second on average, usually too fast for data to be real. Chance responding
#' will yield an accuracy of 0.5 on check trials, so a threshold of 0.8 means
#' participant was likely guessing on at least 40 percent of trials.
#'
#' This function assumes standard triplet data naming conventions for column names.
#'
#' @export
#'
#' @examples
#'
#' #Path to example triplet data
#' fpath <- system.file("extdata", "cfd36_triplets_individual.csv", package = "tripletTools")
#'
#' #Read the data
#' trips <- get.combined(fpath)
#'
#' #Compute summary
#' part.summary <- get.participant.summary(trips)
#'
#' head(part.summary)

get.participant.summary <- function(d, irange = NULL, mintrial = 1000, accthresh = 0.8, rtthresh = 0){

  n <- length(d) #number of participants

  #Initialize output dataframe:
  o <- data.frame(tripfile=rep("", times = n),
                  worker_id = rep("", times = n),
                  ndat = rep(0, times = n),
                  lrt = rep(0.0, times = n),
                  cacc = rep(0.0, times = n),
                  keep = rep(T, times = n))

  fnames <- names(d) #File names

  #Main data construction loop
  for(i in c(1:n)){
    sdat <- d[[i]] #Get subject data
    if(!is.null(irange)) sdat <- sdat[irange,] #Subset if irange set
    o$tripfile[i] <- fnames[i] #Name of file
    o$worker_id[i] <- sdat$worker_id[1] #Worker id
    o$ndat[i] <- dim(sdat)[1] #Number of data points
    o$lrt[i] <- mean(log(sdat$rt/1000), na.rm = TRUE) #Log RT (in seconds)

    #Proportion correct for check trials if these exist
    nct <- sum(sdat$sampleAlg=="check", na.rm=TRUE) #Number of check trials
    #print(nct); flush.console()
    if(nct > 1){
      sdat <- sdat[sdat$sampleAlg=="check",]
      o$cacc[i] <- mean(sdat$Answer==sdat$Center)
    } else {
      o$cacc[i] <- NA
    }
    #Which subjects meet quality criteria
    if(o$cacc[i] <= accthresh | o$lrt[i] <= rtthresh | o$ndat[i] < mintrial) o$keep[i] <- F
    #print(i)
  }
  o
}





