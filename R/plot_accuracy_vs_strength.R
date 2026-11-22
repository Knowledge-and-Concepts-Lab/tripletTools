# Wilson score confidence interval for a binomial proportion -- unlike the
# naive phat +/- z*SE interval, this stays inside [0,1] and doesn't
# misbehave when phat is near 0 or 1 (the common case here: strength bins
# near the top of the scale tend to have very few, sometimes zero,
# incorrect predictions). x/n may be vectors (one bin per element).
wilson_ci <- function(x, n, conf_level = 0.95) {
  z <- stats::qnorm(1 - (1 - conf_level) / 2)
  phat <- x / n
  denom <- 1 + z^2 / n
  center <- (phat + z^2 / (2 * n)) / denom
  halfwidth <- (z * sqrt(phat * (1 - phat) / n + z^2 / (4 * n^2))) / denom
  data.frame(lower = pmax(0, center - halfwidth), upper = pmin(1, center + halfwidth))
}

# Assigns each element of `strength` to one of (up to) n_bins bins and
# returns the per-bin summary plot_accuracy_vs_strength() needs: bin count,
# number correct, mean strength (the x-position actually plotted -- not the
# bin's nominal midpoint, since strength values are rarely uniform within a
# bin), proportion correct, and its Wilson CI. Quantile binning can legally
# collapse to fewer than n_bins when `strength` has heavy ties at the
# requested breakpoints (e.g. many triplets at exactly the same strength) --
# handled by de-duplicating breaks rather than erroring, with a message so
# this doesn't look like the function silently did something unrelated.
bin_accuracy_by_strength <- function(strength, accuracy, n_bins, binning, verbose) {
  if (binning == "quantile") {
    breaks <- unique(stats::quantile(strength, probs = seq(0, 1, length.out = n_bins + 1), na.rm = TRUE))
  } else {
    breaks <- seq(min(strength, na.rm = TRUE), max(strength, na.rm = TRUE), length.out = n_bins + 1)
  }
  if (length(breaks) < n_bins + 1 && verbose) {
    message(sprintf(
      "Requested %d bins, but ties in `strength` at the requested breakpoints collapsed this to %d.",
      n_bins, length(breaks) - 1
    ))
  }

  bin_id <- cut(strength, breaks = breaks, include.lowest = TRUE)
  n <- tapply(accuracy, bin_id, length)
  n_correct <- tapply(accuracy, bin_id, sum)
  mean_strength <- tapply(strength, bin_id, mean)

  keep <- !is.na(n)
  n <- n[keep]; n_correct <- n_correct[keep]; mean_strength <- mean_strength[keep]

  ci <- wilson_ci(n_correct, n)
  data.frame(
    strength = as.numeric(mean_strength),
    n = as.numeric(n),
    n_correct = as.numeric(n_correct),
    p_correct = as.numeric(n_correct) / as.numeric(n),
    ci_lower = ci$lower,
    ci_upper = ci$upper
  )
}

