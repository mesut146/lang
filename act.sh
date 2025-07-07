#!/bin/bash
owner=mesut146
repo=lang

# Get workflow IDs with status "active"
workflow_ids=($(gh api repos/$owner/$repo/actions/workflows --paginate | jq '.workflows[] | select(.["state"] | contains("active")) | .id'))


for workflow_id in "${workflow_ids[@]}"
do
  echo "Listing runs for the workflow ID $workflow_id"
  runs=$(gh api repos/$owner/$repo/actions/workflows/$workflow_id/runs --paginate)
  run_ids=($(echo $runs | jq '.workflow_runs[] | .id'))
  run_numbers=($(echo $runs | jq '.workflow_runs[] | .run_number'))
  idx=0
  #leave last 3 runs only, delete rest
  for run_id in "${run_ids[@]}"
  do
    run_number=${run_numbers[$idx]}
    if [ "$idx" -lt 3 ]; then
      idx=$((idx+1))
      continue
    fi
    echo "Deleting Run ID $run_id run_number=$run_number"
    gh api repos/$owner/$repo/actions/runs/$run_id -X DELETE >/dev/null
    idx=$((idx+1))
  done
done
