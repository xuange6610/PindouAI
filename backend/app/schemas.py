from decimal import Decimal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, field_validator


class HealthResponse(BaseModel):
    status: str
    service: str
    copyright: str


class ColorRead(BaseModel):
    id: UUID
    series: str
    code: str
    color_name_cn: str
    color_name_en: str
    red: int
    green: int
    blue: int
    hex: str
    lab_l: Decimal
    lab_a: Decimal
    lab_b: Decimal
    size_mm: Decimal
    color_type: str
    is_measured: bool

    model_config = ConfigDict(from_attributes=True)


class ColorImportRow(BaseModel):
    series: str = Field(min_length=1, max_length=8)
    code: str = Field(min_length=1, max_length=16)
    color_name_cn: str = Field(min_length=1, max_length=80)
    color_name_en: str = Field(min_length=1, max_length=80)
    red: int = Field(ge=0, le=255)
    green: int = Field(ge=0, le=255)
    blue: int = Field(ge=0, le=255)
    hex: str = Field(pattern=r"^#[0-9A-Fa-f]{6}$")
    lab_l: Decimal = Field(ge=0, le=100)
    lab_a: Decimal
    lab_b: Decimal
    size_mm: Decimal = Field(gt=0)
    color_type: str = "solid"
    is_measured: bool = False

    @field_validator("hex")
    @classmethod
    def uppercase_hex(cls, value: str) -> str:
        return value.upper()
