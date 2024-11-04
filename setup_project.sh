#!/bin/bash

# Set the base directory
BASE_DIR="ssm-test-automation"

# Create the base directory
mkdir -p "$BASE_DIR"

# Create subdirectories
mkdir -p "$BASE_DIR/terraform/scripts"
mkdir -p "$BASE_DIR/terraform/lambda"
mkdir -p "$BASE_DIR/terraform/ssm_documents"
mkdir -p "$BASE_DIR/terraform/eventbridge"
mkdir -p "$BASE_DIR/scripts"
mkdir -p "$BASE_DIR/docs"

# Create files with default content

# Create README.md
cat > "$BASE_DIR/README.md" << EOL
# SSM Test Automation

This project automates the testing of AWS Systems Manager (SSM) documents using Terraform, AWS Lambda, and AWS Systems Manager Run Command.

## Overview

- Provision resources using Terraform.
- Execute SSM documents on target instances.
- Monitor execution with AWS Lambda and EventBridge.
- Receive notifications via SNS (optional).

## Prerequisites

- AWS CLI installed and configured.
- Terraform installed.
- AWS account with necessary permissions.

## Usage

1. Build the Lambda function package.
2. Initialize and apply the Terraform configuration.
3. Monitor execution and view logs.

EOL

# Create .gitignore
cat > "$BASE_DIR/.gitignore" << EOL
# Terraform files
*.tfstate
*.tfstate.backup
.terraform/

# Python compiled files
__pycache__/
*.pyc

# Lambda deployment package
lambda_function.zip

# Secrets or sensitive files
*.secret

# Visual Studio Code files
.vscode/

EOL

# Create LICENSE (MIT License as an example)
cat > "$BASE_DIR/LICENSE" << EOL
MIT License

Copyright (c) $(date +"%Y")

Permission is hereby granted, free of charge, to any person obtaining a copy...
EOL

# Create Terraform files
cat > "$BASE_DIR/terraform/main.tf" << EOL
provider "aws" {
  region = var.aws_region
}

# Upload the SSM document
resource "aws_ssm_document" "my_ssm_document" {
  name          = "MySSMDocument"
  document_type = "Command"
  content       = file("\${path.module}/ssm_documents/my_ssm_document.yaml")
}

# IAM Role for Lambda Execution
resource "aws_iam_role" "lambda_execution_role" {
  name               = "LambdaExecutionRole"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role_policy.json
}

# Attach policies to Lambda execution role
resource "aws_iam_role_policy_attachment" "lambda_execution_policy" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "lambda_ssm_policy" {
  name   = "LambdaSSMPolicy"
  role   = aws_iam_role.lambda_execution_role.id
  policy = file("\${path.module}/policies/lambda_ssm_policy.json")
}

# Create the Lambda function
resource "aws_lambda_function" "monitoring_lambda_function" {
  function_name    = "MonitoringLambdaFunction"
  runtime          = "python3.8"
  role             = aws_iam_role.lambda_execution_role.arn
  handler          = "lambda_function.lambda_handler"
  filename         = "lambda_function.zip"
  source_code_hash = filebase64sha256("lambda_function.zip")
}

# EventBridge rule to capture Run Command status changes
resource "aws_cloudwatch_event_rule" "run_command_completion_rule" {
  name        = "RunCommandCompletionRule"
  description = "Triggers Lambda function upon Run Command completion"
  event_pattern = file("\${path.module}/eventbridge/event_rule.json")
}

# Permission for EventBridge to invoke Lambda
resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.monitoring_lambda_function.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.run_command_completion_rule.arn
}

# EventBridge target
resource "aws_cloudwatch_event_target" "run_command_completion_target" {
  rule      = aws_cloudwatch_event_rule.run_command_completion_rule.name
  target_id = "LambdaFunction"
  arn       = aws_lambda_function.monitoring_lambda_function.arn
}

# Null resource to execute Run Command
resource "null_resource" "execute_run_command" {
  depends_on = [aws_ssm_document.my_ssm_document]

  provisioner "local-exec" {
    command = "bash scripts/run_command.sh \${aws_ssm_document.my_ssm_document.name} \${var.project_name} \${var.aws_region}"
  }
}
EOL

# Create variables.tf
cat > "$BASE_DIR/terraform/variables.tf" << EOL
variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name used for tagging and identification"
  type        = string
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {
    Environment = "Test"
    Project     = var.project_name
  }
}
EOL

