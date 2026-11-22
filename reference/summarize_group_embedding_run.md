# Summarize a `condor_workflow.py` run

Reads the output directory of `condor_workflow.py`'s five-stage Condor
pipeline (package `inst/condor/`; see
[`vignette("condor_workflows_vignette")`](https://knowledge-and-concepts-lab.github.io/tripletTools/articles/condor_workflows_vignette.md)'s
Workflow 1, and
[`run_group_embedding_workflow`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/run_group_embedding_workflow.md)
for the local, non-Condor equivalent) and writes a self-contained
Markdown report with one section per stage: the dimensionality search,
the learning curve, the crowd-kernel warm-start fit, alpha estimation,
and the final-final production fit – each with the plots this project
has repeatedly needed by hand after a real Condor run (loss/accuracy vs.
dimension or fraction, training curves, restart stability, the alpha
trajectory, and the recovered embedding's own geometry). The same
report-generation idea as
[`summarize_joint_estimation`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/summarize_joint_estimation.md),
for this package's other Condor workflow.

## Usage

``` r
summarize_group_embedding_run(
  output_dir,
  item_colors = NULL,
  output_md = NULL,
  verbose = TRUE
)
```

## Arguments

- output_dir:

  Path to a `condor_workflow.py` output directory (must contain
  `run_manifest.txt`).

- item_colors:

  Character vector, same length and row order as the production
  embedding, or `NULL` (default): colors for the embedding-geometry
  plots. With no dataset-specific semantics available in general, the
  default colors items by row position via
  [`rainbow`](https://rdrr.io/r/grDevices/palettes.html); pass a
  semantically meaningful vector for a more informative plot.

- output_md:

  Path to write the Markdown report to. Default
  `file.path(output_dir, "summary.md")`. Figures are written as PNG
  files to a sibling `<name>_files/` directory and referenced with
  relative paths, so the report is self-contained if copied as a unit.

- verbose:

  Logical, print progress. Default `TRUE`.

## Value

Invisibly, the parsed run as a named list (see the source of
`read_group_embedding_run()` for its fields) – mainly useful for
follow-up inspection in an interactive session. Also writes `output_md`
and its figures as a side effect.

## Details

Stages 2 (learning curve), 4 (alpha estimation), and 5 (final-final fit)
are optional in `condor_workflow.py` itself (`run_learning_curve: false`
/ `refit_alpha: false` in its config) – this function detects their
absence from `output_dir` directly (rather than trusting
`run_manifest.txt`'s own fields, which an older run may not have) and
writes a short note in place of that stage's section instead of failing.
When stages 4-5 were skipped, `best_embedding.csv` (stage 3) is reported
as the production embedding instead of `best_final_embedding.csv`,
matching
[`vignette("condor_workflows_vignette")`](https://knowledge-and-concepts-lab.github.io/tripletTools/articles/condor_workflows_vignette.md)'s
own convention.
