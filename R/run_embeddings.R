#' Compute a group-level embedding from a triplet data list
#'
#' Trains a single embedding on the combined triplet judgments from all
#' participants.  Individual per-participant embeddings are not computed.
#' Use this function when you only need a group summary of the similarity
#' structure, which is faster than \code{\link{run_embeddings_from_list}}.
#'
#' @section Item indexing:
#' All unique item names appearing in the \code{Center}, \code{Left}, and
#' \code{Right} columns across all participants are collected and sorted
#' alphabetically.  Each item's zero-based index in this sorted list is used
#' as the integer index for the Python model.
#'
#' @section Filtering:
#' Trials with \code{sampleAlg == "check"} are excluded.  The
#' \code{sampleSet} column (\code{"train"} / \code{"test"}) must be present
#' and is used to split data for early stopping.
#'
#' @param triplet_list A named list of data frames, one per participant, as
#'   returned by \code{\link{get.combined}}.  Each data frame must contain the
#'   columns \code{Center}, \code{Left}, \code{Right}, \code{Answer},
#'   \code{sampleAlg}, and \code{sampleSet}.
#' @param d Number of embedding dimensions.  Default \code{5}.
#' @param max_epochs Maximum number of training epochs.  Default \code{50000}.
#' @param tolerance Loss tolerance for early stopping.  Default \code{1e-4}.
#' @param tol_window Epochs without improvement before early stopping triggers.
#'   Default \code{10000}.
#' @param seed Integer random seed for reproducibility.  Default \code{222}.
#' @param device PyTorch device string, or \code{NULL} (default) to
#'   auto-select: CUDA GPU if available, then Apple MPS, then CPU.
#'   Pass \code{"cpu"} to force CPU even on a GPU machine.
#' @param geometry Either \code{"euclidean"} (default) or \code{"sphere"}.
#'   When \code{"sphere"}, items are placed on the surface of a
#'   \code{d}-dimensional sphere of radius \code{radius} (\code{d = 2} is a
#'   circle) instead of freely in \eqn{R^d}.  See the \emph{Spherical
#'   embeddings} section of \code{\link{train_embedding}} for details,
#'   including why this roughly doubles training time.
#' @param radius Radius of the sphere used when \code{geometry = "sphere"}.
#'   Ignored when \code{geometry = "euclidean"}.  Default \code{1}.
#' @param warm_start Optional numeric matrix of existing embedding
#'   coordinates to start training from, instead of a random initialization
#'   — for example, the \code{embedding} returned by a previous call to this
#'   function.  Must have row names matching item names and \code{d} columns;
#'   rows are matched and reordered by name, so \code{warm_start} does not
#'   need to list items in the same order as this call (every item present
#'   in \code{triplet_list} must have a matching row name, though).
#'
#'   When \code{geometry = "sphere"}, pass an already-computed
#'   \strong{Euclidean} embedding of the same items (e.g. from a prior
#'   \code{geometry = "euclidean"} call) to skip the internal warm-start
#'   Euclidean fit — see the \emph{Spherical embeddings} section of
#'   \code{\link{train_embedding}} for why that stage normally runs.  When
#'   \code{geometry = "euclidean"}, it is used directly as the starting
#'   point for training.  \code{NULL} (default) starts from a random
#'   initialization.
#'
#' @return A named list with three elements:
#' \describe{
#'   \item{\code{embedding}}{Numeric matrix with one row per item (item names
#'     as row names) and \code{d} columns (\code{dim_0}, \code{dim_1}, …).}
#'   \item{\code{loss}}{Best test loss achieved during training.}
#'   \item{\code{history}}{Data frame with one row per epoch and columns
#'     \code{epoch}, \code{train_loss}, \code{test_loss}, \code{train_acc},
#'     \code{test_acc}.}
#' }
#'
#' @export
#'
#' @examples
#' \dontrun{
#' grp <- run_group_embedding_from_list(
#'   triplet_list = icon_triplets,
#'   d            = 3L,
#'   max_epochs   = 50000L
#' )
#'
#' # Embedding matrix (items x dimensions)
#' head(grp$embedding)
#'
#' # Best test loss
#' grp$loss
#'
#' # Already have a Euclidean fit of the same items? Skip the internal
#' # warm-start stage when fitting a spherical embedding.
#' grp_circle <- run_group_embedding_from_list(
#'   triplet_list = icon_triplets,
#'   d            = 2L,
#'   geometry     = "sphere",
#'   warm_start   = grp$embedding
#' )
#' }
run_group_embedding_from_list <- function(triplet_list,
                                          d          = 5L,
                                          max_epochs = 50000L,
                                          tolerance  = 1e-4,
                                          tol_window = 10000L,
                                          seed       = 222L,
                                          device     = NULL,
                                          geometry   = c("euclidean", "sphere"),
                                          radius     = 1,
                                          warm_start = NULL) {
  geometry <- match.arg(geometry)
  set.seed(seed)

  # Collect and sort all item names for consistent zero-based indexing
  all_items <- sort(unique(unlist(lapply(triplet_list, function(df) {
    c(df$Center, df$Left, df$Right)
  }))))

  warm_start_mat <- NULL
  if (!is.null(warm_start)) {
    if (is.null(rownames(warm_start))) {
      stop("warm_start must have row names matching item names")
    }
    missing_items <- setdiff(all_items, rownames(warm_start))
    if (length(missing_items)) {
      stop(sprintf(
        "warm_start is missing %d item(s) present in triplet_list: %s",
        length(missing_items),
        paste(utils::head(missing_items, 5), collapse = ", ")
      ))
    }
    warm_start_mat <- as.matrix(warm_start[all_items, , drop = FALSE])
  }

  # Combine all participants, excluding check trials, converting to 0-based indices
  combined <- do.call(rbind, lapply(triplet_list, function(df) {
    df <- df[!is.na(df$sampleSet), ]
    winner <- ifelse(df$Answer == df$Left, df$Left, df$Right)
    loser  <- ifelse(df$Answer == df$Left, df$Right, df$Left)
    data.frame(
      head      = match(df$Center, all_items) - 1L,
      winner    = match(winner,    all_items) - 1L,
      loser     = match(loser,     all_items) - 1L,
      sampleSet = df$sampleSet,
      stringsAsFactors = FALSE
    )
  }))

  train_rows <- combined$sampleSet == "train"
  test_rows  <- combined$sampleSet == "test"

  if (!any(train_rows) || !any(test_rows)) {
    shuffled   <- combined[sample(nrow(combined)), ]
    split_idx  <- floor(0.7 * nrow(shuffled))
    train_rows <- seq_len(split_idx)
    test_rows  <- seq(split_idx + 1L, nrow(shuffled))
    X_train <- as.matrix(shuffled[train_rows, c("head", "winner", "loser")])
    X_test  <- as.matrix(shuffled[test_rows,  c("head", "winner", "loser")])
  } else {
    X_train <- as.matrix(combined[train_rows, c("head", "winner", "loser")])
    X_test  <- as.matrix(combined[test_rows,  c("head", "winner", "loser")])
  }

  out <- train_embedding(
    X_train    = X_train,
    X_test     = X_test,
    d          = d,
    max_epochs = max_epochs,
    tolerance  = tolerance,
    tol_window = tol_window,
    device     = device,
    geometry   = geometry,
    radius     = radius,
    warm_start = warm_start_mat
  )

  colnames(out$embedding) <- paste0("dim_", seq_len(ncol(out$embedding)) - 1L)
  row.names(out$embedding) <- all_items

  list(
    embedding = out$embedding,
    loss      = out$loss,
    history   = out$history
  )
}


