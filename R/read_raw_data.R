# Find a column whose name matches one of several candidate names, matching
# case- and punctuation-insensitively (e.g. "sampleAlg" matches "sample_alg").
# Returns the actual column name found in `df`, or NULL if none match.
resolve_column_alias <- function(candidates, df) {
  clean_names      <- tolower(gsub("[[:punct:]]", "", colnames(df)))
  clean_candidates <- tolower(gsub("[[:punct:]]", "", candidates))
  for (candidate in clean_candidates) {
    idx <- which(clean_names == candidate)
    if (length(idx) > 0) return(colnames(df)[idx[1]])
  }
  NULL
}

# Read one raw jsPsych CSV export, resolving known column-name variants for
# `trial_category` and `worker_id` so files from differently-configured
# jsPsych experiments can be combined in read_raw_data(). Falls back to
# deriving `worker_id` from the file name when no participant-ID column is
# present at all.
read_one_raw_file <- function(file, worker_id_regex = NULL) {
  d <- read_csv(file, show_col_types = FALSE)

  trial_category_col <- resolve_column_alias(
    c("trial_category", "sampleAlg", "AlgSample"), d
  )
  if (is.null(trial_category_col)) {
    stop(
      "Could not find a trial-category column (tried: trial_category, ",
      "sampleAlg, AlgSample) in file: ", file
    )
  }
  if (trial_category_col != "trial_category") {
    names(d)[names(d) == trial_category_col] <- "trial_category"
  }

  worker_id_col <- resolve_column_alias(
    c("worker_id", "sessionID", "session_ID", "puid", "Participant.ID",
      "sub_id", "pid"),
    d
  )
  if (!is.null(worker_id_col)) {
    if (worker_id_col != "worker_id") {
      names(d)[names(d) == worker_id_col] <- "worker_id"
    }
  } else {
    base_name <- file_path_sans_ext(basename(file))
    id <- base_name
    if (!is.null(worker_id_regex)) {
      m <- regmatches(base_name, regexec(worker_id_regex, base_name))[[1]]
      if (length(m) >= 2) id <- m[2]
    }
    d$worker_id <- id
  }

  d
}

# Normalize a jsPsych `response` column to 0/1, where 0 means "chose the
# first (left) option" and 1 means "chose the second (right) option" -- the
# convention the rest of read_raw_data()'s winner/loser logic assumes.
# Handles both a numeric/character 0-based button index (the original
# assumption) and the literal key name jsPsych's keyboard-response plugins
# record (e.g. "arrowleft"/"arrowright"), checked row-by-row so a directory
# mixing both encodings still resolves correctly. Unrecognised values become
# NA, same as an unparseable numeric response would.
normalize_response <- function(response) {
  resp_chr <- tolower(trimws(as.character(response)))
  dplyr::case_when(
    resp_chr %in% c("arrowleft", "left")   ~ 0,
    resp_chr %in% c("arrowright", "right") ~ 1,
    TRUE ~ suppressWarnings(as.numeric(resp_chr))
  )
}

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
#' @param worker_id_regex Character or \code{NULL}. Only used when a file has
#'   no recognised participant-ID column (see \emph{Column-name flexibility}
#'   below). A regular expression with one capture group, applied to the
#'   file's base name (without directory or extension); the captured group
#'   becomes that file's \code{worker_id}. For example,
#'   \code{"motion_(\\\\d+)_part\\\\d+"} extracts \code{"87059"} from
#'   \code{"motion_87059_part1.csv"}. If \code{NULL} (default), or if the
#'   regex does not match, the full base file name is used as the
#'   \code{worker_id} instead.
#'
#' @section Column-name flexibility:
#' Different jsPsych triplet experiments (and different versions of the same
#' experiment code) do not always export identical column names. Before
#' combining files, each one is checked for a small set of known aliases:
#' \describe{
#'   \item{Trial category}{Recognised input names: \code{trial_category},
#'     \code{sampleAlg}, \code{AlgSample}. If none is found in a file, the
#'     function stops with an error naming that file.}
#'   \item{Participant ID (\code{worker_id})}{Recognised input names:
#'     \code{worker_id}, \code{sessionID}, \code{session_ID}, \code{puid},
#'     \code{Participant.ID}, \code{sub_id}, \code{pid}. If none is found,
#'     an ID is derived from the file name instead (see
#'     \code{worker_id_regex}) rather than raising an error, since some
#'     jsPsych configurations never write a participant-ID column at all and
#'     rely on one file per participant instead.}
#' }
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
#' @importFrom tools file_path_sans_ext
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
    stimuli_extension = ".png",
    worker_id_regex   = NULL
) {
  # ── Read all CSVs, resolving column-name aliases per file ──
  file_list <- list.files(data_dir, pattern = "\\.csv$", full.names = TRUE)
  if (length(file_list) == 0) stop("No CSV files found in: ", data_dir)

  f_full <- rbindlist(
    lapply(file_list, read_one_raw_file, worker_id_regex = worker_id_regex),
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
  # `response` is coded differently across jsPsych plugins/versions: some
  # record a 0-based button index (0/1), others record the literal key
  # pressed (e.g. "arrowleft"/"arrowright" from an image-keyboard-response
  # trial). Normalizing per-row (rather than assuming one encoding for the
  # whole file) means a directory mixing both still resolves correctly.
  choices_split <- str_split_fixed(f$choices, ",", 2)
  response_idx  <- normalize_response(f$response)
  f <- f %>%
    mutate(
      winner = if_else(response_idx == 0, choices_split[, 1], choices_split[, 2]),
      loser  = if_else(response_idx == 0, choices_split[, 2], choices_split[, 1]),
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
