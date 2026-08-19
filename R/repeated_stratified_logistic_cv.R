# Internal helpers for repeated_stratified_logistic_cv(). Not exported.

# Convert a binary outcome to numeric 0/1.
make_binary <- function(y, positive_level = NULL) {

  if (is.logical(y)) {
    return(as.integer(y))
  }

  if (is.numeric(y) || is.integer(y)) {
    values <- sort(unique(y[!is.na(y)]))

    if (!identical(values, c(0, 1))) {
      stop("Numeric y must contain only 0 and 1.")
    }

    return(as.integer(y))
  }

  y <- factor(y)

  if (nlevels(y) != 2L) {
    stop("Factor/character y must contain exactly two levels.")
  }

  if (is.null(positive_level)) {
    positive_level <- levels(y)[2L]
    message(
      "Using '", positive_level,
      "' as the positive class."
    )
  }

  if (!positive_level %in% levels(y)) {
    stop("positive_level is not present in y.")
  }

  as.integer(y == positive_level)
}

# Assign observations to stratified folds. Within each outcome class,
# observations are randomly assigned as evenly as possible across folds.
make_stratified_folds <- function(y, v = 3L) {

  fold_id <- integer(length(y))

  for (class_value in sort(unique(y))) {

    indices <- which(y == class_value)
    indices <- sample(indices)

    assignments <- rep(seq_len(v), length.out = length(indices))
    fold_id[indices] <- assignments
  }

  fold_id
}

# ROC AUC: the probability that a randomly selected positive observation
# receives a higher score than a randomly selected negative observation.
# Ties receive half credit.
roc_auc <- function(y, score) {

  keep <- is.finite(score) & !is.na(y)
  y <- y[keep]
  score <- score[keep]

  n_positive <- sum(y == 1L)
  n_negative <- sum(y == 0L)

  if (n_positive == 0L || n_negative == 0L) {
    return(NA_real_)
  }

  score_ranks <- rank(score, ties.method = "average")
  positive_rank_sum <- sum(score_ranks[y == 1L])

  auc <- (
    positive_rank_sum -
      n_positive * (n_positive + 1) / 2
  ) / (n_positive * n_negative)

  as.numeric(auc)
}

# Classification metrics computed from pooled held-out predictions.
classification_metrics <- function(y, probability, threshold = 0.5) {

  predicted <- as.integer(probability >= threshold)

  true_positive  <- sum(predicted == 1L & y == 1L)
  false_positive <- sum(predicted == 1L & y == 0L)
  true_negative  <- sum(predicted == 0L & y == 0L)
  false_negative <- sum(predicted == 0L & y == 1L)

  sensitivity_denominator <- true_positive + false_negative
  specificity_denominator <- true_negative + false_positive
  precision_denominator   <- true_positive + false_positive
  f1_denominator          <- 2 * true_positive +
                             false_positive +
                             false_negative

  sensitivity <- if (sensitivity_denominator > 0) {
    true_positive / sensitivity_denominator
  } else {
    NA_real_
  }

  specificity <- if (specificity_denominator > 0) {
    true_negative / specificity_denominator
  } else {
    NA_real_
  }

  precision <- if (precision_denominator > 0) {
    true_positive / precision_denominator
  } else {
    NA_real_
  }

  f1 <- if (f1_denominator > 0) {
    2 * true_positive / f1_denominator
  } else {
    NA_real_
  }

  c(
    accuracy = mean(predicted == y),
    balanced_accuracy = mean(c(sensitivity, specificity), na.rm = TRUE),
    sensitivity = sensitivity,
    specificity = specificity,
    precision = precision,
    f1 = f1,
    auc = roc_auc(y, probability),
    true_positive = true_positive,
    false_positive = false_positive,
    true_negative = true_negative,
    false_negative = false_negative
  )
}


