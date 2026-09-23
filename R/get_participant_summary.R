#' Get participant summary
#'
#' This function takes a list of triplet data of the kind returned by
#' `get.combined` and from it generates a dataframe summarizing information
#' about each participant in the study.
#'
#' @param d List of triplet data. Each element is data from one participant.
#' @param irange Vector indicating which elements of the list to include. Default is all.
#' @param mintrial Minimum number of trials needed to count as a complete record.
#' @param accthresh Accuracy threshould for check trials to pass quality check
#' @param rtthresh Threshold of log RT to pass quality check
#'
#' @return Data frame containing information about each participant in the
#'   study, with one row per participant and columns:
#' \describe{
#'   \item{\code{tripfile}}{Name of the list element (usually a file/participant
#'     identifier), from \code{names(d)}.}
#'   \item{\code{worker_id}}{Participant identifier, from the \code{worker_id}
#'     column.}
#'   \item{\code{ndat}}{Number of trials (rows) for this participant.}
#'   \item{\code{lrt}}{Mean log response time, in seconds, across all trials.}
#'   \item{\code{cacc}}{Proportion correct on check trials (\code{sampleAlg ==
#'     "check"}); \code{1.0} if the participant has no (or only one) check
#'     trial, since accuracy can't meaningfully be assessed from that little
#'     data -- this is an automatic pass, not evidence of good performance.}
#'   \item{\code{ncheck}, \code{nvalidation}}{Number of trials with
#'     \code{sampleAlg} equal to \code{"check"} / \code{"validation"}
#'     respectively. \code{0} (not an error) if \code{sampleAlg} isn't a
#'     column in this participant's data at all -- some studies never use
#'     check/validation trials.}
#'   \item{\code{ntrain}, \code{ntest}}{Number of trials with \code{sampleSet}
#'     equal to \code{"train"} / \code{"test"} respectively. Also \code{0},
#'     not an error, if \code{sampleSet} is missing.}
#'   \item{\code{keep}}{Logical flag: \code{FALSE} if this participant fails
#'     any of the \code{accthresh}/\code{rtthresh}/\code{mintrial} criteria
#'     below.}
#'   \item{Any other constant-per-participant column}{See \emph{Extra
#'     participant-level fields} below -- present only if at least one
#'     participant's data actually has such a column, so this may add zero
#'     or several columns depending on \code{d}.}
#' }
#'
#' @details
#' The summary always includes participant ID, number of completed trials,
#' mean accuracy on check trials, mean log(RT) across all trials, and a
#' breakdown of trial counts by \code{sampleAlg}/\code{sampleSet} (see
#' \emph{Return}). The arguments \code{accthresh} and \code{rtthresh} set
#' criteria for assessing the participant's data quality. A mean log RT of 0
#' or less means participant was responding in under one second on average,
#' usually too fast for data to be real. Chance responding will yield an
#' accuracy of 0.5 on check trials, so a threshold of 0.8 means participant
#' was likely guessing on at least 40 percent of trials.
#'
#' This function assumes standard triplet data naming conventions for column
#' names.
#'
#' @section Extra participant-level fields:
#' Real triplet data files sometimes carry additional columns beyond the
#' standard ones -- e.g. which of several task variants a participant
#' performed, or other per-session metadata recorded alongside every trial.
#' Any column (other than \code{worker_id}, which is already the dedicated
#' identifier column above) that takes exactly one distinct non-\code{NA}
#' value across a given participant's rows is assumed to be participant-level
#' metadata rather than per-trial data, and is carried through to the summary
#' automatically under its own original column name -- no need to list such
#' columns in advance, since which ones qualify depends entirely on \code{d}.
#' A column that varies within a participant's own rows (as \code{Center},
#' \code{rt}, etc. always will) is correctly left out for that participant,
#' with no special-casing needed to exclude the standard trial-level columns
#' by name. If a qualifying column is constant for at least one participant
#' but not for another (or missing from another's data entirely), that
#' participant gets \code{NA} in the corresponding column rather than the
#' whole column being dropped. These extra columns are always returned as
#' character, regardless of the original column's type, since a single
#' output column may need to hold values collected from participants whose
#' data had that column stored as different types.
#'
#' @export
#'
#' @examples
#'
#' #Path to example triplet data
#' fpath <- system.file("extdata", "icon_all_triplets.csv", package = "tripletTools")
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
                  ncheck = rep(0L, times = n),
                  nvalidation = rep(0L, times = n),
                  ntrain = rep(0L, times = n),
                  ntest = rep(0L, times = n),
                  keep = rep(T, times = n))

  fnames <- names(d) #File names

  #Per-participant values for any field that's constant within that
  #participant's own rows (e.g. a "task" column) -- collected here and
  #assembled into extra output columns after the main loop, since which
  #fields qualify (and therefore how many extra columns are needed) isn't
  #known until every participant has been scanned. See the "Extra
  #participant-level fields" section of the function's documentation.
  extra_fields <- vector("list", n)

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
      cdat <- sdat[sdat$sampleAlg=="check",]
      o$cacc[i] <- mean(cdat$Answer==cdat$Center)
    } else {
      o$cacc[i] <- 1.0 #Automatic pass if no check trials
    }

    #Trial-type counts. sampleAlg ("random"/"check"/"validation") and
    #sampleSet ("train"/"test") are independent categorical columns, so
    #their counts are taken separately; a missing column (e.g. a study
    #that never used check/validation trials, or predates the sampleAlg
    #convention entirely) yields 0 rather than an error, the same way the
    #check-accuracy calculation above already tolerates it.
    o$ncheck[i]      <- sum(sdat$sampleAlg == "check", na.rm = TRUE)
    o$nvalidation[i] <- sum(sdat$sampleAlg == "validation", na.rm = TRUE)
    o$ntrain[i]      <- sum(sdat$sampleSet == "train", na.rm = TRUE)
    o$ntest[i]       <- sum(sdat$sampleSet == "test", na.rm = TRUE)

    #Any other column (besides worker_id, already captured above) that's
    #constant across this participant's rows -- see "Extra participant-
    #level fields" in the function documentation.
    other_cols <- setdiff(names(sdat), "worker_id")
    constant_vals <- lapply(other_cols, function(cn) {
      vals <- unique(sdat[[cn]][!is.na(sdat[[cn]])])
      if (length(vals) == 1) vals else NULL
    })
    names(constant_vals) <- other_cols
    extra_fields[[i]] <- constant_vals[!vapply(constant_vals, is.null, logical(1))]

    #Which subjects meet quality criteria
    if(o$cacc[i] <= accthresh | o$lrt[i] <= rtthresh | o$ndat[i] < mintrial) o$keep[i] <- F
    #print(i)
  }

  #Assemble extra per-participant-constant fields into columns, one per
  #field name that was constant for at least one participant; NA for any
  #participant where that field wasn't present in their data, or wasn't
  #constant across their rows.
  extra_names <- unique(unlist(lapply(extra_fields, names)))
  for (fn in extra_names) {
    o[[fn]] <- vapply(extra_fields, function(ef) {
      if (fn %in% names(ef)) as.character(ef[[fn]]) else NA_character_
    }, character(1))
  }

  o
}