#' Plot prediction accuracy as a function of model strength
#'
#' A calibration/psychometric-function style plot of how often a model's
#' predicted winner matches the actual (e.g. human) choice, as a function of
#' a continuous measure of how "easy" the triplet should be -- typically
#' [model.strength()]'s distance-ratio metric, or (when `model.strength()` is
#' called with its own `alpha` argument set) the choice-model probability of
#' the predicted winner. Shows the raw per-triplet outcomes, Wilson-score
#' binned accuracy with confidence intervals, and (optionally) a fitted
#' binomial GLM curve, all on one plot.
#'
#' @param strength Numeric vector giving each triplet's model-strength value
#'   (e.g. the output of [model.strength()]).
#' @param accuracy Vector the same length as `strength`: 1/`TRUE` if the
#'   model's predicted winner matched the actual choice on that triplet,
#'   0/`FALSE` otherwise.
#' @param n_bins Number of bins along the strength axis (default 10). See
#'   `binning`.
#' @param binning `"quantile"` (default) puts roughly equal numbers of
#'   triplets in each bin, which keeps a bin's point from being a sparse-data
#'   artifact even when `strength` values cluster (e.g. most triplets near
#'   1.0 for a good embedding). `"equal_width"` instead divides the observed
#'   range of `strength` into `n_bins` equal-width bins -- more interpretable
#'   x-axis spacing, at the cost of some bins potentially having very few or
#'   no points.
#' @param ci_level Confidence level for each bin's Wilson score interval
#'   (default 0.95).
#' @param glm Logical; if `TRUE` (default), fits `accuracy ~ strength` as a
#'   binomial GLM and overlays its predicted curve.
#' @param show_raw Logical; if `TRUE` (default), plots the raw 0/1 outcomes,
#'   jittered vertically, as a light background layer so the binned summary
#'   isn't the only thing shown.
#' @param xlab,ylab,main,... Passed to the underlying `plot()` call.
#'
#' @returns Invisibly, a list with `bins` (the per-bin summary data frame:
#'   `strength`, `n`, `n_correct`, `p_correct`, `ci_lower`, `ci_upper`) and
#'   `glm_fit` (the fitted `glm` object, or `NULL` if `glm = FALSE`).
#'
#' @details
#' Binned proportions use the Wilson score interval rather than a naive
#' `phat +/- 1.96*SE` interval, since the latter can extend outside \[0, 1\]
#' or be badly too narrow exactly where this plot is most informative: bins
#' near `strength = 1` where the model should rarely be wrong, so the
#' observed proportion of errors in that bin is small and its naive SE is an
#' unreliable guide to the uncertainty.
#'
#' @export
#'
#' @examples
#' set.seed(1)
#' n <- 300
#' strength <- runif(n, 0.5, 1)
#' # Simulated probability of a correct prediction that increases with
#' # strength, for a plausible example.
#' p_true <- 0.5 + 0.45 * (strength - 0.5) / 0.5
#' accuracy <- rbinom(n, 1, p_true)
#'
#' plot_accuracy_vs_strength(strength, accuracy)
plot_accuracy_vs_strength <- function(strength, accuracy, n_bins = 10,
                                       binning = c("quantile", "equal_width"),
                                       ci_level = 0.95, glm = TRUE, show_raw = TRUE,
                                       xlab = "Model strength", ylab = "P(correct)",
                                       main = NULL, ...) {
  binning <- match.arg(binning)

  if (length(strength) != length(accuracy)) {
    stop("strength and accuracy must be the same length.")
  }
  accuracy <- as.numeric(accuracy)

  keep <- !is.na(strength) & !is.na(accuracy)
  if (!all(keep)) {
    message(sprintf("Dropping %d triplet(s) with NA strength/accuracy.", sum(!keep)))
    strength <- strength[keep]; accuracy <- accuracy[keep]
  }
  if (!all(accuracy %in% c(0, 1))) {
    stop("accuracy must be coercible to 0/1 (e.g. logical, or numeric 0/1).")
  }
  if (n_bins < 1 || n_bins != round(n_bins)) {
    stop("n_bins must be a positive integer.")
  }

  bins <- bin_accuracy_by_strength(strength, accuracy, n_bins, binning, verbose = TRUE)

  glm_fit <- NULL
  if (glm) {
    glm_fit <- stats::glm(accuracy ~ strength, family = stats::binomial())
  }

  graphics::plot(range(strength), c(0, 1), type = "n", xlab = xlab, ylab = ylab,
                 main = main, ...)

  if (show_raw) {
    y_jit <- ifelse(accuracy == 1, 1 - stats::runif(length(accuracy), 0, 0.06),
                     stats::runif(length(accuracy), 0, 0.06))
    graphics::points(strength, y_jit, pch = 16, cex = 0.5,
                      col = grDevices::adjustcolor("gray50", alpha.f = 0.35))
  }

  if (glm) {
    grid <- seq(min(strength), max(strength), length.out = 200)
    pred <- stats::predict(glm_fit, newdata = data.frame(strength = grid), type = "response")
    graphics::lines(grid, pred, col = "steelblue", lwd = 2)
  }

  graphics::arrows(bins$strength, bins$ci_lower, bins$strength, bins$ci_upper,
                    angle = 90, code = 3, length = 0.04, col = "black")
  graphics::points(bins$strength, bins$p_correct, pch = 21, bg = "white", col = "black", cex = 1.3)

  invisible(list(bins = bins, glm_fit = glm_fit))
}