# Create outputs.tf
cat > "$BASE_DIR/terraform/outputs.tf" << EOL
output "ssm_document_name" {
  description = "Name of the SSM document"
  value       = aws_ssm_document.my_ssm_document.name
}

output "lambda_function_arn" {
  description = "ARN of the monitoring Lambda function"
  value       = aws_lambda_function.monitoring_lambda_function.arn
}
EOL

# Create provider.tf
cat > "$BASE_DIR/terraform/provider.tf" << EOL
provider "aws" {
  region = var.aws_region
}
EOL

# Create build_lambda.sh
cat > "$BASE_DIR/terraform/scripts/build_lambda.sh" << 'EOL'
#!/bin/bash
cd ../lambda
zip -r9 ../lambda_function.zip .
EOL
chmod +x "$BASE_DIR/terraform/scripts/build_lambda.sh"

# Create run_command.sh
cat > "$BASE_DIR/terraform/scripts/run_command.sh" << 'EOL'
#!/bin/bash
SSM_DOCUMENT_NAME="$1"
PROJECT_NAME="$2"
AWS_REGION="$3"

aws ssm send-command \
  --document-name "$SSM_DOCUMENT_NAME" \
  --targets "Key=tag:test-project,Values=$PROJECT_NAME" \
  --parameters '{}' \
  --max-concurrency "100%" \
  --max-errors "0" \
  --region "$AWS_REGION"
EOL
chmod +x "$BASE_DIR/terraform/scripts/run_command.sh"

# Create lambda_function.py
cat > "$BASE_DIR/terraform/lambda/lambda_function.py" << 'EOL'
import json
import boto3
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    # Log the received event
    logger.info("Received event: %s", json.dumps(event))

    # Extract details from the event
    detail = event.get('detail', {})
    command_id = detail.get('command-id')
    instance_id = detail.get('instance-id')
    status = detail.get('status')

    # Log or process the information
    logger.info(f"Command ID: {command_id}")
    logger.info(f"Instance ID: {instance_id}")
    logger.info(f"Status: {status}")

    # Optionally, retrieve command output
    ssm_client = boto3.client('ssm')
    response = ssm_client.get_command_invocation(
        CommandId=command_id,
        InstanceId=instance_id
    )

    # Log the output
    logger.info(f"Command Output: {response.get('StandardOutputContent')}")

    # Placeholder for future processing
    # ...

    # Optionally send notification via SNS
    # sns_client = boto3.client('sns')
    # sns_client.publish(
    #     TopicArn='arn:aws:sns:region:account-id:MySNSTopic',
    #     Message=json.dumps({'default': json.dumps(event)}),
    #     MessageStructure='json'
    # )

    return {
        'statusCode': 200,
        'body': json.dumps('Monitoring Lambda executed successfully')
    }
EOL

# Create requirements.txt
cat > "$BASE_DIR/terraform/lambda/requirements.txt" << EOL
boto3
EOL

# Create my_ssm_document.yaml
cat > "$BASE_DIR/terraform/ssm_documents/my_ssm_document.yaml" << EOL
---
schemaVersion: '2.2'
description: "An example SSM document."
parameters:
  commands:
    type: String
    description: "Commands to run"
    default: "echo Hello World"
mainSteps:
  - action: aws:runShellScript
    name: runShellScript
    inputs:
      runCommand:
        - "{{ commands }}"
EOL

# Create event_rule.json
cat > "$BASE_DIR/terraform/eventbridge/event_rule.json" << EOL
{
  "source": ["aws.ssm"],
  "detail-type": ["EC2 Command Invocation Status-change Notification"],
  "detail": {
    "status": ["Success", "Failed"],
    "document-name": ["MySSMDocument"]
  }
}
EOL

# Create event_target.json (empty placeholder)
touch "$BASE_DIR/terraform/eventbridge/event_target.json"

# Create invoke_run_command.sh
cat > "$BASE_DIR/scripts/invoke_run_command.sh" << 'EOL'
#!/bin/bash
SSM_DOCUMENT_NAME="$1"
PROJECT_NAME="$2"
AWS_REGION="$3"

aws ssm send-command \
  --document-name "$SSM_DOCUMENT_NAME" \
  --targets "Key=tag:test-project,Values=$PROJECT_NAME" \
  --parameters '{}' \
  --max-concurrency "100%" \
  --max-errors "0" \
  --region "$AWS_REGION"
EOL
chmod +x "$BASE_DIR/scripts/invoke_run_command.sh"

# Create architecture_diagram.png (empty placeholder)
touch "$BASE_DIR/docs/architecture_diagram.png"

echo "Project setup complete."