#' Run the full embedding pipeline for all workers
#'
#' Reads triplet comparison data from \code{input_file}, trains a separate
#' embedding model with early stopping for each worker, and then trains a
#' combined group-level embedding across all workers.  Output CSV files are
#' written to \code{output_dir} and the results are also returned as R data
#' frames.
#'
#' For a higher-level interface that accepts triplet data already loaded into R
#' as a named list (the format returned by \code{\link{get.combined}}), see
#' \code{\link{run_embeddings_from_list}}.
#'
#' @section Input format:
#' \code{input_file} must be a CSV with at least the following columns:
#' \describe{
#'   \item{\code{worker_id}}{Identifier for the respondent.}
#'   \item{\code{head}}{Zero-based integer index of the reference item.}
#'   \item{\code{winner}}{Zero-based integer index of the item judged closer
#'     to \code{head}.}
#'   \item{\code{loser}}{Zero-based integer index of the item judged further
#'     from \code{head}.}
#'   \item{\code{sampleSet}}{Either \code{"train"} or \code{"test"}, used to
#'     split data for early stopping.}
#' }
#'
#' @section Output files:
#' Three CSV files are written to \code{output_dir}:
#' \describe{
#'   \item{\code{model_history.csv}}{Training history: loss, stopping
#'     epoch, and triplet counts for each worker.}
#'   \item{\code{embeddings_group.csv}}{Group-level embedding only.}
#'   \item{\code{embeddings.csv}}{All per-worker and group-level embeddings
#'     concatenated.}
#' }
#'
#' @param input_file Path to the CSV file containing all triplets (see
#'   \emph{Input format} above).
#' @param additional_data_file Path to a CSV file with item metadata to append
#'   to the embedding output (e.g. image filenames listed in alphabetical
#'   order).  The number of rows should match the number of unique items.
#' @param output_dir Path to the directory where output CSV files will be
#'   saved.  Created automatically if it does not already exist.
#' @param d Number of embedding dimensions.  Default \code{5}.
#' @param max_epochs Maximum number of training epochs.  Default \code{50000}.
#' @param tolerance Loss tolerance for early stopping.  Default \code{1e-4}.
#' @param tol_window Epochs without improvement before early stopping triggers.
#'   Default \code{10000}.
#' @param seed Integer random seed for reproducibility.  Default \code{222}.
#' @param device PyTorch device string, or \code{NULL} (default) to
#'   auto-select: CUDA GPU if available, then Apple MPS, then CPU.
#'   Pass \code{"cpu"} to force CPU even on a GPU machine.
#' @param geometry Either \code{"euclidean"} (default) or \code{"sphere"}.
#'   When \code{"sphere"}, items are placed on the surface of a
#'   \code{d}-dimensional sphere of radius \code{radius} (\code{d = 2} is a
#'   circle) instead of freely in \eqn{R^d}.  See the \emph{Spherical
#'   embeddings} section of \code{\link{train_embedding}} for details,
#'   including why this roughly doubles training time.
#' @param radius Radius of the sphere used when \code{geometry = "sphere"}.
#'   Ignored when \code{geometry = "euclidean"}.  Default \code{1}.
#'
#' @return A named list with two elements:
#' \describe{
#'   \item{\code{history}}{Data frame with one row per worker (plus one for
#'     the group model) containing: \code{worker_id}, \code{lowest_loss},
#'     \code{epoch}, \code{counter_from_last_update},
#'     \code{n_train_triplets}, \code{n_test_triplets}.}
#'   \item{\code{embeddings}}{Data frame of all embeddings concatenated, with
#'     dimension columns (\code{dim_0}, \code{dim_1}, …), a \code{worker_id}
#'     column, and any columns from \code{additional_data_file}.}
#' }
#'
#' @export
#'
#' @examples
#' \dontrun{
#' results <- run_embeddings(
#'   input_file           = "triplets.csv",
#'   additional_data_file = "item_labels.csv",
#'   output_dir           = "embeddings_output",
#'   d                    = 5L,
#'   max_epochs           = 50000L
#' )
#'
#' head(results$history)
#' head(results$embeddings)
#' }
run_embeddings <- function(input_file,
                           additional_data_file,
                           output_dir,
                           d          = 5L,
                           max_epochs = 50000L,
                           tolerance  = 1e-4,
                           tol_window = 10000L,
                           seed       = 222L,
                           device     = NULL,
                           geometry   = c("euclidean", "sphere"),
                           radius     = 1) {
  geometry <- match.arg(geometry)
  compute_py <- .get_compute_py()

  random <- reticulate::import("random")
  random$seed(as.integer(seed))

  result <- compute_py$process_all_workers(
    input_file           = input_file,
    additional_data_file = additional_data_file,
    output_dir           = output_dir,
    d                    = as.integer(d),
    max_epochs           = as.integer(max_epochs),
    tolerance            = tolerance,
    tol_window           = as.integer(tol_window),
    device               = device,
    geometry             = geometry,
    radius               = radius
  )

  list(
    history    = as.data.frame(result[[1]]),
    embeddings = as.data.frame(result[[2]])
  )
}


