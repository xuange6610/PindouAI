import uuid
from datetime import datetime
from decimal import Decimal

from sqlalchemy import Boolean, DateTime, ForeignKey, Numeric, SmallInteger, String, UniqueConstraint
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, relationship
from sqlalchemy.sql import func


class Base(DeclarativeBase):
    pass


class Brand(Base):
    __tablename__ = "brands"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    slug: Mapped[str] = mapped_column(String(40), unique=True, index=True)
    name: Mapped[str] = mapped_column(String(120))
    bead_size_mm: Mapped[Decimal] = mapped_column(Numeric(4, 1))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())


class Palette(Base):
    __tablename__ = "palettes"
    __table_args__ = (UniqueConstraint("brand_id", "version"),)

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    brand_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("brands.id"), index=True)
    name: Mapped[str] = mapped_column(String(120))
    version: Mapped[str] = mapped_column(String(40))
    status: Mapped[str] = mapped_column(String(20), default="draft")
    brand: Mapped[Brand] = relationship()


class Color(Base):
    __tablename__ = "colors"
    __table_args__ = (UniqueConstraint("palette_id", "code"),)

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    palette_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("palettes.id"), index=True)
    series: Mapped[str] = mapped_column(String(8), index=True)
    code: Mapped[str] = mapped_column(String(16))
    color_name_cn: Mapped[str] = mapped_column(String(80))
    color_name_en: Mapped[str] = mapped_column(String(80))
    red: Mapped[int] = mapped_column(SmallInteger)
    green: Mapped[int] = mapped_column(SmallInteger)
    blue: Mapped[int] = mapped_column(SmallInteger)
    hex: Mapped[str] = mapped_column(String(7))
    lab_l: Mapped[Decimal] = mapped_column(Numeric(7, 3))
    lab_a: Mapped[Decimal] = mapped_column(Numeric(7, 3))
    lab_b: Mapped[Decimal] = mapped_column(Numeric(7, 3))
    size_mm: Mapped[Decimal] = mapped_column(Numeric(4, 1))
    color_type: Mapped[str] = mapped_column(String(24), default="solid")
    is_measured: Mapped[bool] = mapped_column(Boolean, default=False)
    sort_order: Mapped[int] = mapped_column(SmallInteger)
