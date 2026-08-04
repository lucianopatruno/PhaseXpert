from __future__ import annotations

from enum import Enum
from typing import Literal

from pydantic import BaseModel, Field, field_validator, model_validator


API_SCHEMA_VERSION = "neqsim-provider.v1"
PROVIDER_ID = "neqsim-remote-srk-classic"
CAPABILITY_VERSION = "2026.08-pr23"
NEQSIM_VERSION = "3.16.0"
NEQSIM_SOURCE_COMMIT = "3af7b560525b57f2d3da2c803a08e2b41a8d7f5a"
EOS = "SystemSrkEos"
MIXING_RULE = "classic"
INTERACTION_DATA_ID = "neqsim-v3.16.0:src/main/resources/data/INTER.csv:7452:CO2-nitrogen:Classic"


class Component(str, Enum):
    co2 = "co2"
    n2 = "n2"


class PropertyID(str, Enum):
    density = "density"
    dynamicViscosity = "dynamicViscosity"
    molarMass = "molarMass"
    compressibilityFactor = "compressibilityFactor"
    specificVolume = "specificVolume"
    enthalpy = "enthalpy"
    entropy = "entropy"
    internalEnergy = "internalEnergy"
    isobaricHeatCapacity = "isobaricHeatCapacity"
    isochoricHeatCapacity = "isochoricHeatCapacity"
    heatCapacityRatio = "heatCapacityRatio"
    speedOfSound = "speedOfSound"
    thermalConductivity = "thermalConductivity"
    jouleThomsonCoefficient = "jouleThomsonCoefficient"
    isothermalCompressibility = "isothermalCompressibility"
    thermalExpansionCoefficient = "thermalExpansionCoefficient"
    vapourFraction = "vapourFraction"


class PropertyStatus(str, Enum):
    calculated = "calculated"
    unavailable = "unavailable"
    failed = "failed"


class PhaseRegion(str, Enum):
    gas = "gas"
    liquid = "liquid"
    dense = "dense"
    supercritical = "supercritical"
    twoPhase = "twoPhase"
    unknown = "unknown"
    unavailable = "unavailable"


class Branch(str, Enum):
    bubble = "bubble"
    dew = "dew"
    critical = "critical"


class CompositionEntry(BaseModel):
    component: Component
    mole_fraction: float = Field(ge=0.0, le=1.0)


class StateRequest(BaseModel):
    schema_version: Literal["neqsim-provider.v1"]
    request_id: str = Field(min_length=1, max_length=128)
    pressure_pa: float = Field(gt=0.0)
    temperature_k: float = Field(gt=0.0)
    composition: list[CompositionEntry] = Field(min_length=1, max_length=2)
    requested_properties: list[PropertyID] = Field(min_length=1)
    normalize_composition: bool = False
    client_version: str = Field(min_length=1, max_length=128)

    @field_validator("pressure_pa", "temperature_k")
    @classmethod
    def finite_scalar(cls, value: float) -> float:
        if not value == value or value in (float("inf"), float("-inf")):
            raise ValueError("state scalars must be finite")
        return value

    @model_validator(mode="after")
    def validate_composition(self) -> "StateRequest":
        components = [entry.component for entry in self.composition]
        if len(set(components)) != len(components):
            raise ValueError("duplicate components are not supported")
        if Component.co2 not in components:
            raise ValueError("CO2 must be present")
        total = sum(entry.mole_fraction for entry in self.composition)
        if abs(total - 1.0) > 1e-10 and not self.normalize_composition:
            raise ValueError("composition must sum to one unless normalization is requested")
        return self


class EnvelopeRequest(BaseModel):
    schema_version: Literal["neqsim-provider.v1"]
    request_id: str = Field(min_length=1, max_length=128)
    composition: list[CompositionEntry] = Field(min_length=1, max_length=2)
    maximum_points: int = Field(default=240, ge=4, le=400)
    timeout_seconds: float = Field(default=20.0, gt=0.0, le=60.0)
    normalize_composition: bool = False

    @model_validator(mode="after")
    def validate_composition(self) -> "EnvelopeRequest":
        state = StateRequest(
            schema_version=self.schema_version,
            request_id=self.request_id,
            pressure_pa=100000.0,
            temperature_k=273.15,
            composition=self.composition,
            requested_properties=[PropertyID.density],
            normalize_composition=self.normalize_composition,
            client_version="envelope-validator",
        )
        self.composition = state.composition
        return self


class ProviderProvenance(BaseModel):
    provider_id: str = PROVIDER_ID
    provider_capability_version: str = CAPABILITY_VERSION
    service_version: str
    api_schema_version: str = API_SCHEMA_VERSION
    neqsim_version: str = NEQSIM_VERSION
    neqsim_source_commit: str = NEQSIM_SOURCE_COMMIT
    java_runtime_version: str
    eos: str = EOS
    alpha_function: str = "NeqSim default for SystemSrkEos component parameters"
    mixing_rule: str = MIXING_RULE
    interaction_data: str = INTERACTION_DATA_ID


class ConvergenceMetadata(BaseModel):
    method: str
    converged: bool
    iteration_count: int | None = None
    duration_ms: float
    status: str


class PropertyResult(BaseModel):
    property: PropertyID
    value: float | None
    unit: str
    status: PropertyStatus
    message: str | None = None


class StateResponse(BaseModel):
    schema_version: str = API_SCHEMA_VERSION
    request_id: str
    calculation_id: str
    provenance: ProviderProvenance
    pressure_pa: float
    temperature_k: float
    composition: list[CompositionEntry]
    composition_basis: str = "mole_fraction"
    phase: PhaseRegion
    properties: list[PropertyResult]
    warnings: list[str]
    convergence: ConvergenceMetadata


class EnvelopePoint(BaseModel):
    temperature_k: float
    pressure_pa: float
    branch: Branch


class EnvelopeResponse(BaseModel):
    schema_version: str = API_SCHEMA_VERSION
    request_id: str
    calculation_id: str
    provenance: ProviderProvenance
    points: list[EnvelopePoint]
    is_available: bool
    is_complete: bool
    warnings: list[str]
    convergence: ConvergenceMetadata


class CapabilityResponse(BaseModel):
    schema_version: str = API_SCHEMA_VERSION
    provider_id: str = PROVIDER_ID
    provider_capability_version: str = CAPABILITY_VERSION
    service_version: str
    neqsim_version: str = NEQSIM_VERSION
    neqsim_source_commit: str = NEQSIM_SOURCE_COMMIT
    eos: str = EOS
    mixing_rule: str = MIXING_RULE
    interaction_data: str = INTERACTION_DATA_ID
    supported_components: list[Component] = [Component.co2, Component.n2]
    supported_properties: list[PropertyID] = list(PropertyID)
    production_transport_requires_https: bool = True
