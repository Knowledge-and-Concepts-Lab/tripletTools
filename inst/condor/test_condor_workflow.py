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
import statistics
import sys
import tempfile
import unittest
from pathlib import Path

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


if __name__ == "__main__":
    unittest.main()
