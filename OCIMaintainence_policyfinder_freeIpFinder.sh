#!/bin/bash

# Create the output directory if it doesn't exist
echo -e "\e[92m This script requires ADMIN access to the OCI.\e[0m"

mkdir -p output

# Check if a saved tenancy OCID exists
if [ -f "output/tenancy_ocid.txt" ]; then
    # Read the tenancy OCID from the file
    TENANCY_OCID=$(cat output/tenancy_ocid.txt)
else
    # Ask the user for the tenancy OCID
    read -p "Enter your tenancy OCID: " TENANCY_OCID

    # Ask the user if they want to save the tenancy OCID for future use
    read -p "Do you want to save this tenancy OCID for future use? (y/n): " SAVE_OCID

    # If the user confirmed, save the tenancy OCID to a file
    if [ "$SAVE_OCID" = "y" ]; then
        echo $TENANCY_OCID > output/tenancy_ocid.txt
    fi
fi


# Define the grep patterns
GREP_PATTERN1="BASELINE_1_8"
GREP_PATTERN2="BASELINE_1_2"

# Function for finalcompartmentlistintances.sh content
function finalcompartmentlistintances() {
    # Function to handle the recursive search of compartments
    function extract_compartments() {
        local compartment_id=$1

        # Run the OCI command and save the output to a variable
        local output=$(oci iam compartment list --compartment-id $compartment_id)

        # Use jq to parse the JSON output and extract the name and compartment-id fields
        local compartments=$(echo $output | jq -r '.data[] | "\(.name),\(.id)"')

        # Store the compartments in an array
        local compartment_array=()
        while IFS= read -r line; do
            compartment_array+=("$line")
        done <<< "$compartments"

        # Iterate over the compartments
        for compartment in "${compartment_array[@]}"; do
            IFS=',' read -r name sub_compartment_id <<< "$compartment"
        
            # Skip the header line
            if [ "$name" != "name" ]; then
                # Write the compartment to the file
                echo "$compartment" >> output/compartments.txt
        
                # Check if sub_compartment_id is not empty
                if [ -n "$sub_compartment_id" ]; then
                    # Recursive call to search sub-compartments
                    extract_compartments $sub_compartment_id
                fi
            fi
        done
    }

    # Create a new text file for the output
    echo "compartment-name,OCID" > output/compartments.txt

    # Add the root compartment with the tenancy OCID
    echo "root-compartment,$TENANCY_OCID" >> output/compartments.txt

    # Start the recursive search with the tenancy OCID
    extract_compartments $TENANCY_OCID

    # Remove empty lines from the output file
    sed -i '/^$/d' output/compartments.txt

    # Print the message after all recursive calls have completed
    echo -e "\e[92mOutput has been written to output/compartments.txt \e[0m"
}

# Check if the compartment.txt file exists and has a size greater than zero
if [ ! -s "output/compartments.txt" ]; then
    echo -e "\e[91mThe compartments.txt file is empty or does not exist. Running the finalcompartmentlistintances function.\e[0m"
    # If the file doesn't exist or is empty, run the finalcompartmentlistintances function
    finalcompartmentlistintances
fi
display_compartment_names() {
    echo -n "Here are the compartment names: "
    awk -F',' 'NR>1 {print $1}' output/compartments.txt | paste -sd, -
    echo
}

