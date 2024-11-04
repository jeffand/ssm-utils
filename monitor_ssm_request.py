#!/usr/bin/env python3

import json
import sys
import argparse
import time
import boto3
from botocore.exceptions import ClientError

def parse_arguments():
    parser = argparse.ArgumentParser(
        description="Monitor the status of an AWS SSM Run Command execution."
    )
    parser.add_argument(
        "--interval",
        type=int,
        default=15,
        help="Polling interval in seconds (default: 15)"
    )
    parser.add_argument(
        "--profile",
        type=str,
        default=None,
        help="AWS CLI profile to use (default: default)"
    )
    parser.add_argument(
        "--region",
        type=str,
        default=None,
        help="AWS region where the command was executed (default: region from AWS config)"
    )
    return parser.parse_args()

def extract_command_id(input_json):
    try:
        data = json.loads(input_json)
        command_id = data["Command"]["CommandId"]
        if not command_id:
            raise KeyError
        return command_id
    except (json.JSONDecodeError, KeyError):
        print("Error: Invalid input JSON. Ensure it contains 'Command.CommandId'.", file=sys.stderr)
        sys.exit(1)

def fetch_command_invocations(ssm_client, command_id):
    try:
        response = ssm_client.list_command_invocations(
            CommandId=command_id,
            Details=True
        )
        return response.get("CommandInvocations", [])
    except ClientError as e:
        print(f"Error fetching command invocations: {e}", file=sys.stderr)
        sys.exit(1)

def summarize_status(invocations):
    summary = {
        "Success": 0,
        "Failed": 0,
        "InProgress": 0,
        "Cancelled": 0,
        "TimedOut": 0,
        "Cancelling": 0,
        "Received": 0,
        "Other": 0
    }
    for invocation in invocations:
        status = invocation.get("Status")
        if status in summary:
            summary[status] += 1
        else:
            summary["Other"] += 1
    return summary

def print_summary(summary):
    print("Status Summary:")
    print(f"  Total Instances:    {sum(summary.values())}")
    print(f"  Success:            {summary['Success']}")
    print(f"  Failed:             {summary['Failed']}")
    print(f"  In Progress:        {summary['InProgress']}")
    print(f"  Cancelled:          {summary['Cancelled']}")
    print(f"  Timed Out:          {summary['TimedOut']}")
    print(f"  Cancelling:         {summary['Cancelling']}")
    print(f"  Received:           {summary['Received']}")
    print(f"  Other:              {summary['Other']}")
    print("----------------------------------------")

def main():
    args = parse_arguments()

    # Read JSON input from stdin
    input_json = sys.stdin.read()

    # Extract CommandId
    command_id = extract_command_id(input_json)
    print(f"Monitoring AWS SSM Command ID: {command_id}")
    print(f"Polling interval: {args.interval} seconds")
    print("----------------------------------------")

    # Initialize boto3 session
    session = boto3.Session(profile_name=args.profile) if args.profile else boto3.Session()
    region = args.region if args.region else session.region_name

    ssm_client = session.client("ssm", region_name=region)

    all_completed = False

    while not all_completed:
        invocations = fetch_command_invocations(ssm_client, command_id)
        summary = summarize_status(invocations)
        print_summary(summary)

        # Check if all invocations have completed
        if summary["InProgress"] == 0 and summary["Cancelling"] == 0 and summary["Received"] == 0:
            all_completed = True
            if summary["Failed"] > 0:
                print("Some invocations failed.")
                sys.exit(1)
            else:
                print("All invocations succeeded.")
                sys.exit(0)
        else:
            time.sleep(args.interval)

if __name__ == "__main__":
    main()