#' Repeated stratified cross-validated logistic regression for embedding coordinates
#'
#' Tests whether a binary category label can be predicted from a set of
#' embedding coordinates (or any numeric predictors), using repeated
#' stratified k-fold cross-validation with a logistic regression model.
#'
#' @param X Numeric matrix or data frame of predictors, rows = items,
#'   columns = dimensions (e.g. embedding coordinates).
#' @param y Binary outcome: coded \code{0}/\code{1}, \code{FALSE}/\code{TRUE},
#'   or a two-level factor/character vector. Must have the same length as
#'   \code{nrow(X)}.
#' @param repetitions Number of times the full cross-validation is repeated
#'   with a fresh random fold assignment. Default \code{100L}.
#' @param folds Number of stratified folds per repetition. Default \code{3L}.
#' @param seed Integer random seed for reproducibility. Default \code{12345}.
#' @param standardize Logical. If \code{TRUE} (default), each predictor is
#'   centered and scaled using only the training fold's mean/SD before
#'   fitting, and the same transform is applied to the held-out fold.
#' @param threshold Probability threshold used to convert predicted
#'   probabilities into class predictions. Default \code{0.5}.
#' @param coefficient_warning Numeric threshold on the largest absolute
#'   logistic-regression coefficient; fits exceeding this are flagged
#'   \code{large_coefficient} (a common symptom of quasi-complete
#'   separation). Default \code{10}.
#' @param probability_tolerance Numeric tolerance for counting predicted
#'   probabilities as numerically extreme (near 0 or 1). Default \code{1e-8}.
#'
#' @return An object of class \code{"repetitioned_logistic_cv"}: a named list
#'   with elements:
#' \describe{
#'   \item{\code{performance}}{Data frame with one row per repetition,
#'     giving pooled held-out performance metrics for that repetition
#'     (accuracy, balanced accuracy, sensitivity, specificity, precision,
#'     F1, AUC) plus a count of unstable folds.}
#'   \item{\code{summary}}{Data frame with one row per metric, summarizing
#'     \code{performance} across repetitions (mean, SD, median, and 95\%
#'     interval).}
#'   \item{\code{diagnostics}}{Data frame with one row per repetition x fold,
#'     recording fit convergence, coefficient size, and separation warnings,
#'     for identifying unstable fits.}
#'   \item{\code{predictions}}{Data frame with one row per repetition x fold
#'     x item, giving the held-out predicted probability and class for every
#'     item in every repetition.}
#'   \item{\code{settings}}{The arguments this call was made with, plus
#'     \code{n_items}, \code{n_dimensions}, \code{n_positive}, and
#'     \code{n_negative}.}
#' }
#'
#' @details
#' In each repetition, observations are split into \code{folds} stratified
#' folds (class proportions preserved within each fold), and a logistic
#' regression is fit on all but one fold and evaluated on the held-out fold,
#' cycling through every fold. Held-out predictions from all folds are pooled
#' before computing that repetition's performance metrics. Repeating this
#' with fresh fold assignments (\code{repetitions} times) characterizes how
#' sensitive performance is to the particular fold split, which matters most
#' when the number of items is small relative to \code{folds}.
#'
#' Each fold's fit is checked for signs of instability — non-convergence,
#' non-finite or very large coefficients, or a "fitted probabilities
#' numerically 0 or 1 occurred" warning (a symptom of (quasi-)complete
#' separation, which is common with small samples and can inflate apparent
#' performance). See \code{diagnostics$unstable_fit}.
#'
#' @export
#'
#' @examples
#' # Two well-separated clusters in a 2D embedding
#' set.seed(1)
#' n <- 40
#' X <- rbind(
#'   cbind(rnorm(n / 2, mean = -2), rnorm(n / 2)),
#'   cbind(rnorm(n / 2, mean =  2), rnorm(n / 2))
#' )
#' y <- rep(c(0, 1), each = n / 2)
#'
#' cv_result <- repeated_stratified_logistic_cv(
#'   X = X, y = y,
#'   repetitions = 5, folds = 3, seed = 1
#' )
#'
#' # Mean performance and variability across repetitions
#' cv_result$summary
#'
#' # Number of folds flagged as unstable
#' sum(cv_result$diagnostics$unstable_fit)
repeated_stratified_logistic_cv <- function(
    X,
    y,
    repetitions = 100L,
    folds = 3L,
    seed = 12345,
    standardize = TRUE,
    threshold = 0.5,
    coefficient_warning = 10,
    probability_tolerance = 1e-8
) {

  X <- as.matrix(X)
  storage.mode(X) <- "double"

  if (is.null(colnames(X))) {
    colnames(X) <- paste0("dim", seq_len(ncol(X)))
  }

  y <- make_binary(y)

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

  prediction_results <- vector("list", repetitions * folds)
  diagnostic_results <- vector("list", repetitions * folds)
  repetition_results <- vector("list", repetitions)

  result_index <- 1L

  for (repetition_number in seq_len(repetitions)) {

    fold_id <- make_stratified_folds(y, v = folds)

    repetition_predictions <- rep(NA_real_, n_items)
    repetition_predicted_class <- rep(NA_integer_, n_items)

    for (fold_number in seq_len(folds)) {

      test_index <- which(fold_id == fold_number)
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
        stats::glm(
          outcome ~ .,
          data = train_data,
          family = stats::binomial(link = "logit")
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

      test_probability <- stats::predict(
        fit,
        newdata = test_data,
        type = "response"
      )

      train_probability <- stats::fitted(fit)

      predicted_class <- as.integer(test_probability >= threshold)

      repetition_predictions[test_index] <- test_probability
      repetition_predicted_class[test_index] <- predicted_class

      finite_coefficients <- all(is.finite(coefficients))
      maximum_absolute_coefficient <- if (finite_coefficients) {
        max(abs(coefficients))
      } else {
        Inf
      }

      extreme_train_probabilities <- sum(
        train_probability <= probability_tolerance |
          train_probability >= 1 - probability_tolerance
      )

      extreme_test_probabilities <- sum(
        test_probability <= probability_tolerance |
          test_probability >= 1 - probability_tolerance
      )

      large_coefficient <- (
        maximum_absolute_coefficient > coefficient_warning
      )

      separation_warning <- any(
        grepl(
          "fitted probabilities numerically 0 or 1 occurred",
          captured_warnings,
          fixed = TRUE
        )
      )

      unstable_fit <- (
        !isTRUE(fit$converged) ||
          !finite_coefficients ||
          large_coefficient ||
          separation_warning
      )

      prediction_results[[result_index]] <- data.frame(
        repetition = repetition_number,
        fold = fold_number,
        item = test_index,
        observed = y_test,
        probability = as.numeric(test_probability),
        predicted = predicted_class
      )

      diagnostic_results[[result_index]] <- data.frame(
        repetition = repetition_number,
        fold = fold_number,
        n_train = length(train_index),
        n_test = length(test_index),
        train_positive = sum(y_train == 1L),
        train_negative = sum(y_train == 0L),
        test_positive = sum(y_test == 1L),
        test_negative = sum(y_test == 0L),
        converged = isTRUE(fit$converged),
        finite_coefficients = finite_coefficients,
        maximum_absolute_coefficient = maximum_absolute_coefficient,
        large_coefficient = large_coefficient,
        separation_warning = separation_warning,
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

    if (anyNA(repetition_predictions)) {
      stop("Some observations did not receive held-out predictions.")
    }

    metrics <- classification_metrics(
      y = y,
      probability = repetition_predictions,
      threshold = threshold
    )

    repetition_results[[repetition_number]] <- data.frame(
      repetition = repetition_number,
      t(metrics),
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
  }

  predictions <- do.call(rbind, prediction_results)
  diagnostics <- do.call(rbind, diagnostic_results)
  performance <- do.call(rbind, repetition_results)

  metric_names <- c(
    "accuracy",
    "balanced_accuracy",
    "sensitivity",
    "specificity",
    "precision",
    "f1",
    "auc"
  )

  performance_summary <- data.frame(
    metric = metric_names,
    mean = vapply(
      performance[metric_names],
      mean,
      numeric(1),
      na.rm = TRUE
    ),
    sd = vapply(
      performance[metric_names],
      stats::sd,
      numeric(1),
      na.rm = TRUE
    ),
    median = vapply(
      performance[metric_names],
      stats::median,
      numeric(1),
      na.rm = TRUE
    ),
    lower_2.5 = vapply(
      performance[metric_names],
      stats::quantile,
      numeric(1),
      probs = 0.025,
      na.rm = TRUE,
      names = FALSE
    ),
    upper_97.5 = vapply(
      performance[metric_names],
      stats::quantile,
      numeric(1),
      probs = 0.975,
      na.rm = TRUE,
      names = FALSE
    )
  )

  structure(
    list(
      performance = performance,
      summary = performance_summary,
      diagnostics = diagnostics,
      predictions = predictions,
      settings = list(
        repetitions = repetitions,
        folds = folds,
        seed = seed,
        standardize = standardize,
        threshold = threshold,
        coefficient_warning = coefficient_warning,
        probability_tolerance = probability_tolerance,
        n_items = n_items,
        n_dimensions = ncol(X),
        n_positive = sum(y == 1L),
        n_negative = sum(y == 0L)
      )
    ),
    class = "repetitioned_logistic_cv"
  )
}
