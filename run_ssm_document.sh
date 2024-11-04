#!/bin/bash

# Usage: ./run_ssm_document.sh -d <SSM_DOCUMENT_NAME_OR_ARN> -k <TAG_KEY> -v <TAG_VALUE> -r <AWS_REGION> -p <AWS_PROFILE> [--parameters '{"param1":["value1"],"param2":["value2"]}']

# Function to display usage information
usage() {
    echo "Usage: $0 -d <SSM_DOCUMENT_NAME_OR_ARN> -k <TAG_KEY> -v <TAG_VALUE> -r <AWS_REGION> -p <AWS_PROFILE> [--parameters '<PARAMETERS_JSON>']"
    echo ""
    echo "Options:"
    echo "  -d, --document      Name or ARN of the SSM document to execute (required)"
    echo "  -k, --tag-key       Tag key to identify target instances (required)"
    echo "  -v, --tag-value     Tag value to identify target instances (required)"
    echo "  -r, --region        AWS region where instances are located (required)"
    echo "  -p, --profile       AWS CLI profile to use (required)"
    echo "      --parameters    JSON string of parameters for the SSM document (optional)"
    echo "  -h, --help          Display this help message"
    exit 1
}

# Initialize variables
PARAMETERS_JSON='{}'

# Parse command-line arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -d|--document)
            SSM_DOCUMENT_NAME_OR_ARN="$2"
            shift 2
            ;;
        -k|--tag-key)
            TAG_KEY="$2"
            shift 2
            ;;
        -v|--tag-value)
            TAG_VALUE="$2"
            shift 2
            ;;
        -r|--region)
            AWS_REGION="$2"
            shift 2
            ;;
        -p|--profile)
            AWS_PROFILE="$2"
            shift 2
            ;;
        --parameters)
            PARAMETERS_JSON="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "Unknown parameter passed: $1"
            usage
            ;;
    esac
done

# Check for required arguments
if [ -z "$SSM_DOCUMENT_NAME_OR_ARN" ] || [ -z "$TAG_KEY" ] || [ -z "$TAG_VALUE" ] || [ -z "$AWS_REGION" ] || [ -z "$AWS_PROFILE" ]; then
    echo "Error: Missing required arguments."
    usage
fi

# Execute the send-command
aws ssm send-command \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --document-name "$SSM_DOCUMENT_NAME_OR_ARN" \
  --targets "Key=tag:$TAG_KEY,Values=$TAG_VALUE" \
  --parameters "$PARAMETERS_JSON" \
  --max-concurrency "100%" \
  --max-errors "0"