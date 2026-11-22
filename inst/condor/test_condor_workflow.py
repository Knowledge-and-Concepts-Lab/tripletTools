"""Unit tests for condor_workflow.py's pure logic (config resolution, job-grid
generation, submit-file syntax, result aggregation) -- everything that
doesn't require a real HTCondor cluster or condor_submit/condor_wait.

Run locally with:
    python3 -m unittest inst/condor/test_condor_workflow.py -v

This is a plain unittest suite (stdlib only) rather than pytest, so it needs
no extra dependency beyond PyYAML (condor_workflow.py's own requirement) to
run. It is not invoked by devtools::test()/R CMD check -- it's a
developer-facing check for the Python side of the Condor workflow.
"""
import csv
import re
import statistics
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent))
import condor_workflow as cw  # noqa: E402


class TestParseDims(unittest.TestCase):
    def test_range_string(self):
        self.assertEqual(cw.parse_dims("1:8"), list(range(1, 9)))

    def test_range_string_with_spaces(self):
        self.assertEqual(cw.parse_dims(" 2 : 5 "), [2, 3, 4, 5])

    def test_explicit_list(self):
        self.assertEqual(cw.parse_dims([1, 3, 5]), [1, 3, 5])

    def test_single_value_string(self):
        self.assertEqual(cw.parse_dims("4"), [4])


class TestComputeFractions(unittest.TestCase):
    def test_by_one_tenth(self):
        fractions = cw.compute_fractions(0.1)
        expected = [round(x * 0.1, 8) for x in range(1, 11)]
        self.assertEqual(fractions, expected)
        self.assertEqual(fractions[-1], 1.0)

    def test_by_half(self):
        self.assertEqual(cw.compute_fractions(0.5), [0.5, 1.0])

    def test_by_that_overshoots_one(self):
        # Matches R's estimate_learning_curve(): fractions > 1 clamp to 1,
        # and duplicates (e.g. two steps both landing on 1.0) collapse to
        # one entry via unique().
        fractions = cw.compute_fractions(0.34)
        self.assertEqual(fractions[-1], 1.0)
        self.assertEqual(len(fractions), len(set(fractions)))


class TestGetConfigAndResources(unittest.TestCase):
    def test_stage_override_wins(self):
        config = {"defaults": {"max_epochs": 50000, "tol_window": 10000}}
        stage_cfg = {"max_epochs": 20000}
        self.assertEqual(cw.get_config(stage_cfg, "max_epochs", config, 999), 20000)

    def test_falls_back_to_defaults(self):
        config = {"defaults": {"max_epochs": 50000, "tol_window": 10000}}
        stage_cfg = {"max_epochs": 20000}
        self.assertEqual(cw.get_config(stage_cfg, "tol_window", config, 999), 10000)

    def test_falls_back_to_hardcoded_default(self):
        config = {"defaults": {}}
        self.assertEqual(cw.get_config({}, "tolerance", config, 1e-4), 1e-4)

    def test_resources_config_inheritance(self):
        config = {"defaults": {"resources": {"request_memory": "4GB"}}}
        stage_with_override = {"resources": {"request_memory": "16GB"}}
        self.assertEqual(cw.resources_config(stage_with_override, config),
                          {"request_memory": "16GB"})
        self.assertEqual(cw.resources_config({}, config), {"request_memory": "4GB"})
        self.assertEqual(cw.resources_config({}, {}), {})


class TestSummarizeDimensionality(unittest.TestCase):
    """Scenarios ported directly from
    tests/testthat/test-summarize_dimensionality.R, verified there against
    the actual R implementation -- the numeric results here must match."""

    def test_mean_loss_and_columns(self):
        results = (
            [{"d": 1, "restart": i, "loss": l, "accuracy": 0.8, "norm_ratio": 1.2}
             for i, l in enumerate([0.50, 0.52, 0.48, 0.50], start=1)]
            + [{"d": 2, "restart": i, "loss": l, "accuracy": 0.8, "norm_ratio": 1.2}
               for i, l in enumerate([0.30, 0.32, 0.28, 0.30], start=1)]
        )
        summary, best_d = cw.summarize_dimensionality(results, n_restarts=4, best_d_norm_penalty=0)
        means = {row["d"]: row["mean_loss"] for row in summary}
        self.assertAlmostEqual(means[1], 0.50, places=8)
        self.assertAlmostEqual(means[2], 0.30, places=8)
        for row in summary:
            self.assertAlmostEqual(row["penalized_loss"], row["mean_loss"], places=8)

    def test_one_se_parsimony_rule(self):
        # d=3 has the global min mean_loss but high variance; d=2's
        # mean_loss falls within d=3's one-SE band, so the smaller,
        # more parsimonious d=2 should win. Matches the R test exactly.
        results = []
        for d, losses in [(1, [0.50, 0.52, 0.48, 0.50]),
                           (2, [0.30, 0.32, 0.30, 0.32]),
                           (3, [0.20, 0.40, 0.20, 0.40])]:
            for i, l in enumerate(losses, start=1):
                results.append({"d": d, "restart": i, "loss": l,
                                 "accuracy": 0.8, "norm_ratio": 1})
        summary, best_d = cw.summarize_dimensionality(results, n_restarts=4, best_d_norm_penalty=0)
        self.assertEqual(best_d, 2)
        means = {row["d"]: row["mean_loss"] for row in summary}
        self.assertAlmostEqual(means[3], 0.30, places=8)

    def test_norm_penalty_flips_best_d(self):
        results = (
            [{"d": 1, "restart": i, "loss": 0.31, "accuracy": 0.8, "norm_ratio": 1}
             for i in range(1, 5)]
            + [{"d": 2, "restart": i, "loss": 0.30, "accuracy": 0.8, "norm_ratio": 5}
               for i in range(1, 5)]
        )
        _, best_d_unpenalized = cw.summarize_dimensionality(results, n_restarts=4, best_d_norm_penalty=0)
        self.assertEqual(best_d_unpenalized, 2)

        summary_penalized, best_d_penalized = cw.summarize_dimensionality(
            results, n_restarts=4, best_d_norm_penalty=1
        )
        self.assertEqual(best_d_penalized, 1)
        penalized_by_d = {row["d"]: row["penalized_loss"] for row in summary_penalized}
        self.assertAlmostEqual(penalized_by_d[1], 0.31, places=8)
        self.assertAlmostEqual(penalized_by_d[2], 4.30, places=8)


