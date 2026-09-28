"""Tests for calculations module."""

import unittest
from pv_analyzer.models import Measurement, Result, AnalysisConfig
from pv_analyzer.calculations import (
    calculate_p_calc,
    calculate_fill_factor,
    stc_correct,
    calculate_efficiency,
    calculate_power_deviation,
    analyze_measurement,
)


class TestCalculations(unittest.TestCase):
    """Test calculation functions."""

    def test_p_calc(self):
        """Test p_calc = impp * vmpp."""
        result = calculate_p_calc(9, 32)
        self.assertAlmostEqual(result, 288, places=6)

    def test_fill_factor(self):
        """Test FF = pmpp / (isc * voc)."""
        # FF = 288 / (10 * 40) = 288 / 400 = 0.72
        result = calculate_fill_factor(10, 40, 288)
        self.assertAlmostEqual(result, 0.72, places=6)

    def test_stc_correction_at_stc(self):
        """Test STC correction at STC conditions returns unchanged values."""
        config = AnalysisConfig(
            alpha_rel=0.0005,
            beta_rel=-0.0029,
            gamma_rel=-0.0037,
            g_stc=1000.0,
            t_stc=25.0,
        )
        meas = Measurement(
            row_number=1,
            module_id="TEST",
            isc=10.0,
            voc=40.0,
            impp=9.0,
            vmpp=32.0,
            irradiance=1000.0,
            temperature=25.0,
        )
        result = analyze_measurement(meas, config)
        # At STC: irradiance unchanged, temp unchanged -> no change
        self.assertAlmostEqual(result.isc_stc, 10.0, places=6)
        self.assertAlmostEqual(result.voc_stc, 40.0, places=6)
        self.assertAlmostEqual(result.pmpp_stc, 288.0, places=5)

    def test_stc_correction_g800_t45(self):
        """Test STC correction at G=800, T=45 with gamma=-0.004."""
        config = AnalysisConfig(
            alpha_rel=0.0005,
            beta_rel=-0.0029,
            gamma_rel=-0.004,
            g_stc=1000.0,
            t_stc=25.0,
        )
        pmpp_measured = 300.0  # at G=800, T=45
        # Expected: pmpp_stc = 300 * (1000/800) / (1 + (-0.004)*(45-25))
        #                     = 300 * 1.25 / (1 - 0.08)
        #                     = 375 / 0.92
        expected = 375.0 / 0.92

        meas = Measurement(
            row_number=1,
            module_id="TEST",
            isc=10.0,
            voc=40.0,
            impp=9.0,
            vmpp=33.33,  # pmpp_measured / impp
            irradiance=800.0,
            temperature=45.0,
        )
        result = analyze_measurement(meas, config)
        self.assertAlmostEqual(result.pmpp_stc, expected, places=1)

    def test_stc_correction_isc_at_t45(self):
        """Test Isc STC correction at T=45 with alpha=0.0005."""
        config = AnalysisConfig(
            alpha_rel=0.0005,
            beta_rel=-0.0029,
            gamma_rel=-0.0037,
            g_stc=1000.0,
            t_stc=25.0,
        )
        # Expected: isc_stc = isc * 1.25 / (1 + 0.0005*20)
        #                    = isc * 1.25 / 1.01
        expected_ratio = 1.25 / 1.01

        meas = Measurement(
            row_number=1,
            module_id="TEST",
            isc=10.0,
            voc=40.0,
            impp=9.0,
            vmpp=32.0,
            irradiance=800.0,
            temperature=45.0,
        )
        result = analyze_measurement(meas, config)
        self.assertAlmostEqual(result.isc_stc / 10.0, expected_ratio, places=4)

    def test_stc_correction_voc_at_t45(self):
        """Test Voc STC correction at T=45 with beta=-0.003."""
        config = AnalysisConfig(
            alpha_rel=0.0005,
            beta_rel=-0.003,
            gamma_rel=-0.0037,
            g_stc=1000.0,
            t_stc=25.0,
        )
        # Expected: voc_stc = voc / (1 + (-0.003)*20)
        #                     = voc / (1 - 0.06)
        #                     = voc / 0.94
        expected_ratio = 1.0 / 0.94

        meas = Measurement(
            row_number=1,
            module_id="TEST",
            isc=10.0,
            voc=40.0,
            impp=9.0,
            vmpp=32.0,
            irradiance=800.0,
            temperature=45.0,
        )
        result = analyze_measurement(meas, config)
        self.assertAlmostEqual(result.voc_stc / 40.0, expected_ratio, places=4)

    def test_efficiency(self):
        """Test efficiency: 450 W, area 2.0 m² -> 22.5%."""
        result = calculate_efficiency(450.0, 2.0, 1000.0)
        self.assertAlmostEqual(result, 22.5, places=6)

    def test_power_deviation(self):
        """Test power deviation: 441 vs 450 -> -2.0%."""
        result = calculate_power_deviation(441.0, 450.0)
        self.assertAlmostEqual(result, -2.0, places=6)

    def test_mod001_stc_hand_computed(self):
        """Test MOD-001 STC values using hand-computed formula from sample data.

        Data: Isc=11.6, Voc=49.5, Impp=11.0, Vmpp=41.2, Pmax=453.2, G=1005, T=24
        Expected STC: pmpp_stc = 453.2*1000/1005/(1+0.0037*(-1))
                                = 453.2*1000/1005/0.9963
        """
        config = AnalysisConfig(
            alpha_rel=0.0005,
            beta_rel=-0.0029,
            gamma_rel=-0.0037,
            g_stc=1000.0,
            t_stc=25.0,
        )
        meas = Measurement(
            row_number=2,
            module_id="MOD-001",
            isc=11.6,
            voc=49.5,
            impp=11.0,
            vmpp=41.2,
            pmpp=453.2,
            irradiance=1005.0,
            temperature=24.0,
        )
        result = analyze_measurement(meas, config)

        # Hand-computed expected values
        # dT = 24 - 25 = -1
        # gk = 1000 / 1005
        # pmpp_stc = 453.2 * gk / (1 + gamma_rel * dT) where gamma_rel = -0.0037
        pmpp_stc_expected = 453.2 * 1000.0 / 1005.0 / (1 + (-0.0037) * (-1))
        # isc_stc = 11.6 * gk / (1 + alpha_rel * dT) where alpha_rel = 0.0005
        isc_stc_expected = 11.6 * 1000.0 / 1005.0 / (1 + 0.0005 * (-1))
        # voc_stc = 49.5 / (1 + beta_rel * dT) where beta_rel = -0.0029
        voc_stc_expected = 49.5 / (1 + (-0.0029) * (-1))
        # ff_stc = pmpp_stc / (isc_stc * voc_stc)
        ff_stc_expected = pmpp_stc_expected / (isc_stc_expected * voc_stc_expected)

        self.assertAlmostEqual(result.pmpp_stc, pmpp_stc_expected, places=6)
        self.assertAlmostEqual(result.isc_stc, isc_stc_expected, places=6)
        self.assertAlmostEqual(result.voc_stc, voc_stc_expected, places=6)
        self.assertAlmostEqual(result.ff_stc, ff_stc_expected, places=6)


if __name__ == "__main__":
    unittest.main()
