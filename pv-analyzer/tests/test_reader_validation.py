"""Tests for reader and validation modules."""

import unittest
import tempfile
import os
from pv_analyzer.models import InputFormatError, Measurement
from pv_analyzer.reader import (
    normalize_header,
    map_header_to_field,
    detect_delimiter,
    read_csv_measurements,
)
from pv_analyzer.validation import validate_measurement


class TestHeaderNormalization(unittest.TestCase):
    """Test header normalization."""

    def test_normalize_voc_with_brackets(self):
        """Test 'Voc [V]' -> 'voc'."""
        result = normalize_header("Voc [V]")
        self.assertEqual(result, "voc")

    def test_normalize_pmax_with_parens(self):
        """Test 'Pmax (W)' -> 'pmax'."""
        result = normalize_header("Pmax (W)")
        self.assertEqual(result, "pmax")

    def test_normalize_module_id(self):
        """Test 'Module ID' -> 'module_id'."""
        result = normalize_header("Module ID")
        self.assertEqual(result, "module_id")

    def test_map_header_isc(self):
        """Test header mapping for isc."""
        result = map_header_to_field("Isc")
        self.assertEqual(result, "isc")

    def test_map_header_impp_alias(self):
        """Test header mapping for Impp alias 'IMP'."""
        result = map_header_to_field("IMP")
        self.assertEqual(result, "impp")

    def test_detect_comma_delimiter(self):
        """Test comma delimiter detection."""
        header_line = "ID,Isc,Voc"
        result = detect_delimiter(header_line)
        self.assertEqual(result, ",")

    def test_detect_semicolon_delimiter(self):
        """Test semicolon delimiter detection."""
        header_line = "ID;Isc;Voc"
        result = detect_delimiter(header_line)
        self.assertEqual(result, ";")

    def test_detect_tab_delimiter(self):
        """Test tab delimiter detection."""
        header_line = "ID\tIsc\tVoc"
        result = detect_delimiter(header_line)
        self.assertEqual(result, "\t")


class TestReader(unittest.TestCase):
    """Test CSV reading."""

    def test_missing_required_column(self):
        """Test error when required column missing."""
        with tempfile.NamedTemporaryFile(mode="w", suffix=".csv", delete=False) as f:
            f.write("ID,Isc,Voc,Impp\n")
            f.write("MOD-001,11.5,49.5,11.0\n")
            f.flush()
            fname = f.name
        try:
            with self.assertRaises(InputFormatError) as ctx:
                read_csv_measurements(fname)
            self.assertIn("vmpp", str(ctx.exception).lower())
        finally:
            os.unlink(fname)

    def test_empty_file(self):
        """Test error on empty file."""
        with tempfile.NamedTemporaryFile(mode="w", suffix=".csv", delete=False) as f:
            f.write("")
            f.flush()
            fname = f.name
        try:
            with self.assertRaises(InputFormatError):
                read_csv_measurements(fname)
        finally:
            os.unlink(fname)

    def test_header_only_file(self):
        """Test error on header-only file."""
        with tempfile.NamedTemporaryFile(mode="w", suffix=".csv", delete=False) as f:
            f.write("Module ID,Isc [A],Voc [V],Impp [A],Vmpp [V]\n")
            f.flush()
            fname = f.name
        try:
            with self.assertRaises(InputFormatError):
                read_csv_measurements(fname)
        finally:
            os.unlink(fname)

    def test_semicolon_delimiter_with_decimal_comma(self):
        """Test semicolon delimiter and decimal comma handling."""
        with tempfile.NamedTemporaryFile(mode="w", suffix=".csv", delete=False) as f:
            f.write("Module ID;Isc [A];Voc [V];Impp [A];Vmpp [V]\n")
            f.write("MOD-001;11,5;49,5;11,0;41,2\n")
            f.flush()
            fname = f.name
        try:
            measurements, _, _ = read_csv_measurements(fname)
            self.assertEqual(len(measurements), 1)
            self.assertAlmostEqual(measurements[0].isc, 11.5)
            self.assertAlmostEqual(measurements[0].voc, 49.5)
        finally:
            os.unlink(fname)

    def test_utf8_bom_header(self):
        """Test UTF-8 BOM handling."""
        with tempfile.NamedTemporaryFile(mode="wb", suffix=".csv", delete=False) as f:
            # Write UTF-8 BOM + CSV
            f.write(b"\xef\xbb\xbf")
            f.write(b"Module ID,Isc [A],Voc [V],Impp [A],Vmpp [V]\n")
            f.write(b"MOD-001,11.5,49.5,11.0,41.2\n")
            f.flush()
            fname = f.name
        try:
            measurements, _, _ = read_csv_measurements(fname)
            self.assertEqual(len(measurements), 1)
            self.assertEqual(measurements[0].module_id, "MOD-001")
        finally:
            os.unlink(fname)

    def test_row_numbers(self):
        """Test that row numbers are correct (first data row = 2)."""
        with tempfile.NamedTemporaryFile(mode="w", suffix=".csv", delete=False) as f:
            f.write("Module ID,Isc [A],Voc [V],Impp [A],Vmpp [V]\n")
            f.write("MOD-001,11.5,49.5,11.0,41.2\n")
            f.write("MOD-002,11.6,49.6,11.1,41.3\n")
            f.flush()
            fname = f.name
        try:
            measurements, _, _ = read_csv_measurements(fname)
            self.assertEqual(measurements[0].row_number, 2)
            self.assertEqual(measurements[1].row_number, 3)
        finally:
            os.unlink(fname)

    def test_skip_empty_rows(self):
        """Test that completely empty rows are skipped."""
        with tempfile.NamedTemporaryFile(mode="w", suffix=".csv", delete=False) as f:
            f.write("Module ID,Isc [A],Voc [V],Impp [A],Vmpp [V]\n")
            f.write("MOD-001,11.5,49.5,11.0,41.2\n")
            f.write(",,,,\n")  # Completely empty row
            f.write("MOD-002,11.6,49.6,11.1,41.3\n")
            f.flush()
            fname = f.name
        try:
            measurements, _, _ = read_csv_measurements(fname)
            # Should have 2 measurements (empty row skipped)
            self.assertEqual(len(measurements), 2)
            self.assertEqual(measurements[0].module_id, "MOD-001")
            self.assertEqual(measurements[1].module_id, "MOD-002")
            # Row numbers should reflect file lines
            self.assertEqual(measurements[0].row_number, 2)
            self.assertEqual(measurements[1].row_number, 4)  # Skipped row 3
        finally:
            os.unlink(fname)


