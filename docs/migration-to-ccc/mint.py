#!/usr/bin/env python3
"""Serial mint runner: consume per-area manifest JSONs -> CCC artifacts via ccc-bd.

Safe under the Dolt no-auto-commit server because ccc-bd commits each write and
we never run two writes concurrently. Run from the project root.
"""
import json, subprocess, re, sys, glob, os, pathlib

ROOT = "/private/var/mdes/workspace"
MANI = "/private/tmp/mdes-migration"
DRY  = "--dry-run" in sys.argv

report = {"designs":0,"standalone_designs":0,"epics":0,"stories":0,"tasks":0,
          "shipped":0,"in_progress":0,"open":0,"errors":[]}

def run(args):
    """Run ccc-bd; return (rc, stdout+stderr)."""
    if DRY:
        print("DRY:", " ".join(args)); return 0, "DRY created: DRY-XID  (x)\n  path:  /dev/null"
    p = subprocess.run(args, cwd=ROOT, capture_output=True, text=True)
    return p.returncode, (p.stdout or "") + (p.stderr or "")

def mint(args):
    rc, out = run(args)
    xid = path = None
    m = re.search(r"created:\s+(\S+)", out)
    if m: xid = m.group(1)
    m = re.search(r"path:\s+(\S+)", out)
    if m: path = m.group(1)
    if rc != 0 or not xid:
        report["errors"].append({"cmd":" ".join(args[1:]), "out":out.strip()[:400]})
    return xid, path, rc, out

def set_status(xid, status, version):
    if not xid or DRY: return
    if status == "shipped":
        reason = f"historical: shipped in TUMU {version}".strip()
        run(["ccc-bd","close",xid,"--reason",reason,"--force"]); report["shipped"]+=1
    elif status == "in-progress":
        run(["ccc-bd","update",xid,"--status=in-progress"]); report["in_progress"]+=1
    else:
        run(["ccc-bd","update",xid,"--status=open"]); report["open"]+=1

def inject_summary(path, summary, source, version, provenance):
    """Replace the template '## Summary' placeholder + append a TUMU Provenance block."""
    if not path or DRY or not os.path.exists(path): return
    t = pathlib.Path(path).read_text()
    # replace first italic placeholder under ## Summary
    t = re.sub(r"(## Summary\n\n)_\(.*?\)_", lambda m: m.group(1)+summary, t, count=1, flags=re.S)
    prov = f"\n\n## TUMU Provenance\n\n- **Source:** {source}\n- **Shipped in:** {version or 'n/a'}\n- **History:** {provenance}\n"
    if "## TUMU Provenance" not in t:
        t += prov
    pathlib.Path(path).write_text(t)

def inject_tasks(path, tasks):
    """Replace the Definition of Done placeholder block with real backlog tasks."""
    if not path or DRY or not os.path.exists(path) or not tasks: return
    t = pathlib.Path(path).read_text()
    lines = ["- [x] "+x["title"] if x.get("done") else "- [ ] "+x["title"] for x in tasks]
    block = "## Definition of Done\n\n" + "\n".join(lines) + "\n"
    # replace from '## Definition of Done' up to the next '## ' header
    t2 = re.sub(r"## Definition of Done\n.*?(?=\n## )", block+"\n", t, count=1, flags=re.S)
    if t2 == t:  # no following header; replace to EOF
        t2 = re.sub(r"## Definition of Done\n.*\Z", block, t, count=1, flags=re.S)
    pathlib.Path(path).write_text(t2)

def process(area):
    eff = area["effort"]; slug = area["slug"]
    # 1. area DESIGN
    xid, path, rc, _ = mint(["ccc-bd","new","design",slug,"--effort",eff,"--title",area["design_title"]])
    if xid:
        report["designs"]+=1
        inject_summary(path, area.get("design_summary",""), "PROJECT_AREAS.md", "", "Area-level grouping.")
    # 2. standalone designs (own folders, same effort token)
    for sd in area.get("standalone_designs",[]) or []:
        sx, sp, _, _ = mint(["ccc-bd","new","design",sd["slug"],"--effort",eff,"--title",sd["title"]])
        if sx:
            report["standalone_designs"]+=1
            inject_summary(sp, sd.get("summary",""), sd.get("source",""), sd.get("version",""), sd.get("summary",""))
            set_status(sx, sd.get("status","open"), sd.get("version",""))
    # 3. epics
    for ep in area.get("epics",[]) or []:
        ex, epath, _, _ = mint(["ccc-bd","new","epic",slug,ep["slug"],"--effort",eff,"--title",ep["title"]])
        if not ex: continue
        report["epics"]+=1
        inject_summary(epath, ep.get("summary",""), ep.get("source",""), ep.get("version",""),
                       ep.get("summary",""))
        # 4. stories
        for st in ep.get("stories",[]) or []:
            parent = f"{slug}/epic-{ep['slug']}"
            sx, spath, _, _ = mint(["ccc-bd","new","story",parent,st["slug"],"--effort",eff,
                                    "--title",st["title"],"--status","open"])
            if not sx: continue
            report["stories"]+=1
            tasks = st.get("tasks",[]) or []
            report["tasks"] += len(tasks)
            inject_summary(spath, st.get("summary",""), st.get("source",""), st.get("version",""),
                           st.get("summary",""))
            inject_tasks(spath, tasks)
            set_status(sx, st.get("status","open"), st.get("version",""))

def main():
    files = sorted(glob.glob(f"{MANI}/*.json"))
    files = [f for f in files if os.path.basename(f) not in ("mint-report.json",)]
    print(f"manifests: {len(files)}")
    for f in files:
        try:
            area = json.load(open(f))
        except Exception as e:
            report["errors"].append({"file":f,"out":f"JSON parse: {e}"}); continue
        print(f"== {area.get('slug')} ({area.get('effort')}) ==")
        process(area)
    json.dump(report, open(f"{MANI}/mint-report.json","w"), indent=2)
    print(json.dumps({k:v for k,v in report.items() if k!='errors'}, indent=2))
    print(f"errors: {len(report['errors'])} (see {MANI}/mint-report.json)")

if __name__ == "__main__":
    main()
