# Script to extract services per compartment


#!/usr/bin/env bash
set -euo pipefail

# Prompt for compartment OCID
read -p "Enter compartment OCID: " COMPARTMENT_OCID

# Validate it's not empty
if [[ -z "$COMPARTMENT_OCID" ]]; then
  echo "Error: Compartment OCID cannot be empty"
  exit 1
fi

echo "Fetching resources from compartment: $COMPARTMENT_OCID"

PAGE=""
FIRST=1

while :; do
  if [[ -z "$PAGE" ]]; then
    RESP=$(oci search resource structured-search --query-text "query all resources where compartmentId = '$COMPARTMENT_OCID'" --limit 1000)
  else
    RESP=$(oci search resource structured-search --query-text "query all resources where compartmentId = '$COMPARTMENT_OCID'" --limit 1000 --page "$PAGE")
  fi

  if [[ $FIRST -eq 1 ]]; then
    echo "$RESP" | jq -r '["display-name","lifecycle-state","resource-type"], (.data.items[] | [.["display-name"], .["lifecycle-state"], .["resource-type"]]) | @tsv'
    FIRST=0
  else
    echo "$RESP" | jq -r '.data.items[] | [.["display-name"], .["lifecycle-state"], .["resource-type"]] | @tsv'
  fi

  PAGE=$(echo "$RESP" | jq -r '."opc-next-page" // empty')
  [[ -z "$PAGE" ]] && break
done | sed 's/\t/,/g' > resources.csv

echo "Results saved to resources.csv ($(wc -l < resources.csv) resources)"
