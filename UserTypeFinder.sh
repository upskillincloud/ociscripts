############################
# Documentation for User Extraction Script

## Overview
This script is designed to extract and list all identity domains and users within a specified root tenancy in Oracle Cloud Infrastructure (OCI). The script performs the following tasks:
1. Lists all identity domains in the root tenancy.
2. Extracts domain URLs and lists users for each domain.

## Prerequisites
- OCI CLI installed and configured.
- jq installed for JSON parsing.

## Script Details

### Define the Root Tenancy OCID
The script starts by defining the root tenancy OCID.

### List All Identity Domains
The script lists all identity domains in the root tenancy and saves the details to `domains.csv`.

### Extract Domain URLs and List Users
The script reads the `domains.csv` file, extracts user details for each domain, and saves them to `users.csv`.

## Script Reference



################################

#!/bin/bash

# Define the root tenancy OCID
TENANCY_OCID="ocid1.tenancy.oc1..aaaaaaaap575aefb7krdfcd374xgggeutd4ylwdlhg6f44uajrqzuktz6rcq"

# Function to list all identity domains in the root tenancy
list_domains() {
    DOMAIN_LIST=$(oci iam domain list --compartment-id $TENANCY_OCID --all --output json)
    echo "compartment-id,display-name,url" > domains.csv
    echo $DOMAIN_LIST | jq -r '.data[] | [.["compartment-id"], .["display-name"], .url] | @csv' >> domains.csv
    echo "Domain details have been saved to domains.csv"
}

# Function to extract domain URLs and list users
list_users() {
# Extract domain URLs and list users
echo "id,user-name,ocid,expired,lock-date,type,domain-name" > users.csv
while IFS=, read -r compartment_id display_name url
do
    if [ "$url" != "url" ]; then
        # Remove any extra quotes from the URL
        clean_url=$(echo $url | sed 's/"//g')
        next_page_token=""
        while : ; do
            if [ -z "$next_page_token" ]; then
                                USER_LIST1=$(oci identity-domains users list --endpoint $clean_url --limit 100 --output json)
                USER_LIST=$(oci identity-domains users list --endpoint $clean_url --query 'data.resources[].[id,"user-name",ocid,("locked"."expired"),("locked"."lock-date"),("urn:ietf:params:scim:schemas:oracle:idcs:extension:user-user"."is-federated-user")]' --limit 100 --output json)
            else
                                USER_LIST1=$(oci identity-domains users list --endpoint $clean_url --limit 100 --page $next_page_token --output json)
                USER_LIST=$(oci identity-domains users list --endpoint $clean_url --query 'data.resources[].[id,"user-name",ocid,("locked"."expired"),("locked"."lock-date"),("urn:ietf:params:scim:schemas:oracle:idcs:extension:user-user"."is-federated-user")]' --limit 100 --page $next_page_token --output json)
            fi
            
            # Check if USER_LIST is empty or null
            if [ -z "$USER_LIST" ] || [ "$USER_LIST" == "null" ]; then
                echo "Warning: No users found for domain $display_name."
                break
            fi
            
            echo $USER_LIST | jq -r --arg domain_name "$display_name" '
                .[] | 
                [
                    if .[0] then .[0] else "N/A" end, 
                    if .[1] then .[1] else "N/A" end, 
                    if .[2] then .[2] else "N/A" end, 
                    if .[3] then .[3] else "N/A" end, 
                    if .[4] then .[4] else "N/A" end, 
                    if .[5] == true then "federated" else "local" end, 
                    $domain_name
                ] | @csv' | sed 's/""//g' >> users.csv
            
            # Get the next page token
            next_page_token=$(echo $USER_LIST1 | jq -r '.["opc-next-page"]')
            if [ -z "$next_page_token" ] || [ "$next_page_token" == "null" ]; then
                break
            fi
        done
        
        echo "User extraction from domain $display_name completed."
    fi
done < domains.csv

echo "User details have been saved to users.csv"
}

# Main script execution
list_domains
list_users