#' Run the embedding pipeline from a triplet data list
#'
#' A convenience wrapper around \code{\link{run_embeddings}} that accepts
#' triplet data already loaded into R as a named list — the format returned
#' by \code{\link{get.combined}} — rather than reading from CSV files.
#'
#' The function converts items to consistent zero-based integer indices
#' (sorted alphabetically), writes temporary CSV files, calls the Python
#' embedding pipeline, and returns results in the standard \code{tripletTools}
#' format.
#'
#' @section Item indexing:
#' All unique item names appearing in the \code{Center}, \code{Left}, and
#' \code{Right} columns across all participants are collected and sorted
#' alphabetically.  Each item's zero-based index in this sorted list is used
#' as the integer index for the Python model.  The same ordering is applied to
#' all participants so that indices are consistent across workers.
#'
#' @section Filtering:
#' Trials with \code{sampleAlg == "check"} are excluded before fitting the
#' embedding (these are attention-check trials that do not reflect genuine
#' similarity judgments).  The \code{sampleSet} column (indicating
#' \code{"train"} or \code{"test"}) must be present and is passed through
#' unchanged.
#'
#' @param triplet_list A named list of data frames, one per participant, as
#'   returned by \code{\link{get.combined}}.  Each data frame must contain the
#'   columns \code{worker_id}, \code{Center}, \code{Left}, \code{Right},
#'   \code{Answer}, \code{sampleAlg}, and \code{sampleSet}.
#' @param output_dir Path to the directory where output CSV files will be
#'   saved.  Created automatically if it does not already exist.
#' @param d Number of embedding dimensions.  Default \code{5}.
#' @param max_epochs Maximum number of training epochs.  Default \code{50000}.
#' @param tolerance Loss tolerance for early stopping.  Default \code{1e-4}.
#' @param tol_window Epochs without improvement before early stopping triggers.
#'   Default \code{10000}.
#' @param seed Integer random seed for reproducibility.  Default \code{222}.
#' @param device PyTorch device string, or \code{NULL} (default) to
#'   auto-select: CUDA GPU if available, then Apple MPS, then CPU.
#'   Pass \code{"cpu"} to force CPU even on a GPU machine.
#' @param geometry Either \code{"euclidean"} (default) or \code{"sphere"}.
#'   When \code{"sphere"}, items are placed on the surface of a
#'   \code{d}-dimensional sphere of radius \code{radius} (\code{d = 2} is a
#'   circle) instead of freely in \eqn{R^d}.  See the \emph{Spherical
#'   embeddings} section of \code{\link{train_embedding}} for details,
#'   including why this roughly doubles training time.
#' @param radius Radius of the sphere used when \code{geometry = "sphere"}.
#'   Ignored when \code{geometry = "euclidean"}.  Default \code{1}.
#'
#' @return A named list with three elements:
#' \describe{
#'   \item{\code{individual}}{Named list of numeric matrices, one per
#'     participant.  Each matrix has one row per item (with item names as row
#'     names) and \code{d} columns (\code{dim_0}, \code{dim_1}, …).}
#'   \item{\code{group}}{Numeric matrix of the group-level embedding, with
#'     item names as row names and \code{d} columns.}
#'   \item{\code{history}}{Data frame with one row per worker (plus \code{"group"})
#'     containing training diagnostics: \code{worker_id}, \code{lowest_loss},
#'     \code{epoch}, \code{counter_from_last_update},
#'     \code{n_train_triplets}, \code{n_test_triplets}.}
#' }
#'
#' @export
#'
#' @examples
#' \dontrun{
#' results <- run_embeddings_from_list(
#'   triplet_list = icon_triplets,
#'   output_dir   = "embeddings_output",
#'   d            = 3L,
#'   max_epochs   = 50000L
#' )
#'
#' # Group embedding
#' head(results$group)
#'
#' # First participant's individual embedding
#' head(results$individual[[1]])
#'
#' # Training diagnostics
#' results$history
#' }
run_embeddings_from_list <- function(triplet_list,
                                     output_dir,
                                     d          = 5L,
                                     max_epochs = 50000L,
                                     tolerance  = 1e-4,
                                     tol_window = 10000L,
                                     seed       = 222L,
                                     device     = NULL,
                                     geometry   = c("euclidean", "sphere"),
                                     radius     = 1) {
  geometry <- match.arg(geometry)
  # Collect all item names across all participants and sort alphabetically
  all_items <- sort(unique(unlist(lapply(triplet_list, function(df) {
    c(df$Center, df$Left, df$Right)
  }))))

  # Combine all participants into one data frame, excluding check trials,
  # and convert item names to zero-based integer indices
  combined <- do.call(rbind, lapply(triplet_list, function(df) {
    df <- df[!is.na(df$sampleSet), ]  # drop check trials (NA sampleSet)
    winner <- ifelse(df$Answer == df$Left, df$Left, df$Right)
    loser  <- ifelse(df$Answer == df$Left, df$Right, df$Left)
    data.frame(
      worker_id = df$worker_id,
      head      = match(df$Center, all_items) - 1L,
      winner    = match(winner,    all_items) - 1L,
      loser     = match(loser,     all_items) - 1L,
      sampleSet = df$sampleSet,
      stringsAsFactors = FALSE
    )
  }))

  # Write the combined triplets to a temp CSV
  tmp_dir     <- tempdir()
  input_file  <- file.path(tmp_dir, "triplets_tmp.csv")
  items_file  <- file.path(tmp_dir, "items_tmp.csv")

  utils::write.csv(combined, input_file, row.names = FALSE)
  utils::write.csv(data.frame(item = all_items), items_file, row.names = FALSE)

  # Run the pipeline
  result <- run_embeddings(
    input_file           = input_file,
    additional_data_file = items_file,
    output_dir           = output_dir,
    d                    = d,
    max_epochs           = max_epochs,
    tolerance            = tolerance,
    tol_window           = tol_window,
    seed                 = seed,
    device               = device,
    geometry             = geometry,
    radius               = radius
  )

  emb_df <- result$embeddings
  dim_cols <- grep("^dim_", names(emb_df), value = TRUE)

  # Split by worker_id, set item row names from the 'item' column
  worker_ids <- unique(emb_df$worker_id)
  worker_ids_ind <- worker_ids[worker_ids != "group"]

  ind_list <- lapply(setNames(worker_ids_ind, worker_ids_ind), function(wid) {
    sub <- emb_df[emb_df$worker_id == wid, ]
    m <- as.matrix(sub[, dim_cols])
    row.names(m) <- sub$item
    m
  })

  group_sub <- emb_df[emb_df$worker_id == "group", ]
  group_mat <- as.matrix(group_sub[, dim_cols])
  row.names(group_mat) <- group_sub$item

  list(
    individual = ind_list,
    group      = group_mat,
    history    = result$history
  )
}
