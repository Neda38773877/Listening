"""Pure calculation functions for PV analysis."""

from typing import Optional
from pv_analyzer.models import Measurement, Result, AnalysisConfig


def calculate_p_calc(impp: float, vmpp: float) -> float:
    """Calculate power at MPP: p_calc = impp * vmpp."""
    return impp * vmpp


def calculate_fill_factor(
    isc: float, voc: float, pmpp: float
) -> float:
    """Calculate fill factor: FF = pmpp / (isc * voc)."""
    return pmpp / (isc * voc)


def stc_correct(
    isc: float,
    voc: float,
    pmpp: float,
    irradiance: Optional[float],
    temperature: Optional[float],
    config: AnalysisConfig,
) -> tuple[Optional[float], Optional[float], Optional[float], Optional[float]]:
    """
    Calculate STC-corrected values (pure function).

    Formula (with dT = temperature - t_stc, gk = g_stc / irradiance):
    - isc_stc = isc * gk / (1 + alpha_rel * dT)
    - voc_stc = voc / (1 + beta_rel * dT)  [temp only; irradiance effect ignored]
    - pmpp_stc = pmpp * gk / (1 + gamma_rel * dT)
    - ff_stc = pmpp_stc / (isc_stc * voc_stc)

    Returns:
        (isc_stc, voc_stc, pmpp_stc, ff_stc) or (None, None, None, None) if
        irradiance or temperature missing.

    Note: Simplification—the logarithmic irradiance dependence of Voc is not
    corrected (IEC 60891 procedures would); keep measurements near 1000 W/m²
    for accurate Voc_STC.
    """
    # Only correct if both irradiance and temperature are present
    if irradiance is None or temperature is None:
        return None, None, None, None

    dT = temperature - config.t_stc
    gk = config.g_stc / irradiance

    # STC corrections
    denom_isc = 1 + config.alpha_rel * dT
    denom_voc = 1 + config.beta_rel * dT
    denom_pmpp = 1 + config.gamma_rel * dT

    isc_stc = isc * gk / denom_isc
    voc_stc = voc / denom_voc
    pmpp_stc = pmpp * gk / denom_pmpp
    ff_stc = pmpp_stc / (isc_stc * voc_stc)

    return isc_stc, voc_stc, pmpp_stc, ff_stc


def calculate_efficiency(
    pmpp_stc: float, area_m2: Optional[float], g_stc: float = 1000.0
) -> Optional[float]:
    """
    Calculate efficiency: efficiency = pmpp_stc / (g_stc * area) * 100.

    Returns percentage or None if area is None or non-positive.
    """
    if area_m2 is None or area_m2 <= 0:
        return None
    return (pmpp_stc / (g_stc * area_m2)) * 100


def calculate_power_deviation(
    pmpp_stc: Optional[float], nameplate: Optional[float]
) -> Optional[float]:
    """
    Calculate power deviation from nameplate: (pmpp_stc - nameplate) / nameplate * 100.

    Returns percentage or None if nameplate missing or both None.
    """
    if pmpp_stc is None or nameplate is None or nameplate == 0:
        return None
    return ((pmpp_stc - nameplate) / nameplate) * 100


def analyze_measurement(
    meas: Measurement, config: AnalysisConfig
) -> Result:
    """
    Analyze a validated measurement and compute all derived fields.

    Assumes meas has been validated (no errors).
    """
    result = Result(measurement=meas)

    # All required fields are present (validated earlier)
    isc = float(meas.isc)
    voc = float(meas.voc)
    impp = float(meas.impp)
    vmpp = float(meas.vmpp)

    # Calculate p_calc
    result.p_calc = calculate_p_calc(impp, vmpp)

    # Determine pmpp_used
    if meas.pmpp is not None:
        pmpp_used = float(meas.pmpp)
        result.pmpp_consistency_pct = (pmpp_used - result.p_calc) / result.p_calc * 100
    else:
        pmpp_used = result.p_calc

    # Calculate fill factor
    result.fill_factor = calculate_fill_factor(isc, voc, pmpp_used)

    # Apply STC correction if possible
    irradiance = float(meas.irradiance) if meas.irradiance is not None else None
    temperature = float(meas.temperature) if meas.temperature is not None else None
    result.isc_stc, result.voc_stc, result.pmpp_stc, result.ff_stc = stc_correct(
        isc, voc, pmpp_used, irradiance, temperature, config
    )

    # Calculate efficiency
    if result.pmpp_stc is not None:
        result.efficiency_pct = calculate_efficiency(
            result.pmpp_stc, config.module_area_m2, config.g_stc
        )

    # Calculate power deviation
    nameplate = meas.nameplate_power or config.nameplate_power
    if result.pmpp_stc is not None and nameplate is not None:
        result.power_deviation_pct = calculate_power_deviation(result.pmpp_stc, nameplate)

    return result
