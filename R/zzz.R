# Package-level state for Python integration (optional — requires reticulate).
.pkg_env <- new.env(parent = emptyenv())
.envname <- "triplet-embeddings"
.python_dir        <- NULL
.requirements_file <- NULL

.onLoad <- function(libname, pkgname) {
  .python_dir        <<- system.file("python",           package = pkgname)
  .requirements_file <<- system.file("requirements.txt", package = pkgname)

  if (!requireNamespace("reticulate", quietly = TRUE)) return(invisible(NULL))

  if (!nzchar(Sys.getenv("RETICULATE_CONDA"))) {
    conda_path <- tryCatch(reticulate::conda_binary(), error = function(e) "")
    if (!nzchar(conda_path)) conda_path <- Sys.which("conda")
    if (nzchar(conda_path)) Sys.setenv(RETICULATE_CONDA = conda_path)
  }

  if (reticulate::condaenv_exists(.envname)) {
    reticulate::use_condaenv(.envname, required = TRUE)
  }
}

# Returns the lazily-loaded compute_embeddings Python module.
.get_compute_py <- function() {
  if (!requireNamespace("reticulate", quietly = TRUE))
    stop("The 'reticulate' package is required. Install it with install.packages('reticulate').")

  if (!exists("module", envir = .pkg_env, inherits = FALSE)) {
    python_dir <- if (!is.null(.python_dir) && nzchar(.python_dir) && dir.exists(.python_dir)) {
      .python_dir
    } else {
      getwd()
    }
    reticulate::py_run_string(sprintf(
      "import sys\nif r'%s' not in sys.path: sys.path.insert(0, r'%s')",
      python_dir, python_dir
    ))
    .pkg_env$module <- reticulate::import("compute_embeddings")
  }
  .pkg_env$module
}
