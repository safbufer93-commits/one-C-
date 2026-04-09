import argparse
import json
import re
import zlib
from pathlib import Path


def printable_runs(data: bytes, min_len: int = 4) -> list[str]:
    text = data.decode("latin1", errors="ignore")
    runs = re.findall(r"[\x20-\x7EА-Яа-яЁё]{%d,}" % min_len, text)
    return [run.strip() for run in runs if run.strip()]


def decode_utf16_hex_strings(text: str) -> list[str]:
    values: list[str] = []
    for match in re.finditer(r"<([0-9A-Fa-f]{8,})>", text):
        raw_hex = match.group(1)
        if len(raw_hex) % 2:
            continue
        data = bytes.fromhex(raw_hex)
        for encoding in ("utf-16-be", "utf-16-le"):
            try:
                decoded = data.decode(encoding).strip("\x00").strip()
            except UnicodeDecodeError:
                continue
            if decoded and any(ch.isalpha() for ch in decoded):
                values.append(decoded)
    return values


def extract_streams(pdf_bytes: bytes) -> list[dict]:
    streams: list[dict] = []
    pattern = re.compile(rb"stream\r?\n(.*?)\r?\nendstream", re.S)
    for index, match in enumerate(pattern.finditer(pdf_bytes), start=1):
        raw = match.group(1)
        decompressed = None
        error = None
        try:
            decompressed = zlib.decompress(raw)
        except Exception as exc:
            error = str(exc)

        payload = decompressed if decompressed is not None else raw
        latin_text = payload.decode("latin1", errors="ignore")
        streams.append(
            {
                "index": index,
                "raw_length": len(raw),
                "decompressed_length": len(decompressed) if decompressed is not None else None,
                "decompress_error": error,
                "printable": printable_runs(payload),
                "utf16_hex": decode_utf16_hex_strings(latin_text),
            }
        )
    return streams


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("pdf", type=Path)
    parser.add_argument("out_dir", type=Path)
    args = parser.parse_args()

    pdf_bytes = args.pdf.read_bytes()
    args.out_dir.mkdir(parents=True, exist_ok=True)

    streams = extract_streams(pdf_bytes)
    summary = {
        "path": str(args.pdf),
        "size": len(pdf_bytes),
        "stream_count": len(streams),
        "streams": streams,
    }

    json_path = args.out_dir / "drawio_pdf_streams.json"
    text_path = args.out_dir / "drawio_pdf_streams.txt"
    json_path.write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8")

    lines: list[str] = []
    lines.append(f"PDF: {args.pdf}")
    lines.append(f"Streams: {len(streams)}")
    lines.append("")
    for stream in streams:
        lines.append(f"## stream {stream['index']}")
        lines.append(f"raw={stream['raw_length']} decompressed={stream['decompressed_length']} error={stream['decompress_error']}")
        if stream["utf16_hex"]:
            lines.append("utf16_hex:")
            lines.extend(f"- {value}" for value in stream["utf16_hex"][:200])
        if stream["printable"]:
            lines.append("printable:")
            lines.extend(f"- {value}" for value in stream["printable"][:300])
        lines.append("")

    text_path.write_text("\n".join(lines), encoding="utf-8")
    print(json.dumps({"json": str(json_path), "text": str(text_path), "stream_count": len(streams)}, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
