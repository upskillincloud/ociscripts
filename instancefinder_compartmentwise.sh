#!/bin/bash

#This script creates csv file of instance and primary vnic attached to it.

# Prompt the user for the compartment ID
read -p "Enter the compartment ID: " compartment_id

# Output file
output_file="instances.txt"

# Write the header to the output file
echo "Instance Name, Private IP" > $output_file

# Get the list of instances in the compartment
instances=$(oci compute instance list --compartment-id $compartment_id --query 'data[*].{ID:id, Name:"display-name"}' --output json)

# Loop over the instances
echo $instances | jq -c '.[]' | while read instance; do
    instance_id=$(echo $instance | jq -r '.ID')
    instance_name=$(echo $instance | jq -r '.Name')

    # Get the VNIC attachments for the instance
    vnic_attachments=$(oci compute vnic-attachment list --compartment-id $compartment_id --instance-id $instance_id --output json | jq -r '.data[] | select(."lifecycle-state" == "ATTACHED") | ."vnic-id"')

    # Loop over the VNIC attachments
    echo $vnic_attachments | tr ' ' '\n' | while read vnic_id; do
        # Get the VNIC details
        vnic_details=$(oci network vnic get --vnic-id $vnic_id --output json)

        # Check if the VNIC is primary
        is_primary=$(echo $vnic_details | jq -r '.data."is-primary"')

        if [ "$is_primary" = "true" ]; then
            # Get the private IP of the VNIC
            private_ip=$(echo $vnic_details | jq -r '.data."private-ip"')

            # Write the instance name and private IP to the output file
            echo "$instance_name, $private_ip" >> $output_file

            # Since we've found the primary VNIC, we can break the loop
            break
        fi
    done
done
