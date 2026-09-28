"""Row validation for measurements."""

import math
from pv_analyzer.models import Measurement, Issue


def validate_measurement(
    meas: Measurement, seen_module_ids: dict[str, int]
) -> list[Issue]:
    """
    Validate a measurement and return list of Issues.

    A row is EXCLUDED from calculations if it has any error.
    """
    issues: list[Issue] = []

    # Check module_id
    if not meas.module_id or not str(meas.module_id).strip():
        issues.append(
            Issue(
                row_number=meas.row_number,
                module_id=None,
                field="module_id",
                severity="error",
                code="missing_value",
                message="Missing module_id",
            )
        )
        return issues  # Can't continue without module_id

    module_id = str(meas.module_id).strip()

    # Check for duplicate module_id
    if module_id in seen_module_ids:
        issues.append(
            Issue(
                row_number=meas.row_number,
                module_id=module_id,
                field="module_id",
                severity="error",
                code="duplicate_id",
                message=f"Duplicate module_id (first occurrence at row {seen_module_ids[module_id]})",
            )
        )
        return issues

    seen_module_ids[module_id] = meas.row_number

    # Validate required numeric fields
    required_fields = [
        ("isc", meas.isc),
        ("voc", meas.voc),
        ("impp", meas.impp),
        ("vmpp", meas.vmpp),
    ]

    for field_name, value in required_fields:
        # Check for missing/empty
        if value is None or (isinstance(value, str) and not value.strip()):
            issues.append(
                Issue(
                    row_number=meas.row_number,
                    module_id=module_id,
                    field=field_name,
                    severity="error",
                    code="missing_value",
                    message=f"Missing or empty {field_name}",
                )
            )
            continue

        # Try to parse and validate
        try:
            num_val = float(value)
            if math.isnan(num_val) or math.isinf(num_val):
                issues.append(
                    Issue(
                        row_number=meas.row_number,
                        module_id=module_id,
                        field=field_name,
                        severity="error",
                        code="not_a_number",
                        message=f"{field_name} is NaN or Inf",
                    )
                )
            elif num_val <= 0:
                issues.append(
                    Issue(
                        row_number=meas.row_number,
                        module_id=module_id,
                        field=field_name,
                        severity="error",
                        code="non_positive",
                        message=f"{field_name} must be positive (got {num_val})",
                    )
                )
        except (ValueError, TypeError):
            issues.append(
                Issue(
                    row_number=meas.row_number,
                    module_id=module_id,
                    field=field_name,
                    severity="error",
                    code="not_a_number",
                    message=f"{field_name} is not numeric: {value!r}",
                )
            )

    # If there are errors in required fields, stop
    if any(i.severity == "error" for i in issues):
        return issues

    # Now we know all required fields are valid floats
    isc = float(meas.isc)
    voc = float(meas.voc)
    impp = float(meas.impp)
    vmpp = float(meas.vmpp)

    # Relationship checks
    if impp > isc:
        issues.append(
            Issue(
                row_number=meas.row_number,
                module_id=module_id,
                field="impp",
                severity="error",
                code="impp_gt_isc",
                message=f"impp ({impp}) > isc ({isc})",
            )
        )

    if vmpp > voc:
        issues.append(
            Issue(
                row_number=meas.row_number,
                module_id=module_id,
                field="vmpp",
                severity="error",
                code="vmpp_gt_voc",
                message=f"vmpp ({vmpp}) > voc ({voc})",
            )
        )

    # Validate optional pmpp
    if meas.pmpp is not None:
        try:
            pmpp_val = float(meas.pmpp)
            if math.isnan(pmpp_val) or math.isinf(pmpp_val):
                issues.append(
                    Issue(
                        row_number=meas.row_number,
                        module_id=module_id,
                        field="pmpp",
                        severity="error",
                        code="not_a_number",
                        message="pmpp is NaN or Inf",
                    )
                )
            elif pmpp_val <= 0:
                issues.append(
                    Issue(
                        row_number=meas.row_number,
                        module_id=module_id,
                        field="pmpp",
                        severity="error",
                        code="non_positive",
                        message=f"pmpp must be positive (got {pmpp_val})",
                    )
                )
        except (ValueError, TypeError):
            issues.append(
                Issue(
                    row_number=meas.row_number,
                    module_id=module_id,
                    field="pmpp",
                    severity="error",
                    code="not_a_number",
                    message=f"pmpp is not numeric: {meas.pmpp!r}",
                )
            )

    # Validate optional irradiance
    if meas.irradiance is not None:
        try:
            irr_val = float(meas.irradiance)
            if math.isnan(irr_val) or math.isinf(irr_val):
                issues.append(
                    Issue(
                        row_number=meas.row_number,
                        module_id=module_id,
                        field="irradiance",
                        severity="error",
                        code="not_a_number",
                        message="irradiance is NaN or Inf",
                    )
                )
            elif irr_val <= 0:
                issues.append(
                    Issue(
                        row_number=meas.row_number,
                        module_id=module_id,
                        field="irradiance",
                        severity="error",
                        code="non_positive",
                        message=f"irradiance must be positive (got {irr_val})",
                    )
                )
        except (ValueError, TypeError):
            issues.append(
                Issue(
                    row_number=meas.row_number,
                    module_id=module_id,
                    field="irradiance",
                    severity="error",
                    code="not_a_number",
                    message=f"irradiance is not numeric: {meas.irradiance!r}",
                )
            )

    # Validate optional temperature (can be negative, so no sign check)
    if meas.temperature is not None:
        try:
            temp_val = float(meas.temperature)
            if math.isnan(temp_val) or math.isinf(temp_val):
                issues.append(
                    Issue(
                        row_number=meas.row_number,
                        module_id=module_id,
                        field="temperature",
                        severity="error",
                        code="not_a_number",
                        message="temperature is NaN or Inf",
                    )
                )
        except (ValueError, TypeError):
            issues.append(
                Issue(
                    row_number=meas.row_number,
                    module_id=module_id,
                    field="temperature",
                    severity="error",
                    code="not_a_number",
                    message=f"temperature is not numeric: {meas.temperature!r}",
                )
            )

    # Validate optional nameplate_power
    if meas.nameplate_power is not None:
        try:
            np_val = float(meas.nameplate_power)
            if math.isnan(np_val) or math.isinf(np_val):
                issues.append(
                    Issue(
                        row_number=meas.row_number,
                        module_id=module_id,
                        field="nameplate_power",
                        severity="error",
                        code="not_a_number",
                        message="nameplate_power is NaN or Inf",
                    )
                )
            elif np_val <= 0:
                issues.append(
                    Issue(
                        row_number=meas.row_number,
                        module_id=module_id,
                        field="nameplate_power",
                        severity="error",
                        code="non_positive",
                        message=f"nameplate_power must be positive (got {np_val})",
                    )
                )
        except (ValueError, TypeError):
            issues.append(
                Issue(
                    row_number=meas.row_number,
                    module_id=module_id,
                    field="nameplate_power",
                    severity="error",
                    code="not_a_number",
                    message=f"nameplate_power is not numeric: {meas.nameplate_power!r}",
                )
            )

    return issues
