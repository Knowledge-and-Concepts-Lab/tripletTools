#' Set up the Python environment for triplet embeddings
#'
#' Call this function once the very first time you use the embedding pipeline.
#' It will:
#' \enumerate{
#'   \item Check whether Miniconda/Anaconda is available on the system.
#'   \item Create a self-contained conda environment named \code{envname}.
#'   \item Install all required Python packages listed in
#'         \code{requirements.txt} into that environment.
#'   \item Activate the environment for the current R session.
#' }
#'
#' On future R sessions you do \strong{not} need to call this function again.
#' Loading the package with \code{library()} is sufficient — the environment
#' is detected and activated automatically at that point.
#'
#' @section Python dependencies:
#' The following packages are installed into the conda environment:
#' \code{numpy}, \code{pandas}, \code{torch}, \code{scikit-learn},
#' \code{scipy}, and \code{skorch}.  PyTorch is installed via conda from the
#' pytorch channel; all other packages come from conda-forge.  No pip installs
#' are used, which ensures DLL compatibility on Windows.  PyTorch is a large
#' download (~300–800 MB depending on platform), so the first-time
#' installation may take several minutes.
#'
#' @param envname Name of the conda environment to create.
#'   Defaults to \code{"triplet-embeddings"}.  Change this only if you need
#'   to keep multiple isolated environments on the same machine.
#' @param requirements Path to a \code{requirements.txt} file listing the
#'   Python packages to install.  Defaults to the copy bundled with the
#'   package (\code{inst/requirements.txt}).
#'
#' @return The environment name, invisibly.
#'
#' @export
#'
#' @examples
#' \dontrun{
#' # Run once after installing the package:
#' setup_python_env()
#'
#' # On all subsequent sessions just load the package as normal:
#' library(tripletTools)
#' results <- run_embeddings(
#'   input_file           = "triplets.csv",
#'   additional_data_file = "item_labels.csv",
#'   output_dir           = "embeddings_output"
#' )
#' }
setup_python_env <- function(
    envname      = NULL,
    requirements = NULL
) {
  if (!requireNamespace("reticulate", quietly = TRUE))
    stop("The 'reticulate' package is required. Install it with install.packages('reticulate').")

  if (is.null(envname))
    envname <- if (exists(".envname", inherits = TRUE)) .envname else "triplet-embeddings"
  if (is.null(requirements))
    requirements <- if (exists(".requirements_file", inherits = TRUE)) .requirements_file else ""

  # Ensure conda is available
  conda <- tryCatch(reticulate::conda_binary(), error = function(e) "")
  if (!nzchar(conda)) {
    conda <- Sys.which("conda")
    if (nzchar(conda)) Sys.setenv(RETICULATE_CONDA = conda)
  }
  if (!nzchar(conda))
    stop(
      "Conda (Miniconda or Anaconda) was not found on this system.\n",
      "Please install Miniconda from https://docs.conda.io/en/latest/miniconda.html ",
      "and try again."
    )

  if (reticulate::condaenv_exists(envname)) {
    message(sprintf("Python environment '%s' already exists — skipping installation.", envname))
  } else {
    message(sprintf("Creating conda environment '%s'...", envname))
    # Python 3.13 has a known incompatibility with PyTorch's DLL initialisation
    # when embedded in R on Windows.  Python 3.11 is the recommended version.
    reticulate::conda_create(envname, python_version = "3.11")

    if (!nzchar(requirements) || !file.exists(requirements))
      stop(
        "requirements.txt not found at: ", requirements, "\n",
        "Ensure requirements.txt is present under inst/ in the package source."
      )

    pkgs <- readLines(requirements, warn = FALSE)
    pkgs <- pkgs[nzchar(trimws(pkgs)) & !startsWith(trimws(pkgs), "#")]
    is_torch <- grepl("^torch", tolower(trimws(pkgs)))

    message(
      "Installing pytorch via conda (pytorch channel). PyTorch is a large\n",
      "package (~300-800 MB), so this may take several minutes. Please wait..."
    )
    reticulate::conda_install(
      packages = c("pytorch", "numpy<2"),
      envname  = envname,
      channel  = "pytorch"
    )

    other_pkgs <- pkgs[!is_torch]
    if (length(other_pkgs) > 0) {
      message("Installing remaining dependencies via conda-forge...")
      reticulate::conda_install(packages = other_pkgs, envname = envname)
    }

    message("Setup complete.")
  }

  reticulate::use_condaenv(envname, required = TRUE)
  invisible(envname)
}
