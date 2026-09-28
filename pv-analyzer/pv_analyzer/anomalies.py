"""Anomaly detection: rule-based and statistical."""

import statistics
from pv_analyzer.models import Issue, Result, AnalysisConfig


def detect_rule_based_anomalies(result: Result, config: AnalysisConfig) -> None:
    """Detect rule-based anomalies and add Issues to result."""
    meas = result.measurement
    module_id = meas.module_id

    # pmpp_inconsistent
    if result.pmpp_consistency_pct is not None:
        if abs(result.pmpp_consistency_pct) > config.pmpp_consistency_tol_pct:
            result.issues.append(
                Issue(
                    row_number=meas.row_number,
                    module_id=module_id,
                    field="pmpp",
                    severity="warning",
                    code="pmpp_inconsistent",
                    message=f"Pmax inconsistent with Impp*Vmpp by {result.pmpp_consistency_pct:.2f}%",
                )
            )

    # ff_out_of_range / ff_impossible
    ff_to_check = result.ff_stc if result.ff_stc is not None else result.fill_factor
    if ff_to_check is not None:
        if ff_to_check > 1.0:
            result.issues.append(
                Issue(
                    row_number=meas.row_number,
                    module_id=module_id,
                    field="fill_factor",
                    severity="error",
                    code="ff_impossible",
                    message=f"Fill factor > 1.0 ({ff_to_check:.4f}) is physically impossible",
                )
            )
        elif ff_to_check < config.ff_min or ff_to_check > config.ff_max:
            result.issues.append(
                Issue(
                    row_number=meas.row_number,
                    module_id=module_id,
                    field="fill_factor",
                    severity="warning",
                    code="ff_out_of_range",
                    message=f"Fill factor {ff_to_check:.4f} outside range [{config.ff_min:.2f}, {config.ff_max:.2f}]",
                )
            )

    # irradiance_out_of_range
    if meas.irradiance is not None:
        irradiance = float(meas.irradiance)
        if irradiance < config.irradiance_min or irradiance > config.irradiance_max:
            result.issues.append(
                Issue(
                    row_number=meas.row_number,
                    module_id=module_id,
                    field="irradiance",
                    severity="warning",
                    code="irradiance_out_of_range",
                    message=f"Irradiance {irradiance:.1f} W/m² outside range [{config.irradiance_min:.0f}, {config.irradiance_max:.0f}]",
                )
            )

    # temperature_out_of_range
    if meas.temperature is not None:
        temperature = float(meas.temperature)
        if temperature < config.temp_min or temperature > config.temp_max:
            result.issues.append(
                Issue(
                    row_number=meas.row_number,
                    module_id=module_id,
                    field="temperature",
                    severity="warning",
                    code="temperature_out_of_range",
                    message=f"Temperature {temperature:.1f}°C outside range [{config.temp_min:.0f}, {config.temp_max:.0f}]",
                )
            )

    # power tolerance
    if result.power_deviation_pct is not None:
        if result.power_deviation_pct < -config.power_tolerance_minus_pct:
            result.issues.append(
                Issue(
                    row_number=meas.row_number,
                    module_id=module_id,
                    field="power_deviation",
                    severity="warning",
                    code="below_power_tolerance",
                    message=f"Power {result.power_deviation_pct:.2f}% below nameplate",
                )
            )
        elif result.power_deviation_pct > config.power_tolerance_plus_pct:
            result.issues.append(
                Issue(
                    row_number=meas.row_number,
                    module_id=module_id,
                    field="power_deviation",
                    severity="warning",
                    code="above_power_tolerance",
                    message=f"Power {result.power_deviation_pct:.2f}% above nameplate",
                )
            )

    # no_stc_correction (only if not already caught by validation)
    if meas.irradiance is None or meas.temperature is None:
        if not any(i.code == "missing_value" for i in result.issues):
            result.issues.append(
                Issue(
                    row_number=meas.row_number,
                    module_id=module_id,
                    field=None,
                    severity="warning",
                    code="no_stc_correction",
                    message="Missing irradiance or temperature: STC correction skipped",
                )
            )


def detect_statistical_anomalies(results: list[Result], config: AnalysisConfig) -> None:
    """
    Detect statistical outliers in valid results.

    Only runs if len(results) >= min_rows_for_statistics.
    Uses robust z-score: z = 0.6745 * (x - median) / MAD
    """
    if len(results) < config.min_rows_for_statistics:
        return

    # Collect metrics from valid results
    metrics_to_check = {
        "pmpp_stc": [],
        "pmpp_used": [],
        "fill_factor": [],
        "voc": [],
        "isc": [],
    }

    for result in results:
        meas = result.measurement

        # pmpp_stc with fallback
        if result.pmpp_stc is not None:
            metrics_to_check["pmpp_stc"].append((result, result.pmpp_stc))
        elif result.p_calc is not None:
            metrics_to_check["pmpp_used"].append((result, result.p_calc))

        # fill_factor
        if result.ff_stc is not None:
            metrics_to_check["fill_factor"].append((result, result.ff_stc))
        elif result.fill_factor is not None:
            metrics_to_check["fill_factor"].append((result, result.fill_factor))

        # voc (use voc_stc if available)
        if result.voc_stc is not None:
            metrics_to_check["voc"].append((result, result.voc_stc))
        else:
            metrics_to_check["voc"].append((result, float(meas.voc)))

        # isc (use isc_stc if available)
        if result.isc_stc is not None:
            metrics_to_check["isc"].append((result, result.isc_stc))
        else:
            metrics_to_check["isc"].append((result, float(meas.isc)))

    # Check each metric for outliers
    for metric_name, data_list in metrics_to_check.items():
        if not data_list:
            continue

        values = [v for _, v in data_list]

        # Skip if all same value (MAD == 0)
        median_val = statistics.median(values)
        mad = statistics.median(abs(x - median_val) for x in values)

        if mad == 0:
            # All values are the same; no outliers
            continue

        # Check each value
        for result, value in data_list:
            z_score = 0.6745 * (value - median_val) / mad
            if abs(z_score) > config.robust_z_threshold:
                result.issues.append(
                    Issue(
                        row_number=result.measurement.row_number,
                        module_id=result.measurement.module_id,
                        field=None,
                        severity="warning",
                        code="statistical_outlier",
                        message=f"Statistical outlier in {metric_name}: {value:.3f} (median {median_val:.3f}, z={z_score:.1f})",
                    )
                )
