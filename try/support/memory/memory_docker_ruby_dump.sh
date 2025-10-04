#!/bin/bash
# try/edge_cases/docker_dump.sh

# Usage: bash $0 <container_id>
#
# See example output at end.

# UnsortedSet CONTAINER_ID to $CONTAINER_ID or the first argument
CONTAINER_ID=${CONTAINER_ID:-$1}

if [ -z "$CONTAINER_ID" ]; then
  echo "Usage: $0 <container_id>"
  echo "Or set CONTAINER_ID environment variable"
  exit 1
fi

# Create a script to dump all string-like patterns
docker exec $CONTAINER_ID bash -c '
  # Install required packages
  apt-get update -qq && apt-get install -y -qq procps binutils

  PID=$(pgrep -f ruby)

  if [ -z "$PID" ]; then
    echo "No Ruby process found"
    exit 1
  fi

  echo "Dumping memory for Ruby process $PID"

  # Check if maps file exists
  if [ ! -f "/proc/$PID/maps" ]; then
    echo "Cannot access memory maps for process $PID"
    exit 1
  fi

  # Get memory regions
  grep -E "rw-p|r--p" /proc/$PID/maps | while read line; do
    start=$(echo $line | cut -d"-" -f1)
    end=$(echo $line | cut -d" " -f1 | cut -d"-" -f2)

    # Convert hex to decimal and dump
    start_dec=$((16#$start))
    end_dec=$((16#$end))
    size=$((end_dec - start_dec))

    # Skip if size is too large (> 10MB) to avoid hanging
    if [ $size -gt 10485760 ]; then
      continue
    fi

    dd if=/proc/$PID/mem bs=1 skip=$start_dec count=$size 2>/dev/null
  done | strings | grep -i "secret\|api\|key\|token" | head -20
'

# Example Output:
#
#   $ SECRET=august7th2025
#   $
#   $ docker run --rm -d -p 3000:3000 \
#     -e SECRET=$SECRET \
#     -e REDIS_URL=redis://host.docker.internal:2525/0 \
#     ghcr.io/onetimesecret/devtimesecret-lite:latest
#
#     abcd1234
#
#   $ bash try/edge_cases/docker_ruby_dump.sh abcd1234
#   ...
#   Dumping memory for Ruby process 60
#   SECRET
#   SECRET
#   SECRET=august6th2025
#     done | strings | grep -i "secret...
#   SECRET=august6th2025
#     done | strings | grep -i "secret...
#   grep -i "secret\|api\|key|token"
#     done | strings | grep -i "secret...
#   SECRET=august6th2025
#
#   $ docker kill abcd1234
