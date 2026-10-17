"""Unit tests for condor_recovery_sweep_refit_capped.py's pure logic --
everything that doesn't require a real HTCondor cluster.

Run locally with:
    python3 -m unittest inst/condor/test_condor_recovery_sweep_refit_capped.py -v

Plain unittest (stdlib only, no extra dependency beyond PyYAML). Not
invoked by devtools::test()/R CMD check -- a developer-facing check for
the Python side of this Condor workflow.
"""
import csv
import sys
import tempfile
import unittest
import unittest.mock as mock
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import condor_recovery_sweep_refit_capped as refit  # noqa: E402
import condor_recovery_sweep_workflow as rs  # noqa: E402


def write_long_csv(path, rows):
    with open(path, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=["replicate", "gen_alpha", "fit_alpha",
                                                "recovery_error", "loss", "epoch"])
        writer.writeheader()
        writer.writerows(rows)


class TestFindCappedRows(unittest.TestCase):
    def test_infers_old_max_epochs_and_capped_rows(self):
        rows = [
            {"replicate": "0", "gen_alpha": "1.0", "fit_alpha": "1.0",
             "recovery_error": "0.2", "loss": "0.5", "epoch": "59999"},
            {"replicate": "0", "gen_alpha": "1.0", "fit_alpha": "2.0",
             "recovery_error": "0.3", "loss": "0.5", "epoch": "4200"},
            {"replicate": "1", "gen_alpha": "1.0", "fit_alpha": "1.0",
             "recovery_error": "0.25", "loss": "0.5", "epoch": "60000"},
        ]
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "results_long.csv"
            write_long_csv(path, rows)
            all_rows, capped, old_max = refit.find_capped_rows(path)
            self.assertEqual(len(all_rows), 3)
            self.assertEqual(old_max, 60000)
            # epoch>=59999 (old_max - 1) -- both the 59999 and 60000 rows
            self.assertEqual(len(capped), 2)
            self.assertEqual({r["epoch"] for r in capped}, {"59999", "60000"})

    def test_empty_file_errors(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "results_long.csv"
            write_long_csv(path, [])
            with self.assertRaises(SystemExit):
                refit.find_capped_rows(path)


class TestBuildRefitJobs(unittest.TestCase):
    def test_reconstructs_jobs_with_correct_seed_and_paths(self):
        alphas = [1.0, 2.0, float("inf")]
        capped_rows = [
            {"replicate": "2", "gen_alpha": "1.0", "fit_alpha": "2.0",
             "recovery_error": "0.3", "loss": "0.5", "epoch": "59999"},
        ]
        jobs = refit.build_refit_jobs(capped_rows, alphas, seed=1)
        self.assertEqual(len(jobs), 1)
        (triplets_src, triplets_name, gt_src, gt_name, output_name,
         rep, gen_label, fit_label, fit_seed) = jobs[0]

        self.assertEqual(rep, 2)
        self.assertEqual(gen_label, "1.0")
        self.assertEqual(fit_label, "2.0")
        self.assertEqual(gt_name, "ground_truth_rep2.csv")
        self.assertEqual(triplets_name, "triplets_rep2_gen1.0.csv")
        self.assertEqual(gt_src, "../stage0_simulate/ground_truth_rep2.csv")
        self.assertEqual(triplets_src, "../stage0_simulate/triplets_rep2_gen1.0.csv")
        # gi=0 (gen=1.0 is position 0), fi=1 (fit=2.0 is position 1)
        self.assertEqual(output_name, "result_rep2_gen0fit1.csv")
        # Must match run_fit_stage()'s own formula exactly:
        # rep_seed = seed + r*STRIDE; fit_seed = rep_seed + gi*100 + fi
        expected_fit_seed = 1 + 2 * rs.REPLICATE_SEED_STRIDE + 0 * 100 + 1
        self.assertEqual(fit_seed, expected_fit_seed)

    def test_seed_matches_original_run_fit_stage_formula_exactly(self):
        # Build the SAME cell both ways (via the real orchestrator's
        # simulate_stage/run_fit_stage, and via build_refit_jobs) and
        # confirm the fit_seed comes out identical -- this is the whole
        # point of the tool (retrace the same initialization/split).
        alphas = [0.5, 1.0]
        with tempfile.TemporaryDirectory() as tmp:
            work_dir = Path(tmp)
            config = {"d": 2, "alphas": alphas, "n_triplets_per_gen": 5, "seed": 7,
                      "n_replicates": 2,
                      "synthetic_embedding": {"n_super": 2, "n_sub_per_super": 1, "n_items_per_sub": 3}}
            replicates = rs.simulate_stage(work_dir, config)
            with mock.patch.object(rs, "submit_jobs_with_retry"):
                _stage_dir, real_jobs = rs.run_fit_stage(work_dir, replicates, config, {},
                                                          "docker://example:latest")
            # pick the (rep=1, gen=0.5, fit=1.0) cell from the real jobs
            real_job = next(j for j in real_jobs if j[5] == 1 and j[6] == "0.5" and j[7] == "1.0")
            real_fit_seed = real_job[8]

            capped_row = {"replicate": "1", "gen_alpha": "0.5", "fit_alpha": "1.0",
                          "recovery_error": "0.3", "loss": "0.5", "epoch": "999"}
            refit_jobs = refit.build_refit_jobs([capped_row], alphas, seed=7)
            self.assertEqual(refit_jobs[0][8], real_fit_seed)


class TestMergeAndWrite(unittest.TestCase):
    def _write_refit_output(self, stage_dir, output_name, rep, gen, fit, error, loss, epoch):
        with open(stage_dir / output_name, "w", newline="") as f:
            writer = csv.writer(f)
            writer.writerow(["replicate", "gen_alpha", "fit_alpha", "recovery_error", "loss", "epoch"])
            writer.writerow([rep, gen, fit, error, loss, epoch])

    def test_merge_replaces_only_capped_rows(self):
        alphas = [1.0, 2.0]
        all_rows = [
            {"replicate": "0", "gen_alpha": "1.0", "fit_alpha": "1.0",
             "recovery_error": "0.50", "loss": "0.5", "epoch": "999"},  # capped, will be replaced
            {"replicate": "0", "gen_alpha": "1.0", "fit_alpha": "2.0",
             "recovery_error": "0.20", "loss": "0.5", "epoch": "4000"},  # untouched
            {"replicate": "0", "gen_alpha": "2.0", "fit_alpha": "1.0",
             "recovery_error": "0.30", "loss": "0.5", "epoch": "3000"},  # untouched
            {"replicate": "0", "gen_alpha": "2.0", "fit_alpha": "2.0",
             "recovery_error": "0.10", "loss": "0.5", "epoch": "2000"},  # untouched
        ]
        capped_rows = [all_rows[0]]

        with tempfile.TemporaryDirectory() as tmp:
            work_dir = Path(tmp)
            stage_refit_dir = work_dir / "stage_refit"
            stage_refit_dir.mkdir()
            # gen=1.0 is index 0, fit=1.0 is index 0 -> result_rep0_gen0fit0.csv
            self._write_refit_output(stage_refit_dir, "result_rep0_gen0fit0.csv",
                                      0, "1.0", "1.0", 0.21, 0.45, 150000)

            long_path, mean_path, sd_path, n_replaced = refit.merge_and_write(
                work_dir, all_rows, capped_rows, stage_refit_dir, alphas)

            self.assertEqual(n_replaced, 1)
            with open(long_path, newline="") as f:
                merged = list(csv.DictReader(f))
            self.assertEqual(len(merged), 4)
            replaced = next(r for r in merged if r["gen_alpha"] == "1.0" and r["fit_alpha"] == "1.0")
            self.assertEqual(replaced["recovery_error"], "0.21")
            self.assertEqual(replaced["epoch"], "150000")
            untouched = next(r for r in merged if r["gen_alpha"] == "1.0" and r["fit_alpha"] == "2.0")
            self.assertEqual(untouched["recovery_error"], "0.20")

            with open(mean_path, newline="") as f:
                mean_rows = list(csv.reader(f))
            self.assertEqual(mean_rows[0], ["", "fit_1.0", "fit_2.0"])
            # gen=1.0/fit=1.0 cell should reflect the REPLACED value, not the original
            self.assertEqual(mean_rows[1][1], "0.21")

    def test_merge_exits_on_missing_refit_output(self):
        alphas = [1.0]
        all_rows = [{"replicate": "0", "gen_alpha": "1.0", "fit_alpha": "1.0",
                     "recovery_error": "0.5", "loss": "0.5", "epoch": "999"}]
        with tempfile.TemporaryDirectory() as tmp:
            work_dir = Path(tmp)
            stage_refit_dir = work_dir / "stage_refit"
            stage_refit_dir.mkdir()
            with self.assertRaises(SystemExit):
                refit.merge_and_write(work_dir, all_rows, all_rows, stage_refit_dir, alphas)


if __name__ == "__main__":
    unittest.main()
