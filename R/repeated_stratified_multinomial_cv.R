# Internal helpers for repeated_stratified_multinomial_cv(). Not exported.

# predict(<multinom>, type = "probs") returns a bare numeric vector (the
# probability of the second level) when there are exactly 2 classes, instead
# of the n x nlevels matrix it returns for 3+ classes. Normalize to always
# return a full n x nlevels matrix with class-labeled columns.
multinom_probs_matrix <- function(fit, newdata, levels) {
  probs <- stats::predict(fit, newdata = newdata, type = "probs")
  if (is.matrix(probs)) {
    return(probs[, levels, drop = FALSE])
  }
  two_class <- cbind(1 - probs, probs)
  colnames(two_class) <- levels
  two_class
}

# Macro-averaged (one-vs-rest, then mean across classes) multiclass metrics,
# plus a per-class breakdown, computed from pooled held-out predictions.
multiclass_metrics <- function(y, predicted, prob_matrix, levels) {

  per_class <- do.call(rbind, lapply(levels, function(cl) {
    true_positive  <- sum(predicted == cl & y == cl)
    false_positive <- sum(predicted == cl & y != cl)
    false_negative <- sum(predicted != cl & y == cl)

    sensitivity_denominator <- true_positive + false_negative
    precision_denominator   <- true_positive + false_positive
    f1_denominator          <- 2 * true_positive + false_positive + false_negative

    data.frame(
      class = cl,
      n = sum(y == cl),
      sensitivity = if (sensitivity_denominator > 0) true_positive / sensitivity_denominator else NA_real_,
      precision   = if (precision_denominator > 0) true_positive / precision_denominator else NA_real_,
      f1          = if (f1_denominator > 0) 2 * true_positive / f1_denominator else NA_real_,
      auc         = roc_auc(as.integer(y == cl), prob_matrix[, cl]),
      stringsAsFactors = FALSE
    )
  }))

  macro <- c(
    accuracy          = mean(predicted == y),
    balanced_accuracy = mean(per_class$sensitivity, na.rm = TRUE),
    precision         = mean(per_class$precision, na.rm = TRUE),
    f1                = mean(per_class$f1, na.rm = TRUE),
    auc               = mean(per_class$auc, na.rm = TRUE)
  )

  list(macro = macro, per_class = per_class)
}


