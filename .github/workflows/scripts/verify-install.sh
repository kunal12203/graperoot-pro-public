#!/usr/bin/env bash
# Verify a fresh GrapeRoot Pro install on Linux/macOS. Used by the smoke-test workflow.
set -Eeuo pipefail

PRO=$HOME/.graperoot-pro

fail() { echo "FAIL: $1"; exit 1; }

[ -d "$PRO" ]                                      || fail "install dir missing"
[ -f "$PRO/license.key" ]                          || fail "license.key missing"
[ -f "$PRO/mcp_graph_server_v7.4.py" ]             || fail "MCP server missing"
[ -f "$PRO/graph_builder.py" ]                     || fail "graph_builder missing"
[ -f "$PRO/launch.py" ]                            || fail "launch.py missing"
[ -x "$PRO/venv/bin/python3" ]                     || fail "venv python missing"
[ -x "$PRO/bin/dgc-pro" ]                          || fail "dgc-pro shim missing"
[ -x "$PRO/bin/launch_pro.sh" ]                    || fail "launch_pro.sh missing"
[ -f "$PRO/bin/version.txt" ]                      || fail "version.txt missing"
echo "[ok] all expected files present"

# Security regression guard
if grep -q '0\.0\.0\.0' "$PRO/mcp_graph_server_v7.4.py"; then
  fail "server binds to 0.0.0.0 — security regression"
fi
echo "[ok] server binds 127.0.0.1 only"

VER=$(cat "$PRO/bin/version.txt")
echo "[ok] installed version: $VER"

# venv has all our deps
"$PRO/venv/bin/python3" -c "import mcp, uvicorn, starlette, graperoot; print('[ok] python imports')"

# launch.py runs cleanly
"$PRO/venv/bin/python3" "$PRO/launch.py" --version

echo
echo "================================="
echo " ALL LINUX CHECKS PASSED ($VER)"
echo "================================="
