"""Tests for anomaly detection."""

import unittest
from pv_analyzer.models import Measurement, Result, AnalysisConfig, Issue
from pv_analyzer.anomalies import detect_rule_based_anomalies, detect_statistical_anomalies


class TestAnomalies(unittest.TestCase):
    """Test anomaly detection."""

    def test_ff_out_of_range(self):
        """Test FF out of range warning."""
        config = AnalysisConfig(ff_min=0.60, ff_max=0.86)
        meas = Measurement(
            row_number=2,
            module_id="MOD-001",
            isc=10.0,
            voc=50.0,
            impp=9.0,
            vmpp=40.0,
        )
        result = Result(measurement=meas)
        result.fill_factor = 0.72  # OK
        result.isc_stc = 10.0
        result.voc_stc = 50.0
        result.pmpp_stc = 288.0
        result.ff_stc = 0.576  # Out of range

        detect_rule_based_anomalies(result, config)
        self.assertTrue(any(i.code == "ff_out_of_range" for i in result.issues))

    def test_ff_impossible(self):
        """Test FF > 1.0 error."""
        config = AnalysisConfig(ff_min=0.60, ff_max=0.86)
        meas = Measurement(
            row_number=2,
            module_id="MOD-001",
            isc=10.0,
            voc=50.0,
            impp=9.0,
            vmpp=40.0,
        )
        result = Result(measurement=meas)
        result.fill_factor = 0.72
        result.ff_stc = 1.05  # Impossible

        detect_rule_based_anomalies(result, config)
        self.assertTrue(any(i.code == "ff_impossible" and i.severity == "error" for i in result.issues))

    def test_pmpp_inconsistent(self):
        """Test pmpp inconsistency warning."""
        config = AnalysisConfig(pmpp_consistency_tol_pct=1.0)
        meas = Measurement(
            row_number=2,
            module_id="MOD-001",
            isc=11.0,
            voc=49.5,
            impp=11.0,
            vmpp=41.0,
            pmpp=460.0,  # Inconsistent with impp*vmpp
        )
        result = Result(measurement=meas)
        result.p_calc = 451.0  # impp * vmpp
        result.pmpp_consistency_pct = (460.0 - 451.0) / 451.0 * 100  # ~2%

        detect_rule_based_anomalies(result, config)
        self.assertTrue(any(i.code == "pmpp_inconsistent" for i in result.issues))

    def test_irradiance_out_of_range(self):
        """Test irradiance out of range warning."""
        config = AnalysisConfig(irradiance_min=700.0, irradiance_max=1300.0)
        meas = Measurement(
            row_number=2,
            module_id="MOD-001",
            isc=11.0,
            voc=49.5,
            impp=11.0,
            vmpp=41.0,
            irradiance=600.0,  # Below min
        )
        result = Result(measurement=meas)
        detect_rule_based_anomalies(result, config)
        self.assertTrue(any(i.code == "irradiance_out_of_range" for i in result.issues))

    def test_temperature_out_of_range(self):
        """Test temperature out of range warning."""
        config = AnalysisConfig(temp_min=15.0, temp_max=35.0)
        meas = Measurement(
            row_number=2,
            module_id="MOD-001",
            isc=11.0,
            voc=49.5,
            impp=11.0,
            vmpp=41.0,
            temperature=40.0,  # Above max
        )
        result = Result(measurement=meas)
        detect_rule_based_anomalies(result, config)
        self.assertTrue(any(i.code == "temperature_out_of_range" for i in result.issues))

    def test_power_below_tolerance(self):
        """Test power below tolerance warning."""
        config = AnalysisConfig(power_tolerance_minus_pct=3.0, power_tolerance_plus_pct=3.0)
        meas = Measurement(
            row_number=2,
            module_id="MOD-001",
            isc=11.0,
            voc=49.5,
            impp=11.0,
            vmpp=41.0,
            nameplate_power=450.0,
        )
        result = Result(measurement=meas)
        result.pmpp_stc = 435.0  # 3.3% below nameplate
        result.power_deviation_pct = (435.0 - 450.0) / 450.0 * 100

        detect_rule_based_anomalies(result, config)
        self.assertTrue(any(i.code == "below_power_tolerance" for i in result.issues))

    def test_power_above_tolerance(self):
        """Test power above tolerance warning."""
        config = AnalysisConfig(power_tolerance_minus_pct=0.0, power_tolerance_plus_pct=3.0)
        meas = Measurement(
            row_number=2,
            module_id="MOD-001",
            isc=11.0,
            voc=49.5,
            impp=11.0,
            vmpp=41.0,
            nameplate_power=450.0,
        )
        result = Result(measurement=meas)
        result.pmpp_stc = 465.0  # 3.3% above nameplate
        result.power_deviation_pct = (465.0 - 450.0) / 450.0 * 100

        detect_rule_based_anomalies(result, config)
        self.assertTrue(any(i.code == "above_power_tolerance" for i in result.issues))

    def test_statistical_outlier_detected(self):
        """Test statistical outlier detection in batch."""
        config = AnalysisConfig(robust_z_threshold=3.5, min_rows_for_statistics=5)

        # Create 8 results with one low value
        results = []
        values = [450.0, 451.0, 450.5, 452.0, 451.5, 450.8, 451.2, 400.0]  # Last one is outlier

        for i, val in enumerate(values):
            meas = Measurement(
                row_number=i + 2,
                module_id=f"MOD-{i:03d}",
                isc=11.0,
                voc=49.5,
                impp=11.0,
                vmpp=41.0,
            )
            result = Result(measurement=meas)
            result.pmpp_stc = val
            result.fill_factor = 0.72
            result.ff_stc = 0.72
            result.isc_stc = 11.0
            result.voc_stc = 49.5
            results.append(result)

        detect_statistical_anomalies(results, config)

        # Last result should have statistical outlier issue
        outlier_issues = [i for i in results[-1].issues if i.code == "statistical_outlier"]
        self.assertTrue(len(outlier_issues) > 0)

    def test_statistical_outlier_mad_zero(self):
        """Test MAD == 0 (all same value) -> no outliers."""
        config = AnalysisConfig(robust_z_threshold=3.5, min_rows_for_statistics=5)

        # Create 5 results with all same value
        results = []
        for i in range(5):
            meas = Measurement(
                row_number=i + 2,
                module_id=f"MOD-{i:03d}",
                isc=11.0,
                voc=49.5,
                impp=11.0,
                vmpp=41.0,
            )
            result = Result(measurement=meas)
            result.pmpp_stc = 450.0  # All same
            result.fill_factor = 0.72
            result.ff_stc = 0.72
            result.isc_stc = 11.0
            result.voc_stc = 49.5
            results.append(result)

        # Should not crash and should not add issues
        detect_statistical_anomalies(results, config)
        for result in results:
            self.assertTrue(all(i.code != "statistical_outlier" for i in result.issues))

    def test_statistical_outlier_skipped_when_n_small(self):
        """Test statistical check skipped when n < min_rows."""
        config = AnalysisConfig(robust_z_threshold=3.5, min_rows_for_statistics=5)

        # Create only 3 results
        results = []
        for i in range(3):
            meas = Measurement(
                row_number=i + 2,
                module_id=f"MOD-{i:03d}",
                isc=11.0,
                voc=49.5,
                impp=11.0,
                vmpp=41.0,
            )
            result = Result(measurement=meas)
            result.pmpp_stc = 400.0 if i == 0 else 450.0  # First is outlier
            result.fill_factor = 0.72
            result.ff_stc = 0.72
            result.isc_stc = 11.0
            result.voc_stc = 49.5
            results.append(result)

        # Should not add outlier issues (n < 5)
        detect_statistical_anomalies(results, config)
        for result in results:
            self.assertTrue(all(i.code != "statistical_outlier" for i in result.issues))


if __name__ == "__main__":
    unittest.main()