# Function for finalburstableinstances.sh content
function finalburstableinstances() {
# If the output file exists, delete it
if [ -f output/burstableinstancelist.txt ]; then
    rm output/burstableinstancelist.txt
fi

# Print a colored message to the user
echo -e "\e[93mPlease provide a compartment name exactly as mentioned in the compartments.txt file. If the name is not correct, the script will fail.\e[0m"

# Prompt the user for a specific compartment name or "all"
read -p "Enter a specific compartment name to check or 'all' to check all compartments: " specific_compartment

# Read each line in the compartments file
while IFS=, read -r name compartment_id
do
    # Trim leading and trailing spaces from compartment_id
    compartment_id=$(echo $compartment_id | xargs)

    # Skip the header line
    if [ "$name" != "compartment-name" ]; then
        # If a specific compartment was entered and it's not "all", skip this iteration if the name doesn't match
        if [ "$specific_compartment" != "all" ] && [ "$name" != "$specific_compartment" ]; then
            continue
        fi

        # Run the OCI command and save the output to a file
        oci compute instance list --compartment-id $compartment_id --all > output/instancedetails.txt

        # If this is the first valid line, create the output file and write the header
        if [ ! -f output/burstableinstancelist.txt ]; then
            echo "compartment-name,instance-name,shape,baseline-ocpu-utilization" > output/burstableinstancelist.txt
        fi

        # Use jq to parse the JSON output and print the compartment name, instance name, shape, and baseline OCPU utilization
        jq -r ".data[] | \"${name},\(.\"display-name\"), \(.shape), \(.\"shape-config\".\"baseline-ocpu-utilization\" // \"N/A\")\"" output/instancedetails.txt | egrep "$GREP_PATTERN1|$GREP_PATTERN2" >> output/burstableinstancelist.txt
    fi
done < output/compartments.txt

# Print the message after all recursive calls have completed
echo -e "\e[92mOutput has been written to output/burstableinstancelist.txt \e[0m"
}

function finalpolicyscript() {
# Remove the old output file if it exists and create a new one
rm -f output/matchedgroupinpolicy.txt
touch output/matchedgroupinpolicy.txt

echo "Compartment,Policy,Statements" > output/matchedgroupinpolicy.txt

# Get user input for the group name
read -p "Enter the group name to search for: " GROUP_NAME

# Print a colored message to the user
echo -e "\e[93mPlease provide a compartment name exactly as mentioned in the compartments.txt file. If the name is not correct, the script will fail.\e[0m"

# Prompt the user for a specific compartment name or "all"
read -p "Enter a specific compartment name to check or 'all' to check all compartments: " specific_compartment

# Initialize a variable to keep track of whether any policies were found
policies_found=false

# Read each line in the compartments file
while IFS=, read -r name compartment_id
do
    # Trim leading and trailing spaces from compartment_id
    compartment_id=$(echo $compartment_id | xargs)

    # Skip the header line
    if [ "$name" != "compartment-name" ]; then
        # If a specific compartment was entered and it's not "all", skip this iteration if the name doesn't match
        if [ "$specific_compartment" != "all" ] && [ "$name" != "$specific_compartment" ]; then
            continue
        fi

        # Run the OCI command and save the output to a variable
        POLICY_OUTPUT=$(oci iam policy list --compartment-id $compartment_id)

        # Use jq to parse the JSON output and print the policy name and statements that contain the group name
        POLICY_MATCHES=$(echo $POLICY_OUTPUT | jq -r ".data[] | select((.statements | arrays | .[]? | tostring | contains(\"$GROUP_NAME\"))) | \"${name},\(.name),\(.statements | @csv)\"")

        # If any policies were found, write them to the output file and set the policies_found variable to true
        if [ ! -z "$POLICY_MATCHES" ]; then
            # Split the policy matches into an array
            IFS=$'\n' read -rd '' -a policy_array <<<"$POLICY_MATCHES"

            # Loop through the array and only print unique policies
            for policy in "${policy_array[@]}"; do
                # Write the policy to a temporary file
                echo $policy | tr ',' '\n' > temp.txt

                # If the policy is not already in the output file, append it
                if ! grep -q -f temp.txt output/matchedgroupinpolicy.txt; then
                    cat temp.txt >> output/matchedgroupinpolicy.txt
                    policies_found=true
                fi
            done

            # Remove the temporary file
            rm temp.txt
        fi
    fi
done < output/compartments.txt

# If any policies were found, print a success message
if $policies_found; then
    echo -e "\e[92mOutput has been written to output/matchedgroupinpolicy.txt \e[0m"
else
    echo -e "\e[91mNo policies found.\e[0m"
    rm output/matchedgroupinpolicy.txt
fi
}
# Function for final_instance_status.sh content
function final_instance_status() {
# Print a colored message to the user
echo -e "\e[93mPlease provide a compartment name exactly as mentioned in the compartments.txt file. If the name is not correct, the script will fail.\e[0m"

# Define the output directory and file
OUTPUT_DIR="output"
OUTPUT_FILE="instance_details.txt"
COMPARTMENTS_FILE="compartments.txt"

# If the output directory doesn't exist, create it
if [ ! -d "$OUTPUT_DIR" ]; then
    mkdir "$OUTPUT_DIR"
fi

# If the output file exists, delete it
if [ -f "$OUTPUT_DIR/$OUTPUT_FILE" ]; then
    rm "$OUTPUT_DIR/$OUTPUT_FILE"
fi

# Write the header line to the output file
echo "Compartment Name,Instance Name,Instance ID,CPU,Memory,Shape,Instance Status" >> "$OUTPUT_DIR/$OUTPUT_FILE"

# Prompt the user for a specific compartment name or "all"
read -p "Enter a specific compartment name to check or 'all' to check all compartments: " specific_compartment

# Initialize a variable to track if any instances were found
instances_found=false

# Read the compartments file line by line
while IFS=',' read -r compartment_name compartment_ocid
do
    # Skip the header line
    if [ "$compartment_name" = "compartment-name" ]; then
        continue
    fi

    # If the user entered a specific compartment name and it doesn't match the current one, skip this iteration
    if [ "$specific_compartment" != "all" ] && [ "$specific_compartment" != "$compartment_name" ]; then
        continue
    fi

    # List all instances in the compartment
    INSTANCE_LIST=$(oci compute instance list --compartment-id $compartment_ocid)

    # Parse the JSON output to get the instance ids
    INSTANCE_IDS=$(echo $INSTANCE_LIST | jq -r '.data[].id')

    # Loop over each instance id and write the details to the output file
    for INSTANCE_ID in $INSTANCE_IDS
    do
        # Get the instance details
        INSTANCE_DETAILS=$(oci compute instance get --instance-id $INSTANCE_ID)

        # Extract the required details
        INSTANCE_NAME=$(echo $INSTANCE_DETAILS | jq -r '.data."display-name"')
        CPU=$(echo $INSTANCE_DETAILS | jq -r '.data."shape-config"."ocpus"')
        MEMORY=$(echo $INSTANCE_DETAILS | jq -r '.data."shape-config"."memory-in-gbs"')
        SHAPE=$(echo $INSTANCE_DETAILS | jq -r '.data.shape')
        INSTANCE_STATUS=$(echo $INSTANCE_DETAILS | jq -r '.data."lifecycle-state"')

        # Write the details to the output file
        echo "$compartment_name,$INSTANCE_NAME,$INSTANCE_ID,$CPU,$MEMORY,$SHAPE,$INSTANCE_STATUS" >> "$OUTPUT_DIR/$OUTPUT_FILE"

        # Set the instances_found variable to true
        instances_found=true
    done
done < "$OUTPUT_DIR/$COMPARTMENTS_FILE"

# If any instances were found, print a success message
if $instances_found; then
    echo -e "\e[92mOutput has been written to $OUTPUT_DIR/$OUTPUT_FILE \e[0m"
else
    echo -e "\e[91mNo instances found.\e[0m"
    rm "$OUTPUT_DIR/$OUTPUT_FILE"
fi
}

