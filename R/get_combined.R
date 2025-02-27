#' Get combined data
#'
#' This function reads a triplet or embedding data file containing
#' data from multiple participants, returning a named list with
#' each element containing data from one participant.
#'
#' @importFrom utils read.csv
#'
#' @param fname Path to and name of the data file.
#' @param eflag Flag indicating whether data are embeddings, default FALSE
#'
#' @return A named list, each element being a dataframe containing one participant's
#'  data.
#'
#' @details
#' Data files must be in CSV format with column names in the first line.
#' The function assumes participant identifier labels are included in
#' a field called `worker_id`. If the data are embeddings, the file
#' must contain column names called `dim_x` where `x` is the dimension
#' number. Embedding data must also include a column named `item` that
#' indicates the item embedded at each row. The function will use this
#' column to set row names for each dataframe. The list elements will be
#' labelled by the `worker_id` value.
#'
#' Use this function to read in combined (across subjects) triplet data
#' files (with `eflag=FALSE`) or embedding files (with `eflag=TRUE`)
#'
#' @export
#'
#' @examples
#' fpath <- system.file("extdata", "cfd36_embeddings_individual.csv", package="tripletTools")
#'
#' embeddings <- get.combined(fpath, eflag=TRUE)
#'
#' head(embeddings[[1]])

get.combined <- function(fname, eflag = FALSE){

  tmp <- read.csv(fname, header = TRUE) #Read file
  sjs <- unique(tmp$worker_id) #Get unique participants
  nsj <- length(sjs) #Number of participants
  o <- list() #Initialize output list

  for(i in c(1:nsj)){
    o[[i]] <- subset(tmp, tmp$worker_id==sjs[i])   #Get current subject
    if(eflag){ #If data are embeddings
      row.names(o[[i]]) <- o[[i]]$item #Name rows
      cnames <- grep("dim", names(tmp), value = T) #Pull out embedding columns
      o[[i]] <- o[[i]][,cnames] #Discard columns other than embedding coordinates
    }
  }
  names(o) <- sjs
  o
}
