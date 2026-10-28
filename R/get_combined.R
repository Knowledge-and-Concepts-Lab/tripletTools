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
#' `worker_id` and `item` are always read as character, even when every
#' value in the file happens to look numeric (e.g. randomly-generated
#' all-digit worker IDs) -- otherwise `read.csv()`'s default type inference
#' would read such a column as numeric, silently dropping any leading zeros
#' and breaking exact matching against the original string IDs downstream.
#'
#' @export
#'
#' @examples
#' fpath <- system.file("extdata", "icon_embeddings_individual.csv", package="tripletTools")
#'
#' embeddings <- get.combined(fpath, eflag=TRUE)
#'
#' head(embeddings[[1]])

get.combined <- function(fname, eflag = FALSE){

  # worker_id (and item, for embeddings) must stay character even when every
  # value happens to look numeric (e.g. randomly-generated all-digit worker
  # IDs) -- read.csv()'s default type inference would otherwise silently
  # read such a column as numeric, dropping any leading zeros and breaking
  # exact matching against the original string IDs downstream.
  header_names <- names(read.csv(fname, header = TRUE, nrows = 0))
  force_character <- intersect(c("worker_id", "item"), header_names)
  col_classes <- stats::setNames(rep("character", length(force_character)), force_character)

  tmp <- read.csv(fname, header = TRUE, colClasses = col_classes) #Read file
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