# Function to list and filter policies
function list_and_filter_policies() {
   # Remove the old output file if it exists and create a new one
    rm -f output/matchedpolicies.txt
    touch output/matchedpolicies.txt

    echo "Compartment,Policy,Statements" > output/matchedpolicies.txt

    # Prompt the user for the verb and resource type
    read -p "Enter the verb (e.g., 'manage', 'use', 'read'): " verb
    read -p "Enter the resource type (e.g., 'instance-family', 'virtual-network-family'): " resource_type

    # Print a colored message to the user
    echo -e "\e[93mPlease provide a compartment name exactly as mentioned in the compartments.txt file. If the name is not correct, the script will fail.\e[0m"

    # Prompt the user for a specific compartment name or "all"
    read -p "Enter a specific compartment name to check or 'all' to check all compartments: " specific_compartment

    # Flag to track whether any policies were found
    local policies_found=false

    # Read each line in the compartments file
    while IFS=, read -r name compartment_id
    do
        # Trim leading and trailing spaces from compartment_id
        compartment_id=$(echo $compartment_id | xargs)

        # Skip the header line
        if [ "$name" != "compartment-name" ]; then
            # If a specific compartment was entered and it's not "all", skip this iteration if the name doesn't match
            if [ "$specific_compartment" != "all" ] && [ "$name" != "$specific_compartment" ]; then
                continue
            fi

            # List all policies in the compartment
            local policies=$(oci iam policy list --compartment-id $compartment_id)

            # Filter the policies that contain the specified verb and resource type
            local filtered_policies=$(echo $policies | jq -r --arg verb "$verb" --arg resource_type "$resource_type" '.data[] | select(.statements[] | contains("\($verb) \($resource_type)"))')

            # If any policies were found, write them to the output file
            if [ ! -z "$filtered_policies" ]; then
                # Loop over each policy
                echo $filtered_policies | jq -r --arg verb "$verb" --arg resource_type "$resource_type" --arg compartment_name "$name" '. | "\($compartment_name),\(.name),\(.statements[] | select(contains("\($verb) \($resource_type)")))"' >> output/matchedpolicies.txt
                policies_found=true
            fi
        fi
    done < compartments.txt

    # If any policies were found, print a success message
    if [ "$policies_found" = true ]; then
        echo -e "\e[92mOutput has been written to output/matchedpolicies.txt\e[0m"
    else
        # If no policies were found in any compartment, print a message
        echo -e "\e[91mNo policies found.\e[0m"
        rm output/matchedpolicies.txt
    fi
}
# Function to list and filter Network IP
function finalNetworkScript() {
    # Remove the old output file if it exists and create a new one
    rm -f output/networkdetails.txt
    touch output/networkdetails.txt

    echo "VCN Name, VCN CIDR, Subnet Name, Subnet CIDR, Total IPs, Used IPs, Remaining IPs" > output/networkdetails.txt

    # Print a colored message to the user
    echo -e "\e[93mPlease provide a compartment name exactly as mentioned in the compartments.txt file. If the name is not correct, the script will fail.\e[0m"

    # Prompt the user for a specific compartment name or "all"
    read -p "Enter a specific compartment name to check or 'all' to check all compartments: " specific_compartment

    # Initialize a variable to keep track of whether any subnets were found
    subnets_found=false

    # Read each line in the compartments file
    while IFS=, read -r name compartment_id
    do
        # Trim leading and trailing spaces from compartment_id
        compartment_id=$(echo $compartment_id | xargs)

        # Skip the header line
        if [ "$name" != "compartment-name" ]; then
            # If a specific compartment was entered and it's not "all", skip this iteration if the name doesn't match
            if [ "$specific_compartment" != "all" ] && [ "$name" != "$specific_compartment" ]; then
                continue
            fi

            # Get all VCNs in the compartment
            vcns=$(oci network vcn list --compartment-id $compartment_id --query 'data[*].{"ID":id, "Name":"display-name", "CIDR":"cidr-block"}' --output json)

            # Get all subnets in the compartment
            subnet_ids=$(oci network subnet list --compartment-id $compartment_id --query 'data[*].id' --output json)

            # Loop over each subnet ID
            for subnet_id in $(echo "${subnet_ids}" | jq -r '.[]'); do
                # Get details about the subnet
                subnet=$(oci network subnet get --subnet-id $subnet_id)

                # Extract the required details
                name=$(echo "$subnet" | jq -r '.data."display-name" // "Unknown"')
                cidr_block=$(echo "$subnet" | jq -r '.data."cidr-block"')
                total_ips=$((2**(32-$(echo "$cidr_block" | cut -d'/' -f2))))
                
                # Get the number of used IPs using the oci network private-ip list command
                used_ips=$(oci network private-ip list --subnet-id $subnet_id --query 'data[]."ip-address"' | wc -l)
                remaining_ips=$((total_ips - used_ips))

                # Get the VCN ID of the subnet
                vcn_id=$(echo "$subnet" | jq -r '.data."vcn-id"')

                # Get the VCN name and CIDR from the VCNs list using the VCN ID
                vcn_name=$(echo "$vcns" | jq -r --arg vcn_id "$vcn_id" '.[] | select(.ID == $vcn_id) | .Name')
                vcn_cidr=$(echo "$vcns" | jq -r --arg vcn_id "$vcn_id" '.[] | select(.ID == $vcn_id) | .CIDR')

                # Print the details in the specified format
                echo "$vcn_name, $vcn_cidr, $name, $cidr_block, $total_ips, $used_ips, $remaining_ips" >> output/networkdetails.txt
                subnets_found=true
            done
        fi
    done < output/compartments.txt

    # If any subnets were found, print a success message
    if $subnets_found; then
        echo -e "\e[92mOutput has been written to output/networkdetails.txt\e[0m"
    else
        echo -e "\e[91mNo subnets found.\e[0m"
        rm output/networkdetails.txt
    fi
}

