#!/bin/bash

run_start_time=$(date +"%Y-%m-%dT%H:%M:%S")
if [ -z "$SOURCE_ES" ] || [ -z "$SOURCE_INDEX" ]; then
  echo "Please set the environment variables SOURCE_ES and SOURCE_INDEX"
  exit 1
fi

check_destination_variables() {
    if [ -z "$DESTINATION_ES" ] || [ -z "$DESTINATION_INDEX" ]; then
        echo "Please set the environment variables DESTINATION_ES and DESTINATION_INDEX"
        exit 1
    fi
}

alias=$SOURCE_INDEX
indices=$(curl -s -X GET $SOURCE_ES'/_alias/'$SOURCE_INDEX | jq -r 'keys[0]')
index_prefix=${indices%-[0-9]*}
all_indices=$(curl -s -X GET $SOURCE_ES'/_cat/indices/'$index_prefix'*?format=json')
sorted_indices=$(echo "$all_indices" | jq -r '.[] | .index' | sort -r)
sorted_indices_array=()
while IFS= read -r index; do
    sorted_indices_array+=("$index")
done <<< "${sorted_indices}"

BACKUP_ONLY=${BACKUP_ONLY:-false};
INITIAL_RUN=${INITIAL_RUN:-false};
REINDEX_ONLY=${REINDEX_ONLY:-false}
BACKFILL=${BACKFILL:-false}
BACKFILL_INDEX=${BACKFILL_INDEX:-$SOURCE_INDEX}
BACKFILL_DRY_RUN=${BACKFILL_DRY_RUN:-false}
TIMESTAMP_FIELD=${TIMESTAMP_FIELD:-"timestamp"}

# Create a directory name based on START_TIME and END_TIME
START_TIME=${START_TIME:-$(date -d '3 days ago' +'%Y-%m-%dT%H:%M:%S')};
END_TIME=${END_TIME:-$(date +'%Y-%m-%dT%H:%M:%S')};
directory_name="$(date -d "$START_TIME" +%s)-$(date -d "$END_TIME" +%s)";

# publishes a given list of S3 backup files to destination ES
publish_to_destination(){
    local file_array=("$@")
    # Iterate over the array of file names
    for file in "${file_array[@]}"; do
      echo "Processing file: $file"
      elasticdump \
        --s3AccessKeyId $AWS_ACCESS_KEY_ID \
        --s3SecretAccessKey $AWS_SECRET_ACCESS_KEY \
        --s3Region $AWS_DEFAULT_REGION \
        --type=data \
        --input="s3://${S3_BUCKET}/$file" \
        --output="$DESTINATION_ES/$DESTINATION_INDEX" \
        --s3Compress \
        --limit 1000 \
        --concurrency 1;
      sleep 2;
      status=$?;
      if [ $status -ne 0 ]; then
          echo "Failed in processing file: $file from the backup";
          exit $status;
      fi
    done
}

if [ "$BACKFILL" = "true" ]; then
  # Logic for a backfill job
  echo "Backfilling data from S3 s3://${S3_BUCKET} into $DESTINATION_ES/$DESTINATION_INDEX between time range $START_TIME and $END_TIME";
  start_time=$(date -d "$START_TIME" +%s)
  end_time=$(date -d "$END_TIME" +%s)

  # Recursive scan specifed s3 bucket to filter out files within given time range
  folder_list=$(AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY aws s3 ls "s3://${S3_BUCKET}" | awk '{gsub(/\/$/, ""); print $NF}');
  if [ -z "$folder_list" ]; then
      echo "No backup folders found in specified S3 location for given time range"
  fi

  filtered_folders=()
  while read -r line; do
      folder_name=$(echo "$line" | awk '{print $NF}')
      folder_epoch_start=$(echo "$folder_name" | cut -d'-' -f1)
      folder_epoch_end=$(echo "$folder_name" | cut -d'-' -f2)

      if ((folder_epoch_start >= start_time && folder_epoch_end <= end_time)) || ((folder_epoch_start < start_time && start_time <= folder_epoch_end)) || ((folder_epoch_end > end_time && folder_epoch_start <= end_time)); then
          filtered_folders+=("$folder_name")
      fi
  done <<< "$folder_list"

  backup_list=()
  for folder in "${filtered_folders[@]}"; do
      nested_folder_list=$(AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY aws s3 ls "s3://${S3_BUCKET}/$folder/$BACKFILL_INDEX" | awk '{gsub(/\/$/, ""); print $NF}');
      for subfolder in $nested_folder_list; do
          file_list=$(AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY aws s3 ls "s3://${S3_BUCKET}/$folder/$subfolder/data" | awk '{gsub(/\/$/, ""); print $NF}');
          for file in $file_list; do
              backup_list+=("$folder/$subfolder/$file")
          done
      done
  done
  if [ "$BACKFILL_DRY_RUN" == "true" ]; then
    for modified_file in "${backup_list[@]}"; do
        echo "$modified_file"
    done
  else
    # publishes the list of backup files to destination
    publish_to_destination "${backup_list[@]}"
  fi
