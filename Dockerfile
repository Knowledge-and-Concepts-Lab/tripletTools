# tripletTools runtime image: R + the `triplet-embeddings` conda/Python
# environment + tripletTools itself, all pre-installed so it can be shipped
# to HTCondor execute nodes via Apptainer (which runs Docker images
# directly -- no separate native container build needed).
#
# Build locally:
#   docker build -t tripletTools .
#
# The GitHub Actions workflow at .github/workflows/docker-publish.yml builds
# and pushes this to ghcr.io automatically; you normally shouldn't need to
# build it by hand except to debug a failing build.
#
# ---------------------------------------------------------------------------

ARG R_VERSION=4.4.2
FROM rocker/r-ver:${R_VERSION}

# System libraries needed to compile the R packages in Imports/Suggests
# (vegan/ape need Fortran + BLAS via r-ver's build tools; png/dplyr/etc.
# need these). Add more here if a future dependency fails to compile.
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    curl \
    ca-certificates \
    libcurl4-openssl-dev \
    libssl-dev \
    libxml2-dev \
    libpng-dev \
    zlib1g-dev \
    libfontconfig1-dev \
    libharfbuzz-dev \
    libfribidi-dev \
    libfreetype6-dev \
    libtiff5-dev \
    libjpeg-dev \
    && rm -rf /var/lib/apt/lists/*

# ---- Miniconda (for the Python/PyTorch side of the pipeline) --------------
ENV CONDA_DIR=/opt/miniconda3
ENV PATH=${CONDA_DIR}/bin:${PATH}
ENV RETICULATE_CONDA=${CONDA_DIR}/bin/conda

RUN curl -fsSL -o /tmp/miniconda.sh \
      https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh \
    && bash /tmp/miniconda.sh -b -p ${CONDA_DIR} \
    && rm /tmp/miniconda.sh \
    && conda config --system --set always_yes yes \
    && conda clean -afy

# ---- R package dependencies -------------------------------------------------
# Only what's needed at *runtime* on an execute node: the package's own
# Imports, plus the Suggests actually used by the Condor workflow
# (reticulate, future/future.apply/future.batchtools, progressr, yaml).
# knitr/rmarkdown/testthat are build/dev-time only and deliberately omitted
# to keep the image smaller.
RUN Rscript -e '\
    install.packages(c( \
      "ape", "png", "vegan", "data.table", "dplyr", "magrittr", "readr", \
      "stringr", "rlang", \
      "reticulate", "future", "future.apply", "future.batchtools", \
      "progressr", "yaml", "remotes" \
    ), repos = "https://cloud.r-project.org")'

# ---- tripletTools itself ----------------------------------------------------
# Installs from GitHub so the image always reflects a real, pushed commit.
# Override with --build-arg TRIPLETTOOLS_REF=<branch/tag/sha> to pin a
# specific version instead of always tracking main.
ARG TRIPLETTOOLS_REF=main
RUN Rscript -e "remotes::install_github('Knowledge-and-Concepts-Lab/tripletTools', ref = '${TRIPLETTOOLS_REF}', upgrade = 'never')"

# ---- The triplet-embeddings conda environment -------------------------------
# Reuses the package's own setup_python_env() rather than re-deriving the
# conda-create logic here, so the container's environment is built exactly
# the way a local install would build it.
RUN Rscript -e 'tripletTools::setup_python_env()'

# ---- Build-time sanity check -------------------------------------------------
# Fail the image build loudly if the package or its Python backend can't
# load, rather than shipping a broken image that only fails once a real
# Condor job hits it.
RUN Rscript -e '\
    library(tripletTools); \
    reticulate::py_config(); \
    compute_py <- tripletTools:::.get_compute_py(); \
    cat("tripletTools + Python backend loaded OK\n")'

CMD ["Rscript", "--version"]
