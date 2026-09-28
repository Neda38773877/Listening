"""Report generation: text, CSV, and JSON."""

import csv
import json
import statistics
from typing import Optional
from pv_analyzer import __version__
from pv_analyzer.models import Result, AnalysisConfig


def format_number(value: Optional[float], decimals: int) -> str:
    """Format a number to given decimal places, or empty string if None."""
    if value is None:
        return ""
    return f"{value:.{decimals}f}"


def format_std(values: list[float], decimals: int) -> str:
    """Format standard deviation, returning 'n/a' for n<2."""
    if len(values) < 2:
        return "n/a"
    std = statistics.stdev(values)
    return f"{std:.{decimals}f}"


def generate_text_report(
    input_file: str,
    results: list[Result],
    ignored_columns: list[str],
    config: AnalysisConfig,
) -> str:
    """Generate a text summary report."""
    lines = []
    lines.append(f"PV Analyzer v{__version__}")
    lines.append(f"Input: {input_file}")

    valid_results = [r for r in results if not any(i.severity == "error" for i in r.issues)]
    rejected_results = [r for r in results if any(i.severity == "error" for i in r.issues)]

    lines.append(f"Rows read: {len(results)}")
    lines.append(f"Valid: {len(valid_results)}")
    lines.append(f"Rejected: {len(rejected_results)}")
    lines.append("")

    # Config summary - formatted with proper units
    lines.append("Configuration:")
    lines.append(f"  alpha: {config.alpha_rel*100:.3f} %/K")
    lines.append(f"  beta: {config.beta_rel*100:.3f} %/K")
    lines.append(f"  gamma: {config.gamma_rel*100:.3f} %/K")
    lines.append(f"  G_STC: {config.g_stc:.0f} W/m²")
    lines.append(f"  T_STC: {config.t_stc:.1f} °C")
    area_str = f"{config.module_area_m2:.2f} m²" if config.module_area_m2 is not None else "not set"
    lines.append(f"  Module area: {area_str}")
    nameplate_str = (
        f"{config.nameplate_power:.0f} W" if config.nameplate_power is not None else "per row / not set"
    )
    lines.append(f"  Nameplate power: {nameplate_str}")
    minus = config.power_tolerance_minus_pct
    plus = config.power_tolerance_plus_pct
    lines.append(f"  Power tolerance: −{minus:.1f} % / +{plus:.1f} %")
    lines.append(f"  FF range: [{config.ff_min:.2f}, {config.ff_max:.2f}]")
    lines.append(f"  Irradiance range: [{config.irradiance_min:.0f}, {config.irradiance_max:.0f}] W/m²")
    lines.append(f"  Temperature range: [{config.temp_min:.0f}, {config.temp_max:.0f}] °C")
    lines.append(f"  Robust z-threshold: {config.robust_z_threshold:.1f}")
    lines.append("")

    # Valid modules table
    if valid_results:
        lines.append("Valid Modules:")
        lines.append(
            "  ID                   Pmpp_STC [W]  FF_STC   Voc_STC [V]  Isc_STC [A]  ΔP [%]   Status"
        )
        has_asterisks = False
        for result in valid_results:
            module_id = result.measurement.module_id[:20].ljust(20)

            # Pmpp_STC with fallback and asterisk
            if result.pmpp_stc is not None:
                pmpp_stc = format_number(result.pmpp_stc, 1)
            else:
                pmpp_stc = format_number(result.p_calc, 1) + "*"
                has_asterisks = True

            # FF_STC with fallback and asterisk
            if result.ff_stc is not None:
                ff = format_number(result.ff_stc, 4)
            else:
                ff = format_number(result.fill_factor, 4) + "*"
                has_asterisks = True

            # Voc_STC with fallback and asterisk
            if result.voc_stc is not None:
                voc_stc = format_number(result.voc_stc, 2)
            else:
                voc_stc = format_number(float(result.measurement.voc), 2) + "*"
                has_asterisks = True

            # Isc_STC with fallback and asterisk
            if result.isc_stc is not None:
                isc_stc = format_number(result.isc_stc, 2)
            else:
                isc_stc = format_number(float(result.measurement.isc), 2) + "*"
                has_asterisks = True

            power_dev = format_number(result.power_deviation_pct, 2)

            if any(i.severity == "error" for i in result.issues):
                status = "ERROR"
            elif any(i.severity == "warning" for i in result.issues):
                status = "WARN"
            else:
                status = "OK"

            lines.append(
                f"  {module_id}  {pmpp_stc:>12}  {ff:>8}  {voc_stc:>11}  {isc_stc:>10}  {power_dev:>7}  {status}"
            )

        if has_asterisks:
            lines.append("  * measured value, not STC-corrected")

    # Statistics
    if valid_results:
        lines.append("")
        lines.append("Batch Statistics (Valid Modules):")

        # Separate STC-corrected from uncorrected
        pmpp_stc_values = [r.pmpp_stc for r in valid_results if r.pmpp_stc is not None]
        pmpp_measured_values = [r.p_calc for r in valid_results if r.p_calc is not None]

        ff_stc_values = [r.ff_stc for r in valid_results if r.ff_stc is not None]
        ff_measured_values = [r.fill_factor for r in valid_results if r.fill_factor is not None]

        # Report STC statistics if available
        if pmpp_stc_values:
            pmpp_mean = statistics.mean(pmpp_stc_values)
            pmpp_median = statistics.median(pmpp_stc_values)
            pmpp_std_str = format_std(pmpp_stc_values, 1)
            pmpp_min = min(pmpp_stc_values)
            pmpp_max = max(pmpp_stc_values)
            lines.append(
                f"  Pmpp_STC: n={len(pmpp_stc_values)}, "
                f"mean={pmpp_mean:.1f} W, median={pmpp_median:.1f} W, "
                f"std={pmpp_std_str}{'' if pmpp_std_str == 'n/a' else ' W'}, min={pmpp_min:.1f} W, max={pmpp_max:.1f} W"
            )

        if ff_stc_values:
            ff_mean = statistics.mean(ff_stc_values)
            ff_median = statistics.median(ff_stc_values)
            ff_std_str = format_std(ff_stc_values, 4)
            ff_min = min(ff_stc_values)
            ff_max = max(ff_stc_values)
            lines.append(
                f"  FF_STC: n={len(ff_stc_values)}, "
                f"mean={ff_mean:.4f}, median={ff_median:.4f}, "
                f"std={ff_std_str}, min={ff_min:.4f}, max={ff_max:.4f}"
            )

        # If some rows lack STC correction, show measured statistics and note
        if pmpp_stc_values and len(pmpp_stc_values) < len(valid_results):
            lines.append(f"  Not STC-corrected (excluded from STC statistics): {len(valid_results) - len(pmpp_stc_values)} modules")

        if pmpp_measured_values and (not pmpp_stc_values or len(pmpp_measured_values) > len(pmpp_stc_values)):
            pmpp_mean = statistics.mean(pmpp_measured_values)
            pmpp_median = statistics.median(pmpp_measured_values)
            pmpp_std_str = format_std(pmpp_measured_values, 1)
            pmpp_min = min(pmpp_measured_values)
            pmpp_max = max(pmpp_measured_values)
            lines.append(
                f"  Pmpp (measured): n={len(pmpp_measured_values)}, "
                f"mean={pmpp_mean:.1f} W, median={pmpp_median:.1f} W, "
                f"std={pmpp_std_str}{'' if pmpp_std_str == 'n/a' else ' W'}, min={pmpp_min:.1f} W, max={pmpp_max:.1f} W"
            )

        if ff_measured_values and (not ff_stc_values or len(ff_measured_values) > len(ff_stc_values)):
            ff_mean = statistics.mean(ff_measured_values)
            ff_median = statistics.median(ff_measured_values)
            ff_std_str = format_std(ff_measured_values, 4)
            ff_min = min(ff_measured_values)
            ff_max = max(ff_measured_values)
            lines.append(
                f"  FF (measured): n={len(ff_measured_values)}, "
                f"mean={ff_mean:.4f}, median={ff_median:.4f}, "
                f"std={ff_std_str}, min={ff_min:.4f}, max={ff_max:.4f}"
            )

    # Statistical outlier note
    if len(results) < config.min_rows_for_statistics:
        lines.append("")
        lines.append(f"Statistical outlier check skipped (n={len(results)} < {config.min_rows_for_statistics})")

    # Issues
    all_issues = []
    for result in results:
        all_issues.extend(result.issues)

    if all_issues:
        lines.append("")
        lines.append("Issues:")
        # Errors first
        for issue in all_issues:
            if issue.severity == "error":
                module_info = f" ({issue.module_id})" if issue.module_id else ""
                lines.append(
                    f"  Row {issue.row_number}{module_info}: [{issue.severity.upper()}] "
                    f"{issue.code} - {issue.message}"
                )
        # Then warnings
        for issue in all_issues:
            if issue.severity == "warning":
                module_info = f" ({issue.module_id})" if issue.module_id else ""
                lines.append(
                    f"  Row {issue.row_number}{module_info}: [{issue.severity.upper()}] "
                    f"{issue.code} - {issue.message}"
                )

    if ignored_columns:
        lines.append("")
        lines.append(f"Ignored columns: {', '.join(ignored_columns)}")

    return "\n".join(lines)


