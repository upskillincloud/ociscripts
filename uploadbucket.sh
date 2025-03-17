#!/bin/bash

# Define the bucket name and folder path
BUCKET_NAME="test-bucket1"
FOLDER_PATH="Standard/"
FILE_PATH="/home/rishabh_si/final/abcd.txt"

# Upload the file to the specified folder in the bucket
oci os object put --bucket-name $BUCKET_NAME --name $FOLDER_PATH$(basename $FILE_PATH) --file $FILE_PATH

echo "File uploaded to $BUCKET_NAME/$FOLDER_PATH successfully."
