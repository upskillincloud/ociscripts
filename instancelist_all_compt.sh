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
    echo -e "\e[92mOutput has been written to $OUTPUT_DIR/$OUTPUT_FILE.\e[0m"
else
    echo -e "\e[91mNo instances found.\e[0m"
    rm "$OUTPUT_DIR/$OUTPUT_FILE"
fi
