#' Standardise a legacy triadic comparison dataset
#'
#' Reads a single CSV file from a legacy triplet experiment and converts it to
#' the standard column format used by this package. Unrecognised or missing
#' columns are derived where possible from the data that are present; see the
#' \strong{Column mappings} section below for full details. Two output files
#' are written alongside the input: a standardised data CSV and a
#' stimulus-level mapping CSV.
#'
#' @section Output columns:
#' \describe{
#'   \item{\code{p_id}}{Character participant identifier.}
#'   \item{\code{Center}}{Character label of the target (reference) stimulus.}
#'   \item{\code{Left}}{Character label of the left-hand choice stimulus.}
#'   \item{\code{Right}}{Character label of the right-hand choice stimulus.}
#'   \item{\code{Answer}}{Character label of the chosen stimulus.}
#'   \item{\code{head}}{Integer (0-indexed) factor code for \code{Center},
#'     ordered alphabetically across all unique stimuli in \code{Center},
#'     \code{Left}, and \code{Right}.}
#'   \item{\code{winner}}{Integer factor code for \code{Answer}, using the
#'     same ordering as \code{head}.}
#'   \item{\code{loser}}{Integer factor code for the unchosen option, using
#'     the same ordering as \code{head}.}
#'   \item{\code{RT}}{Numeric reaction time. \code{NA} if not present in the
#'     input.}
#'   \item{\code{sampleAlg}}{Character sampling algorithm label:
#'     \code{"random"}, \code{"check"}, \code{"validation"},
#'     \code{"uncertainty"}, or \code{NA}.}
#'   \item{\code{sampleSet}}{Character set label: \code{"train"} or
#'     \code{"test"}.}
#' }
#'
#' @section Column mappings:
#' Input column names are matched case-insensitively and ignoring punctuation.
#' \describe{
#'   \item{Participant ID (\code{p_id})}{Recognised input names:
#'     \code{sessionID}, \code{session_ID}, \code{puid},
#'     \code{Participant.ID}, \code{worker_id}, \code{sub_id}, \code{pid}.
#'     If none are found, participants are assigned sequential IDs
#'     (\code{"P1"}, \code{"P2"}, \ldots).}
#'   \item{Center}{Recognised input names: \code{Center}, \code{Target}.}
#'   \item{Left}{Recognised input names: \code{Left}, \code{Option1}.}
#'   \item{Right}{Recognised input names: \code{Right}, \code{Option2}.}
#'   \item{winner / loser}{Recognised input names: \code{winner} /
#'     \code{primary} and \code{loser} / \code{alternate}. Derived from
#'     \code{Answer}, \code{Left}, and \code{Right} when absent.}
#'   \item{sampleAlg}{Recognised input names: \code{sampleAlg},
#'     \code{AlgSample}. Values are recoded: \code{"Random"} →
#'     \code{"random"}; \code{"Test"} → \code{"validation"};
#'     \code{"check"} → \code{"check"}; \code{"uncertainty"} →
#'     \code{"uncertainty"}. Filled with \code{NA} when absent.}
#'   \item{sampleSet}{Recognised input names: \code{sampleSet},
#'     \code{Alg.Label}, \code{TrnTest}. When absent, 10\% of trials are
#'     randomly assigned to \code{"test"} and the remainder to
#'     \code{"train"} (seed \code{2025}).}
#' }
#'
#' @param input_file Character. Path to the input CSV file.
#'
#' @return A list returned invisibly with two elements:
#'   \describe{
#'     \item{\code{data_file}}{Path of the written standardised data CSV
#'       (input filename with \code{_v2025.csv} suffix).}
#'     \item{\code{levels_file}}{Path of the written stimulus-level mapping
#'       CSV (input filename with \code{_2025_levels.csv} suffix).}
#'   }
#'
#' @examples
#' \dontrun{
#' result <- clean_triadic_comparisons("data/triplets.csv")
#' print(paste("Wrote:", result$data_file, "and", result$levels_file))
#' }
#'
#' @importFrom dplyr mutate select case_when
#' @importFrom readr read_csv write_csv
#' @importFrom utils write.csv
#' @importFrom stats setNames
#' @importFrom stringr str_to_lower
#' @importFrom tools file_path_sans_ext
#' @importFrom rlang .data
#'
#' @export
read_legacy <- function(input_file) {
  # Extract base filename without extension
  base_name <- tools::file_path_sans_ext(input_file)

  # Read the input CSV
  data <- read.csv(input_file, stringsAsFactors = FALSE)

  # Find a column whose name matches any of the candidates (case- and
  # punctuation-insensitive). Returns the actual column name or NULL.
  find_column <- function(possible_names, df) {
    clean_names   <- tolower(gsub("[[:punct:]]", "", colnames(df)))
    possible_names <- tolower(gsub("[[:punct:]]", "", possible_names))
    for (name in possible_names) {
      idx <- which(clean_names == name)
      if (length(idx) > 0) return(colnames(df)[idx[1]])
    }
    return(NULL)
  }

  # ── Column-name aliases ────────────────────────────────
  id_cols        <- c("sessionID", "session_ID", "puid", "Participant.ID",
                      "worker_id", "sub_id", "pid")
  center_cols    <- c("Center", "Target")
  left_cols      <- c("Left", "Option1")
  right_cols     <- c("Right", "Option2")
  winner_cols    <- c("winner", "primary")
  loser_cols     <- c("loser", "alternate")
  sampleset_cols <- c("sampleSet", "Alg.Label", "TrnTest")
  samplealg_cols <- c("sampleAlg", "AlgSample")

  # ── Resolve column names ───────────────────────────────
  p_id_col      <- find_column(id_cols,        data)
  center_col    <- find_column(center_cols,    data)
  left_col      <- find_column(left_cols,      data)
  right_col     <- find_column(right_cols,     data)
  winner_col    <- find_column(winner_cols,    data)
  loser_col     <- find_column(loser_cols,     data)
  sampleset_col <- find_column(sampleset_cols, data)
  samplealg_col <- find_column(samplealg_cols, data)

  new_data <- data

  # ── Participant ID ─────────────────────────────────────
  new_data$p_id <- if (!is.null(p_id_col)) {
    data[[p_id_col]]
  } else {
    paste0("P", seq_len(nrow(data)))
  }

  # ── Stimulus labels ────────────────────────────────────
  new_data$Center <- if (!is.null(center_col)) data[[center_col]] else NA
  new_data$Left   <- if (!is.null(left_col))   data[[left_col]]   else NA
  new_data$Right  <- if (!is.null(right_col))  data[[right_col]]  else NA

  # ── Answer ─────────────────────────────────────────────
  new_data$Answer <- if ("Answer" %in% colnames(data)) {
    data$Answer
  } else if (!is.null(winner_col)) {
    data[[winner_col]]
  } else {
    NA
  }

  # ── Stimulus factor levels ─────────────────────────────
  all_stimuli    <- sort(unique(c(new_data$Center, new_data$Left,
                                  new_data$Right)))
  all_stimuli    <- all_stimuli[!is.na(all_stimuli)]
  stimulus_levels <- data.frame(
    numeric_value = seq(0, length(all_stimuli) - 1),
    stimulus      = all_stimuli,
    stringsAsFactors = FALSE
  )
  write.csv(stimulus_levels,
            paste0(base_name, "_2025_levels.csv"),
            row.names = FALSE)

  # ── Numeric head / winner / loser ──────────────────────
  stimulus_map   <- setNames(stimulus_levels$numeric_value,
                             stimulus_levels$stimulus)
  new_data$head  <- stimulus_map[new_data$Center]
  new_data <- new_data %>%
    mutate(
      winner = stimulus_map[.data$Answer],
      loser  = case_when(
        .data$Answer == .data$Left  ~ stimulus_map[.data$Right],
        .data$Answer == .data$Right ~ stimulus_map[.data$Left],
        TRUE                        ~ NA_real_
      )
    )

  # ── Reaction time ──────────────────────────────────────
  new_data$RT <- if ("RT" %in% colnames(data)) data$RT else NA

  # ── sampleAlg ──────────────────────────────────────────
  new_data$sampleAlg <- if (!is.null(samplealg_col)) {
    case_when(
      tolower(data[[samplealg_col]]) == "random"      ~ "random",
      tolower(data[[samplealg_col]]) == "test"        ~ "validation",
      tolower(data[[samplealg_col]]) == "check"       ~ "check",
      tolower(data[[samplealg_col]]) == "uncertainty" ~ "uncertainty",
      TRUE                                            ~ NA_character_
    )
  } else {
    NA_character_
  }

  # ── sampleSet ──────────────────────────────────────────
  new_data$sampleSet <- if (!is.null(sampleset_col)) {
    data[[sampleset_col]]
  } else {
    set.seed(2025)
    sample(c("train", "test"), size = nrow(new_data), replace = TRUE,
           prob = c(0.9, 0.1))
  }

  # ── Select and order output columns ───────────────────
  new_data <- new_data %>%
    select(.data$p_id, .data$Center, .data$Left, .data$Right, .data$Answer, .data$head,
           .data$winner, .data$loser, .data$RT, .data$sampleAlg, .data$sampleSet)

  # ── Write output ───────────────────────────────────────
  output_file <- paste0(base_name, "_v2025.csv")
  write.csv(new_data, output_file, row.names = FALSE)

  invisible(list(
    data_file   = output_file,
    levels_file = paste0(base_name, "_2025_levels.csv")
  ))
}
