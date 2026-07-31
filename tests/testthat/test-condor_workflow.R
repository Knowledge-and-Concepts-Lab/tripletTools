# These files are plain scripts/templates under inst/condor/, not package
# functions -- they can't be unit tested by calling exported functions, and
# actually running condor_workflow.R requires an HTCondor cluster this
# environment doesn't have. These tests instead check: the helper logic
# (sourced directly) behaves correctly in isolation, the driver script and
# helpers parse without a syntax error, and the shipped template/config
# files are structurally sound.

skip_if_not_installed("yaml")

condor_dir <- system.file("condor", package = "tripletTools")

test_that("inst/condor files are present", {
  expect_true(nzchar(condor_dir))
  expect_true(file.exists(file.path(condor_dir, "condor_workflow.R")))
  expect_true(file.exists(file.path(condor_dir, "condor_helpers.R")))
  expect_true(file.exists(file.path(condor_dir, "condor.tmpl")))
  expect_true(file.exists(file.path(condor_dir, "condor_apptainer.tmpl")))
  expect_true(file.exists(file.path(condor_dir, "params_template.yml")))
})

test_that("condor_workflow.R and condor_helpers.R parse without a syntax error", {
  expect_no_error(parse(file.path(condor_dir, "condor_workflow.R")))
  expect_no_error(parse(file.path(condor_dir, "condor_helpers.R")))
})

# Source the helpers into a private environment so their tests don't leak
# `%||%`/get_config/etc. into the rest of the test suite.
helpers <- new.env()
sys.source(file.path(condor_dir, "condor_helpers.R"), envir = helpers)

test_that("%||% falls back only on NULL", {
  expect_equal(helpers$`%||%`(NULL, "default"), "default")
  expect_equal(helpers$`%||%`("value", "default"), "value")
  expect_equal(helpers$`%||%`(0, "default"), 0)  # falsy but non-NULL
})

test_that("parse_dims handles range strings and explicit lists", {
  expect_equal(helpers$parse_dims("1:8"), 1:8)
  expect_equal(helpers$parse_dims(" 2 : 5 "), 2:5)
  expect_equal(helpers$parse_dims(list(1, 3, 5)), c(1L, 3L, 5L))
  expect_equal(helpers$parse_dims(c(2, 4, 6)), c(2L, 4L, 6L))
})

test_that("load_triplet_data reads a combined CSV via get.combined()", {
  csv_path <- system.file("extdata", "icon_all_triplets.csv", package = "tripletTools")
  skip_if(!nzchar(csv_path), "bundled example CSV not found")

  from_helper <- helpers$load_triplet_data(csv_path)
  from_get_combined <- get.combined(csv_path)

  expect_true(is.list(from_helper))
  expect_false(is.null(names(from_helper)))
  expect_equal(from_helper, from_get_combined)
})

test_that("load_triplet_data reads a saved triplet_list from .rds", {
  tmp <- tempfile(fileext = ".rds")
  on.exit(unlink(tmp))
  saveRDS(icon_triplets, tmp)

  expect_equal(helpers$load_triplet_data(tmp), icon_triplets)
})

test_that("load_triplet_data errors clearly on an unrecognized extension", {
  expect_error(
    helpers$load_triplet_data("triplet_data.txt"),
    "Unrecognized triplet data file extension"
  )
})

test_that("get_config resolves stage override > defaults > hardcoded default", {
  config <- list(
    defaults = list(max_epochs = 50000L, tol_window = 10000L),
    dimensionality = list(max_epochs = 20000L)
  )
  # Stage-level override wins
  expect_equal(
    helpers$get_config(config$dimensionality, "max_epochs", config, 999L),
    20000L
  )
  # Falls back to defaults when the stage doesn't override
  expect_equal(
    helpers$get_config(config$dimensionality, "tol_window", config, 999L),
    10000L
  )
  # Falls back to the hardcoded default when neither is set
  expect_equal(
    helpers$get_config(config$dimensionality, "tolerance", config, 1e-4),
    1e-4
  )
})