else
  RECONCILATION_QUERY='
  {
    "query": {
      "range": {
        "'"$TIMESTAMP_FIELD"'": {
          "gte": "'$START_TIME'",
          "lte": "'$END_TIME'"
        }
      }
    }
  }
  '
  initial_destination_count=$(curl -s -X GET $DESTINATION_ES/$DESTINATION_INDEX/'_count' -H "Content-Type: application/json" -d "$RECONCILATION_QUERY" | jq '.count')
  source_count=0
  for index in "${sorted_indices_array[@]:0:2}"; do
      SOURCE_INDEX=$index;
      S3_PATH=$directory_name/$SOURCE_INDEX;
      source_data_count=$(curl -s -X GET $SOURCE_ES/$SOURCE_INDEX/'_count' -H "Content-Type: application/json" -d "$RECONCILATION_QUERY" | jq '.count')
      source_count=$((source_count + source_data_count))
      if [ "$REINDEX_ONLY" = "true" ]; then
        check_destination_variables
        echo "Performing direct reindex from $SOURCE_ES/$SOURCE_INDEX to $DESTINATION_ES/$DESTINATION_INDEX";
        elasticdump \
          --type=data \
          --input="$SOURCE_ES/$SOURCE_INDEX" \
          --output="$DESTINATION_ES/$DESTINATION_INDEX" \
          --limit 1000 \
          --concurrency 1 \
          --searchBody '{
            "query": {
              "range": {
                "'"$TIMESTAMP_FIELD"'": {
                  "gte": "'"$START_TIME"'",
                  "lt": "'"$END_TIME"'"
                }
              }
            }
          }';
          status=$?;
          if [ $status -ne 0 ]; then
              echo "Failed in performing direct reindex from $SOURCE_ES/$SOURCE_INDEX to $DESTINATION_ES/$DESTINATION_INDEX";
              exit $status;
          fi
      else
        echo "Backing up $SOURCE_ES/$SOURCE_INDEX for time range $START_TIME-$END_TIME into S3";
        if [ "$INITIAL_RUN" = "true" ]; then
          echo "Backing up index details for $SOURCE_ES/$SOURCE_INDEX";
          elasticdump \
            --s3AccessKeyId $AWS_ACCESS_KEY_ID \
            --s3SecretAccessKey $AWS_SECRET_ACCESS_KEY \
            --s3Region $AWS_DEFAULT_REGION \
            --type=index \
            --input="$SOURCE_ES/$SOURCE_INDEX" \
            --output "s3://${S3_BUCKET}/${S3_PATH}/index.json";
          status=$?;
          if [ $status -ne 0 ]; then
              echo "Failed in backing up index details for $SOURCE_ES/$SOURCE_INDEX";
              exit $status;
          fi
          echo "Backing up index_template for $SOURCE_ES/$SOURCE_INDEX";
          elasticdump \
            --s3AccessKeyId $AWS_ACCESS_KEY_ID \
            --s3SecretAccessKey $AWS_SECRET_ACCESS_KEY \
            --s3Region $AWS_DEFAULT_REGION \
            --type=index_template \
            --input="$SOURCE_ES/$SOURCE_INDEX" \
            --output "s3://${S3_BUCKET}/${S3_PATH}/index_template.json";
          status=$?;
          if [ $status -ne 0 ]; then
              echo "Failed in backing up index_template for $SOURCE_ES/$SOURCE_INDEX";
              exit $status;
          fi
        fi

        # Run the elasticdump command with the specified timestamps and generated directory name
        echo "Backing up data for $SOURCE_ES/$SOURCE_INDEX";
        elasticdump \
          --s3AccessKeyId $AWS_ACCESS_KEY_ID \
          --s3SecretAccessKey $AWS_SECRET_ACCESS_KEY \
          --s3Region $AWS_DEFAULT_REGION \
          --type=data \
          --input="$SOURCE_ES/$SOURCE_INDEX" \
          --s3Compress \
          --fileSize=1gb \
          --output "s3://${S3_BUCKET}/${S3_PATH}/data" \
          --limit 1000 \
          --concurrency 1 \
          --searchBody '{
            "query": {
              "range": {
                "'"$TIMESTAMP_FIELD"'": {
                  "gte": "'"$START_TIME"'",
                  "lt": "'"$END_TIME"'"
                }
              }
            }
          }';
        status=$?;
        if [ $status -ne 0 ]; then
            echo "Failed in backing up data for $SOURCE_ES/$SOURCE_INDEX";
            exit $status;
        fi
        echo "Finished backing up $SOURCE_ES/$SOURCE_INDEX";
        if [ "$BACKUP_ONLY" = "true" ]; then
          exit 0
        fi

        check_destination_variables
        echo "Assuming the desination index mappings are already created"
        # List files in the S3 bucket and store them in an array
        echo "Restoring data from S3 s3://${S3_BUCKET}/${S3_PATH}/ into $DESTINATION_ES/$DESTINATION_INDEX";
        file_list=$(AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY aws s3 ls "s3://${S3_BUCKET}/${S3_PATH}/data" | awk '{print $NF}');
        if [ -z "$file_list" ]; then
          echo "No backup files found in the specified S3 location"
        fi
        modified_file_list=()
        for file in $file_list; do
            modified_file_list+=("${S3_PATH}/$file")
        done
        publish_to_destination "${modified_file_list[@]}"

      fi
  done
  current_destination_count=$(curl -s -X GET $DESTINATION_ES/$DESTINATION_INDEX/'_count' -H "Content-Type: application/json" -d "$RECONCILATION_QUERY" | jq '.count')
  destination_count=$((current_destination_count-initial_destination_count))
  if [ "$initial_destination_count" -ge "$source_count" ] || [ "$current_destination_count" -eq "$source_count" ] || [ "$destination_count" -ge "$source_count" ]; then
    echo "Data Reconcilation Successfull"
  else
    echo "Data Reconcilation Failed"
    echo "Source Count: $source_count"
    echo "Initial Destination Count: $initial_destination_count"
    echo "Current Destination Count: $current_destination_count"
    echo "Destination Count Delta: $destination_count"
    exit 1
  fi
fi

run_end_time=$(date +"%Y-%m-%dT%H:%M:%S")

# Calculate time taken
start_seconds=$(date -d "$run_start_time" +%s)
end_seconds=$(date -d "$run_end_time" +%s)
total_seconds=$((end_seconds - start_seconds))

# Format total time taken
hours=$((total_seconds / 3600))
minutes=$(( (total_seconds % 3600) / 60 ))
seconds=$((total_seconds % 60))
total_time="$hours hours, $minutes minutes, $seconds seconds"

# Print job summary
echo "Job Summary:"
echo "Source ES Index: $alias"
echo "Destination ES Index: $DESTINATION_INDEX"
echo "S3 Backup Bucket: s3://$S3_BUCKET"
echo "S3 Backup File Range: $(date -d "$START_TIME" +%s)-$(date -d "$END_TIME" +%s)"
echo "Job Start Time: $run_start_time"
echo "Job End Time: $run_end_time"
echo "Total Time Taken: $total_time"
echo "Data Migration Between Dates: $START_TIME and $END_TIME"
echo "Data Reconcilation Successfull. Dump Volume: $source_count Docs"