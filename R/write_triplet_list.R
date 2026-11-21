#' Write a list of participant triplet data frames to a CSV file
#'
#' Converts a named or unnamed list of per-participant triplet data frames
#' -- the package's standard \code{Center}/\code{Left}/\code{Right}/
#' \code{Answer}/\code{worker_id} shape, e.g. \code{\link{icon_triplets}} --
#' into a single combined CSV file, one row per trial. Counterpart to
#' \code{\link{write_embedding_list}}, for triplet data rather than fitted
#' embeddings; the result round-trips through \code{\link{get.combined}}
#' (\code{eflag = FALSE}).
#'
#' @section Output format:
#' The CSV has one row per trial, with every column present in any element
#' of \code{triplet_list} (participants whose own data frame is missing a
#' column some other participant has get \code{NA} in that column, via
#' \code{\link[dplyr]{bind_rows}} -- see Details). Unlike
#' \code{\link{write_embedding_list}}, \code{worker_id} is read directly
#' from each data frame's own \code{worker_id} column, not from
#' \code{names(triplet_list)} -- the list itself need not be named (most of
#' this package's own triplet lists, e.g. those built by
#' \code{\link{read_raw_data}}, are not).
#'
#' @param triplet_list A list of data frames, one per participant, each with
#'   its own \code{worker_id} column (the format \code{\link{find_frequent_triplets}}
#'   and \code{\link{assign_validation_from_frequency}} also expect).
#' @param file Path to the output CSV file. The parent directory must
#'   already exist.
#'
#' @return The output file path, invisibly.
#'
#' @details
#' Participants' data frames are combined with \code{\link[dplyr]{bind_rows}}
#' rather than \code{rbind()}, so they don't need to share identical columns
#' or column order -- a real possibility for legacy data assembled from
#' several sources (e.g. after splitting off a held-out subset of
#' participants, or combining data read in separate batches).
#'
#' @seealso \code{\link{write_embedding_list}} for the embedding-list
#'   analogue; \code{\link{get.combined}} to read the result back in.
#'
#' @export
#'
#' @examples
#' out <- tempfile(fileext = ".csv")
#' write_triplet_list(icon_triplets, out)
#'
#' # Read back and reconstruct the named list
#' triplet_list <- get.combined(out, eflag = FALSE)
#' names(triplet_list)
write_triplet_list <- function(triplet_list, file) {
  if (!is.list(triplet_list) || is.data.frame(triplet_list)) {
    stop("triplet_list must be a list of per-participant triplet data frames.")
  }
  if (length(triplet_list) == 0) {
    stop("'triplet_list' is empty.")
  }
  if (!all(vapply(triplet_list, is.data.frame, logical(1)))) {
    stop("Every element of 'triplet_list' must be a data frame.")
  }
  if (!all(vapply(triplet_list, function(df) "worker_id" %in% names(df), logical(1)))) {
    stop("Every data frame in 'triplet_list' must have a 'worker_id' column.")
  }

  out <- dplyr::bind_rows(triplet_list)
  utils::write.csv(out, file, row.names = FALSE)
  invisible(file)
}
