# Shared internal helpers for operating on a triplet_list (a list of
# per-participant data frames) while preserving its original order and
# names exactly -- rather than relying on dplyr::bind_rows() + split(),
# which reorders groups by factor level (alphabetical by worker_id by
# default) and would silently reshuffle the list. Used by
# assign_sample_sets_list() (R/assign_sample_sets.R) and
# fold_alpha_test_to_train() (R/fold_alpha_test_to_train.R).
.TRIPLET_LIST_IDX_COL <- ".triplet_list_orig_idx"

# Tags each element with its position in triplet_list, then combines into
# one data frame (dplyr::bind_rows(), so elements don't need identical
# columns). The tag column lets split_combined_to_triplet_list() reconstruct
# the original list order afterward, since worker_id alone can't be trusted
# to sort back into the input's own order.
tag_and_combine_triplet_list <- function(triplet_list) {
  tagged <- Map(function(d, i) { d[[.TRIPLET_LIST_IDX_COL]] <- i; d },
                triplet_list, seq_along(triplet_list))
  dplyr::bind_rows(tagged)
}

# Inverse of tag_and_combine_triplet_list(): splits a combined data frame
# (still carrying the tag column) back into a list, in the original
# position order, with the tag column removed and orig_names restored.
split_combined_to_triplet_list <- function(combined, orig_names) {
  out <- split(combined, combined[[.TRIPLET_LIST_IDX_COL]])
  out <- out[order(as.integer(names(out)))]
  out <- lapply(out, function(d) {
    d[[.TRIPLET_LIST_IDX_COL]] <- NULL
    rownames(d) <- NULL
    d
  })
  names(out) <- orig_names
  out
}
