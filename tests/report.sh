#!/bin/bash
# Tests for savings-report against a local stub of the LangSmith API.
#
# Session s1 has two bulk-reads and one code-write, five main-agent Claude
# calls of 10,000 input tokens each at 09:50, 10:10, 10:20, 10:40, and 10:50,
# and one subagent call of 10,000 at 10:15:
#   bulk-read at 10:00: 5,000 in, 200 out -> 4,800 avoided, 4 later main calls -> 19,200
#   bulk-read at 10:30: 3,000 in, 100 out -> 2,900 avoided, 2 later main calls ->  5,800
#   estimated reduction = 25,000 / (60,000 + 25,000) = 29.41%

# shellcheck source=tests/lib.sh
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"

WORK=$(mktemp -d)
cat >"$WORK/stub.py" <<'PY'
import json, sys
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import urlparse, parse_qs

def run(id, name, start, tin, tout, thread=None, cost=0.0, agent=None):
    meta = {"thread_id": thread} if thread else {}
    if agent:
        meta["ls_agent_type"] = agent
    return {"id": id, "name": name, "start_time": start, "prompt_tokens": tin,
            "completion_tokens": tout, "total_cost": cost, "extra": {"metadata": meta}}

DELEGATIONS = [
    run("d1", "shunt:bulk-read", "2026-09-28T10:00:00.000000", 5000, 200, "s1", 0.01),
    run("d2", "shunt:bulk-read", "2026-09-28T10:30:00.000000", 3000, 100, "s1", 0.005),
    run("d3", "shunt:code-write", "2026-09-28T10:45:00.000000", 800, 400, "s1", 0.002),
    run("d4", "shunt:bulk-read", "2026-09-28T11:00:00.000000", 1000, 50),
]
CLAUDE = [run(f"c{i}", "Claude", f"2026-09-28T{t}:00.000000", 10000, 500, "s1", agent="root")
          for i, t in enumerate(["09:50", "10:10", "10:20", "10:40", "10:50"])]
CLAUDE.append(run("c8", "Claude", "2026-09-28T10:15:00.000000", 10000, 500, "s1", agent="subagent"))
CLAUDE.append(run("c9", "shunt:bulk-read", "2026-09-28T10:00:00.000000", 5000, 200, "s1"))

class H(BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def reply(self, obj):
        data = json.dumps(obj).encode()
        self.send_response(200); self.send_header("content-type", "application/json")
        self.send_header("content-length", str(len(data))); self.end_headers(); self.wfile.write(data)
    def do_GET(self):
        with open(sys.argv[2], "a") as log: log.write(f"GET {self.path} key={self.headers.get('x-api-key')}\n")
        q = parse_qs(urlparse(self.path).query)
        name = q.get("name", [""])[0]
        self.reply([] if name == "missing" else [{"id": "proj-1", "name": name}])
    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers["content-length"])))
        with open(sys.argv[2], "a") as log: log.write(f"POST {self.path} {json.dumps(body)}\n")
        f = body.get("filter", "")
        if body.get("run_type") == "llm":
            self.reply({"runs": CLAUDE if '"s1"' in f else [], "cursors": {"next": None}})
        elif "cursor" not in body:
            self.reply({"runs": DELEGATIONS[:1], "cursors": {"next": "page2"}})
        else:
            self.reply({"runs": DELEGATIONS[1:], "cursors": {"next": None}})

srv = HTTPServer(("127.0.0.1", 0), H)
open(sys.argv[1], "w").write(str(srv.server_port))
srv.serve_forever()
PY

python3 "$WORK/stub.py" "$WORK/port" "$WORK/requests.log" &
stub_pid=$!
trap 'kill $stub_pid 2>/dev/null; rm -rf "$WORK"' EXIT
for _ in $(seq 1 50); do [ -s "$WORK/port" ] && break; sleep 0.1; done
ENDPOINT="http://127.0.0.1:$(cat "$WORK/port")"

report() {
  env -i PATH="/usr/bin:/bin" LANGSMITH_ENDPOINT="$ENDPOINT" SHUNT_LANGSMITH_API_KEY=test-key "$@" \
    python3 "$SHUNT/scripts/savings-report" "${REPORT_ARGS[@]}" >"$WORK/out" 2>"$WORK/err"
  rc=$?
}
field() { jq -r --arg s "$1" ".sessions[] | select(.session == \$s) | .$2" "$WORK/out"; }

echo "savings-report"
REPORT_ARGS=(--json)
report
assert "exits 0" [ "$rc" -eq 0 ]
assert "follows the pagination cursor" [ "$(grep -c '"cursor": "page2"' "$WORK/requests.log")" -eq 1 ]
assert "sends the key" contains "$WORK/requests.log" "key=test-key"
assert "filters delegations by tag" contains "$WORK/requests.log" 'has(tags, \"langsmith-shunt\")'
assert "filters Claude runs by thread_id" contains "$WORK/requests.log" 'eq(metadata_value, \"s1\")'
assert "counts bulk-reads" [ "$(field s1 bulk_reads)" = 2 ]
assert "counts code-writes" [ "$(field s1 code_writes)" = 1 ]
assert "sums worker input tokens" [ "$(field s1 worker_input_tokens)" = 8800 ]
assert "context tokens avoided = 4,800 + 2,900" [ "$(field s1 context_tokens_avoided)" = 7700 ]
assert "estimated input avoided = 19,200 + 5,800" [ "$(field s1 input_tokens_avoided_est)" = 25000 ]
assert "excludes shunt runs from Claude calls" [ "$(field s1 claude_calls)" = 6 ]
assert "sums Claude input tokens, subagent included" [ "$(field s1 claude_input_tokens)" = 60000 ]
assert "reduction = 25,000 / 85,000" [ "$(field s1 input_reduction_est)" = 0.2941 ]
assert "code tokens written by the worker" [ "$(field s1 code_tokens_written_by_worker)" = 400 ]
assert "run without a session id is grouped" [ "$(field '(no session id)' bulk_reads)" = 1 ]
assert "no reduction without Claude calls" [ "$(field '(no session id)' input_reduction_est)" = null ]

REPORT_ARGS=()
report
assert "table shows the reduction" contains "$WORK/out" "Input reduction, est. [3]        29.4%"
assert "table explains the figures" contains "$WORK/out" "[2] [1] for each bulk-read, times the number of main-agent Claude calls"

: >"$WORK/requests.log"
REPORT_ARGS=(--current --json)
report CLAUDE_CODE_SESSION_ID=s1
assert "--current filters on this session" contains "$WORK/requests.log" 'eq(metadata_key, \"thread_id\"), eq(metadata_value, \"s1\"))'

REPORT_ARGS=(--project missing)
report
assert "unknown project exits non-zero" [ "$rc" -ne 0 ]
assert "unknown project says so" contains "$WORK/err" "no LangSmith project named 'missing'"

REPORT_ARGS=()
report SHUNT_LANGSMITH_API_KEY=
assert "no key exits non-zero" [ "$rc" -ne 0 ]

summary
