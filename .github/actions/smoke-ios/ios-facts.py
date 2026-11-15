"""Facts for the iOS guideline checks, collected from the built app on the macOS runner (nm, otool, plistlib).

Usage: python3 -I ios-facts.py <App.app> <ios-symbols.json> <out.json>
Only facts — which watched symbols each binary references, the Info.plist, the privacy manifests and the embedded
frameworks. The rules (what is missing, how serious) live in packages/cli/src/guidelines/ios.ts.
"""
import glob
import json
import os
import plistlib
import re
import subprocess
import sys


def sh(*args: str) -> str:
    return subprocess.run(args, capture_output=True, check=False).stdout.decode("utf-8", "replace")


def load_plist(path: str):
    try:
        with open(path, "rb") as f:
            return plistlib.load(f)
    except Exception as e:  # noqa: BLE001
        return {"_error": str(e)}


def jsonable(v):
    if isinstance(v, dict):
        return {k: jsonable(x) for k, x in v.items()}
    if isinstance(v, list):
        return [jsonable(x) for x in v]
    if isinstance(v, (bytes, bytearray)):
        return f"<{len(v)} bytes>"
    if isinstance(v, (str, int, float, bool)) or v is None:
        return v
    return str(v)


def main(app: str, symbols_file: str, out: str) -> None:
    with open(symbols_file) as f:
        cfg = json.load(f)
    watch_syms, watch_sels = set(), set()
    for spec in cfg["required_reason"].values():
        watch_syms.update(spec["symbols"])
        watch_sels.update(spec["selectors"])
    for p in cfg["purpose"]:
        watch_syms.update(p["symbols"])
        watch_sels.update(p["selectors"])
    watch_syms.update([cfg["idfa"], cfg["att"]])

    info = load_plist(os.path.join(app, "Info.plist"))
    binaries = []
    targets = [(os.path.join(app, info.get("CFBundleExecutable", "")), None)]
    for fw in sorted(glob.glob(os.path.join(app, "Frameworks", "*.framework"))):
        name = os.path.splitext(os.path.basename(fw))[0]
        fwinfo = load_plist(os.path.join(fw, "Info.plist")) if os.path.exists(os.path.join(fw, "Info.plist")) else {}
        targets.append((os.path.join(fw, fwinfo.get("CFBundleExecutable", name)), name))
    for dylib in sorted(glob.glob(os.path.join(app, "Frameworks", "*.dylib"))):
        targets.append((dylib, os.path.basename(dylib)))
    for path, framework in targets:
        if not os.path.isfile(path):
            continue
        syms = set(sh("nm", "-u", "-j", path).split())
        syms |= {s for s in sh("nm", "-U", "-j", path).split() if s.startswith("_OBJC_CLASS_$_")}  # statically linked classes
        meth = sh("otool", "-v", "-s", "__TEXT", "__objc_methname", path)
        sels = {m.group(1).strip() for m in re.finditer(r"^[0-9a-fA-F]{8,}\s+(\S.*)$", meth, re.M)}
        binaries.append({
            "path": os.path.relpath(path, app),
            "framework": framework,
            "symbols": sorted(syms & watch_syms),
            "selectors": sorted(sels & watch_sels),
        })

    manifests = {}
    for p in glob.glob(os.path.join(app, "**", "PrivacyInfo.xcprivacy"), recursive=True):
        manifests[os.path.relpath(p, app)] = jsonable(load_plist(p))
    frameworks = [{"name": os.path.splitext(os.path.basename(fw))[0], "has_manifest": os.path.exists(os.path.join(fw, "PrivacyInfo.xcprivacy"))}
                  for fw in sorted(glob.glob(os.path.join(app, "Frameworks", "*.framework")))]
    facts = {
        "app": os.path.basename(app),
        "info": jsonable(info),
        "has_assets_car": os.path.exists(os.path.join(app, "Assets.car")),
        "binaries": binaries,
        "manifests": manifests,
        "frameworks": frameworks,
    }
    with open(out, "w") as f:
        json.dump(facts, f, indent=1)
    print(f"🔎 iOS facts: {len(binaries)} binaries, {len(manifests)} privacy manifests → {out}")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2], sys.argv[3])
