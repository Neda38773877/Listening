"""Data models for PV analysis."""

from dataclasses import dataclass, field
from typing import Optional


class InputFormatError(Exception):
    """Raised when input CSV format is invalid."""

    pass


@dataclass
class Measurement:
    """Raw measurement from CSV row."""

    row_number: int  # 1-based, including header
    module_id: str
    isc: float
    voc: float
    impp: float
    vmpp: float
    pmpp: Optional[float] = None
    irradiance: Optional[float] = None
    temperature: Optional[float] = None
    nameplate_power: Optional[float] = None


@dataclass
class Issue:
    """Validation or anomaly issue."""

    row_number: int
    module_id: Optional[str]
    field: Optional[str]
    severity: str  # "error" or "warning"
    code: str
    message: str


@dataclass
class Result:
    """Analysis result for a measurement."""

    measurement: Measurement
    # Calculated fields
    p_calc: Optional[float] = None
    pmpp_consistency_pct: Optional[float] = None
    fill_factor: Optional[float] = None
    isc_stc: Optional[float] = None
    voc_stc: Optional[float] = None
    pmpp_stc: Optional[float] = None
    ff_stc: Optional[float] = None
    efficiency_pct: Optional[float] = None
    power_deviation_pct: Optional[float] = None
    issues: list[Issue] = field(default_factory=list)


@dataclass
class AnalysisConfig:
    """Configuration for analysis."""

    alpha_rel: float = 0.0005  # Isc temperature coefficient (1/K)
    beta_rel: float = -0.0029  # Voc temperature coefficient (1/K)
    gamma_rel: float = -0.0037  # Pmax temperature coefficient (1/K)
    g_stc: float = 1000.0  # STC irradiance (W/m²)
    t_stc: float = 25.0  # STC temperature (°C)
    module_area_m2: Optional[float] = None  # Module area for efficiency
    nameplate_power: Optional[float] = None  # Global default nameplate power
    power_tolerance_minus_pct: float = 0.0  # Lower tolerance on power
    power_tolerance_plus_pct: float = 3.0  # Upper tolerance on power
    pmpp_consistency_tol_pct: float = 1.0  # Tolerance on pmpp consistency
    ff_min: float = 0.60  # Minimum fill factor
    ff_max: float = 0.86  # Maximum fill factor
    irradiance_min: float = 700.0  # Minimum irradiance
    irradiance_max: float = 1300.0  # Maximum irradiance
    temp_min: float = 15.0  # Minimum temperature (°C)
    temp_max: float = 35.0  # Maximum temperature (°C)
    robust_z_threshold: float = 3.5  # Z-score threshold for outliers
    min_rows_for_statistics: int = 5  # Minimum rows for statistical analysis
