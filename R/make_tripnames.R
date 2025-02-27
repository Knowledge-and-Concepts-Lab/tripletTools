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
#' @export
#'
#' @examples
#' trips <- cfd_triplets[[10]] #Triplet data for participant 10
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

  #Put two options in alphabetical order for all triplets:
  for(i in c(1:nitems)) opts[i,] <- sort(opts[i,])

  #Return vector
  paste(cent, opts[,1], opts[,2], sep="_")
}

