#' CIE LAB coordinates for 58 color patches
#'
#' Reference perceptually-based coordinates for the same 58 color patches
#' judged in the triplet study documented in `color_triplets`. Unlike
#' `color_emb_ind`/`color_emb_group`, this is not a fitted embedding -- it is
#' the patches' own CIE LAB color-space coordinates, included as a comparison
#' point for how the triplet-derived embedding relates to standard,
#' perceptually-based color space.
#'
#' @format ## `color_lab`
#' A data frame with 58 rows (items, row names equal to the item's hex color
#' code, e.g. `"#5E2B3A"`) and three columns as follows:
#' \describe{
#'   \item{l}{Lightness.}
#'   \item{a}{Green-red axis.}
#'   \item{b}{Blue-yellow axis.}
#' }
#'
#' @source Zimnicki et al., presented at the Annual Meeting of the Cognitive
#'   Science Society. \url{https://escholarship.org/uc/item/8778p3t3}
"color_lab"
