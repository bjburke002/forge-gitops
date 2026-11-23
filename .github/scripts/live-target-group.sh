#!/usr/bin/env bash
# Prints active=primary|alternate: the target group production is live on, for a canary template.
# Prints nothing for a template without ActiveTargetGroup (no ingress, rolling deploy).
# ECS swaps the two target groups on every deploy; passing the live one keeps the stack's
# rules matching the real ones, so a stack update can't send traffic to the empty target group.
# Usage: live-target-group.sh <stack> <template>
set -euo pipefail
stack=$1
template=$2

jq -e '.Parameters.ActiveTargetGroup' "$template" > /dev/null || exit 0

# No stack yet, or one without the outputs (created before canaries): production is on TargetGroup.
outputs=$(aws cloudformation describe-stacks --stack-name "$stack" \
  --query 'Stacks[0].Outputs' --output json 2>/dev/null || echo '[]')
output() { jq -r --arg key "$1" '(. // [])[] | select(.OutputKey == $key) | .OutputValue' <<<"$outputs"; }
rule=$(output ListenerRuleArn)
alternate=$(output AlternateTargetGroupArn)

active=primary
if [[ -n $rule && -n $alternate ]]; then
  # Mid-canary the rule is split (e.g. 900/100): the larger weight is production.
  live=$(aws elbv2 describe-rules --rule-arns "$rule" \
    --query 'Rules[0].Actions[0].ForwardConfig.TargetGroups | sort_by(@, &Weight)[-1].TargetGroupArn' \
    --output text)
  if [[ $live == "$alternate" ]]; then
    active=alternate
  fi
fi

[[ -n ${GITHUB_STEP_SUMMARY:-} ]] && echo "$stack: production is on the $active target group." >> "$GITHUB_STEP_SUMMARY"
echo "active=$active"
