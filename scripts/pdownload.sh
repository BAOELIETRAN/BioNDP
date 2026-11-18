#!/usr/bin/env bash
# Parallel, resumable HTTP range download.
# Usage: pdownload.sh URL OUTFILE [NPARTS]
# Re-running the same command resumes any unfinished parts.
set -euo pipefail
url=$1; out=$2; n=${3:-16}
size=$(curl -sI "$url" | awk 'tolower($1)=="content-length:"{print $2+0}')
chunk=$(( (size + n - 1) / n ))
mkdir -p "$out.parts"
for i in $(seq 0 $((n-1))); do
  start=$(( i*chunk )); end=$(( start+chunk-1 )); (( end >= size )) && end=$((size-1))
  part="$out.parts/$i"; want=$(( end-start+1 ))
  (
    for try in $(seq 1 50); do
      have=$( [ -f "$part" ] && stat -c%s "$part" || echo 0 )
      (( have >= want )) && break
      curl -s --retry 5 -r $((start+have))-$end "$url" >> "$part" || sleep 5
    done
  ) &
done
wait
for i in $(seq 0 $((n-1))); do cat "$out.parts/$i"; done > "$out"
if [ "$(stat -c%s "$out")" -eq "$size" ]; then
  rm -r "$out.parts"; echo "DONE $out ($size bytes)"
else
  echo "SIZE MISMATCH: re-run the same command to resume"; exit 1
fi
