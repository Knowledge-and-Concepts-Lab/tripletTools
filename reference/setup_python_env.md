# Set up the Python environment for triplet embeddings

Call this function once the very first time you use the embedding
pipeline. It will:

1.  Check whether Miniconda/Anaconda is available on the system.

2.  Create a self-contained conda environment named `envname`.

3.  Install all required Python packages listed in `requirements.txt`
    into that environment.

4.  Activate the environment for the current R session.

## Usage

``` r
setup_python_env(envname = NULL, requirements = NULL, cuda_version = NULL)
```

## Arguments

- envname:

  Name of the conda environment to create. Defaults to
  `"triplet-embeddings"`. Change this only if you need to keep multiple
  isolated environments on the same machine.

- requirements:

  Path to a `requirements.txt` file listing the Python packages to
  install. Defaults to the copy bundled with the package
  (`inst/requirements.txt`).

- cuda_version:

  CUDA version string to install GPU-enabled PyTorch (e.g. `"12.1"`), or
  `NULL` (default) to install the CPU-only build. Must match the CUDA
  toolkit version on your system.

## Value

The environment name, invisibly.

## Details

On future R sessions you do **not** need to call this function again.
Loading the package with
[`library()`](https://rdrr.io/r/base/library.html) is sufficient — the
environment is detected and activated automatically at that point.

## Python dependencies

The following packages are installed into the conda environment:
`numpy`, `pandas`, `torch`, `scikit-learn`, `scipy`, `skorch`, and
`setuptools` (pinned to `< 71`; later versions no longer expose
`pkg_resources` as a top-level module, which skorch requires). PyTorch
is installed via conda from the pytorch channel; all other packages come
from conda-forge. No pip installs are used, which ensures DLL
compatibility on Windows. PyTorch is a large download (~300 MB–2 GB
depending on platform and CUDA version), so the first-time installation
may take several minutes.

## CUDA / GPU support

By default, the CPU-only build of PyTorch is installed. To enable GPU
acceleration, pass any non-`NULL` value for `cuda_version` (e.g.
`cuda_version = "12.4"`). You can check your system's maximum supported
CUDA version by running `nvidia-smi` in a terminal; install any version
at or below that number. Common versions are `"11.8"`, `"12.1"`, and
`"12.4"`.

On **Windows**, the pytorch conda channel ships CUDA-enabled builds with
the CUDA runtime bundled, so the `cuda_version` argument is accepted but
the version number is not used to select a specific package — the latest
available CUDA-enabled build is installed. On Linux and macOS the
`pytorch-cuda=<version>` package is installed from the `nvidia` conda
channel.

## Examples

``` r
if (FALSE) { # \dontrun{
# Run once after installing the package:
setup_python_env()

# On all subsequent sessions just load the package as normal:
library(tripletTools)
results <- run_embeddings(
  input_file           = "triplets.csv",
  additional_data_file = "item_labels.csv",
  output_dir           = "embeddings_output"
)
} # }
```