function bucketSize() {
    # Remove the old output file if it exists and create a new one
    rm -f output/bucketsize.txt
    touch output/bucketsize.txt

    echo "Bucket Name, Total Size" > output/bucketsize.txt

    # Print a colored message to the user
    echo -e "\e[93mPlease provide a compartment name exactly as mentioned in the compartments.txt file. If the name is not correct, the script will fail.\e[0m"

    # Prompt the user for a specific compartment name or "all"
    read -p "Enter a specific compartment name to check or 'all' to check all compartments: " specific_compartment

    # Initialize a variable to keep track of whether any buckets were found
    buckets_found=false

    # Read each line in the compartments file
    while IFS=, read -r name compartment_id
    do
        # Trim leading and trailing spaces from compartment_id
        compartment_id=$(echo $compartment_id | xargs)

        # Skip the header line
        if [ "$name" != "compartment-name" ]; then
            # If a specific compartment was entered and it's not "all", skip this iteration if the name doesn't match
            if [ "$specific_compartment" != "all" ] && [ "$name" != "$specific_compartment" ]; then
                continue
            fi

            # Get the list of all buckets in the compartment
            buckets=$(oci os bucket list --compartment-id $compartment_id --all)

            # Get the namespace -- assumes all buckets are in the same namespace
            namespace=$(echo $buckets | jq -r '.data[0]."namespace"')

            # Loop over each bucket
            for bucket in $(echo $buckets | jq -r '.data[].name'); do
                # Get the list of all objects in the bucket
                objects=$(oci os object list --bucket-name $bucket --namespace $namespace --all)

                # Calculate the total size of the objects in the bucket
                totalSize=0
                if [ "$(echo $objects | jq '.data')" != "null" ]; then
                    for size in $(echo $objects | jq '.data[].size'); do
                        totalSize=$((totalSize + size))
                    done
                fi

                # Convert the size to GB and TB
                totalSizeGB=$(awk -v size="$totalSize" 'BEGIN {printf "%.4f", size / (1024^3)}')
                totalSizeTB=$(awk -v size="$totalSize" 'BEGIN {printf "%.4f", size / (1024^4)}')

                # Decide whether to display the size in GB or TB
                if awk -v size="$totalSizeGB" 'BEGIN {exit !(size < 1024)}'; then
                    echo "Compartment: $name, Bucket: $bucket, Total size: $totalSizeGB GB" >> output/bucketsize.txt
                    buckets_found=true
                else
                    echo "Compartment: $name, Bucket: $bucket, Total size: $totalSizeTB TB" >> output/bucketsize.txt
                    buckets_found=true
                fi
            done
        fi
    done < compartments.txt

    if [ "$buckets_found" = false ]; then
        echo "No buckets found."
        rm -f output/bucketsize.txt
    else
	echo -e "\e[92mOutput has been written to output/bucketsize.txt \e[0m"
    fi
}

# Function to display the menu
function display_menu() {
    echo "1. List all compartments"
    echo "2. Find policy containing group"
    echo "3. Find verb and resource type in a policy"
    echo "4. Find burstable instances"
    echo "5. Find instance status,CPU,Memory,OCID"
    echo "6. Find Used and Remaining IPs in a subnet"
    echo "7. Find Bucket Size"
    echo "8. Exit"
}

# Main loop
while true; do
    display_menu

    read -p "Enter your choice: " choice

    case $choice in
        1)
            finalcompartmentlistintances
            ;;
        2)
            display_compartment_names
            finalpolicyscript
            ;;
        3) 
            display_compartment_names
            list_and_filter_policies
            ;;
        4)
            display_compartment_names
            finalburstableinstances
            ;;
        5)
            display_compartment_names
            final_instance_status
            ;;
        6)
            display_compartment_names
            finalNetworkScript
            ;;
        7)
            display_compartment_names
            bucketSize
            ;;
        8)
            break
            ;;
        *)
            echo "Invalid choice. Please enter a number between 1 and 8."
            ;;
    esac
done