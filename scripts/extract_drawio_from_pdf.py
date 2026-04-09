import argparse
import html
import json
import re
import urllib.parse
import xml.etree.ElementTree as ET
import zlib
from pathlib import Path


STREAM_RE = re.compile(rb"stream\r?\n(.*?)\r?\nendstream", re.S)


def strip_html(value: str) -> str:
    value = html.unescape(value or "")
    value = re.sub(r"(?i)<\s*br\s*/?\s*>", "\n", value)
    value = re.sub(r"(?i)</\s*(div|p|h[1-6]|li|tr)\s*>", "\n", value)
    value = re.sub(r"<[^>]+>", "", value)
    value = html.unescape(value)
    value = value.replace("\xa0", " ")
    lines = [re.sub(r"\s+", " ", line).strip() for line in value.splitlines()]
    return "\n".join(line for line in lines if line)


def decompressed_payloads(pdf_bytes: bytes) -> list[bytes]:
    payloads: list[bytes] = []
    for match in STREAM_RE.finditer(pdf_bytes):
        raw = match.group(1)
        payloads.append(raw)
        try:
            payloads.append(zlib.decompress(raw))
        except Exception:
            pass
    return payloads


def find_encoded_mxfile(payloads: list[bytes]) -> str:
    candidates: list[str] = []
    for payload in payloads:
        latin = payload.decode("latin1", errors="ignore")
        for match in re.finditer(r"<(FEFF[0-9A-Fa-f]{32,})>", latin):
            hex_text = match.group(1)
            try:
                decoded = bytes.fromhex(hex_text).decode("utf-16-be", errors="ignore")
            except Exception:
                continue
            if "%3Cmxfile" in decoded:
                idx = decoded.find("%3Cmxfile")
                end_marker = "%3C%2Fmxfile%3E"
                end = decoded.find(end_marker, idx)
                if end >= 0:
                    candidates.append(decoded[idx : end + len(end_marker)])
        for encoding in ("utf-8", "latin1", "utf-16-le", "utf-16-be"):
            try:
                text = payload.decode(encoding, errors="ignore")
            except Exception:
                continue
            if "%3Cmxfile" in text:
                idx = text.find("%3Cmxfile")
                # The embedded value runs until the encoded closing mxfile tag.
                end_marker = "%3C%2Fmxfile%3E"
                end = text.find(end_marker, idx)
                if end >= 0:
                    candidates.append(text[idx : end + len(end_marker)])
            if "<mxfile" in text:
                idx = text.find("<mxfile")
                end = text.find("</mxfile>", idx)
                if end >= 0:
                    candidates.append(urllib.parse.quote(text[idx : end + len("</mxfile>")]))
    if not candidates:
        raise RuntimeError("mxfile was not found in PDF streams")
    return max(candidates, key=len)


def extract_cells(mxfile_xml: str) -> list[dict]:
    root = ET.fromstring(mxfile_xml)
    result: list[dict] = []
    for page_index, diagram in enumerate(root.findall("diagram"), start=1):
        page_name = diagram.attrib.get("name", f"Page {page_index}")
        graph = diagram.find("mxGraphModel")
        if graph is None:
            continue
        root_node = graph.find("root")
        if root_node is None:
            continue
        for cell in root_node.findall("mxCell"):
            raw_value = cell.attrib.get("value", "")
            text = strip_html(raw_value)
            if not text:
                continue
            geometry = cell.find("mxGeometry")
            x = geometry.attrib.get("x") if geometry is not None else None
            y = geometry.attrib.get("y") if geometry is not None else None
            result.append(
                {
                    "page": page_name,
                    "id": cell.attrib.get("id", ""),
                    "vertex": cell.attrib.get("vertex") == "1",
                    "edge": cell.attrib.get("edge") == "1",
                    "x": float(x) if x not in (None, "") else None,
                    "y": float(y) if y not in (None, "") else None,
                    "text": text,
                    "style": cell.attrib.get("style", ""),
                }
            )
    return sorted(result, key=lambda item: (item["page"], item["y"] is None, item["y"] or 0, item["x"] is None, item["x"] or 0, item["text"]))


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("pdf", type=Path)
    parser.add_argument("out_dir", type=Path)
    args = parser.parse_args()

    pdf_bytes = args.pdf.read_bytes()
    payloads = decompressed_payloads(pdf_bytes)
    encoded = find_encoded_mxfile(payloads)
    mxfile_xml = urllib.parse.unquote(encoded)
    cells = extract_cells(mxfile_xml)

    args.out_dir.mkdir(parents=True, exist_ok=True)
    xml_path = args.out_dir / "drawio_extracted.mxfile.xml"
    json_path = args.out_dir / "drawio_extracted_cells.json"
    md_path = args.out_dir / "drawio_extracted_cells.md"

    xml_path.write_text(mxfile_xml, encoding="utf-8")
    json_path.write_text(json.dumps(cells, ensure_ascii=False, indent=2), encoding="utf-8")

    lines: list[str] = [
        "# Текст схемы Draw.io из PDF",
        "",
        f"Файл: `{args.pdf}`",
        f"Найдено блоков с текстом: `{len(cells)}`",
        "",
    ]
    current_page = None
    for cell in cells:
        if cell["page"] != current_page:
            current_page = cell["page"]
            lines.append(f"## {current_page}")
            lines.append("")
        position = ""
        if cell["x"] is not None or cell["y"] is not None:
            position = f" `x={cell['x']} y={cell['y']}`"
        kind = "edge" if cell["edge"] else "block"
        text = cell["text"].replace("\n", " / ")
        lines.append(f"- `{kind}`{position}: {text}")

    md_path.write_text("\n".join(lines), encoding="utf-8")
    print(json.dumps({"xml": str(xml_path), "json": str(json_path), "markdown": str(md_path), "cells": len(cells)}, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
