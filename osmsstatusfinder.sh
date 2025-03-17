#!/bin/bash

# Prompt for the compartment ID
read -p "Enter the compartment ID: " compartment_id

# Create a text file to store the instance details
touch instance_details.txt

# List all instances in the compartment
instances=$(oci compute instance list --compartment-id $compartment_id --query 'data[*].{id:id,"display-name":"display-name"}' --raw-output)

# Loop through each instance
for instance in $(echo "${instances}" | jq -r '.[] | @base64'); do
    _jq() {
     echo ${instance} | base64 --decode | jq -r ${1}
    }

   instance_id=$(_jq '.id')
   instance_name=$(_jq '."display-name"')

   # Get details about the OSMS on the instance
   osms_status=$(oci os-management managed-instance get --managed-instance-id $instance_id --query 'data."status"' --raw-output)

   # Write the instance name, instance ID, and OSMS status to the text file
   echo "$instance_name, $instance_id, $osms_status" >> instance_details.txt
done

echo "Instance details written to instance_details.txt"
