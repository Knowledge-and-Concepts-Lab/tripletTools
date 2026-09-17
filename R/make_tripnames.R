#' Make triplet names
#'
#' This function creates a unique name for each triplet appearing in a
#' triplet data frame.
#'
#' @param tripdat A data frame containing triplet data; must conform to
#'  naming conventions.
#'
#' @returns A character vector containing the unique triplet name for each trial
#'    in the triplet dataframe.
#'
#' @details
#' This function is useful for finding responses to a given triplet,
#' which is especially important when computing within and between-participant
#' consistency on validation trials.
#'
#' The two options (\code{Left}/\code{Right}) are ordered using
#' \code{\link[stringr]{str_sort}(numeric = TRUE)} before being joined into the
#' name, so embedded numbers are compared by numeric value rather than
#' digit-by-digit (e.g. \code{"deg2"} sorts before \code{"deg10"}, not after).
#' This ordering only needs to be consistent -- the same two options always
#' producing the same name regardless of which was \code{Left} and which was
#' \code{Right} on a given trial -- not "alphabetical" in any meaningful
#' sense, which is why using an ordering that also happens to sort numbers
#' sensibly is a strict improvement with no downside.
#'
#' @importFrom stringr str_sort
#'
#' @export
#'
#' @examples
#' trips <- icon_triplets[[1]] #Triplet data for participant 1
#' tnames <- make.tripnames(trips) #Make triplet names
#' tnames[1:5] #Names of first five triplets

make.tripnames <- function(tripdat){

  ## Check arguments
  #Check that tripdat is or can be coerced to a data frame
  tripdat <- try({
    tripdat <- as.data.frame(tripdat)
  }, silent = TRUE)

  # Check if the coercion was successful
  if (inherits(tripdat, "try-error")) {
    stop("Error: tripdat must be a data frame or coercible to one.")
  }

  #Check column names are correct
  namecheck <- match(c("Center","Left","Right"), names(tripdat))

  if(is.na(sum(namecheck))) stop("Column names must include Center, Left and Right")

  ##Main function

  opts <- as.matrix(tripdat[c("Left","Right")]) #Option items on each triplet
  opts <- gsub(" ","",opts) #Remove any spaces
  cent <- gsub(" ","",tripdat$Center) #Center item on each triplet, spaced removed
  nitems <- dim(opts)[1] #Total number of items

  #Put two options in a consistent order for all triplets (numeric-aware,
  #so e.g. "deg2"/"deg10" order by value rather than digit-by-digit):
  for(i in c(1:nitems)) opts[i,] <- str_sort(opts[i,], numeric = TRUE)

  #Return vector
  paste(cent, opts[,1], opts[,2], sep="_")
}

