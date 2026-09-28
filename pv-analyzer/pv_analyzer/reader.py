"""CSV reading and header parsing."""

import csv
from typing import Optional
from pv_analyzer.models import Measurement, InputFormatError


# Canonical field names and their aliases
FIELD_ALIASES = {
    "module_id": ["id", "module_id", "module", "serial", "serial_number", "sn"],
    "isc": ["isc"],
    "voc": ["voc"],
    "impp": ["impp", "imp", "im", "ipm"],
    "vmpp": ["vmpp", "vmp", "vm", "vpm"],
    "pmpp": ["pmpp", "pmax", "pmp", "pm"],
    "irradiance": ["irradiance", "g", "irr"],
    "temperature": ["temperature", "temp", "t", "tmod", "t_module"],
    "nameplate_power": ["nameplate", "nameplate_power", "pnom", "rated_power"],
}

REQUIRED_FIELDS = {"module_id", "isc", "voc", "impp", "vmpp"}
OPTIONAL_FIELDS = {"pmpp", "irradiance", "temperature", "nameplate_power"}


def normalize_header(header: str) -> str:
    """
    Normalize a header name: lowercase, strip whitespace, remove unit suffix.

    Examples:
        "Voc [V]" -> "voc"
        "Pmax (W)" -> "pmax"
        "Module ID" -> "module_id"
    """
    normalized = header.strip().lower()
    # Remove unit in brackets or parentheses
    if "[" in normalized:
        normalized = normalized.split("[")[0].strip()
    if "(" in normalized:
        normalized = normalized.split("(")[0].strip()
    # Replace spaces with underscores
    normalized = normalized.replace(" ", "_")
    return normalized


def map_header_to_field(header: str) -> Optional[str]:
    """Map a normalized header to canonical field name, or None if unknown."""
    normalized = normalize_header(header)
    for field, aliases in FIELD_ALIASES.items():
        if normalized in aliases:
            return field
    return None


def detect_delimiter(header_line: str) -> str:
    """Auto-detect delimiter from header line using csv.Sniffer."""
    try:
        sniffer = csv.Sniffer()
        delimiter = sniffer.sniff(header_line, delimiters=",;\t").delimiter
        return delimiter
    except Exception:
        return ","  # Default to comma


def read_csv_measurements(
    filepath: str,
) -> tuple[list[Measurement], dict[str, Optional[str]], list[str]]:
    """
    Read CSV measurements.

    Returns:
        (measurements, field_mapping, ignored_columns)

    Raises:
        InputFormatError: if file cannot be read or is invalid
    """
    # Try encodings
    encodings = ["utf-8-sig", "latin-1"]
    content = None
    for enc in encodings:
        try:
            with open(filepath, "r", encoding=enc) as f:
                content = f.read()
            break
        except Exception:
            continue

    if content is None:
        raise InputFormatError(f"Cannot read file {filepath}")

    lines = content.strip().split("\n")
    if not lines:
        raise InputFormatError("no data rows")

    header_line = lines[0]
    if not header_line.strip():
        raise InputFormatError("no data rows")

    # Detect delimiter
    delimiter = detect_delimiter(header_line)

    # Parse header
    reader = csv.reader([header_line], delimiter=delimiter)
    headers = next(reader)
    headers = [h.strip() for h in headers]

    if not headers:
        raise InputFormatError("no data rows")

    # Map headers to fields
    field_mapping: dict[str, Optional[str]] = {}
    found_fields: dict[str, bool] = {f: False for f in FIELD_ALIASES}
    ignored_columns = []

    for header in headers:
        field = map_header_to_field(header)
        if field:
            field_mapping[header] = field
            found_fields[field] = True
        else:
            field_mapping[header] = None
            ignored_columns.append(header)

    # Check required fields
    missing = [f for f in REQUIRED_FIELDS if not found_fields.get(f, False)]
    if missing:
        found_headers = [h for h, f in field_mapping.items() if f is not None]
        raise InputFormatError(
            f"Missing required columns: {', '.join(missing)}. "
            f"Found columns: {', '.join(found_headers or headers)}"
        )

    # Parse data rows
    measurements = []
    if len(lines) <= 1:
        raise InputFormatError("no data rows")

    reader = csv.reader(lines[1:], delimiter=delimiter)
    for row_idx, row in enumerate(reader, start=2):  # Row 1 is header
        row = [cell.strip() for cell in row]

        # Skip completely empty rows (all cells empty)
        if all(cell == "" for cell in row):
            continue

        # Pad row to match header length
        while len(row) < len(headers):
            row.append("")

        # Extract field values
        data = {}
        for col_idx, header in enumerate(headers):
            field = field_mapping[header]
            if field:
                value = row[col_idx] if col_idx < len(row) else ""
                # Handle decimal comma
                if value and "," in value and "." not in value:
                    value = value.replace(",", ".")
                data[field] = value if value else None

        # Convert numeric strings to float or keep as string for validation
        def try_convert(val):
            if val is None or val == "":
                return None
            if isinstance(val, str):
                try:
                    return float(val)
                except ValueError:
                    return val  # Keep as string for validation to catch
            return val

        # Create measurement (validation happens later)
        meas = Measurement(
            row_number=row_idx,
            module_id=data.get("module_id") or "",
            isc=try_convert(data.get("isc")),
            voc=try_convert(data.get("voc")),
            impp=try_convert(data.get("impp")),
            vmpp=try_convert(data.get("vmpp")),
            pmpp=try_convert(data.get("pmpp")),
            irradiance=try_convert(data.get("irradiance")),
            temperature=try_convert(data.get("temperature")),
            nameplate_power=try_convert(data.get("nameplate_power")),
        )
        measurements.append(meas)

    return measurements, field_mapping, ignored_columns
