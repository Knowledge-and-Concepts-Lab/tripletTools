#' Basic emotion categories for the 213 Shaver emotion words
#'
#' Shaver et al. (1987) basic-emotion category assignments for the same 213
#' emotion words as \code{\link{emotion_triplet_embedding}} and
#' \code{\link{emotion_bge_embedding}}. Bundled as an example categorical
#' label for evaluating an embedding via classifier performance (see
#' \code{\link{repeated_stratified_multinomial_cv}}).
#'
#' @format ## `emotion_categories`
#' A data frame with 213 rows (one per emotion word, given as row names,
#' matching \code{\link{emotion_triplet_embedding}}/
#' \code{\link{emotion_bge_embedding}}) and one column:
#' \describe{
#'   \item{`category`}{Factor with 7 levels: `"Love"`, `"Joy"`,
#'     `"Surprise"`, `"Anger"`, `"Sadness"`, `"Fear"`, and `"Absent"`.}
#' }
#'
#' @details
#' \code{"Absent"} (78 words) marks words Shaver et al. did not end up
#' assigning to a basic-emotion category -- these are typically excluded
#' before classification. \code{"Surprise"} has only 3 words, too few for
#' reliable cross-validated classification (with \code{folds <= 3} and a
#' single held-out item per fold, there's no stable way to estimate that
#' class's performance) -- it's usually worth excluding too, leaving 132
#' words across 5 categories (Anger 29, Fear 17, Joy 33, Love 16,
#' Sadness 37). Both are kept in this dataset rather than pre-filtered out,
#' so that filtering step can be shown explicitly rather than hidden in
#' \code{data-raw/emotion_categories.R}.
#'
#' @source Shaver, P., Schwartz, J., Kirson, D., & O'Connor, C. (1987).
#'   Emotion knowledge: further exploration of a prototype approach.
#'   \emph{Journal of Personality and Social Psychology}, 52(6), 1061.
"emotion_categories"
