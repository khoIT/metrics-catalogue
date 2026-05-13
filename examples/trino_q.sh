#!/usr/bin/env bash
# Run a SQL statement against trino.gio.vng.vn via REST and dump full result.
# Usage: bash trino_q.sh "SELECT 1"
set -euo pipefail

: "${TRINO_HOST:=trino.gio.vng.vn}"
: "${TRINO_USER:=gds_da}"
: "${TRINO_PASS:=HSayxxgeMPtW2DnP4KXH}"
: "${TRINO_CATALOG:=game_integration}"
: "${TRINO_SCHEMA:=cfm_vn}"

SQL="$1"
AUTH=$(printf '%s:%s' "$TRINO_USER" "$TRINO_PASS" | base64 -w0)

resp=$(curl -sS "https://$TRINO_HOST/v1/statement" \
  -H "Authorization: Basic $AUTH" \
  -H "X-Trino-User: $TRINO_USER" \
  -H "X-Trino-Catalog: $TRINO_CATALOG" \
  -H "X-Trino-Schema: $TRINO_SCHEMA" \
  -H "Content-Type: text/plain" \
  --data "$SQL")

# Walk nextUri until done. Print all data arrays.
echo "$resp" | python3 -c '
import json,sys,urllib.request,base64,os
auth = base64.b64encode(f"{os.environ[\"TRINO_USER\"]}:{os.environ[\"TRINO_PASS\"]}".encode()).decode()
d = json.loads(sys.stdin.read())
cols = None
rows = []
while True:
    if "columns" in d and cols is None:
        cols = [c["name"] for c in d["columns"]]
    if "data" in d:
        rows.extend(d["data"])
    if "error" in d:
        print("ERROR:", d["error"]); sys.exit(2)
    nxt = d.get("nextUri")
    if not nxt:
        break
    req = urllib.request.Request(nxt, headers={"Authorization": f"Basic {auth}", "X-Trino-User": os.environ["TRINO_USER"]})
    d = json.loads(urllib.request.urlopen(req).read())
print("\t".join(cols or []))
for r in rows:
    print("\t".join("" if v is None else str(v) for v in r))
'