def write_csv_report(filepath: str, results: list[Result]) -> None:
    """Write results to CSV file (one line per input row)."""
    with open(filepath, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(
            [
                "row",
                "module_id",
                "status",
                "isc",
                "voc",
                "impp",
                "vmpp",
                "pmpp_used",
                "p_calc",
                "pmpp_consistency_pct",
                "fill_factor",
                "isc_stc",
                "voc_stc",
                "pmpp_stc",
                "ff_stc",
                "efficiency_pct",
                "power_deviation_pct",
                "issues",
            ]
        )
        for result in results:
            meas = result.measurement
            if any(i.severity == "error" for i in result.issues):
                status = "ERROR"
            elif any(i.severity == "warning" for i in result.issues):
                status = "WARN"
            else:
                status = "OK"

            # Safe float conversion
            def safe_float(val):
                if val is None:
                    return None
                if isinstance(val, (int, float)):
                    return val
                try:
                    return float(val)
                except (ValueError, TypeError):
                    return None

            pmpp_used = result.p_calc
            if meas.pmpp is not None:
                pmpp_used = safe_float(meas.pmpp)

            issue_codes = ";".join(i.code for i in result.issues)

            writer.writerow(
                [
                    meas.row_number,
                    meas.module_id,
                    status,
                    format_number(safe_float(meas.isc), 3),
                    format_number(safe_float(meas.voc), 3),
                    format_number(safe_float(meas.impp), 3),
                    format_number(safe_float(meas.vmpp), 3),
                    format_number(pmpp_used, 3),
                    format_number(result.p_calc, 3),
                    format_number(result.pmpp_consistency_pct, 2),
                    format_number(result.fill_factor, 4),
                    format_number(result.isc_stc, 3),
                    format_number(result.voc_stc, 3),
                    format_number(result.pmpp_stc, 3),
                    format_number(result.ff_stc, 4),
                    format_number(result.efficiency_pct, 2),
                    format_number(result.power_deviation_pct, 2),
                    issue_codes,
                ]
            )


def write_json_report(
    filepath: str,
    input_file: str,
    results: list[Result],
    config: AnalysisConfig,
) -> None:
    """Write results to JSON file."""
    valid_results = [r for r in results if not any(i.severity == "error" for i in r.issues)]
    rejected_results = [r for r in results if any(i.severity == "error" for i in r.issues)]

    # Build results array
    # Safe float conversion helper
    def safe_float(val):
        if val is None:
            return None
        if isinstance(val, (int, float)):
            return val
        try:
            return float(val)
        except (ValueError, TypeError):
            return None

    results_array = []
    for result in results:
        meas = result.measurement
        pmpp_used = result.p_calc
        if meas.pmpp is not None:
            pmpp_used = safe_float(meas.pmpp)

        if any(i.severity == "error" for i in result.issues):
            status = "ERROR"
        elif any(i.severity == "warning" for i in result.issues):
            status = "WARN"
        else:
            status = "OK"

        results_array.append(
            {
                "row": meas.row_number,
                "module_id": meas.module_id,
                "status": status,
                "isc": safe_float(meas.isc),
                "voc": safe_float(meas.voc),
                "impp": safe_float(meas.impp),
                "vmpp": safe_float(meas.vmpp),
                "pmpp_used": pmpp_used,
                "p_calc": result.p_calc,
                "pmpp_consistency_pct": result.pmpp_consistency_pct,
                "fill_factor": result.fill_factor,
                "isc_stc": result.isc_stc,
                "voc_stc": result.voc_stc,
                "pmpp_stc": result.pmpp_stc,
                "ff_stc": result.ff_stc,
                "efficiency_pct": result.efficiency_pct,
                "power_deviation_pct": result.power_deviation_pct,
                "issues": [
                    {
                        "row": i.row_number,
                        "field": i.field,
                        "severity": i.severity,
                        "code": i.code,
                        "message": i.message,
                    }
                    for i in result.issues
                ],
            }
        )

    # Build issues array
    all_issues = []
    for result in results:
        for issue in result.issues:
            all_issues.append(
                {
                    "row": issue.row_number,
                    "module_id": issue.module_id,
                    "field": issue.field,
                    "severity": issue.severity,
                    "code": issue.code,
                    "message": issue.message,
                }
            )

    data = {
        "version": __version__,
        "input": input_file,
        "config": {
            "alpha_rel": config.alpha_rel,
            "beta_rel": config.beta_rel,
            "gamma_rel": config.gamma_rel,
            "g_stc": config.g_stc,
            "t_stc": config.t_stc,
            "module_area_m2": config.module_area_m2,
            "nameplate_power": config.nameplate_power,
            "power_tolerance_minus_pct": config.power_tolerance_minus_pct,
            "power_tolerance_plus_pct": config.power_tolerance_plus_pct,
            "pmpp_consistency_tol_pct": config.pmpp_consistency_tol_pct,
            "ff_min": config.ff_min,
            "ff_max": config.ff_max,
            "irradiance_min": config.irradiance_min,
            "irradiance_max": config.irradiance_max,
            "temp_min": config.temp_min,
            "temp_max": config.temp_max,
            "robust_z_threshold": config.robust_z_threshold,
            "min_rows_for_statistics": config.min_rows_for_statistics,
        },
        "summary": {
            "rows": len(results),
            "valid": len(valid_results),
            "rejected": len(rejected_results),
            "warnings": len([r for r in valid_results if any(i.severity == "warning" for i in r.issues)]),
            "errors": len([r for r in results if any(i.severity == "error" for i in r.issues)]),
        },
        "results": results_array,
        "issues": all_issues,
    }

    with open(filepath, "w") as f:
        json.dump(data, f, indent=2)
