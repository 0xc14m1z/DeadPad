#!/bin/zsh
set -e
cd "$(dirname "$0")"
exec ./deadpad --left-cm 2 --right-cm 2 --policy all "$@"
