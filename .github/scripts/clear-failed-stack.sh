#!/usr/bin/env bash
# Makes a stack deployable again where that's safe, and stops the job where it isn't.
#   ROLLBACK_COMPLETE (a failed first create) can't be updated: delete it so the deploy recreates it.
#   *_FAILED (a failed rollback or delete) needs a person: skipping resources is a decision, not a retry.
# Usage: clear-failed-stack.sh <stack> <cloudformation-role-arn>
set -euo pipefail
stack=$1
role_arn=$2

status=$(aws cloudformation describe-stacks --stack-name "$stack" \
  --query 'Stacks[0].StackStatus' --output text 2>/dev/null || echo NONE)

case $status in
  ROLLBACK_COMPLETE)
    [[ -n ${GITHUB_STEP_SUMMARY:-} ]] && echo "$stack was in ROLLBACK_COMPLETE from a failed first deploy; deleted before redeploying." >> "$GITHUB_STEP_SUMMARY"
    aws cloudformation delete-stack --stack-name "$stack" --role-arn "$role_arn"
    aws cloudformation wait stack-delete-complete --stack-name "$stack"
    ;;
  *_FAILED)
    echo "::error::$stack is in $status and needs manual recovery (aws cloudformation continue-update-rollback, or delete-stack with --retain-resources)."
    exit 1
    ;;
esac