class TestSummarizeLearningCurve(unittest.TestCase):
    def test_per_fraction_stats(self):
        results = (
            [{"fraction": 0.5, "n_train": 50, "restart": i, "loss": l,
              "accuracy": a, "norm_ratio": nr}
             for i, (l, a, nr) in enumerate(
                 zip([0.50, 0.52, 0.48], [0.6, 0.62, 0.58], [1.1, 1.2, 1.0]), start=1)]
            + [{"fraction": 1.0, "n_train": 100, "restart": i, "loss": l,
                "accuracy": a, "norm_ratio": nr}
               for i, (l, a, nr) in enumerate(
                   zip([0.30, 0.32, 0.28], [0.8, 0.82, 0.78], [1.3, 1.4, 1.2]), start=1)]
        )
        summary = cw.summarize_learning_curve(results)
        self.assertEqual([row["fraction"] for row in summary], [0.5, 1.0])
        self.assertEqual([row["n_train"] for row in summary], [50, 100])
        self.assertAlmostEqual(summary[0]["mean_loss"], statistics.fmean([0.50, 0.52, 0.48]))
        self.assertAlmostEqual(summary[1]["mean_loss"], statistics.fmean([0.30, 0.32, 0.28]))
        self.assertEqual(summary[0]["max_norm_ratio"], 1.2)
        self.assertEqual(summary[1]["max_norm_ratio"], 1.4)


class TestJobGridRandomState(unittest.TestCase):
    """The random_state formulas must match estimate_dimensionality()/
    estimate_learning_curve() exactly -- see condor_fit.R's header comment
    and the manual cross-checks recorded in the commit history."""

    def test_dimensionality_random_state_formula(self):
        seed = 1
        dims = [1, 2, 3]
        n_restarts = 2
        jobs = [(d, restart, seed + (restart - 1) * 1000 + d)
                for d in dims for restart in range(1, n_restarts + 1)]
        # d=2, restart=1 -> 1 + 0*1000 + 2 = 3 (matches the manual R
        # cross-check: estimate_dimensionality(dims=2, n_restarts=1, seed=1)
        # uses random_state=3 for its only restart)
        self.assertIn((2, 1, 3), jobs)
        # d=3, restart=2 -> 1 + 1*1000 + 3 = 1004
        self.assertIn((3, 2, 1004), jobs)

    def test_learning_curve_random_state_formula(self):
        seed = 1
        fractions = cw.compute_fractions(0.5)  # [0.5, 1.0]
        n_restarts = 2
        jobs = [(frac, restart, seed + (restart - 1) * 1000 + i)
                for i, frac in enumerate(fractions, start=1)
                for restart in range(1, n_restarts + 1)]
        # fraction=0.5 is index i=1, restart=1 -> 1 + 0 + 1 = 2 (matches the
        # manual R cross-check for estimate_learning_curve(by=0.5, seed=1))
        self.assertIn((0.5, 1, 2), jobs)
        # fraction=1.0 is index i=2, restart=2 -> 1 + 1000 + 2 = 1003
        self.assertIn((1.0, 2, 1003), jobs)

    def test_final_fit_random_state_formula(self):
        seed = 1
        n_restarts = 3
        jobs = [(restart, seed + (restart - 1) * 1000, restart - 1)
                for restart in range(1, n_restarts + 1)]
        # No d/fraction term, unlike the other two stages -- there is only
        # one d at this stage. restart=1 -> 1 + 0*1000 = 1 (matches prior
        # single-restart behavior, where seed was passed directly).
        self.assertIn((1, 1, 0), jobs)
        # restart=3 -> 1 + 2*1000 = 2001
        self.assertIn((3, 2001, 2), jobs)


