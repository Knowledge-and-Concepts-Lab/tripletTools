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
#' \code{scipy}, \code{skorch}, and \code{setuptools} (pinned to \code{< 71};
#' later versions no longer expose \code{pkg_resources} as a top-level module,
#' which skorch requires).  PyTorch is installed via conda from the pytorch
#' channel; all other packages come from conda-forge.  No pip installs are
#' used, which ensures DLL compatibility on Windows.  PyTorch is a large
#' download (~300 MB–2 GB depending on platform and CUDA version), so the
#' first-time installation may take several minutes.
#'
#' @section CUDA / GPU support:
#' By default, the CPU-only build of PyTorch is installed.  To enable GPU
#' acceleration, pass any non-\code{NULL} value for \code{cuda_version}
#' (e.g. \code{cuda_version = "12.4"}).  You can check your system's maximum
#' supported CUDA version by running \code{nvidia-smi} in a terminal; install
#' any version at or below that number.  Common versions are \code{"11.8"},
#' \code{"12.1"}, and \code{"12.4"}.
#'
#' On \strong{Windows}, the pytorch conda channel ships CUDA-enabled builds
#' with the CUDA runtime bundled, so the \code{cuda_version} argument is
#' accepted but the version number is not used to select a specific package —
#' the latest available CUDA-enabled build is installed.  On Linux and macOS
#' the \code{pytorch-cuda=<version>} package is installed from the
#' \code{nvidia} conda channel.
#'
#' @param envname Name of the conda environment to create.
#'   Defaults to \code{"triplet-embeddings"}.  Change this only if you need
#'   to keep multiple isolated environments on the same machine.
#' @param requirements Path to a \code{requirements.txt} file listing the
#'   Python packages to install.  Defaults to the copy bundled with the
#'   package (\code{inst/requirements.txt}).
#' @param cuda_version CUDA version string to install GPU-enabled PyTorch
#'   (e.g. \code{"12.1"}), or \code{NULL} (default) to install the CPU-only
#'   build.  Must match the CUDA toolkit version on your system.
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
    requirements = NULL,
    cuda_version = NULL
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

    if (!is.null(cuda_version)) {
      conda_bin <- reticulate::conda_binary()
      # --override-channels prevents conda from falling back to pkgs/main, which
      # only carries CPU-only PyTorch builds.
      #
      # On Windows the nvidia channel's cuda-runtime packages are Linux-only, so
      # pytorch-cuda=X.Y cannot be used. Instead the pytorch channel ships
      # CUDA-enabled Windows builds with the CUDA libraries bundled. On Linux/Mac
      # the nvidia channel is needed to supply the separate CUDA runtime packages.
      if (.Platform$OS.type == "windows") {
        message(
          "Installing pytorch (CUDA-enabled Windows build) via conda (pytorch channel).\n",
          "PyTorch with CUDA is a large package (~1.5-2 GB); this may take several minutes. Please wait..."
        )
        args <- c(
          "install", "-n", envname,
          "--override-channels",
          "-c", "pytorch", "-c", "conda-forge",
          "pytorch", "numpy<2",
          "-y"
        )
      } else {
        message(sprintf(
          "Installing pytorch with CUDA %s via conda (pytorch + nvidia channels).\n",
          cuda_version
        ), "PyTorch with CUDA is a large package (~1.5-2 GB); this may take several minutes. Please wait...")
        args <- c(
          "install", "-n", envname,
          "--override-channels",
          "-c", "pytorch", "-c", "nvidia",
          "pytorch", paste0("pytorch-cuda=", cuda_version), "numpy<2",
          "-y"
        )
      }
      ret <- system2(conda_bin, args)
      if (ret != 0L)
        stop("conda install failed with exit code ", ret, ".")
    } else {
      message(
        "Installing pytorch via conda (pytorch channel). PyTorch is a large\n",
        "package (~300-800 MB), so this may take several minutes. Please wait..."
      )
      reticulate::conda_install(
        packages = c("pytorch", "numpy<2"),
        envname  = envname,
        channel  = "pytorch"
      )
    }

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
