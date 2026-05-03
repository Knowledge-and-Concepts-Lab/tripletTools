#' Clean raw jsPsych triplet experiment data
#'
#' Reads all CSV files exported from a jsPsych triplet experiment, filters to
#' experiment trials, applies quality-control exclusions, and returns cleaned
#' data ready for modelling. Optionally writes the results to disk.
#'
#' @param data_dir Character. Path to the directory containing raw CSV exports.
#'   Default: \code{"experiment/raw_data/"}.
#' @param output_df Character or \code{NULL}. File path for the cleaned
#'   trial-level CSV. Set to \code{NULL} to skip writing.
#'   Default: \code{"icon_fp_clean.csv"} (written to the working directory).
#' @param output_levels Character or \code{NULL}. File path for the
#'   stimulus-level mapping CSV. Set to \code{NULL} to skip writing.
#'   Default: \code{"icon_fp_levels.csv"} (written to the working directory).
#' @param min_trials Integer. Minimum number of experiment trials a participant
#'   must have completed to be retained. Passed to
#'   \code{\link{filter_incomplete}}. Default: \code{200}.
#' @param min_mean_rt_ms Numeric. Minimum mean reaction time in milliseconds
#'   for a participant to be retained. Passed to
#'   \code{\link{filter_fast_responders}}. Default: \code{200}.
#' @param max_prop_wrong Numeric between 0 and 1. Maximum proportion of failed
#'   catch trials before a participant is excluded. Passed to
#'   \code{\link{filter_failed_catch}}. Default: \code{0.2}.
#' @param test_prop Numeric between 0 and 1. Proportion of non-check trials
#'   assigned to the test set in the train/test split. Passed to
#'   \code{\link{assign_sample_sets}}. Default: \code{0.2}.
#' @param seed Integer. Random seed for reproducible train/test splitting.
#'   Passed to \code{\link{assign_sample_sets}}. Default: \code{42}.
#' @param stimuli_extension Character. File extension (including the leading
#'   dot) to strip from stimulus and choice names. Default: \code{".png"}.
#'
#' @return A list returned invisibly with two elements:
#'   \describe{
#'     \item{\code{trials}}{Data frame of cleaned trial-level data with columns
#'       \code{head}, \code{winner}, \code{loser}, \code{worker_id}, \code{rt},
#'       \code{Center}, \code{Left}, \code{Right}, \code{Answer},
#'       \code{sampleAlg}, and \code{sampleSet}.}
#'     \item{\code{levels}}{Data frame mapping integer stimulus indices to file
#'       names and paths.}
#'   }
#'
#' @importFrom data.table rbindlist
#' @importFrom readr read_csv write_csv
#' @importFrom dplyr filter select mutate rename if_else
#' @importFrom stringr str_replace_all str_split_fixed
#' @importFrom rlang .data
#'
#' @export
read_raw_data <- function(
    data_dir          = ".",
    output_df         = NULL,
    output_levels     = NULL,
    min_trials        = 0,
    min_mean_rt_ms    = 0,
    max_prop_wrong    = 1.0,
    test_prop         = 0.1,
    seed              = 42,
    stimuli_extension = ".png"
) {
  # ── Read all CSVs ──────────────────────────────────────
  file_list <- list.files(data_dir, pattern = "\\.csv$", full.names = TRUE)
  if (length(file_list) == 0) stop("No CSV files found in: ", data_dir)

  f_full <- rbindlist(
    lapply(file_list, read_csv, show_col_types = FALSE),
    fill = TRUE
  )

  # ── Filter for experiment trials ───────────────────────
  # trial_category is set by the experiment for all response modes.
  f <- f_full %>%
    dplyr::filter(.data$trial_category %in% c("random", "check", "validation")) %>%
    dplyr::select("worker_id", "trial_index", "rt", "stimulus", "choices",
                  "response", "trial_category")

  # ── Quality-control exclusions ─────────────────────────
  f <- filter_incomplete(f, min_trials = min_trials)
  f <- filter_fast_responders(f, min_mean_rt_ms = min_mean_rt_ms)

  # ── Clean stimulus names ───────────────────────────────
  f <- f %>%
    mutate(
      choices  = gsub(stimuli_extension, "",
                      str_replace_all(.data$choices,
                                      c("\\[|\\]" = "", "assets/stimuli/" = "",
                                        "resources/" = "", '"' = "")),
                      fixed = TRUE),
      stimulus = gsub(stimuli_extension, "",
                      str_replace_all(.data$stimulus,
                                      c("assets/stimuli/" = "",
                                        "resources/" = "")),
                      fixed = TRUE)
    ) %>%
    rename(head = "stimulus")

  # ── Split choices into winner and loser ────────────────
  choices_split <- str_split_fixed(f$choices, ",", 2)
  f <- f %>%
    mutate(
      winner = if_else(.data$response == 0, choices_split[, 1], choices_split[, 2]),
      loser  = if_else(.data$response == 0, choices_split[, 2], choices_split[, 1]),
      left   = choices_split[, 1],
      right  = choices_split[, 2]
    ) %>%
    rename(sampleAlg = "trial_category")

  # ── Filter participants failing catch trials ───────────
  f <- filter_failed_catch(f, max_prop_wrong = max_prop_wrong)

  # ── Build final dataset ────────────────────────────────
  split_choices <- str_split_fixed(f$choices, ",", 2)
  unique_labels <- sort(unique(c(f$head, f$winner, f$loser)))

  df1 <- data.frame(
    head      = as.numeric(factor(f$head,   levels = unique_labels)) - 1,
    winner    = as.numeric(factor(f$winner, levels = unique_labels)) - 1,
    loser     = as.numeric(factor(f$loser,  levels = unique_labels)) - 1,
    worker_id = f$worker_id,
    rt        = f$rt,
    Center    = f$head,
    Left      = split_choices[, 1],
    Right     = split_choices[, 2],
    Answer    = f$winner,
    sampleAlg = f$sampleAlg
  ) %>%
    assign_sample_sets(test_prop = test_prop, seed = seed)

  # ── Stimulus-level mapping ─────────────────────────────
  levels_map <- data.frame(item = unique_labels) %>%
    mutate(path = paste0("resources/", .data$item, stimuli_extension))

  # ── Write outputs ──────────────────────────────────────
  if (!is.null(output_df))     write_csv(df1,        output_df)
  if (!is.null(output_levels)) write_csv(levels_map, output_levels)

  invisible(list(trials = df1, levels = levels_map))
}