class TestPickBestRestart(unittest.TestCase):
    def test_picks_lowest_loss_index(self):
        results = [{"loss": 0.50}, {"loss": 0.30}, {"loss": 0.40}]
        self.assertEqual(cw.pick_best_restart(results), 1)

    def test_single_restart(self):
        self.assertEqual(cw.pick_best_restart([{"loss": 0.50}]), 0)

    def test_ties_keep_the_first_occurrence(self):
        results = [{"loss": 0.30}, {"loss": 0.30}, {"loss": 0.50}]
        self.assertEqual(cw.pick_best_restart(results), 0)


class TestSubmitFileGeneration(unittest.TestCase):
    def test_write_submit_file_single_job(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "test.sub"
            cw.write_submit_file(
                path,
                container_image="docker://ghcr.io/example/image:latest",
                arguments="condor_fit.R --stage=final",
                transfer_input_files="condor_fit.R, data.csv",
                log="test.log", output="test.out", error="test.err",
                resources={"request_cpus": 2, "request_memory": "8GB"},
                initialdir=tmp,
            )
            text = path.read_text()
            self.assertIn("universe        = container", text)
            self.assertIn("container_image = docker://ghcr.io/example/image:latest", text)
            self.assertIn("executable          = /usr/local/bin/Rscript", text)
            # Without this, condor_submit stats `executable` on the submit
            # node and fails -- Rscript only ever exists inside the
            # container. Regression check for that failure mode.
            self.assertIn("transfer_executable = False", text)
            # Without this, HTCondor's default new-output-file transfer
            # (e.g. a job's bare --output=result_$(Process).csv) lands in
            # whatever directory condor_submit happened to run from, not
            # the stage directory read_result_row() looks in afterwards.
            self.assertIn(f"initialdir = {tmp}", text)
            self.assertIn("request_cpus   = 2", text)
            self.assertIn("request_memory = 8GB", text)
            self.assertTrue(text.rstrip().endswith("queue"))

    def test_queue_from_block_multi_job(self):
        block = cw.queue_from_block(["d", "restart", "random_state"],
                                     [(1, 1, 3), (2, 1, 4)])
        self.assertTrue(block.startswith("queue d,restart,random_state from ("))
        self.assertIn("1,1,3", block)
        self.assertIn("2,1,4", block)
        self.assertTrue(block.rstrip().endswith(")"))

    def test_write_submit_file_multi_job(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "test.sub"
            queue_stmt = cw.queue_from_block(["d", "restart", "random_state"],
                                              [(1, 1, 3), (2, 1, 4)])
            cw.write_submit_file(
                path,
                container_image="docker://ghcr.io/example/image:latest",
                arguments="condor_fit.R --stage=dimensionality --d=$(d)",
                transfer_input_files="condor_fit.R, data.csv",
                log="dim.log", output="dim_$(Process).out", error="dim_$(Process).err",
                resources={},
                initialdir=tmp,
                queue_statement=queue_stmt,
            )
            text = path.read_text()
            # Exactly one queue statement, not a leftover default "queue"
            # line as well (the earlier string-replacement approach risked
            # this).
            self.assertEqual(text.count("queue "), 1)
            self.assertIn("1,1,3", text)
            self.assertIn("2,1,4", text)


class TestSubmitJobsWithRetry(unittest.TestCase):
    """jobs here are simple (name,) tuples; output_path_fn resolves each job's
    expected file directly (this stage names results by a job_index field
    rather than a fixed tuple column, unlike the other two workflows)."""

    def test_all_succeed_first_try_calls_build_and_submit_once(self):
        with tempfile.TemporaryDirectory() as tmp:
            stage_dir = Path(tmp)
            jobs = [("a",), ("b",)]
            calls = []

            def build_and_submit(jobs_subset):
                calls.append(list(jobs_subset))
                for (name,) in jobs_subset:
                    (stage_dir / f"out_{name}.csv").write_text("data\n")

            cw.submit_jobs_with_retry(
                stage_dir, jobs, output_path_fn=lambda j: stage_dir / f"out_{j[0]}.csv",
                build_and_submit=build_and_submit, label="test",
            )
            self.assertEqual(len(calls), 1)
            self.assertEqual(calls[0], jobs)

    def test_missing_output_is_retried_with_only_the_missing_subset(self):
        with tempfile.TemporaryDirectory() as tmp:
            stage_dir = Path(tmp)
            jobs = [("a",), ("b",), ("c",)]
            calls = []

            def build_and_submit(jobs_subset):
                calls.append([j[0] for j in jobs_subset])
                for (name,) in jobs_subset:
                    if name == "b" and len(calls) == 1:
                        (stage_dir / f"out_{name}.csv").touch()  # simulates the failure
                    else:
                        (stage_dir / f"out_{name}.csv").write_text("data\n")

            cw.submit_jobs_with_retry(
                stage_dir, jobs, output_path_fn=lambda j: stage_dir / f"out_{j[0]}.csv",
                build_and_submit=build_and_submit, label="test",
            )
            self.assertEqual(calls, [["a", "b", "c"], ["b"]])
            self.assertGreater((stage_dir / "out_b.csv").stat().st_size, 0)

    def test_persistently_missing_output_exits_after_max_retries(self):
        with tempfile.TemporaryDirectory() as tmp:
            stage_dir = Path(tmp)
            jobs = [("a",)]

            def build_and_submit(jobs_subset):
                pass  # never actually produces out_a.csv

            with self.assertRaises(SystemExit):
                cw.submit_jobs_with_retry(
                    stage_dir, jobs, output_path_fn=lambda j: stage_dir / f"out_{j[0]}.csv",
                    build_and_submit=build_and_submit, label="test", max_retries=2,
                )

    def test_batch_size_splits_into_sequential_chunks(self):
        with tempfile.TemporaryDirectory() as tmp:
            stage_dir = Path(tmp)
            jobs = [(str(i),) for i in range(5)]
            calls = []

            def build_and_submit(jobs_subset):
                calls.append([j[0] for j in jobs_subset])
                for (name,) in jobs_subset:
                    (stage_dir / f"out_{name}.csv").write_text("data\n")

            cw.submit_jobs_with_retry(
                stage_dir, jobs, output_path_fn=lambda j: stage_dir / f"out_{j[0]}.csv",
                build_and_submit=build_and_submit, label="test", batch_size=2,
            )
            self.assertEqual(calls, [["0", "1"], ["2", "3"], ["4"]])


class TestRunFinalStage(unittest.TestCase):
    """End-to-end test of run_final_stage()'s job-grid restructuring (one
    Condor job per restart, aggregated in Python afterwards) -- the one
    piece of this new logic submit_jobs_with_retry()/pick_best_restart()'s
    own isolated unit tests don't cover: that run_final_stage() correctly
    reads every job's own result file, picks the lowest-loss one via
    pick_best_restart(), and copies *that* job's embedding/history to
    best_embedding.csv/best_embedding_history.csv. condor_submit/
    condor_wait themselves are mocked out via submit_and_wait() and
    queue_from_block(); nothing here touches a real HTCondor cluster."""

    def test_picks_lowest_loss_restart_and_writes_outputs(self):
        with tempfile.TemporaryDirectory() as tmp:
            work_dir = Path(tmp)
            data_path = work_dir / "data.csv"
            data_path.write_text("dummy")
            config = {"final_fit": {"n_restarts": 3}}
            losses = {0: 0.50, 1: 0.30, 2: 0.42}  # job_index 1 (restart 2) wins

            captured_rows = {}
            real_queue_from_block = cw.queue_from_block

            def fake_queue_from_block(varnames, rows):
                captured_rows["rows"] = rows
                return real_queue_from_block(varnames, rows)

            def fake_submit_and_wait(submit_path, log_path, label):
                for restart, random_state, job_index in captured_rows["rows"]:
                    stage_dir = submit_path.parent
                    (stage_dir / f"embedding_{job_index}.csv").write_text(
                        f"item,dim_0\nfoo,{job_index}\n")
                    (stage_dir / f"embedding_{job_index}_history.csv").write_text(
                        "epoch\n0\n")
                    with open(stage_dir / f"embedding_{job_index}_result.csv",
                              "w", newline="") as f:
                        writer = csv.DictWriter(f, fieldnames=["restart", "seed", "loss"])
                        writer.writeheader()
                        writer.writerow({"restart": restart, "seed": random_state,
                                          "loss": losses[job_index]})

            with mock.patch.object(cw, "submit_and_wait", side_effect=fake_submit_and_wait), \
                 mock.patch.object(cw, "queue_from_block", side_effect=fake_queue_from_block):
                cw.run_final_stage(work_dir, data_path, config, seed=1, best_d=3,
                                    geometry="euclidean", radius=1, norm_penalty=0,
                                    container_image="docker://fake")

            # job_index 1 (restart 2, the lowest loss) must be the one kept.
            self.assertEqual((work_dir / "best_embedding.csv").read_text(),
                              "item,dim_0\nfoo,1\n")
            self.assertEqual((work_dir / "best_embedding_history.csv").read_text(),
                              "epoch\n0\n")

            with open(work_dir / "best_embedding_restarts.csv", newline="") as f:
                rows = list(csv.DictReader(f))
            self.assertEqual(len(rows), 3)
            self.assertEqual({r["restart"] for r in rows}, {"1", "2", "3"})

    def test_single_restart_default_preserves_prior_behavior(self):
        with tempfile.TemporaryDirectory() as tmp:
            work_dir = Path(tmp)
            data_path = work_dir / "data.csv"
            data_path.write_text("dummy")
            config = {}  # n_restarts defaults to 1

            def fake_submit_and_wait(submit_path, log_path, label):
                stage_dir = submit_path.parent
                (stage_dir / "embedding_0.csv").write_text("item,dim_0\nfoo,0\n")
                (stage_dir / "embedding_0_history.csv").write_text("epoch\n0\n")
                with open(stage_dir / "embedding_0_result.csv", "w", newline="") as f:
                    writer = csv.DictWriter(f, fieldnames=["restart", "seed", "loss"])
                    writer.writeheader()
                    writer.writerow({"restart": 1, "seed": 1, "loss": 0.5})

            with mock.patch.object(cw, "submit_and_wait", side_effect=fake_submit_and_wait):
                cw.run_final_stage(work_dir, data_path, config, seed=1, best_d=3,
                                    geometry="euclidean", radius=1, norm_penalty=0,
                                    container_image="docker://fake")

            self.assertEqual((work_dir / "best_embedding.csv").read_text(),
                              "item,dim_0\nfoo,0\n")


class TestRunAlphaStage(unittest.TestCase):
    """run_alpha_stage() is a single Condor job (no restart grid, unlike
    every other stage) -- this checks it reads back alpha_embedding_result.csv
    correctly, promotes the four expected files to work_dir, and returns
    (alpha, folded_path) for run_final_final_stage() to consume. No real
    HTCondor cluster or R needed: submit_and_wait() is mocked out."""

    def test_reads_alpha_and_promotes_outputs(self):
        with tempfile.TemporaryDirectory() as tmp:
            work_dir = Path(tmp)
            data_path = work_dir / "data.csv"
            data_path.write_text("dummy")
            (work_dir / "best_embedding.csv").write_text("item,dim_0\nfoo,0.1\n")
            config = {"alpha_stage": {"alpha_test_frac": 0.4}}

            def fake_submit_and_wait(submit_path, log_path, label):
                stage_dir = submit_path.parent
                (stage_dir / "alpha_embedding.csv").write_text("item,dim_0\nfoo,0.2\n")
                (stage_dir / "alpha_embedding_history.csv").write_text("iter\n1\n")
                (stage_dir / "triplet_data_folded.csv").write_text("worker_id\np1\n")
                with open(stage_dir / "alpha_embedding_result.csv", "w", newline="") as f:
                    writer = csv.DictWriter(f, fieldnames=[
                        "alpha", "log_alpha", "ci_lo", "ci_hi", "n_test_fit", "n_alpha_test"])
                    writer.writeheader()
                    writer.writerow({"alpha": 2.5, "log_alpha": 0.9163, "ci_lo": 1.1,
                                      "ci_hi": 5.0, "n_test_fit": 30, "n_alpha_test": 20})

            with mock.patch.object(cw, "submit_and_wait", side_effect=fake_submit_and_wait):
                alpha, folded_path = cw.run_alpha_stage(
                    work_dir, data_path, config, seed=1, best_d=3, norm_penalty=0,
                    container_image="docker://fake")

            self.assertAlmostEqual(alpha, 2.5)
            self.assertEqual(folded_path, work_dir / "triplet_data_folded.csv")
            self.assertEqual((work_dir / "alpha_embedding.csv").read_text(), "item,dim_0\nfoo,0.2\n")
            self.assertEqual((work_dir / "alpha_history.csv").read_text(), "iter\n1\n")
            self.assertEqual((work_dir / "triplet_data_folded.csv").read_text(), "worker_id\np1\n")

            with open(work_dir / "alpha_result.csv", newline="") as f:
                rows = list(csv.DictReader(f))
            self.assertEqual(len(rows), 1)
            self.assertEqual(rows[0]["alpha"], "2.5")
            self.assertEqual(rows[0]["n_alpha_test"], "20")


class TestRunFinalFinalStage(unittest.TestCase):
    """Mirrors TestRunFinalStage: checks run_final_final_stage() reads every
    restart job's own result file, picks the lowest-loss one via
    pick_best_restart(), and copies that job's embedding/history to
    best_final_embedding.csv/best_final_embedding_history.csv -- distinct
    filenames from stage 3's best_embedding.csv, which is only the alpha=1
    warm start, not the production embedding."""

    def test_picks_lowest_loss_restart_and_writes_outputs(self):
        with tempfile.TemporaryDirectory() as tmp:
            work_dir = Path(tmp)
            folded_path = work_dir / "triplet_data_folded.csv"
            folded_path.write_text("dummy")
            config = {"final_final_fit": {"n_restarts": 3}}
            losses = {0: 0.50, 1: 0.30, 2: 0.42}  # job_index 1 (restart 2) wins

            captured_rows = {}
            real_queue_from_block = cw.queue_from_block

            def fake_queue_from_block(varnames, rows):
                captured_rows["rows"] = rows
                return real_queue_from_block(varnames, rows)

            def fake_submit_and_wait(submit_path, log_path, label):
                for restart, random_state, job_index in captured_rows["rows"]:
                    stage_dir = submit_path.parent
                    (stage_dir / f"embedding_{job_index}.csv").write_text(
                        f"item,dim_0\nfoo,{job_index}\n")
                    (stage_dir / f"embedding_{job_index}_history.csv").write_text(
                        "epoch\n0\n")
                    with open(stage_dir / f"embedding_{job_index}_result.csv",
                              "w", newline="") as f:
                        writer = csv.DictWriter(f, fieldnames=["restart", "seed", "loss"])
                        writer.writeheader()
                        writer.writerow({"restart": restart, "seed": random_state,
                                          "loss": losses[job_index]})

            with mock.patch.object(cw, "submit_and_wait", side_effect=fake_submit_and_wait), \
                 mock.patch.object(cw, "queue_from_block", side_effect=fake_queue_from_block):
                cw.run_final_final_stage(work_dir, folded_path, config, seed=1, best_d=3,
                                          alpha=2.5, norm_penalty=0,
                                          container_image="docker://fake")

            self.assertEqual((work_dir / "best_final_embedding.csv").read_text(),
                              "item,dim_0\nfoo,1\n")
            self.assertEqual((work_dir / "best_final_embedding_history.csv").read_text(),
                              "epoch\n0\n")

            with open(work_dir / "best_final_embedding_restarts.csv", newline="") as f:
                rows = list(csv.DictReader(f))
            self.assertEqual(len(rows), 3)

    def test_fixed_alpha_is_passed_through_to_every_job(self):
        with tempfile.TemporaryDirectory() as tmp:
            work_dir = Path(tmp)
            folded_path = work_dir / "triplet_data_folded.csv"
            folded_path.write_text("dummy")
            config = {"final_final_fit": {"n_restarts": 1}}
            captured = {}

            def fake_submit_and_wait(submit_path, log_path, label):
                captured["args"] = submit_path.read_text()
                stage_dir = submit_path.parent
                (stage_dir / "embedding_0.csv").write_text("item,dim_0\nfoo,0\n")
                (stage_dir / "embedding_0_history.csv").write_text("epoch\n0\n")
                with open(stage_dir / "embedding_0_result.csv", "w", newline="") as f:
                    writer = csv.DictWriter(f, fieldnames=["restart", "seed", "loss"])
                    writer.writeheader()
                    writer.writerow({"restart": 1, "seed": 1, "loss": 0.5})

            with mock.patch.object(cw, "submit_and_wait", side_effect=fake_submit_and_wait):
                cw.run_final_final_stage(work_dir, folded_path, config, seed=1, best_d=3,
                                          alpha=7.25, norm_penalty=0,
                                          container_image="docker://fake")

            self.assertIn("--stage=final_final", captured["args"])
            self.assertIn("--alpha=7.25", captured["args"])


class TestRunReportStage(unittest.TestCase):
    """run_report_stage() is a single Condor job (no restart grid, like
    run_alpha_stage()) that runs summarize_group_embedding_run() inside the
    container against whichever of stages 1-5's own output files exist in
    work_dir, then copies summary.md + summary_files/ (a directory, hence
    the transfer_output_files requirement -- see write_submit_file()) back.
    No real HTCondor cluster or R needed: submit_and_wait() is mocked."""

    def test_transfers_only_existing_input_files_and_copies_back_report(self):
        with tempfile.TemporaryDirectory() as tmp:
            work_dir = Path(tmp)
            # Only a subset of REPORT_INPUT_FILES exists -- e.g. a run with
            # run_learning_curve: false and refit_alpha: false.
            (work_dir / "run_manifest.txt").write_text("best_d: 2\n")
            (work_dir / "dimensionality_results.csv").write_text("d\n2\n")
            (work_dir / "dimensionality_summary.csv").write_text("d\n2\n")
            (work_dir / "best_embedding.csv").write_text("item,dim_0\nfoo,0.1\n")
            (work_dir / "best_embedding_history.csv").write_text("epoch\n0\n")
            (work_dir / "best_embedding_restarts.csv").write_text("restart\n1\n")
            captured = {}

            def fake_submit_and_wait(submit_path, log_path, label):
                captured["transfer_input_files"] = re.search(
                    r"^transfer_input_files\s*=\s*(.*)$", submit_path.read_text(), re.M
                ).group(1)
                captured["transfer_output_files"] = re.search(
                    r"^transfer_output_files\s*=\s*(.*)$", submit_path.read_text(), re.M
                ).group(1)
                stage_dir = submit_path.parent
                (stage_dir / "summary.md").write_text("# report\n")
                (stage_dir / "summary_files").mkdir()
                (stage_dir / "summary_files" / "fig1.png").write_text("fake png bytes")

            with mock.patch.object(cw, "submit_and_wait", side_effect=fake_submit_and_wait):
                cw.run_report_stage(work_dir, config={}, seed=1, container_image="docker://fake")

            # Files that exist are transferred in; files that don't (e.g.
            # learning_curve_*.csv, alpha_*.csv, best_final_embedding*.csv)
            # are not -- transferring a nonexistent path would fail the
            # whole submission.
            self.assertIn("dimensionality_results.csv", captured["transfer_input_files"])
            self.assertIn("best_embedding.csv", captured["transfer_input_files"])
            self.assertNotIn("alpha_result.csv", captured["transfer_input_files"])
            self.assertNotIn("best_final_embedding.csv", captured["transfer_input_files"])
            self.assertEqual(captured["transfer_output_files"], "summary.md, summary_files")

            # Regression test for a real production bug: condor_fit.R itself
            # (the script `arguments = condor_fit.R --stage=report ...` runs)
            # was never included in this stage's transfer_input_files -- every
            # other stage's build_and_submit() prepends CONDOR_FIT_R, but this
            # one built its list purely from REPORT_INPUT_FILES. The job then
            # failed near-instantly on a real CHTC deployment (Rscript can't
            # find condor_fit.R in its sandbox) and held with a confusing
            # "transfer output files failure... summary.md: No such file or
            # directory" -- summary.md was never written because the script
            # never ran, not because of any transfer-overload flakiness.
            self.assertIn(str(cw.CONDOR_FIT_R), captured["transfer_input_files"])

            self.assertEqual((work_dir / "summary.md").read_text(), "# report\n")
            self.assertEqual((work_dir / "summary_files" / "fig1.png").read_text(),
                              "fake png bytes")

    def test_skips_cleanly_when_no_stage_outputs_exist(self):
        with tempfile.TemporaryDirectory() as tmp:
            work_dir = Path(tmp)
            with mock.patch.object(cw, "submit_and_wait") as mock_submit:
                cw.run_report_stage(work_dir, config={}, seed=1, container_image="docker://fake")
            mock_submit.assert_not_called()
            self.assertFalse((work_dir / "summary.md").exists())


class TestEveryStagePassesEveryRequiredArg(unittest.TestCase):
    """Regression test for a real production bug: condor_fit.R's required-
    argument list (parsed directly from the .R source below, not duplicated
    by hand, so this can't itself drift out of sync with that file) was
    extended to require --warm_start/--alpha_test_frac/--max_outer/
    --tol_log_alpha/--alpha for every stage when stage=alpha/final_final
    were added, but run_dimensionality_stage()/run_learning_curve_stage()/
    run_final_stage()'s own submit-file arguments were never updated to
    pass them -- so every job in stages 1-3 failed immediately with
    "Missing required arguments", on a real CHTC deployment, before this was
    caught and fixed. Checks that every stage's generated `arguments =` line
    contains a --<flag>= token for each of condor_fit.R's required flags
    (job-grid variables substituted as $(...) still count, since the
    substring check only looks for "--flag=")."""

    @staticmethod
    def _required_flags():
        text = (Path(__file__).resolve().parent / "condor_fit.R").read_text()
        m = re.search(r'required <- c\((.*?)\)', text, re.S)
        return re.findall(r'"([^"]+)"', m.group(1))

    def _capture_arguments(self, run_stage_fn, stub_outputs):
        """Run a run_*_stage() function with submit_and_wait()/
        queue_from_block() mocked so no real Condor is touched; returns the
        captured submit-file `arguments =` line. `stub_outputs(stage_dir,
        rows)` must write whatever output file(s) make submit_jobs_with_retry
        see every job as done after one fake "submission"."""
        captured = {}
        real_queue_from_block = cw.queue_from_block

        def fake_queue_from_block(varnames, rows):
            captured["rows"] = rows
            return real_queue_from_block(varnames, rows)

        def fake_submit_and_wait(submit_path, log_path, label):
            text = submit_path.read_text()
            m = re.search(r"^arguments\s*=\s*(.*)$", text, re.M)
            captured["arguments"] = m.group(1)
            stub_outputs(submit_path.parent, captured.get("rows", [(None, None, 0)]))

        with mock.patch.object(cw, "submit_and_wait", side_effect=fake_submit_and_wait), \
             mock.patch.object(cw, "queue_from_block", side_effect=fake_queue_from_block):
            run_stage_fn()
        return captured["arguments"]

    def test_dimensionality_stage(self):
        with tempfile.TemporaryDirectory() as tmp:
            work_dir = Path(tmp)
            data_path = work_dir / "data.csv"
            data_path.write_text("dummy")
            config = {"dimensionality": {"dims": [2], "n_restarts": 1}}

            def stub_outputs(stage_dir, rows):
                for row in rows:
                    job_index = row[3]
                    with open(stage_dir / f"result_{job_index}.csv", "w", newline="") as f:
                        w = csv.DictWriter(f, fieldnames=[
                            "d", "restart", "loss", "accuracy", "epoch",
                            "norm_ratio", "n_fit", "n_internal_test"])
                        w.writeheader()
                        w.writerow({"d": 2, "restart": 1, "loss": 0.5, "accuracy": 0.8,
                                    "epoch": 10, "norm_ratio": 1.0, "n_fit": 5,
                                    "n_internal_test": 2})

            args = self._capture_arguments(
                lambda: cw.run_dimensionality_stage(
                    work_dir, data_path, config, seed=1, geometry="euclidean",
                    radius=1, norm_penalty=0, container_image="docker://fake"),
                stub_outputs,
            )
            for flag in self._required_flags():
                self.assertIn(f"--{flag}=", args, f"missing --{flag}= in: {args}")

    def test_learning_curve_stage(self):
        with tempfile.TemporaryDirectory() as tmp:
            work_dir = Path(tmp)
            data_path = work_dir / "data.csv"
            data_path.write_text("dummy")
            config = {"learning_curve": {"by": 1.0, "n_restarts": 1}}

            def stub_outputs(stage_dir, rows):
                for row in rows:
                    job_index = row[3]
                    with open(stage_dir / f"result_{job_index}.csv", "w", newline="") as f:
                        w = csv.DictWriter(f, fieldnames=[
                            "fraction", "n_train", "restart", "loss", "accuracy",
                            "epoch", "norm_ratio", "n_internal_test"])
                        w.writeheader()
                        w.writerow({"fraction": 1.0, "n_train": 5, "restart": 1,
                                    "loss": 0.5, "accuracy": 0.8, "epoch": 10,
                                    "norm_ratio": 1.0, "n_internal_test": 2})

            args = self._capture_arguments(
                lambda: cw.run_learning_curve_stage(
                    work_dir, data_path, config, seed=1, best_d=2, norm_penalty=0,
                    container_image="docker://fake"),
                stub_outputs,
            )
            for flag in self._required_flags():
                self.assertIn(f"--{flag}=", args, f"missing --{flag}= in: {args}")

    def test_final_stage(self):
        with tempfile.TemporaryDirectory() as tmp:
            work_dir = Path(tmp)
            data_path = work_dir / "data.csv"
            data_path.write_text("dummy")
            config = {"final_fit": {"n_restarts": 1}}

            def stub_outputs(stage_dir, rows):
                for row in rows:
                    job_index = row[2]
                    (stage_dir / f"embedding_{job_index}.csv").write_text("item,dim_0\nfoo,0\n")
                    (stage_dir / f"embedding_{job_index}_history.csv").write_text("epoch\n0\n")
                    with open(stage_dir / f"embedding_{job_index}_result.csv", "w", newline="") as f:
                        w = csv.DictWriter(f, fieldnames=["restart", "seed", "loss"])
                        w.writeheader()
                        w.writerow({"restart": 1, "seed": 1, "loss": 0.5})

            args = self._capture_arguments(
                lambda: cw.run_final_stage(
                    work_dir, data_path, config, seed=1, best_d=2, geometry="euclidean",
                    radius=1, norm_penalty=0, container_image="docker://fake"),
                stub_outputs,
            )
            for flag in self._required_flags():
                self.assertIn(f"--{flag}=", args, f"missing --{flag}= in: {args}")

    def test_alpha_stage(self):
        with tempfile.TemporaryDirectory() as tmp:
            work_dir = Path(tmp)
            data_path = work_dir / "data.csv"
            data_path.write_text("dummy")
            (work_dir / "best_embedding.csv").write_text("item,dim_0\nfoo,0.1\n")
            config = {}

            def stub_outputs(stage_dir, rows):
                (stage_dir / "alpha_embedding.csv").write_text("item,dim_0\nfoo,0.2\n")
                (stage_dir / "alpha_embedding_history.csv").write_text("iter\n1\n")
                (stage_dir / "triplet_data_folded.csv").write_text("worker_id\np1\n")
                with open(stage_dir / "alpha_embedding_result.csv", "w", newline="") as f:
                    w = csv.DictWriter(f, fieldnames=[
                        "alpha", "log_alpha", "ci_lo", "ci_hi", "n_test_fit", "n_alpha_test"])
                    w.writeheader()
                    w.writerow({"alpha": 2.5, "log_alpha": 0.9163, "ci_lo": 1.1,
                                "ci_hi": 5.0, "n_test_fit": 30, "n_alpha_test": 20})

            args = self._capture_arguments(
                lambda: cw.run_alpha_stage(
                    work_dir, data_path, config, seed=1, best_d=2, norm_penalty=0,
                    container_image="docker://fake"),
                stub_outputs,
            )
            for flag in self._required_flags():
                self.assertIn(f"--{flag}=", args, f"missing --{flag}= in: {args}")

    def test_final_final_stage(self):
        with tempfile.TemporaryDirectory() as tmp:
            work_dir = Path(tmp)
            folded_path = work_dir / "triplet_data_folded.csv"
            folded_path.write_text("dummy")
            config = {"final_final_fit": {"n_restarts": 1}}

            def stub_outputs(stage_dir, rows):
                for row in rows:
                    job_index = row[2]
                    (stage_dir / f"embedding_{job_index}.csv").write_text("item,dim_0\nfoo,0\n")
                    (stage_dir / f"embedding_{job_index}_history.csv").write_text("epoch\n0\n")
                    with open(stage_dir / f"embedding_{job_index}_result.csv", "w", newline="") as f:
                        w = csv.DictWriter(f, fieldnames=["restart", "seed", "loss"])
                        w.writeheader()
                        w.writerow({"restart": 1, "seed": 1, "loss": 0.5})

            args = self._capture_arguments(
                lambda: cw.run_final_final_stage(
                    work_dir, folded_path, config, seed=1, best_d=2, alpha=2.5,
                    norm_penalty=0, container_image="docker://fake"),
                stub_outputs,
            )
            for flag in self._required_flags():
                self.assertIn(f"--{flag}=", args, f"missing --{flag}= in: {args}")

    def test_report_stage(self):
        with tempfile.TemporaryDirectory() as tmp:
            work_dir = Path(tmp)
            (work_dir / "run_manifest.txt").write_text("best_d: 2\n")

            def stub_outputs(stage_dir, rows):
                (stage_dir / "summary.md").write_text("# report\n")
                (stage_dir / "summary_files").mkdir()

            args = self._capture_arguments(
                lambda: cw.run_report_stage(
                    work_dir, config={}, seed=1, container_image="docker://fake"),
                stub_outputs,
            )
            for flag in self._required_flags():
                self.assertIn(f"--{flag}=", args, f"missing --{flag}= in: {args}")


if __name__ == "__main__":
    unittest.main()
