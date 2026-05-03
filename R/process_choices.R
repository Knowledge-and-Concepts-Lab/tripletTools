#' Clean raw choice strings from jsPsych CSV output
#'
#' Strips file-path prefixes, surrounding brackets, quotes, and the file
#' extension from the \code{choices} column as exported by jsPsych. The
#' result is a plain comma-separated string of bare stimulus names suitable
#' for downstream splitting and matching.
#'
#' @param choices Character vector of raw choice strings, e.g.
#'   \code{"[\"assets/stimuli/cat.png\",\"assets/stimuli/dog.png\"]"}.
#' @param extension Character. File extension to strip, including the leading
#'   dot. Default: \code{".png"}.
#'
#' @return Character vector of the same length as \code{choices}, with
#'   brackets, quotes, path prefixes, and the extension removed.
#'
#' @examples
#' raw <- c(
#'   "[\"assets/stimuli/cat.png\",\"assets/stimuli/dog.png\"]",
#'   "[\"resources/apple.png\",\"resources/banana.png\"]"
#' )
#' process_choices(raw)
#' # [1] "cat,dog"   "apple,banana"
#'
#'
#' @export
process_choices <- function(choices, extension = ".png") {
  choices <- gsub("\\[|\\]", "", choices)
  choices <- gsub("assets/stimuli/", "", choices)
  choices <- gsub("resources/", "", choices)
  choices <- gsub('"', "", choices)
  gsub(extension, "", choices, fixed = TRUE)
}
