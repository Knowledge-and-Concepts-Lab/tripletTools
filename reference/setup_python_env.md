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
setup_python_env(envname = NULL, requirements = NULL)
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

## Value

The environment name, invisibly.

## Details

On future R sessions you do **not** need to call this function again.
Loading the package with
[`library()`](https://rdrr.io/r/base/library.html) is sufficient — the
environment is detected and activated automatically at that point.

## Python dependencies

The following packages are installed into the conda environment:
`numpy`, `pandas`, `torch`, `scikit-learn`, `scipy`, and `skorch`.
PyTorch is installed via conda from the pytorch channel; all other
packages come from conda-forge. No pip installs are used, which ensures
DLL compatibility on Windows. PyTorch is a large download (~300–800 MB
depending on platform), so the first-time installation may take several
minutes.

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
