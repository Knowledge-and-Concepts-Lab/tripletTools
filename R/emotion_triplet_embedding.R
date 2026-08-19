#' Triplet-based embedding of 213 emotion words
#'
#' A 4-dimensional embedding of 213 emotion words, fit from triplet
#' similarity judgments. Bundled alongside \code{\link{emotion_bge_embedding}}
#' -- a language-model embedding of the same words -- as example data for
#' comparing triplet-based and alternative embedding spaces (see
#' \code{\link{procrustes_rank_ceiling}}, \code{\link{procrustes_spectral_ceiling}}).
#'
#' @format ## `emotion_triplet_embedding`
#' A data frame with 213 rows (one per emotion word, given as row names) and
#' 4 columns (`dim_0`-`dim_3`), the embedding coordinates.
#'
#' @source Emotion words from Shaver, P., Schwartz, J., Kirson, D., &
#'   O'Connor, C. (1987). Emotion knowledge: further exploration of a
#'   prototype approach. \emph{Journal of Personality and Social Psychology},
#'   52(6), 1061.
"emotion_triplet_embedding"
