#!/bin/bash

# Prompt the user for the subnet ID
read -p "Enter the subnet ID: " SUBNET_ID

CSV_FILE="ingress_rules.csv"

# Get the security list ID associated with the subnet
SECURITY_LIST_ID=$(oci network subnet get --subnet-id $SUBNET_ID --query 'data."security-list-ids"[0]' --raw-output)

# Check if security list ID is retrieved
if [ -z "$SECURITY_LIST_ID" ]; then
  echo "No security list found for the subnet ID: $SUBNET_ID"
  exit 1
fi

# Get the ingress rules from the security list
INGRESS_RULES=$(oci network security-list get --security-list-id $SECURITY_LIST_ID --query 'data."ingress-security-rules"' --raw-output)

# Print the ingress rules
echo "Ingress Rules for Security List ID $SECURITY_LIST_ID:"

# Convert JSON to CSV and save to file
echo $INGRESS_RULES | jq -r '.[] | [
  .description,
  .protocol,
  .source,
  .["source-type"],
  (.["tcp-options"] // {} | .["destination-port-range"]?.min // "N/A"),
  (.["tcp-options"] // {} | .["destination-port-range"]?.max // "N/A"),
  (.["udp-options"] // {} | .["destination-port-range"]?.min // "N/A"),
  (.["udp-options"] // {} | .["destination-port-range"]?.max // "N/A")
] | @csv' > $CSV_FILE

echo "Ingress rules have been saved to $CSV_FILE"
