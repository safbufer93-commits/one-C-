from __future__ import annotations

import json
from pathlib import Path
from typing import Iterable
from xml.etree import ElementTree as ET


ROOT = Path(__file__).resolve().parents[1]
EXTRACT = ROOT / "docs" / "source_extract" / "workbook_extract.json"
OUT = ROOT / "docs" / "source_extract" / "custom_coverage_report.md"


TYPE_MAP = {
    "Справочник": "Catalog",
    "Документ": "Document",
    "РегистрСведений": "InformationRegister",
    "РегистрНакопления": "AccumulationRegister",
    "Перечисление": "Enum",
}

OBJECT_EQUIV = {
    "Document.ЗаказНаПеревозку": "Document.Отправка",
    "Enum.ВидТочкиМаршрута": "Enum.ТипМаршрутнойТочки",
    "Catalog.Справочник.ВидыЭтаповДоставки": "Catalog.ВидыЭтаповДоставки",
}

TABLE_EQUIV = {
    "Документ.ЗаказНаПеревозку.Позиции": "Document.Отправка.Позиции",
    "Документ.ЗаказНаПеревозку.Грузоместа": "Document.Отправка.Грузоместа",
    "Справочник.МаршрутыДоставки.Точки": "Catalog.МаршрутыДоставки.Точки",
    "Справочник.Товары.КроссНомера": "Catalog.Товары.КроссНомера",
    "Документ.Заказ.Позиции": "Document.Заказ.Позиции",
    "Документ.Отправка.Позиции": "Document.Отправка.Позиции",
}


def load_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def normalize(value: str) -> str:
    return "".join(str(value).split())


def iter_rows(sheet_rows: list[list[str]]) -> Iterable[list[str]]:
    for row in sheet_rows[1:]:
        if any(str(cell).strip() for cell in row):
            yield row


def xml_names(base: Path, folder: str) -> set[str]:
    result: set[str] = set()
    target = base / folder
    if not target.exists():
        return result
    for obj_dir in target.iterdir():
        if obj_dir.is_dir():
            result.add(obj_dir.name)
        elif obj_dir.is_file() and obj_dir.suffix.lower() == ".xml":
            result.add(obj_dir.stem)
    return result


def xml_table_parts(base: Path) -> set[str]:
    result: set[str] = set()
    for folder, kind in (("Catalogs", "Catalog"), ("Documents", "Document")):
        target = base / folder
        if not target.exists():
            continue

        files: list[Path] = []
        for item in target.iterdir():
            if item.is_dir():
                candidate = item / f"{item.name}.xml"
                if candidate.exists():
                    files.append(candidate)
            elif item.is_file() and item.suffix.lower() == ".xml":
                files.append(item)

        for path in files:
            owner = path.stem
            root = ET.fromstring(path.read_text(encoding="utf-8"))
            candidates = [root]
            candidates.extend(list(root))
            for candidate in candidates:
                if not candidate.tag.endswith(("Catalog", "Document")):
                    continue
                for node in candidate:
                    if not node.tag.endswith("TabularSection"):
                        continue
                    name = None
                    for sub in node:
                        if sub.tag.endswith("n"):
                            name = (sub.text or "").strip()
                            break
                        if sub.tag.endswith("Properties"):
                            for prop in sub:
                                if prop.tag.endswith("Name"):
                                    name = (prop.text or "").strip()
                                    break
                    if name:
                        result.add(f"{kind}.{owner}.{name}")
    return result


def main() -> None:
    data = load_json(EXTRACT)
    sheets = data["sheets"]

    entity_rows = sheets[4]["rows"]
    enum_rows = sheets[2]["rows"]
    table_rows = sheets[7]["rows"]

    project_objects: set[str] = set()
    for kind, folder in TYPE_MAP.items():
        if folder == "Catalog":
            for name in xml_names(ROOT, "Catalogs"):
                project_objects.add(f"Catalog.{name}")
        elif folder == "Document":
            for name in xml_names(ROOT, "Documents"):
                project_objects.add(f"Document.{name}")
        elif folder == "InformationRegister":
            for name in xml_names(ROOT, "InformationRegisters"):
                project_objects.add(f"InformationRegister.{name}")
        elif folder == "AccumulationRegister":
            for name in xml_names(ROOT, "AccumulationRegisters"):
                project_objects.add(f"AccumulationRegister.{name}")
        elif folder == "Enum":
            for name in xml_names(ROOT, "Enums"):
                project_objects.add(f"Enum.{name}")

    project_parts = xml_table_parts(ROOT)

    source_custom_objects: list[str] = []
    for row in iter_rows(entity_rows):
        variant, src_type, src_name = (row + ["", "", ""])[:3]
        if "Типовой" in variant:
            continue
        mapped_type = TYPE_MAP.get(src_type.strip())
        if not mapped_type:
            continue
        key = f"{mapped_type}.{src_name.strip()}"
        source_custom_objects.append(key)

    source_custom_enums: list[str] = []
    for row in iter_rows(enum_rows):
        variant, enum_name = (row + ["", ""])[:2]
        if "Типовой" in variant:
            continue
        source_custom_enums.append(f"Enum.{enum_name.strip()}")

    source_custom_tables: list[str] = []
    for row in iter_rows(table_rows):
        variant, owner, part = (row + ["", "", ""])[:3]
        if "Типовой" in variant:
            continue
        source_custom_tables.append(f"{owner.strip()}.{part.strip()}")

    missing_objects: list[str] = []
    for key in sorted(set(source_custom_objects + source_custom_enums)):
        mapped = OBJECT_EQUIV.get(key, key)
        if mapped not in project_objects:
            missing_objects.append(f"{key} -> {mapped}")

    missing_tables: list[str] = []
    for key in sorted(set(source_custom_tables)):
        mapped = TABLE_EQUIV.get(key, key)
        if mapped not in project_parts:
            missing_tables.append(f"{key} -> {mapped}")

    lines = [
        "# Custom Coverage Report",
        "",
        "Using only source rows from `Базовый (кастом)` and `Расширение логистики`.",
        "",
        f"Source objects: {len(set(source_custom_objects + source_custom_enums))}",
        f"Source table parts: {len(set(source_custom_tables))}",
        f"Current project objects: {len(project_objects)}",
        f"Current project table parts: {len(project_parts)}",
        "",
        "## Missing Objects",
    ]
    if missing_objects:
        lines.extend([f"- {item}" for item in missing_objects])
    else:
        lines.append("- none")

    lines.extend(["", "## Missing Table Parts"])
    if missing_tables:
        lines.extend([f"- {item}" for item in missing_tables])
    else:
        lines.append("- none")

    OUT.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"missing_objects={len(missing_objects)}")
    print(f"missing_table_parts={len(missing_tables)}")
    print(f"report={OUT}")


if __name__ == "__main__":
    main()
