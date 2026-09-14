"""Unit tests for condor_recovery_sweep_workflow.py's pure logic (synthetic
ground-truth/triplet generation, CSV I/O, result aggregation) -- everything
that doesn't require a real HTCondor cluster or condor_submit/condor_wait.

Run locally with:
    python3 -m unittest inst/condor/test_condor_recovery_sweep_workflow.py -v

Plain unittest (stdlib only, no extra dependency beyond PyYAML). Not
invoked by devtools::test()/R CMD check -- a developer-facing check for
the Python side of this Condor workflow.
"""
import csv
import math
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import condor_recovery_sweep_workflow as rs  # noqa: E402


class TestAlphaLabel(unittest.TestCase):
    def test_finite(self):
        self.assertEqual(rs.alpha_label(1.0), "1.0")
        self.assertEqual(rs.alpha_label(0.5), "0.5")

    def test_infinite(self):
        self.assertEqual(rs.alpha_label(float("inf")), "Inf")


class TestChoiceProb(unittest.TestCase):
    def test_closer_option_is_more_likely_to_win(self):
        p = rs.choice_prob(dA2=1.0, dB2=9.0, alpha=2.0)
        self.assertGreater(p, 0.5)

    def test_symmetric_when_equidistant(self):
        p = rs.choice_prob(dA2=4.0, dB2=4.0, alpha=2.0)
        self.assertAlmostEqual(p, 0.5)

    def test_alpha_1_matches_student_t_formula(self):
        p = rs.choice_prob(dA2=2.0, dB2=5.0, alpha=1.0)
        tA = (1 + 2.0) ** (-1.0)
        tB = (1 + 5.0) ** (-1.0)
        self.assertAlmostEqual(p, tA / (tA + tB))

    def test_infinite_alpha_is_gaussian_limit(self):
        p = rs.choice_prob(dA2=2.0, dB2=5.0, alpha=float("inf"))
        expected = 1 / (1 + math.exp(0.5 * (2.0 - 5.0)))
        self.assertAlmostEqual(p, expected)


class TestSyntheticEmbedding(unittest.TestCase):
    def test_item_count_and_reproducibility(self):
        items1 = rs.make_synthetic_embedding(3, 2, 4, 12.0, 2.5, 0.3, seed=7)
        items2 = rs.make_synthetic_embedding(3, 2, 4, 12.0, 2.5, 0.3, seed=7)
        self.assertEqual(len(items1), 24)
        self.assertEqual([name for name, _c in items1], [name for name, _c in items2])
        for (n1, c1), (n2, c2) in zip(items1, items2):
            self.assertEqual(n1, n2)
            self.assertEqual(c1, c2)

    def test_different_seeds_differ(self):
        items1 = rs.make_synthetic_embedding(3, 2, 4, 12.0, 2.5, 0.3, seed=1)
        items2 = rs.make_synthetic_embedding(3, 2, 4, 12.0, 2.5, 0.3, seed=2)
        self.assertNotEqual([c for _n, c in items1], [c for _n, c in items2])

    def test_hierarchical_scale_ordering(self):
        # Within-subcluster distances should be smaller than
        # between-supercluster distances given the default scale params.
        items = rs.make_synthetic_embedding(5, 2, 5, 12.0, 2.5, 0.3, seed=1)
        coords = [c for _n, c in items]

        def dist(i, j):
            return math.sqrt(sum((coords[i][k] - coords[j][k]) ** 2 for k in range(3)))

        within_sub = dist(0, 1)          # same subcluster
        between_super = dist(0, len(coords) - 1)  # different superclusters
        self.assertLess(within_sub, between_super)

    def test_dimensionality_follows_d(self):
        # Ground truth dimensionality must track the fit dimensionality `d`
        # -- get.rep.dist()'s Procrustes comparison requires the two to
        # match, so this can't be hardcoded to 3D.
        items = rs.make_synthetic_embedding(3, 2, 4, 12.0, 2.5, 0.3, seed=1, d=5)
        for _name, coords in items:
            self.assertEqual(len(coords), 5)


class TestSimulateTriplets(unittest.TestCase):
    def test_shape_and_index_validity(self):
        coords = [[0.0, 0.0, 0.0], [1.0, 0.0, 0.0], [5.0, 0.0, 0.0], [10.0, 0.0, 0.0]]
        rows = rs.simulate_triplets(coords, alpha=2.0, n_triplets=50, seed=1)
        self.assertEqual(len(rows), 50)
        for h, w, l in rows:
            self.assertTrue(0 <= h < 4 and 0 <= w < 4 and 0 <= l < 4)
            self.assertNotEqual(h, w)
            self.assertNotEqual(h, l)
            self.assertNotEqual(w, l)

    def test_reproducible_with_same_seed(self):
        coords = [[0.0, 0.0, 0.0], [1.0, 0.0, 0.0], [5.0, 0.0, 0.0], [10.0, 0.0, 0.0]]
        rows1 = rs.simulate_triplets(coords, alpha=2.0, n_triplets=20, seed=42)
        rows2 = rs.simulate_triplets(coords, alpha=2.0, n_triplets=20, seed=42)
        self.assertEqual(rows1, rows2)

    def test_prefers_closer_item_more_often(self):
        # A 3-item embedding where item0 (head) is far closer to item1 than
        # to item2 -- across many simulated triplets with item1/item2 as
        # the two options, item1 should win clearly more than half the time.
        coords = [[0.0, 0.0, 0.0], [0.1, 0.0, 0.0], [20.0, 0.0, 0.0]]
        rows = rs.simulate_triplets(coords, alpha=2.0, n_triplets=2000, seed=1)
        relevant = [(w, l) for h, w, l in rows if h == 0]
        wins_item1 = sum(1 for w, _l in relevant if w == 1)
        self.assertGreater(wins_item1 / len(relevant), 0.9)


