#' Make validation matrix
#'
#' This function uses the validation trials from triplet data to construct
#' a subject-by-trial matrix of judgments on these items.
#'
#' @param triplist Named list whose elements each contain triplet data from one
#'   participant. Names should be participant identifiers, as returned by
#'   `get_combined`.
#'
#' @returns Names list with two elements. `majority` is a data frame with one row
#'   per validation triplet, with columns `triplet` (the unique triplet code from
#'   `make.tripnames`), `majority` (the winning choice), `pmaj` (proportion of
#'   participants who selected it), and `Center`/`Left`/`Right` (the triplet's
#'   items, in the format `test.model` expects -- see Details). `bysbj` is a
#'   matrix indicating, for each participant (rows) and validation triplet
#'   (columns), the choice the participant made.
#'
#' @details
#' Each validation triplet is identified with a unique code of the kind generated
#' by `make.tripnames`, which indicates the target word and the two options in a
#' consistent, numeric-aware order (see `\link{make.tripnames}`).
#'
#' Because `majority` includes `Center`/`Left`/`Right` columns, it can be passed
#' directly to \code{\link{test.model}} (together with a fitted embedding) to
#' get each validation triplet's predicted response as an added `ModPred`
#' column, and compare that to the human majority vote in `majority`.
#'
#' Where a participant judged a particular validation triplet the entries of `bysbj`
#' will indicate the proportion of times the participant's decision agreed with
#' the majority vote. (In most cases this will be 0 or 1 since participants usually
#' judge a validation triplet only once; however in some studies the same validation
#' trials are repeated to evaluate self-consistency). Where a participant did not judge
#' a given triplet, the entry in `bysbj`will be NA.
#'
#' @importFrom stringr str_sort
#'
#' @export
#'
#' @examples
#' vmat <- make.vmat(icon_triplets)
#' vmat$majority

make.vmat <- function(triplist){

  sjs <- names(triplist)
  nsjs <- length(triplist)

  vdat <- NULL #Initialize dataframe

  #Turn list back into dataframe
  for(i in c(1:nsjs)){
    thisdat <- triplist[[i]] #Get current subject
    vdat <- rbind(vdat, thisdat)
  }

  #Make sure there are validation trials
  checktrial <- match("validation", unique(vdat$sampleAlg))
  if(is.na(checktrial)) stop("No validation trials found")

  #Pull out validation trials only
  vdat <- subset(vdat, vdat$sampleAlg=="validation")

  tripnames <- make.tripnames(vdat) #Get triplet names
  vdat <- cbind(vdat, tripnames) #Add as column
  trips <- str_sort(unique(tripnames), numeric = TRUE) #Unique triplets sorted
  ntrips <- length(trips) #Number of unique triplets

  #Initialize response matrix
  resp <- matrix(NA, nsjs, ntrips)
  row.names(resp) <- sjs
  colnames(resp) <- trips

  #Populate response matrix
  for(i in c(1:nsjs)){
    #Get current subject
    sdat <- subset(vdat, vdat$worker_id==sjs[i])
    resp[i,match(sdat$tripnames, trips)] <- sdat$Answer
  }

  #Initialize dataframe for computing majority vote
  pmaj <- data.frame(triplet=trips,
                     majority=rep(NA, times = ntrips),
                     pmaj=rep(NA, times = ntrips))

  for(i in c(1: ntrips)){
    thisone <- table(resp[,i])
    pmaj[i,2] <- names(which.max(thisone)) #Winner
    pmaj[i,3] <- max(thisone)/sum(thisone) #proportion voting for winner
  }

  #Add Center/Left/Right columns so `majority` can be passed directly to
  #test.model(). Center and the *set* of two options are looked up from the
  #original data (one representative row per unique triplet) rather than
  #parsed back out of the "triplet" string, since make.tripnames() joins
  #Center/Left/Right with "_" and item names themselves can contain
  #underscores (e.g. "dots_070deg"), which would make a naive string split
  #ambiguous. Left/Right are then ordered the same way make.tripnames() orders
  #them (str_sort(numeric = TRUE), not plain pmin/pmax) -- the same triplet
  #can appear with the two options on either side across trials/participants,
  #and Left/Right here should reflect the same fixed, numeric-aware order
  #baked into the triplet name, not whichever ordering happened to appear
  #first in the data, and not plain alphabetical order either (which would
  #disagree with make.tripnames() whenever item names contain numbers, e.g.
  #ordering "deg10" before "deg2").
  first_idx <- match(trips, vdat$tripnames)
  left_vals  <- vdat$Left[first_idx]
  right_vals <- vdat$Right[first_idx]
  ordered <- mapply(function(a, b) str_sort(c(a, b), numeric = TRUE),
                     left_vals, right_vals)
  pmaj$Center <- vdat$Center[first_idx]
  pmaj$Left   <- ordered[1, ]
  pmaj$Right  <- ordered[2, ]

  #Initialize numeric by-subject matrix
  bysbj <- matrix(NA, dim(resp)[1], dim(resp)[2]) #Output matrix
  row.names(bysbj) <- row.names(resp)
  colnames(bysbj) <- colnames(resp)

  for(i in c(1:ntrips)){
    winner <- pmaj[i,2] #winner
    #did participant agree with winner:
    agree <- as.numeric(resp[,i] == winner)
    bysbj[,i] <- agree #Store in output matrix
  }

  o <- list(pmaj, bysbj)

  names(o) <- c("majority", "bysbj")
  o

  }
