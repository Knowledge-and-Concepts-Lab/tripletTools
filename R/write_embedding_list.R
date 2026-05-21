#' Write a list of individual embeddings to a CSV file
#'
#' Converts a named list of embedding matrices — as returned by the
#' \code{$individual} element of \code{\link{run_embeddings_from_list}} — into
#' a flat CSV file with one row per item per participant.
#'
#' @section Output format:
#' The CSV has one row per (participant, item) combination and the following
#' columns:
#' \describe{
#'   \item{\code{worker_id}}{Participant identifier, taken from the names of
#'     \code{embedding_list}.}
#'   \item{\code{item}}{Item name, taken from the row names of each matrix.}
#'   \item{\code{dim_0}, \code{dim_1}, …}{Embedding coordinates.  Column names
#'     are taken directly from the column names of each matrix.}
#' }
#'
#' @param embedding_list A named list of numeric matrices, one per participant.
#'   Each matrix must have item names as row names and embedding dimension
#'   columns named \code{dim_0}, \code{dim_1}, etc.  This is the format of the
#'   \code{$individual} element returned by \code{\link{run_embeddings_from_list}}.
#' @param file Path to the output CSV file.  The parent directory must already
#'   exist.
#'
#' @return The output file path, invisibly.
#'
#' @export
#'
#' @examples
#' \dontrun{
#' results <- run_embeddings_from_list(
#'   triplet_list = icon_triplets,
#'   output_dir   = "embeddings_output",
#'   d            = 3L
#' )
#'
#' # Write individual embeddings to a single flat CSV
#' write_embedding_list(results$individual, "embeddings_individual.csv")
#'
#' # Read back and reconstruct the named list
#' df       <- read.csv("embeddings_individual.csv")
#' dim_cols <- grep("^dim_", names(df), value = TRUE)
#' embedding_list <- lapply(
#'   split(df, df$worker_id),
#'   function(sub) {
#'     m <- as.matrix(sub[, dim_cols])
#'     row.names(m) <- sub$item
#'     m
#'   }
#' )
#' }
write_embedding_list <- function(embedding_list, file) {
  if (length(embedding_list) == 0)
    stop("'embedding_list' is empty.")
  if (is.null(names(embedding_list)) || any(names(embedding_list) == ""))
    stop("All elements of 'embedding_list' must be named (worker IDs).")

  rows <- lapply(names(embedding_list), function(wid) {
    m <- embedding_list[[wid]]
    if (!is.matrix(m))
      stop(sprintf("Element '%s' is not a matrix.", wid))
    if (is.null(row.names(m)))
      stop(sprintf("Matrix for '%s' has no row names (item names expected).", wid))
    df <- as.data.frame(m, stringsAsFactors = FALSE)
    df$worker_id  <- wid
    df$item       <- row.names(m)
    row.names(df) <- NULL
    df
  })

  out      <- do.call(rbind, rows)
  dim_cols <- grep("^dim_", names(out), value = TRUE)
  out      <- out[, c("worker_id", "item", dim_cols), drop = FALSE]

  utils::write.csv(out, file, row.names = FALSE)
  invisible(file)
}