class TestCsvIO(unittest.TestCase):
    def test_ground_truth_round_trip(self):
        items = [("item1", [1.0, 2.0, 3.0]), ("item2", [4.0, 5.0, 6.0])]
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "gt.csv"
            rs.write_ground_truth_csv(path, items)
            with open(path, newline="") as f:
                rows = list(csv.DictReader(f))
            self.assertEqual(rows[0]["item"], "item1")
            self.assertEqual(float(rows[0]["dim_0"]), 1.0)
            self.assertEqual(float(rows[1]["dim_2"]), 6.0)

    def test_ground_truth_header_follows_dimensionality(self):
        items = [("item1", [1.0, 2.0]), ("item2", [3.0, 4.0])]
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "gt2d.csv"
            rs.write_ground_truth_csv(path, items)
            with open(path, newline="") as f:
                header = next(csv.reader(f))
            self.assertEqual(header, ["item", "dim_0", "dim_1"])

    def test_triplets_round_trip(self):
        rows = [(0, 1, 2), (3, 4, 5)]
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "trips.csv"
            rs.write_triplets_csv(path, rows)
            with open(path, newline="") as f:
                out = list(csv.DictReader(f))
            self.assertEqual(out[0]["head"], "0")
            self.assertEqual(out[1]["loser"], "5")


class TestAggregateResults(unittest.TestCase):
    def _make_job_output(self, stage1_dir, output_name, gen_alpha, fit_alpha, error):
        with open(stage1_dir / output_name, "w", newline="") as f:
            writer = csv.writer(f)
            writer.writerow(["gen_alpha", "fit_alpha", "recovery_error", "loss", "epoch"])
            writer.writerow([gen_alpha, fit_alpha, error, 0.45, 1000])

    def test_aggregate_builds_long_and_matrix_outputs(self):
        with tempfile.TemporaryDirectory() as tmp:
            work_dir = Path(tmp)
            stage1_dir = work_dir / "stage1_fit"
            stage1_dir.mkdir()

            alphas = [1.0, 2.0]
            jobs = [
                ("../stage0_simulate/triplets_gen1.0.csv", "triplets_gen1.0.csv",
                 "r_g0f0.csv", "1.0", "1.0", 101),
                ("../stage0_simulate/triplets_gen1.0.csv", "triplets_gen1.0.csv",
                 "r_g0f1.csv", "1.0", "2.0", 102),
                ("../stage0_simulate/triplets_gen2.0.csv", "triplets_gen2.0.csv",
                 "r_g1f0.csv", "2.0", "1.0", 103),
                ("../stage0_simulate/triplets_gen2.0.csv", "triplets_gen2.0.csv",
                 "r_g1f1.csv", "2.0", "2.0", 104),
            ]
            self._make_job_output(stage1_dir, "r_g0f0.csv", "1.0", "1.0", 0.05)
            self._make_job_output(stage1_dir, "r_g0f1.csv", "1.0", "2.0", 0.20)
            self._make_job_output(stage1_dir, "r_g1f0.csv", "2.0", "1.0", 0.25)
            self._make_job_output(stage1_dir, "r_g1f1.csv", "2.0", "2.0", 0.04)

            long_path, matrix_path = rs.aggregate_results(work_dir, stage1_dir, jobs, alphas)

            with open(long_path, newline="") as f:
                long_rows = list(csv.DictReader(f))
            self.assertEqual(len(long_rows), 4)

            with open(matrix_path, newline="") as f:
                matrix_rows = list(csv.reader(f))
            self.assertEqual(matrix_rows[0], ["", "fit_1.0", "fit_2.0"])
            self.assertEqual(matrix_rows[1][0], "gen_1.0")
            self.assertEqual(matrix_rows[1][1], "0.05")  # matched diagonal cell
            self.assertEqual(matrix_rows[2][2], "0.04")  # matched diagonal cell

    def test_aggregate_exits_on_missing_output(self):
        with tempfile.TemporaryDirectory() as tmp:
            work_dir = Path(tmp)
            stage1_dir = work_dir / "stage1_fit"
            stage1_dir.mkdir()
            jobs = [("src.csv", "src.csv", "missing.csv", "1.0", "1.0", 1)]
            with self.assertRaises(SystemExit):
                rs.aggregate_results(work_dir, stage1_dir, jobs, [1.0])


if __name__ == "__main__":
    unittest.main()
