#!/bin/zsh
set -e
cd "$(dirname "$0")"
exec ./deadpad --monitor --left-cm 2 --right-cm 2 "$@"
