#' Group embedding data for 58 color patches
#'
#' This dataset contains embedding coordinates from a triplet study using 58
#' color patches spanning color space. 46 participants judged which of two
#' option patches was more similar in color to a reference patch, without
#' further instruction. The object is a single data frame containing 3-D
#' embedding coordinates computed from the training trials pooled across all
#' participants.
#'
#' @format ## `color_emb_group`
#' A data frame with 58 rows (items, row names equal to the item's hex color
#' code, e.g. `"#5E2B3A"`) and three columns as follows:
#' \describe{
#'   \item{dim_0, dim_1, dim_2}{First, second and third dimensions of the embedding.}
#' }
#'
#' @details
#' When aligned (e.g. via `vegan::procrustes()`) to the perceptually-based
#' CIE LAB coordinates of the same patches (`color_lab`), the group embedding
#' roughly recovers lightness as one dimension, but the other two express a
#' hue circle organized more by color category than by the even spacing of
#' standard color space -- see `vignette("trajectory_vignette")`.
#'
#' @source Zimnicki et al., presented at the Annual Meeting of the Cognitive
#'   Science Society. \url{https://escholarship.org/uc/item/8778p3t3}
"color_emb_group"
