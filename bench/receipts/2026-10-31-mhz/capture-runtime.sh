#!/bin/sh
exec python3 "$(dirname "$0")/capture_runtime.py" "$@"
