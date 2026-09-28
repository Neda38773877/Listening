"""CLI interface using argparse."""

import argparse
import sys
from pv_analyzer import __version__
from pv_analyzer.models import InputFormatError, AnalysisConfig
from pv_analyzer.reader import read_csv_measurements
from pv_analyzer.validation import validate_measurement
from pv_analyzer.calculations import analyze_measurement
from pv_analyzer.anomalies import detect_rule_based_anomalies, detect_statistical_anomalies
from pv_analyzer.report import (
    generate_text_report,
    write_csv_report,
    write_json_report,
)


def main(argv: list[str] | None = None) -> int:
    """
    Main CLI entry point.

    Exit codes:
    - 0: all rows OK
    - 1: analysis done but warnings or rejected rows exist
    - 2: input/usage error
    """
    parser = argparse.ArgumentParser(
        description="Analyze photovoltaic module flasher measurements"
    )
    parser.add_argument("input", help="Input CSV file")
    parser.add_argument("--output", help="Output CSV file")
    parser.add_argument("--json", help="Output JSON file")
    parser.add_argument("--nameplate", type=float, help="Default nameplate power (W)")
    parser.add_argument("--area", type=float, help="Module area (m²)")
    parser.add_argument(
        "--alpha", type=float, help="Isc temperature coefficient (%/K)"
    )
    parser.add_argument(
        "--beta", type=float, help="Voc temperature coefficient (%/K)"
    )
    parser.add_argument(
        "--gamma", type=float, help="Pmax temperature coefficient (%/K)"
    )
    parser.add_argument(
        "--tolerance-minus", type=float, help="Power tolerance minus (%)"
    )
    parser.add_argument(
        "--tolerance-plus", type=float, help="Power tolerance plus (%)"
    )
    parser.add_argument(
        "--quiet", action="store_true", help="Suppress text output"
    )

    try:
        args = parser.parse_args(argv)
    except SystemExit:
        return 2

    # Create config
    config = AnalysisConfig()

    if args.nameplate is not None:
        config.nameplate_power = args.nameplate
    if args.area is not None:
        config.module_area_m2 = args.area
    if args.alpha is not None:
        config.alpha_rel = args.alpha / 100.0  # Convert %/K to 1/K
    if args.beta is not None:
        config.beta_rel = args.beta / 100.0
    if args.gamma is not None:
        config.gamma_rel = args.gamma / 100.0
    if args.tolerance_minus is not None:
        config.power_tolerance_minus_pct = args.tolerance_minus
    if args.tolerance_plus is not None:
        config.power_tolerance_plus_pct = args.tolerance_plus

    # Read input
    try:
        measurements, field_mapping, ignored_columns = read_csv_measurements(args.input)
    except InputFormatError as e:
        print(f"Error: {e}", file=sys.stderr)
        return 2
    except FileNotFoundError:
        print(f"Error: File not found: {args.input}", file=sys.stderr)
        return 2
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        return 2

    # Validate and analyze
    from pv_analyzer.models import Result
    results = []
    seen_module_ids = {}

    for meas in measurements:
        issues = validate_measurement(meas, seen_module_ids)

        # If validation failed, create a minimal result for output
        if issues:
            result = Result(measurement=meas, issues=issues)
        else:
            # Analyze the measurement
            result = analyze_measurement(meas, config)
            # Add rule-based anomalies
            detect_rule_based_anomalies(result, config)

        results.append(result)

    # Statistical anomaly detection
    valid_results = [r for r in results if not any(i.severity == "error" for i in r.issues)]
    detect_statistical_anomalies(valid_results, config)

    # Generate reports
    if not args.quiet:
        text_report = generate_text_report(args.input, results, ignored_columns, config)
        print(text_report)

    if args.output:
        try:
            write_csv_report(args.output, results)
        except Exception as e:
            print(f"Error writing CSV: {e}", file=sys.stderr)
            return 2

    if args.json:
        try:
            write_json_report(args.json, args.input, results, config)
        except Exception as e:
            print(f"Error writing JSON: {e}", file=sys.stderr)
            return 2

    # Determine exit code
    has_errors = any(any(i.severity == "error" for i in r.issues) for r in results)
    has_warnings = any(any(i.severity == "warning" for i in r.issues) for r in results)
    has_rejected = any(any(i.severity == "error" for i in r.issues) for r in results)

    if has_errors or has_rejected or has_warnings:
        return 1
    return 0
