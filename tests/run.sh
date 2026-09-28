#!/bin/bash
# Runs every test. No network access and no API keys needed.
cd "$(dirname "$0")" || exit 1
status=0
for t in hooks.sh transport.sh report.sh; do
  echo "== $t"
  bash "$t" || status=1
  echo
done
exit $status