test_that("resources_config resolves stage override > defaults > empty list", {
  config <- list(defaults = list(resources = list(request_memory = "4GB")))
  stage_with_override <- list(resources = list(request_memory = "16GB"))

  expect_equal(
    helpers$resources_config(stage_with_override, config),
    list(request_memory = "16GB")
  )
  expect_equal(
    helpers$resources_config(list(), config),
    list(request_memory = "4GB")
  )
  expect_equal(
    helpers$resources_config(list(), list()),
    list()
  )
})

test_that("params_template.yml loads and has the fields condor_workflow.R expects", {
  config <- yaml::read_yaml(file.path(condor_dir, "params_template.yml"))

  expect_true(all(c("output_dir", "seed", "geometry", "radius", "norm_penalty",
                     "condor", "defaults", "dimensionality", "learning_curve",
                     "final_fit") %in% names(config)))
  expect_true(all(c("template", "workers") %in% names(config$condor)))
  expect_true(all(c("max_epochs", "tolerance", "tol_window", "device",
                     "resources") %in% names(config$defaults)))
  expect_true(all(c("request_cpus", "request_memory") %in%
                    names(config$defaults$resources)))
  # request_disk is deliberately left unset in defaults: so condor.tmpl and
  # condor_apptainer.tmpl each fall back to their own appropriate default.
  expect_false("request_disk" %in% names(config$defaults$resources))
  expect_true("dims" %in% names(config$dimensionality))
  expect_true("by" %in% names(config$learning_curve))

  # dims as shipped ("1:8") must be parseable by parse_dims()
  expect_equal(helpers$parse_dims(config$dimensionality$dims), 1:8)
})

test_that("condor.tmpl contains the fields batchtools/HTCondor expect", {
  tmpl <- readLines(file.path(condor_dir, "condor.tmpl"))
  tmpl_text <- paste(tmpl, collapse = "\n")

  expect_true(grepl("universe", tmpl_text))
  expect_true(grepl("\\$\\(job\\.collection\\)", tmpl_text))
  expect_true(grepl("request_cpus", tmpl_text))
  expect_true(grepl("request_memory", tmpl_text))
  expect_true(grepl("request_disk", tmpl_text))
  expect_true(grepl("resources\\$request_memory", tmpl_text))
  expect_true(grepl("^queue\\s*$", tmpl_text, perl = TRUE) ||
                any(grepl("^queue\\s*$", tmpl)))
})

test_that("condor_apptainer.tmpl references the container image and shares core fields with condor.tmpl", {
  tmpl <- readLines(file.path(condor_dir, "condor_apptainer.tmpl"))
  tmpl_text <- paste(tmpl, collapse = "\n")

  expect_true(grepl("universe\\s*=\\s*container", tmpl_text))
  expect_true(grepl("container_image", tmpl_text))
  expect_true(grepl("resources\\$container_image", tmpl_text))
  expect_true(grepl("ghcr\\.io", tmpl_text))
  expect_true(grepl("\\$\\(job\\.collection\\)", tmpl_text))
  expect_true(grepl("request_cpus", tmpl_text))
  expect_true(grepl("request_memory", tmpl_text))
  expect_true(grepl("request_disk", tmpl_text))
  # Larger default disk than condor.tmpl's 2GB, to also cover the pulled/
  # unpacked container image.
  expect_true(grepl('else "8GB"', tmpl_text, fixed = TRUE))
  # Staged-.sif alternative to pulling docker:// every job, using the
  # confirmed CHTC OSDF/Pelican staging path convention.
  expect_true(grepl("osdf:///chtc\\$ENV\\(STAGING\\)", tmpl_text))
  expect_true(grepl("HasCHTCStaging", tmpl_text))
  expect_true(any(grepl("^queue\\s*$", tmpl)))
})
