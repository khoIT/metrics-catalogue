#!/usr/bin/env python3
"""Trino schema introspection helper.

Lists schemas/tables/columns under a catalog, honouring TRINO_PORT and SSL
(unlike the slimmer trino_q.py which hardcodes :443). Uses HTTP Basic auth
with the same env vars Cube uses, mapped from CUBEJS_DB_*.

Env vars:
  TRINO_HOST       (default: gio-gds-trino.vnggames.net)
  TRINO_PORT       (default: 8080)
  TRINO_SSL        (default: true)
  TRINO_USER       required
  TRINO_PASS       required (HTTP Basic password)
  TRINO_CATALOG    (default: game_integration)

Usage:
  python3 examples/trino_introspect.py schemas
  python3 examples/trino_introspect.py tables <schema>
  python3 examples/trino_introspect.py columns <schema> <table>
  python3 examples/trino_introspect.py describe <schema> [table1 table2 ...]
      # describe = tables + columns for each, in one shot
"""

import base64, json, os, sys, urllib.request, ssl

HOST    = os.environ.get("TRINO_HOST", "gio-gds-trino.vnggames.net")
PORT    = int(os.environ.get("TRINO_PORT", "8080"))
SSL_ON  = os.environ.get("TRINO_SSL", "true").lower() in ("1", "true", "yes")
USER    = os.environ["TRINO_USER"]
PASS    = os.environ["TRINO_PASS"]
CATALOG = os.environ.get("TRINO_CATALOG", "game_integration")

SCHEME = "https" if SSL_ON else "http"
AUTH   = base64.b64encode(f"{USER}:{PASS}".encode()).decode()


def run_sql(sql, schema=None):
    """Execute SQL, return [columns, [rows]]."""
    headers = {
        "Authorization": "Basic " + AUTH,
        "X-Trino-User":    USER,
        "X-Trino-Catalog": CATALOG,
        "Content-Type":    "text/plain",
    }
    if schema:
        headers["X-Trino-Schema"] = schema
    ctx = ssl.create_default_context() if SSL_ON else None
    req = urllib.request.Request(
        f"{SCHEME}://{HOST}:{PORT}/v1/statement",
        data=sql.encode(), headers=headers, method="POST",
    )
    d = json.loads(urllib.request.urlopen(req, context=ctx).read())
    cols, rows = None, []
    while True:
        if "columns" in d and cols is None:
            cols = [c["name"] for c in d["columns"]]
        if "data" in d:
            rows.extend(d["data"])
        if "error" in d:
            sys.stderr.write("ERROR: " + json.dumps(d["error"], indent=2) + "\n")
            sys.exit(2)
        nxt = d.get("nextUri")
        if not nxt:
            return cols or [], rows
        nreq = urllib.request.Request(nxt, headers={
            "Authorization": "Basic " + AUTH, "X-Trino-User": USER,
        })
        d = json.loads(urllib.request.urlopen(nreq, context=ctx).read())


def print_table(cols, rows):
    if cols:
        print("\t".join(cols))
    for r in rows:
        print("\t".join("" if v is None else str(v) for v in r))


def cmd_schemas():
    print_table(*run_sql(f"SHOW SCHEMAS FROM {CATALOG}"))


def cmd_tables(schema):
    print_table(*run_sql(f"SHOW TABLES FROM {CATALOG}.{schema}"))


def cmd_columns(schema, table):
    print_table(*run_sql(
        f"SELECT column_name, data_type, is_nullable, ordinal_position "
        f"FROM {CATALOG}.information_schema.columns "
        f"WHERE table_schema = '{schema}' AND table_name = '{table}' "
        f"ORDER BY ordinal_position"
    ))


def cmd_describe(schema, *tables):
    if not tables:
        _, rows = run_sql(f"SHOW TABLES FROM {CATALOG}.{schema}")
        tables = [r[0] for r in rows]
    for t in tables:
        print(f"\n=== {schema}.{t} ===")
        cmd_columns(schema, t)


def main():
    args = sys.argv[1:]
    if not args:
        print(__doc__); sys.exit(2)
    cmd, rest = args[0], args[1:]
    fns = {"schemas": cmd_schemas, "tables": cmd_tables,
           "columns": cmd_columns, "describe": cmd_describe}
    if cmd not in fns:
        sys.stderr.write(f"unknown command: {cmd}\n{__doc__}")
        sys.exit(2)
    fns[cmd](*rest)


if __name__ == "__main__":
    main()