class TestValidation(unittest.TestCase):
    """Test row validation."""

    def test_non_numeric_value(self):
        """Test error on non-numeric value."""
        meas = Measurement(
            row_number=2,
            module_id="MOD-001",
            isc="abc",
            voc=49.5,
            impp=11.0,
            vmpp=41.2,
        )
        seen = {}
        issues = validate_measurement(meas, seen)
        self.assertTrue(any(i.code == "not_a_number" for i in issues))

    def test_missing_value(self):
        """Test error on missing required value."""
        meas = Measurement(
            row_number=2,
            module_id="MOD-001",
            isc=None,
            voc=49.5,
            impp=11.0,
            vmpp=41.2,
        )
        seen = {}
        issues = validate_measurement(meas, seen)
        self.assertTrue(any(i.code == "missing_value" for i in issues))

    def test_negative_value(self):
        """Test error on negative value."""
        meas = Measurement(
            row_number=2,
            module_id="MOD-001",
            isc=-11.5,
            voc=49.5,
            impp=11.0,
            vmpp=41.2,
        )
        seen = {}
        issues = validate_measurement(meas, seen)
        self.assertTrue(any(i.code == "non_positive" for i in issues))

    def test_impp_gt_isc(self):
        """Test error when impp > isc."""
        meas = Measurement(
            row_number=2,
            module_id="MOD-001",
            isc=10.0,
            voc=49.5,
            impp=11.0,  # > isc
            vmpp=41.2,
        )
        seen = {}
        issues = validate_measurement(meas, seen)
        self.assertTrue(any(i.code == "impp_gt_isc" for i in issues))

    def test_vmpp_gt_voc(self):
        """Test error when vmpp > voc."""
        meas = Measurement(
            row_number=2,
            module_id="MOD-001",
            isc=11.5,
            voc=40.0,
            impp=11.0,
            vmpp=41.2,  # > voc
        )
        seen = {}
        issues = validate_measurement(meas, seen)
        self.assertTrue(any(i.code == "vmpp_gt_voc" for i in issues))

    def test_duplicate_id(self):
        """Test error on duplicate module_id."""
        seen = {"MOD-001": 2}
        meas = Measurement(
            row_number=3,
            module_id="MOD-001",
            isc=11.5,
            voc=49.5,
            impp=11.0,
            vmpp=41.2,
        )
        issues = validate_measurement(meas, seen)
        self.assertTrue(any(i.code == "duplicate_id" for i in issues))
        self.assertIn("row 2", issues[0].message)

    def test_valid_row(self):
        """Test that valid row has no errors."""
        meas = Measurement(
            row_number=2,
            module_id="MOD-001",
            isc=11.5,
            voc=49.5,
            impp=11.0,
            vmpp=41.2,
        )
        seen = {}
        issues = validate_measurement(meas, seen)
        self.assertEqual(len(issues), 0)


if __name__ == "__main__":
    unittest.main()
