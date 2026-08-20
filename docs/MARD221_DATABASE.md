# 《MARD 221 颜色数据库设计方案》

## 数据原则

颜色记录以“品牌 + 色卡版本 + 色号”为唯一事实，不允许用 A1 等短编号跨品牌关联。RGB/HEX 用于显示，LAB 用于匹配；生产测色必须带测量条件和批次。客户端内置色库是可版本化快照。

## PostgreSQL 核心表

```sql
CREATE TABLE brands (
  id uuid PRIMARY KEY,
  slug varchar(40) UNIQUE NOT NULL,
  name varchar(120) NOT NULL,
  bead_size_mm numeric(4,1) NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE palettes (
  id uuid PRIMARY KEY,
  brand_id uuid NOT NULL REFERENCES brands(id),
  name varchar(120) NOT NULL,
  version varchar(40) NOT NULL,
  status varchar(20) NOT NULL DEFAULT 'draft',
  source varchar(200),
  measured_illuminant varchar(20),
  measured_observer varchar(20),
  published_at timestamptz,
  UNIQUE (brand_id, version)
);

CREATE TABLE colors (
  id uuid PRIMARY KEY,
  palette_id uuid NOT NULL REFERENCES palettes(id),
  series varchar(8) NOT NULL,
  code varchar(16) NOT NULL,
  color_name_cn varchar(80) NOT NULL,
  color_name_en varchar(80) NOT NULL,
  red smallint NOT NULL CHECK (red BETWEEN 0 AND 255),
  green smallint NOT NULL CHECK (green BETWEEN 0 AND 255),
  blue smallint NOT NULL CHECK (blue BETWEEN 0 AND 255),
  hex char(7) NOT NULL,
  lab_l numeric(7,3) NOT NULL,
  lab_a numeric(7,3) NOT NULL,
  lab_b numeric(7,3) NOT NULL,
  size_mm numeric(4,1) NOT NULL,
  color_type varchar(24) NOT NULL DEFAULT 'solid',
  is_measured boolean NOT NULL DEFAULT false,
  sort_order smallint NOT NULL,
  UNIQUE (palette_id, code)
);

CREATE INDEX colors_palette_series_idx ON colors (palette_id, series, sort_order);
CREATE INDEX colors_lab_idx ON colors (palette_id, lab_l, lab_a, lab_b);
```

特殊色 P/R/Q/T/Y/L 使用同一结构但位于独立 palette 版本，`color_type` 可取 pearl、jelly、fluorescent、transparent、metallic、glow。普通 MARD221 快照严格包含 A26+B32+C29+D26+E24+F25+G21+H23+M15=221 条。

## 导入和发布

1. 管理员上传 XLSX/CSV 到暂存区。
2. 校验必填字段、编号唯一性、HEX/RGB 一致性、LAB 范围和预期总数。
3. 对未提供 LAB 的行按 sRGB/D65 转换并标记 `is_measured=false`。
4. 生成差异报告，双人复核后把 palette 状态改为 `published`。
5. 生成带 SHA-256 的客户端 JSON 快照；客户端按版本增量更新。
6. 任一已发布版本不可原地修改，只能创建新版本，以保证历史作品可复现。

## 当前数据声明

应用内 221 条记录覆盖上述全部编号，但未收到官方完整数字色值，故其 RGB/LAB 是工程预置近似值并标记为未实测。进入采购或商业印刷前必须以经授权、经测量的数据替换。
