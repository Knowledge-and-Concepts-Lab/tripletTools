#' Individual embedding data for 58 color patches
#'
#' This dataset contains embedding coordinates from a triplet study using 58
#' color patches spanning color space. 46 participants judged which of two
#' option patches was more similar in color to a reference patch, without
#' further instruction. Three-D embeddings were computed separately for each
#' participant.
#'
#' @format ## `color_emb_ind`
#' A list with 46 elements, each containing an embedding from one person. The
#' embedding is a data frame object with 58 rows (items, row names equal to
#' the item's hex color code, e.g. `"#5E2B3A"`) and three columns as follows:
#' \describe{
#'   \item{dim_0, dim_1, dim_2}{First, second and third dimensions of the embedding.}
#' }
#'
#' @details
#' See `vignette("trajectory_vignette")` for a worked example using this
#' dataset to characterize continuous, individual differences in color
#' representation along a 1-D manifold.
#'
#' @source Zimnicki et al., presented at the Annual Meeting of the Cognitive
#'   Science Society. \url{https://escholarship.org/uc/item/8778p3t3}
"color_emb_ind"
