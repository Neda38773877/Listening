# PV Analyzer

A command-line Python tool for analyzing photovoltaic (PV) module flasher (I-V) summary measurements. Reads CSV data, validates input, calculates PV parameters, corrects to standard test conditions (STC), detects anomalies, and generates comprehensive reports.

## Features

- **CSV Input Processing**: Auto-detects delimiters (comma, semicolon, tab) and encodings (UTF-8, Latin-1)
- **Flexible Column Mapping**: Case-insensitive headers with unit stripping and alias support
- **Data Validation**: Comprehensive row-by-row validation with detailed error reporting
- **PV Calculations**: 
  - Power at MPP and fill factor
  - STC correction with temperature and irradiance compensation
  - Efficiency calculation (if module area provided)
  - Power deviation from nameplate
- **Anomaly Detection**:
  - Rule-based checks (out-of-range values, consistency issues)
  - Statistical outlier detection using robust z-score
- **Multiple Output Formats**: Text summary, CSV, and JSON reports

## Usage

```bash
python -m pv_analyzer INPUT.csv [options]
```

### Options

- `--output FILE.csv`: Write detailed CSV report
- `--json FILE.json`: Write JSON report
- `--nameplate W`: Default nameplate power (W) for modules without nameplate column
- `--area M2`: Module area (m²) for efficiency calculations
- `--alpha PCT_PER_K`: Isc temperature coefficient (%/K, default 0.05)
- `--beta PCT_PER_K`: Voc temperature coefficient (%/K, default -0.29)
- `--gamma PCT_PER_K`: Pmax temperature coefficient (%/K, default -0.37)
- `--tolerance-minus PCT`: Lower power tolerance (%, default 0.0)
- `--tolerance-plus PCT`: Upper power tolerance (%, default 3.0)
- `--quiet`: Suppress console output

## Input CSV Format

### Required Columns

- **Module ID**: module_id, id, serial, serial_number, sn
- **Isc [A]**: isc
- **Voc [V]**: voc
- **Impp [A]**: impp, imp, im, ipm
- **Vmpp [V]**: vmpp, vmp, vm, vpm

### Optional Columns

- **Pmax [W]**: pmpp, pmax, pmp, pm (computed if missing)
- **Irradiance [W/m²]**: irradiance, g, irr (required for STC correction)
- **Temperature [°C]**: temperature, temp, t, tmod, t_module (required for STC correction)
- **Nameplate [W]**: nameplate, nameplate_power, pnom, rated_power

### Features

- Headers are case-insensitive with automatic unit stripping (e.g., "Voc [V]" → "voc")
- Decimal comma support: "11,5" is automatically converted to "11.5"
- Delimiters are auto-detected; supported: comma, semicolon, tab
- Unknown extra columns are silently ignored

## Calculations

### Power at MPP
```
p_calc = impp × vmpp
```

### Fill Factor
```
FF = pmpp_used / (isc × voc)
```

### STC Correction

When both irradiance and temperature are available:

```
dT = temperature - 25°C
gk = 1000 / irradiance

isc_stc = isc × gk / (1 + alpha_rel × dT)
voc_stc = voc / (1 + beta_rel × dT)
pmpp_stc = pmpp_used × gk / (1 + gamma_rel × dT)
ff_stc = pmpp_stc / (isc_stc × voc_stc)
```

**Note**: Simplification—the logarithmic irradiance dependence of Voc is not corrected (IEC 60891 procedures would); keep measurements near 1000 W/m² for accurate Voc_STC.

### Efficiency
```
efficiency % = (pmpp_stc / (1000 × area)) × 100
```

### Power Deviation from Nameplate
```
deviation % = ((pmpp_stc - nameplate) / nameplate) × 100
```

## Validation

### Errors (row excluded from analysis)
- Missing module_id or required numeric field
- Non-numeric or NaN/Inf values
- Non-positive values (isc, voc, impp, vmpp, pmpp, irradiance)
- Impp > Isc or Vmpp > Voc (physically impossible)
- Duplicate module_id (second occurrence flagged)

### Warnings
- Out-of-range fill factor (0.60–0.86)
- Fill factor > 1.0 (error severity; physically impossible)
- Pmpp inconsistent with Impp×Vmpp (>1%)
- Out-of-range irradiance (700–1300 W/m²)
- Out-of-range temperature (15–35°C)
- Power deviation beyond tolerance
- Missing irradiance/temperature (STC correction skipped)
- Statistical outliers (robust z-score > 3.5, batch n ≥ 5)

## Output Formats

### Text Report (stdout)
- Tool version and input file info
- Summary: rows read, valid, rejected
- Configuration used
- Table of valid modules with key metrics
- Batch statistics (mean, median, std, min, max)
- Detailed issue list (errors first, then warnings)

### CSV Output
One line per input row (valid and rejected):
- row, module_id, status (OK/WARN/ERROR)
- Raw measurements: isc, voc, impp, vmpp
- Calculations: pmpp_used, p_calc, fill_factor, pmpp_consistency_pct
- STC-corrected: isc_stc, voc_stc, pmpp_stc, ff_stc
- Derived: efficiency_pct, power_deviation_pct
- issues (semicolon-separated codes)

### JSON Output
Complete structured output including:
- config: all analysis parameters
- summary: counts of valid/rejected/warnings/errors
- results: array of detailed results per row
- issues: flat list of all issues with context

## Exit Codes

- **0**: All rows valid, no issues
- **1**: Analysis completed but warnings or rejected rows exist
- **2**: Input error (file not found, invalid format, unreadable)

## Testing

Run the full test suite:

```bash
cd /home/user/Listening/pv-analyzer
python3 -m unittest discover -s tests -v
```

Tests cover:
- Header normalization and column mapping
- CSV delimiter and encoding detection
- Validation rules (missing values, non-numeric, duplicates, etc.)
- Calculation formulas (p_calc, FF, STC correction, efficiency)
- Anomaly detection (rule-based and statistical)
- CLI exit codes and output formats

## Example

```bash
python3 -m pv_analyzer examples/sample_measurements.csv \
  --output results.csv \
  --json results.json \
  --nameplate 450 \
  --area 2.0 \
  --gamma -0.37
```

Generates:
- Console text summary
- `results.csv`: detailed measurements and flags
- `results.json`: structured report for integration

## Implementation Notes

- Pure Python 3.11+, standard library only (no external dependencies)
- Type hints throughout; docstrings on all public functions
- No global mutable state; functions are reusable and testable
- Robust error handling with user-friendly messages
