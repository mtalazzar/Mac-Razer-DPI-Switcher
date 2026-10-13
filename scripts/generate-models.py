#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Generate the mouse model database from an OpenRazer checkout.

Usage: scripts/generate-models.py <openrazer-checkout> [<commit> <date>]

Reads (as text only, nothing from OpenRazer is executed):
  driver/razermouse_driver.h    USB product ids and response wait constants
  driver/razermouse_driver.c    per-model DPI protocol details
  daemon/openrazer_daemon/hardware/mouse.py   max DPI and supported features
and data/verified-models.json from this repo.

Writes:
  Sources/RazerKit/Generated/ModelDatabase.swift
  docs/SUPPORTED_MICE.md
"""

import ast
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CASE_RE = re.compile(r"^\s*case\s+(USB_DEVICE_ID_RAZER_\w+)\s*:")
DEFAULT_RE = re.compile(r"^\s*default\s*:")


def function_body(source, name):
    """Lines of a top-level C function, from its signature to the closing brace."""
    match = re.search(r"^static [^\n]*\b" + re.escape(name) + r"\(", source, re.M)
    if not match:
        sys.exit(f"function {name} not found in driver source")
    lines = []
    for line in source[match.start():].splitlines():
        lines.append(line)
        if line.startswith("}"):
            break
    return lines


def case_groups(lines):
    """[(case labels, body text)] for every run of `case USB_DEVICE_ID_...:` labels.

    A body runs until the next device case label or `default:`, so nested
    switches on other values stay inside the body.
    """
    groups, labels, body = [], [], []
    for line in lines:
        m = CASE_RE.match(line)
        if m:
            if body:
                groups.append((labels, "\n".join(body)))
                labels, body = [], []
            labels.append(m.group(1))
        elif DEFAULT_RE.match(line):
            if labels:
                groups.append((labels, "\n".join(body)))
            labels, body = [], []
        elif labels:
            body.append(line)
    if labels:
        groups.append((labels, "\n".join(body)))
    return groups


def transaction_id(body):
    m = re.search(r"transaction_id\.id\s*=\s*(0x[0-9a-fA-F]+)", body)
    return int(m.group(1), 16) if m else None


def parse_driver(checkout):
    header = (checkout / "driver/razermouse_driver.h").read_text()
    source = (checkout / "driver/razermouse_driver.c").read_text()

    pids = {name: int(value, 16) for name, value in
            re.findall(r"#define\s+(USB_DEVICE_ID_RAZER_\w+)\s+(0x[0-9a-fA-F]+)", header)}
    waits = {name: int(value) for name, value in
             re.findall(r"#define\s+(RAZER_\w+_WAIT_US)\s+(\d+)", header)}

    names = {}
    for labels, body in case_groups(function_body(source, "razer_attr_read_device_type")):
        m = re.search(r'device_type\s*=\s*"([^"]+)"', body)
        if m:
            for label in labels:
                names[label] = m.group(1)

    special = {}        # macro -> reason it can't use the standard protocol
    write_storage = {}  # macro -> "saved" when the driver writes VARSTORE
    write_tid = {}
    for labels, body in case_groups(function_body(source, "razer_attr_write_dpi")):
        if "deathadder3_5g" in body or "orochi2011" in body:
            reason = "uses a model-specific DPI protocol"
        elif "_byte(" in body:
            reason = "uses the older 1-byte DPI protocol"
        else:
            reason = None
        for label in labels:
            if reason:
                special[label] = reason
            elif "VARSTORE" in body:
                write_storage[label] = "saved"
            elif (tid := transaction_id(body)) is not None:
                write_tid[label] = tid

    read = {}  # macro -> (storage, tid)
    for labels, body in case_groups(function_body(source, "razer_attr_read_dpi")):
        m = re.search(r"get_dpi_xy\((NOSTORE|VARSTORE)\)", body)
        tid = transaction_id(body)
        for label in labels:
            if label in special:
                continue
            if "_byte(" in body or "return" in body.split("transaction_id")[0]:
                special.setdefault(label, "uses the older 1-byte DPI protocol")
            elif m and tid is not None:
                read[label] = ("saved" if m.group(1) == "VARSTORE" else "temporary", tid)

    transport = {}  # macro -> (interface, wait_us)
    for labels, body in case_groups(function_body(source, "razer_get_report")):
        wait = next((waits[w] for w in waits if w in body), waits["RAZER_MOUSE_WAIT_US"])
        m = re.search(r"index\s*=\s*(0x[0-9a-fA-F]+|\d+)", body)
        interface = int(m.group(1), 0) if m else 0
        for label in labels:
            transport[label] = (interface, wait)

    return pids, names, special, write_storage, write_tid, read, transport, waits["RAZER_MOUSE_WAIT_US"]


def parse_daemon(checkout):
    """{pid: {"max_dpi", "methods"}} resolved through class inheritance."""
    tree = ast.parse((checkout / "daemon/openrazer_daemon/hardware/mouse.py").read_text())
    classes = {}
    for node in tree.body:
        if not isinstance(node, ast.ClassDef):
            continue
        attrs = {}
        for stmt in node.body:
            if isinstance(stmt, ast.Assign) and len(stmt.targets) == 1 and isinstance(stmt.targets[0], ast.Name):
                try:
                    attrs[stmt.targets[0].id] = ast.literal_eval(stmt.value)
                except ValueError:
                    pass
        bases = [b.id for b in node.bases if isinstance(b, ast.Name)]
        classes[node.name] = (bases, attrs)

    def lookup(name, key, seen=()):
        if name not in classes or name in seen:
            return None
        bases, attrs = classes[name]
        if key in attrs:
            return attrs[key]
        for base in bases:
            value = lookup(base, key, seen + (name,))
            if value is not None:
                return value
        return None

    result = {}
    for name in classes:
        pid = lookup(name, "USB_PID")
        if isinstance(pid, int):
            result[pid] = {"max_dpi": lookup(name, "DPI_MAX"), "methods": lookup(name, "METHODS") or []}
    return result


def battery_powered(macro, all_macros):
    """Wireless mice keep their temporary DPI while the battery holds charge,
    including their wired (charging cable) product ids."""
    wireless = ("WIRELESS", "RECEIVER", "HYPERSPEED", "DONGLE", "DOCK")
    if any(w in macro for w in wireless):
        return True
    base = re.sub(r"_WIRED(_ALT)?$", "", macro)
    if base != macro:
        return any(m != macro and m.startswith(base + "_") and any(w in m for w in wireless) for m in all_macros)
    return False


def family(name):
    return re.sub(r"\s*\((Wired|Wireless|Receiver)\)$", "", name)


def main():
    if len(sys.argv) not in (2, 4):
        sys.exit(__doc__)
    checkout = Path(sys.argv[1])
    commit, date = (sys.argv[2], sys.argv[3]) if len(sys.argv) == 4 else ("unknown", "unknown")

    pids, names, special, write_storage, write_tid, read, transport, default_wait = parse_driver(checkout)
    daemon = parse_daemon(checkout)
    verified = {int(v["pid"], 16): v for v in json.loads((ROOT / "data/verified-models.json").read_text())}

    supported, excluded = [], []
    for macro, pid in sorted(pids.items(), key=lambda kv: kv[1]):
        info = daemon.get(pid)
        name = names.get(macro)
        if name is None and info is None:
            continue  # not a mouse product id
        name = name or macro.replace("USB_DEVICE_ID_RAZER_", "Razer ").replace("_", " ").title()

        reason = special.get(macro)
        if reason is None and "BLUETOOTH" in macro:
            reason = "Bluetooth connection (DPI commands need USB)"
        if reason is None and (macro not in write_tid or macro not in read):
            reason = "no DPI support in OpenRazer"
        if reason is None and write_tid[macro] != read[macro][1]:
            reason = "inconsistent protocol data"
        if reason is None and (info is None or not info["max_dpi"] or "set_dpi_xy" not in info["methods"]):
            reason = "no DPI support in OpenRazer"
        if reason:
            excluded.append({"pid": pid, "name": name, "reason": reason})
            continue

        interface, wait = transport.get(macro, (0, default_wait))
        supported.append({
            "pid": pid,
            "name": name,
            "family": family(name),
            "max_dpi": int(info["max_dpi"]),
            "tid": write_tid[macro],
            "write": write_storage.get(macro, "temporary"),
            "read": read[macro][0],
            "interface": interface,
            "wait": wait,
            "battery": battery_powered(macro, pids),
            "stages": "set_dpi_stages" in info["methods"],
            "verified": pid in verified,
        })

    missing = set(verified) - {m["pid"] for m in supported}
    if missing:
        sys.exit(f"verified models missing from the generated list: {sorted(hex(p) for p in missing)}")

    write_swift(supported, excluded, commit, date)
    write_docs(supported, excluded, verified, commit, date)
    print(f"{len(supported)} supported models, {len(excluded)} excluded, {len(verified)} verified")


def swift_string(s):
    return json.dumps(s, ensure_ascii=False)


def write_swift(supported, excluded, commit, date):
    lines = [
        "// SPDX-License-Identifier: GPL-3.0-or-later",
        "// GENERATED by scripts/generate-models.py — do not edit by hand.",
        f"// Source: OpenRazer {commit} ({date}), GPL-2.0-or-later,",
        "// https://github.com/openrazer/openrazer",
        "",
        "extension DeviceCatalog {",
        f"    public static let openRazerCommit = {swift_string(commit)}",
        "",
        "    static let generatedModels: [RazerModel] = [",
    ]
    for m in supported:
        lines.append(
            f"        RazerModel(productID: 0x{m['pid']:04X}, name: {swift_string(m['name'])}, "
            f"family: {swift_string(m['family'])}, maxDPI: {m['max_dpi']}, transactionID: 0x{m['tid']:02X}, "
            f"writeStorage: .{m['write']}, readStorage: .{m['read']}, interface: {m['interface']}, "
            f"responseDelay: {m['wait']}, batteryPowered: {str(m['battery']).lower()}, "
            f"hasDPIStages: {str(m['stages']).lower()}, support: .{'verified' if m['verified'] else 'untested'}),"
        )
    lines += ["    ]", "", "    static let generatedExclusions: [Int: (name: String, reason: String)] = ["]
    for m in excluded:
        lines.append(f"        0x{m['pid']:04X}: ({swift_string(m['name'])}, {swift_string(m['reason'])}),")
    lines += ["    ]", "}", ""]
    (ROOT / "Sources/RazerKit/Generated/ModelDatabase.swift").write_text("\n".join(lines))


def write_docs(supported, excluded, verified, commit, date):
    def flags(m):
        notes = []
        if m["battery"]:
            notes.append("wireless")
        if m["write"] == "saved":
            notes.append("saved DPI only")
        return ", ".join(notes)

    out = [
        "# Supported mice",
        "",
        "<!-- GENERATED by scripts/generate-models.py — do not edit by hand. -->",
        "",
        f"Protocol data comes from [OpenRazer](https://github.com/openrazer/openrazer) "
        f"(commit `{commit[:12]}`, {date}).",
        "",
        "- **Verified**: tested on real hardware with DPI Switcher.",
        "- **Untested**: should work based on OpenRazer's data. The app asks you to confirm once, "
        "and on wired mice the DPI is temporary, so unplugging resets it. "
        "[Report the result](../CONTRIBUTING.md#report-your-mouse) to get a model verified.",
        "- **wireless**: the mouse keeps the Mac DPI until it powers off, so it can carry over to "
        "another computer.",
        "- **saved DPI only**: the model only accepts a DPI saved to its memory, so the value also "
        "applies on other computers. The app can restore the original value.",
        "",
        f"## Supported ({len(supported)})",
        "",
        "| Model | USB ID | Max DPI | Status | Notes |",
        "|---|---|---|---|---|",
    ]
    for m in sorted(supported, key=lambda m: (not m["verified"], m["name"])):
        status = "✅ Verified" if m["verified"] else "Untested"
        out.append(f"| {m['name']} | `1532:{m['pid']:04X}` | {m['max_dpi']} | {status} | {flags(m)} |")
    out += [
        "",
        f"## Not supported ({len(excluded)})",
        "",
        "| Model | USB ID | Reason |",
        "|---|---|---|",
    ]
    for m in sorted(excluded, key=lambda m: m["name"]):
        out.append(f"| {m['name']} | `1532:{m['pid']:04X}` | {m['reason']} |")
    out.append("")
    (ROOT / "docs/SUPPORTED_MICE.md").write_text("\n".join(out))


if __name__ == "__main__":
    main()
