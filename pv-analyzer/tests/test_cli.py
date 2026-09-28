"""Tests for CLI."""

import unittest
import tempfile
import os
import json
from pv_analyzer.cli import main


class TestCLI(unittest.TestCase):
    """Test CLI functionality."""

    def setUp(self):
        """Create a test CSV file."""
        self.test_dir = tempfile.mkdtemp()

        # Create a clean 5-row file (no warnings)
        self.clean_file = os.path.join(self.test_dir, "clean.csv")
        with open(self.clean_file, "w") as f:
            f.write("Module ID,Isc [A],Voc [V],Impp [A],Vmpp [V],Nameplate [W],Irradiance [W/m2],T [C]\n")
            f.write("MOD-001,11.5,49.5,11.0,41.2,450,1000,25\n")
            f.write("MOD-002,11.6,49.6,11.1,41.3,450,1000,25\n")
            f.write("MOD-003,11.5,49.4,11.0,41.1,450,1000,25\n")
            f.write("MOD-004,11.6,49.5,11.05,41.2,450,1000,25\n")
            f.write("MOD-005,11.55,49.5,11.0,41.15,450,1000,25\n")

        # Create a file with errors and warnings
        self.problem_file = os.path.join(self.test_dir, "problems.csv")
        with open(self.problem_file, "w") as f:
            f.write("Module ID,Isc [A],Voc [V],Impp [A],Vmpp [V],Nameplate [W]\n")
            f.write("MOD-001,11.5,49.5,11.0,41.2,450\n")  # OK
            f.write("MOD-002,,49.5,11.0,41.2,450\n")  # Missing Isc (error)
            f.write("MOD-001,11.6,49.6,11.1,41.3,450\n")  # Duplicate (error)
            f.write("MOD-004,11.6,49.5,11.05,41.2,450\n")  # OK
            f.write("MOD-005,12.0,49.5,11.0,41.2,450\n")  # Impp close to Isc (warning)
            f.write("MOD-006,9.0,49.5,8.5,41.0,450\n")  # Low power (warning/outlier)

    def tearDown(self):
        """Clean up temp files."""
        import shutil
        shutil.rmtree(self.test_dir)

    def test_clean_file_exit_code_0(self):
        """Test clean file returns exit code 0."""
        exit_code = main([self.clean_file, "--quiet"])
        self.assertEqual(exit_code, 0)

    def test_problem_file_exit_code_1(self):
        """Test problem file returns exit code 1."""
        exit_code = main([self.problem_file, "--quiet"])
        self.assertEqual(exit_code, 1)

    def test_missing_file_exit_code_2(self):
        """Test missing file returns exit code 2."""
        exit_code = main(["/nonexistent/file.csv", "--quiet"])
        self.assertEqual(exit_code, 2)

    def test_csv_output(self):
        """Test CSV output generation."""
        output_csv = os.path.join(self.test_dir, "output.csv")
        main([self.problem_file, "--output", output_csv, "--quiet"])

        self.assertTrue(os.path.exists(output_csv))
        with open(output_csv, "r") as f:
            lines = f.readlines()
        # Header + 6 data rows
        self.assertEqual(len(lines), 7)
        self.assertIn("ERROR", lines[2])  # Row 3 is missing value
        self.assertIn("ERROR", lines[3])  # Row 4 is duplicate

    def test_json_output(self):
        """Test JSON output generation."""
        output_json = os.path.join(self.test_dir, "output.json")
        main([self.problem_file, "--output", "/dev/null", "--json", output_json, "--quiet"])

        self.assertTrue(os.path.exists(output_json))
        with open(output_json, "r") as f:
            data = json.load(f)

        self.assertIn("version", data)
        self.assertIn("config", data)
        self.assertIn("summary", data)
        self.assertIn("results", data)
        self.assertEqual(len(data["results"]), 6)  # 6 rows

    def test_rejected_rows_in_output(self):
        """Test that rejected rows have ERROR status."""
        output_csv = os.path.join(self.test_dir, "output.csv")
        main([self.problem_file, "--output", output_csv, "--quiet"])

        with open(output_csv, "r") as f:
            lines = f.readlines()

        # Check that rejected rows have ERROR status
        csv_rows = lines[1:]  # Skip header
        # Row 2 (index 1): missing Isc
        self.assertIn("ERROR", csv_rows[1])
        # Row 3 (index 2): duplicate ID
        self.assertIn("ERROR", csv_rows[2])

    def test_std_n_equals_1(self):
        """Test that std=n/a when n==1 in batch statistics."""
        # Create a single-row file
        single_file = os.path.join(self.test_dir, "single.csv")
        with open(single_file, "w") as f:
            f.write("Module ID,Isc [A],Voc [V],Impp [A],Vmpp [V],Irradiance [W/m2],T [C],Nameplate [W]\n")
            f.write("MOD-001,11.5,49.5,11.0,41.2,1000,25,450\n")

        # Capture output
        import io
        import sys
        old_stdout = sys.stdout
        sys.stdout = io.StringIO()

        try:
            # Run without --quiet to capture statistics output
            main([single_file])
            output = sys.stdout.getvalue()
        finally:
            sys.stdout = old_stdout

        # Check that "std=n/a" appears in the output (not "std=0.0")
        # Since we only have 1 valid module, std should be n/a
        self.assertIn("std=n/a", output)
        self.assertNotIn("std=0.0", output)


if __name__ == "__main__":
    unittest.main()