#' Repeated stratified cross-validated multinomial regression for embedding coordinates
#'
#' Tests whether a categorical label with more than two levels can be
#' predicted from a set of embedding coordinates (or any numeric predictors),
#' using repeated stratified k-fold cross-validation with a multinomial
#' logistic regression model. Sibling function to
#' \code{\link{repeated_stratified_logistic_cv}}, which covers the 2-class
#' case; see that function's documentation for the shared repeated-CV design.
#'
#' @param X Numeric matrix or data frame of predictors, rows = items,
#'   columns = dimensions (e.g. embedding coordinates).
#' @param y Categorical outcome with 2 or more levels: a factor, character
#'   vector, or anything coercible via \code{factor()}. For exactly 2 levels,
#'   \code{\link{repeated_stratified_logistic_cv}} is usually a better fit --
#'   it fits a binomial model directly and reports positive-class-specific
#'   sensitivity/precision/F1 rather than the macro-averages this function
#'   always reports.
#' @param repetitions Number of times the full cross-validation is repeated
#'   with a fresh random fold assignment. Default \code{100L}.
#' @param folds Number of stratified folds per repetition. Default \code{3L}.
#' @param seed Integer random seed for reproducibility. Default \code{12345}.
#' @param standardize Logical. If \code{TRUE} (default), each predictor is
#'   centered and scaled using only the training fold's mean/SD before
#'   fitting, and the same transform is applied to the held-out fold.
#' @param maxit Maximum iterations passed to \code{\link[nnet]{multinom}}.
#'   Default \code{1000L}; the underlying \code{nnet} default of \code{100}
#'   is often insufficient even for well-separated classes (see
#'   \code{diagnostics$converged}).
#' @param coefficient_warning Numeric threshold on the largest absolute
#'   fitted coefficient; fits exceeding this are flagged
#'   \code{large_coefficient} (a common symptom of quasi-complete
#'   separation). Default \code{10}.
#' @param probability_tolerance Numeric tolerance for counting predicted
#'   probabilities as numerically extreme (near 0 or 1). Default \code{1e-8}.
#'
#' @return An object of class \code{"repetitioned_multinomial_cv"}: a named
#'   list with elements:
#' \describe{
#'   \item{\code{performance}}{Data frame with one row per repetition, giving
#'     pooled held-out macro-averaged metrics for that repetition (accuracy,
#'     balanced accuracy, precision, F1, AUC) plus a count of unstable folds.}
#'   \item{\code{summary}}{Data frame with one row per metric, summarizing
#'     \code{performance} across repetitions (mean, SD, median, and 95\%
#'     interval).}
#'   \item{\code{per_class_performance}}{Data frame with one row per
#'     repetition x class, giving that class's one-vs-rest sensitivity,
#'     precision, F1, and AUC for that repetition.}
#'   \item{\code{per_class_summary}}{Data frame with one row per class,
#'     summarizing \code{per_class_performance} across repetitions (mean, SD)
#'     -- use this to see which specific classes are well- or
#'     poorly-predicted, information the macro-averaged metrics above
#'     collapse away.}
#'   \item{\code{diagnostics}}{Data frame with one row per repetition x fold,
#'     recording fit convergence, coefficient size, and probability
#'     extremity, for identifying unstable fits.}
#'   \item{\code{predictions}}{Data frame with one row per repetition x fold
#'     x item, giving the held-out predicted class and per-class predicted
#'     probabilities for every item in every repetition.}
#'   \item{\code{settings}}{The arguments this call was made with, plus
#'     \code{n_items}, \code{n_dimensions}, \code{n_classes}, and
#'     \code{class_counts}.}
#' }
#'
#' @details
#' Follows the same repeated stratified k-fold design as
#' \code{\link{repeated_stratified_logistic_cv}} -- see that function's
#' \emph{Details} -- but fits \code{\link[nnet]{multinom}} instead of
#' \code{\link[stats]{glm}}, predicts each held-out item's class by the
#' highest predicted probability (there is no single \code{threshold} for
#' more than two classes), and reports macro-averaged (one-vs-rest per class,
#' then mean across classes) metrics instead of positive-class-specific ones.
#' \code{balanced_accuracy} (macro-averaged sensitivity/recall) and
#' \code{sensitivity} are the same quantity in
#' \code{\link{repeated_stratified_logistic_cv}}'s 2-class output by
#' construction; this function reports only \code{balanced_accuracy} at the
#' top level and keeps class-specific sensitivity in
#' \code{per_class_summary} instead of duplicating a macro-averaged
#' \code{sensitivity} column.
#'
#' Each fold's fit is checked for signs of instability -- non-convergence
#' within \code{maxit} iterations, non-finite or very large coefficients, or
#' held-out probabilities numerically indistinguishable from 0 or 1. Unlike
#' \code{\link[stats]{glm}}, \code{nnet::multinom} does not reliably emit a
#' distinct warning for quasi-complete separation, so these numeric checks
#' (rather than a captured warning message) carry the diagnostic weight here
#' -- see \code{diagnostics$unstable_fit}.
#'
#' @export
#'
#' @examples
#' # Three partially-overlapping clusters in a 2D embedding. Deliberately not
#' # too cleanly separated -- classes separated enough to be classifiable but
#' # not perfectly, since near-perfect separation drives coefficients toward
#' # infinity and trips every fold's large_coefficient/unstable_fit flag
#' # (this is expected, quasi-complete-separation behavior, not a bug -- see
#' # the "unstable_fit" section above).
#' set.seed(1)
#' n <- 60
#' X <- rbind(
#'   cbind(rnorm(n / 3, mean = -1.5), rnorm(n / 3)),
#'   cbind(rnorm(n / 3, mean =  0),   rnorm(n / 3, mean = 1.5)),
#'   cbind(rnorm(n / 3, mean =  1.5), rnorm(n / 3))
#' )
#' y <- factor(rep(c("a", "b", "c"), each = n / 3))
#'
#' cv_result <- repeated_stratified_multinomial_cv(
#'   X = X, y = y,
#'   repetitions = 5, folds = 3, seed = 1
#' )
#'
#' # Mean performance and variability across repetitions
#' cv_result$summary
#'
#' # Which classes are best/worst predicted
#' cv_result$per_class_summary
repeated_stratified_multinomial_cv <- function(
    X,
    y,
    repetitions = 100L,
    folds = 3L,
    seed = 12345,
    standardize = TRUE,
    maxit = 1000L,
    coefficient_warning = 10,
    probability_tolerance = 1e-8
) {

  if (!requireNamespace("nnet", quietly = TRUE)) {
    stop("The 'nnet' package is required. Install it with install.packages('nnet').")
  }

  X <- as.matrix(X)
  storage.mode(X) <- "double"

  if (is.null(colnames(X))) {
    colnames(X) <- paste0("dim", seq_len(ncol(X)))
  }

  y <- factor(y)
  levels_y <- levels(y)
  n_classes <- nlevels(y)

  if (n_classes < 2L) {
    stop("y must have at least two levels.")
  }

  if (nrow(X) != length(y)) {
    stop("The number of rows in X must equal the length of y.")
  }

  if (anyNA(X) || anyNA(y)) {
    stop("X and y must not contain missing values.")
  }

  if (ncol(X) < 1L) {
    stop("X must contain at least one predictor.")
  }

  if (folds < 2L) {
    stop("folds must be at least 2.")
  }

  class_counts <- table(y)

  if (min(class_counts) < folds) {
    stop(
      "Each outcome class must contain at least as many observations ",
      "as there are folds."
    )
  }

  if (repetitions < 1L) {
    stop("repetitions must be at least 1.")
  }

  set.seed(seed)

  n_items <- nrow(X)

  prediction_results  <- vector("list", repetitions * folds)
  diagnostic_results  <- vector("list", repetitions * folds)
  repetition_results  <- vector("list", repetitions)
  per_class_results   <- vector("list", repetitions)

  result_index <- 1L

  for (repetition_number in seq_len(repetitions)) {

    fold_id <- make_stratified_folds(y, v = folds)

    repetition_predicted    <- vector("character", n_items)
    repetition_prob_matrix  <- matrix(NA_real_, n_items, n_classes,
                                       dimnames = list(NULL, levels_y))

    for (fold_number in seq_len(folds)) {

      test_index  <- which(fold_id == fold_number)
      train_index <- which(fold_id != fold_number)

      X_train <- X[train_index, , drop = FALSE]
      X_test  <- X[test_index, , drop = FALSE]

      y_train <- y[train_index]
      y_test  <- y[test_index]

      # Standardize using only the training observations.
      if (standardize) {

        train_means <- colMeans(X_train)
        train_sds <- apply(X_train, 2L, stats::sd)

        zero_variance <- !is.finite(train_sds) | train_sds == 0

        if (any(zero_variance)) {
          stop(
            "At least one predictor has zero variance in a training fold: ",
            paste(colnames(X_train)[zero_variance], collapse = ", ")
          )
        }

        X_train <- sweep(X_train, 2L, train_means, "-")
        X_train <- sweep(X_train, 2L, train_sds, "/")

        X_test <- sweep(X_test, 2L, train_means, "-")
        X_test <- sweep(X_test, 2L, train_sds, "/")
      }

      train_data <- data.frame(
        outcome = y_train,
        X_train,
        check.names = FALSE
      )

      test_data <- data.frame(
        X_test,
        check.names = FALSE
      )

      captured_warnings <- character(0)

      fit <- withCallingHandlers(
        nnet::multinom(
          outcome ~ .,
          data = train_data,
          trace = FALSE,
          maxit = maxit
        ),
        warning = function(w) {
          captured_warnings <<- c(
            captured_warnings,
            conditionMessage(w)
          )
          invokeRestart("muffleWarning")
        }
      )

      coefficients <- stats::coef(fit)

      test_prob_matrix  <- multinom_probs_matrix(fit, test_data, levels_y)
      train_prob_matrix <- multinom_probs_matrix(fit, train_data, levels_y)

      predicted_class <- levels_y[max.col(test_prob_matrix, ties.method = "first")]

      repetition_predicted[test_index] <- predicted_class
      repetition_prob_matrix[test_index, ] <- test_prob_matrix

      finite_coefficients <- all(is.finite(coefficients))
      maximum_absolute_coefficient <- if (finite_coefficients) {
        max(abs(coefficients))
      } else {
        Inf
      }

      extreme_train_probabilities <- sum(
        train_prob_matrix <= probability_tolerance |
          train_prob_matrix >= 1 - probability_tolerance
      )

      extreme_test_probabilities <- sum(
        test_prob_matrix <= probability_tolerance |
          test_prob_matrix >= 1 - probability_tolerance
      )

      large_coefficient <- (
        maximum_absolute_coefficient > coefficient_warning
      )

      converged <- isTRUE(fit$convergence == 0)

      unstable_fit <- (
        !converged ||
          !finite_coefficients ||
          large_coefficient
      )

      prediction_results[[result_index]] <- data.frame(
        repetition = repetition_number,
        fold = fold_number,
        item = test_index,
        observed = as.character(y_test),
        predicted = predicted_class,
        test_prob_matrix,
        check.names = FALSE
      )

      diagnostic_results[[result_index]] <- data.frame(
        repetition = repetition_number,
        fold = fold_number,
        n_train = length(train_index),
        n_test = length(test_index),
        n_classes = n_classes,
        converged = converged,
        finite_coefficients = finite_coefficients,
        maximum_absolute_coefficient = maximum_absolute_coefficient,
        large_coefficient = large_coefficient,
        extreme_train_probabilities = extreme_train_probabilities,
        extreme_test_probabilities = extreme_test_probabilities,
        unstable_fit = unstable_fit,
        warning_text = if (length(captured_warnings) == 0L) {
          ""
        } else {
          paste(unique(captured_warnings), collapse = " | ")
        }
      )

      result_index <- result_index + 1L
    }

    if (any(repetition_predicted == "")) {
      stop("Some observations did not receive held-out predictions.")
    }

    metrics <- multiclass_metrics(
      y = as.character(y),
      predicted = repetition_predicted,
      prob_matrix = repetition_prob_matrix,
      levels = levels_y
    )

    repetition_results[[repetition_number]] <- data.frame(
      repetition = repetition_number,
      t(metrics$macro),
      unstable_folds = sum(
        vapply(
          diagnostic_results[
            ((repetition_number - 1L) * folds + 1L):
              (repetition_number * folds)
          ],
          function(z) z$unstable_fit,
          logical(1)
        )
      )
    )

    per_class_results[[repetition_number]] <- data.frame(
      repetition = repetition_number,
      metrics$per_class
    )
  }

  predictions     <- do.call(rbind, prediction_results)
  diagnostics     <- do.call(rbind, diagnostic_results)
  performance     <- do.call(rbind, repetition_results)
  per_class_performance <- do.call(rbind, per_class_results)

  metric_names <- c("accuracy", "balanced_accuracy", "precision", "f1", "auc")

  performance_summary <- data.frame(
    metric = metric_names,
    mean = vapply(performance[metric_names], mean, numeric(1), na.rm = TRUE),
    sd = vapply(performance[metric_names], stats::sd, numeric(1), na.rm = TRUE),
    median = vapply(performance[metric_names], stats::median, numeric(1), na.rm = TRUE),
    lower_2.5 = vapply(performance[metric_names], stats::quantile, numeric(1),
                        probs = 0.025, na.rm = TRUE, names = FALSE),
    upper_97.5 = vapply(performance[metric_names], stats::quantile, numeric(1),
                         probs = 0.975, na.rm = TRUE, names = FALSE)
  )

  per_class_summary <- do.call(rbind, lapply(levels_y, function(cl) {
    sub <- per_class_performance[per_class_performance$class == cl, ]
    data.frame(
      class = cl,
      n = sub$n[1],
      mean_sensitivity = mean(sub$sensitivity, na.rm = TRUE),
      sd_sensitivity = stats::sd(sub$sensitivity, na.rm = TRUE),
      mean_precision = mean(sub$precision, na.rm = TRUE),
      sd_precision = stats::sd(sub$precision, na.rm = TRUE),
      mean_f1 = mean(sub$f1, na.rm = TRUE),
      sd_f1 = stats::sd(sub$f1, na.rm = TRUE),
      mean_auc = mean(sub$auc, na.rm = TRUE),
      sd_auc = stats::sd(sub$auc, na.rm = TRUE)
    )
  }))

  structure(
    list(
      performance = performance,
      summary = performance_summary,
      per_class_performance = per_class_performance,
      per_class_summary = per_class_summary,
      diagnostics = diagnostics,
      predictions = predictions,
      settings = list(
        repetitions = repetitions,
        folds = folds,
        seed = seed,
        standardize = standardize,
        maxit = maxit,
        coefficient_warning = coefficient_warning,
        probability_tolerance = probability_tolerance,
        n_items = n_items,
        n_dimensions = ncol(X),
        n_classes = n_classes,
        class_counts = class_counts
      )
    ),
    class = "repetitioned_multinomial_cv"
  )
}
