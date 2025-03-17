#!/bin/bash

# Define the bucket name and folder paths
BUCKET_NAME="test-bucket1"
SOURCE_FOLDER="Standard/"
DEST_FOLDER="Archive/"

# Get the current date and time for the filenames
CURRENT_DATETIME=$(date '+%Y%m%d_%H%M%S')

# Define the output files with the current date and time
MATCHING_CRITERIA_FILE="matching_criteria_${CURRENT_DATETIME}.txt"
NOT_MATCHING_CRITERIA_FILE="not_matching_criteria_${CURRENT_DATETIME}.txt"

# Clear the output files if they exist
> $MATCHING_CRITERIA_FILE
> $NOT_MATCHING_CRITERIA_FILE

# Get the current date and date 30 days ago
CURRENT_DATE=$(date +%s)
#THIRTY_DAYS_AGO=$(date -d '30 days ago' +%s)
THIRTY_DAYS_AGO=1740578495

# List all objects in the source folder
OBJECTS=$(oci os object list --bucket-name $BUCKET_NAME --prefix $SOURCE_FOLDER --query 'data[].{name:name, timeCreated:"time-created"}' --output json)

# Iterate over each object
for row in $(echo "${OBJECTS}" | jq -r '.[] | @base64'); do
    _jq() {
        echo ${row} | base64 --decode | jq -r ${1}
    }

    OBJECT_NAME=$(_jq '.name')
    TIME_CREATED=$(_jq '.timeCreated')

    # Skip if the object is a folder
    if [[ "$OBJECT_NAME" == */ ]]; then
        echo "Skipping folder $OBJECT_NAME"
        continue
    fi

    # Check if timeCreated is not null
    if [ "$TIME_CREATED" != "null" ]; then
        # Convert the timeCreated to seconds since epoch
        TIME_CREATED_SECONDS=$(date -d $TIME_CREATED +%s)

        # Check if the object is older than 30 days
        if [ $TIME_CREATED_SECONDS -lt $THIRTY_DAYS_AGO ]; then
            # Rename (move) the object to the destination folder
            oci os object rename --bucket-name $BUCKET_NAME --source-name $OBJECT_NAME --new-name $DEST_FOLDER$(basename $OBJECT_NAME)

            # Verify if the object is present in the destination folder
            if oci os object head --bucket-name $BUCKET_NAME --name $DEST_FOLDER$(basename $OBJECT_NAME) > /dev/null 2>&1; then
                # Update the storage tier to Archive
                oci os object update-storage-tier --bucket-name $BUCKET_NAME --object-name $DEST_FOLDER$(basename $OBJECT_NAME) --storage-tier Archive

                echo "Moved and updated storage tier for $OBJECT_NAME"
                echo $OBJECT_NAME >> $MATCHING_CRITERIA_FILE
            else
                echo "Failed to move $OBJECT_NAME to $DEST_FOLDER"
                echo $OBJECT_NAME >> $NOT_MATCHING_CRITERIA_FILE
            fi
        else
            echo $OBJECT_NAME >> $NOT_MATCHING_CRITERIA_FILE
        fi
    else
        echo "Skipping $OBJECT_NAME as it does not have a valid timeCreated"
        echo $OBJECT_NAME >> $NOT_MATCHING_CRITERIA_FILE
    fi
done

echo "Completed moving and updating storage tier for objects older than 30 days."
echo "Objects matching criteria are listed in $MATCHING_CRITERIA_FILE"
echo "Objects not matching criteria are listed in $NOT_MATCHING_CRITERIA_FILE"
