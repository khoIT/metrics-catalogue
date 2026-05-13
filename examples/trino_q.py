#!/usr/bin/env python3
"""Tiny Trino REST client. Usage: python3 trino_q.py 'SQL...'"""
import base64, json, os, sys, urllib.request, ssl

HOST = os.environ.get("TRINO_HOST", "trino.gio.vng.vn")
USER = os.environ.get("TRINO_USER", "gds_da")
PASS = os.environ.get("TRINO_PASS", "HSayxxgeMPtW2DnP4KXH")
CATALOG = os.environ.get("TRINO_CATALOG", "game_integration")
SCHEMA = os.environ.get("TRINO_SCHEMA", "cfm_vn")

sql = sys.argv[1] if len(sys.argv) > 1 else sys.stdin.read()
auth = base64.b64encode(f"{USER}:{PASS}".encode()).decode()
headers = {
    "Authorization": "Basic " + auth,
    "X-Trino-User": USER,
    "X-Trino-Catalog": CATALOG,
    "X-Trino-Schema": SCHEMA,
    "Content-Type": "text/plain",
}
ctx = ssl.create_default_context()

req = urllib.request.Request(f"https://{HOST}/v1/statement", data=sql.encode(), headers=headers, method="POST")
d = json.loads(urllib.request.urlopen(req, context=ctx).read())

cols = None
rows = []
while True:
    if "columns" in d and cols is None:
        cols = [c["name"] for c in d["columns"]]
    if "data" in d:
        rows.extend(d["data"])
    if "error" in d:
        print("ERROR:", json.dumps(d["error"], indent=2), file=sys.stderr)
        sys.exit(2)
    nxt = d.get("nextUri")
    if not nxt:
        break
    nreq = urllib.request.Request(nxt, headers={"Authorization": "Basic " + auth, "X-Trino-User": USER})
    d = json.loads(urllib.request.urlopen(nreq, context=ctx).read())

print("\t".join(cols or []))
for r in rows:
    print("\t".join("" if v is None else str(v) for v in r))
