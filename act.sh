owner=mesut146
repo=lang

# Get workflow IDs with status "disabled_manually"
workflow_ids=($(gh api repos/$owner/$repo/actions/workflows --paginate | jq '.workflows[] | select(.["state"] | contains("active")) | .id'))


for workflow_id in "${workflow_ids[@]}"
do
  echo "Listing runs for the workflow ID $workflow_id"
  #gh api repos/$owner/$repo/actions/workflows/$workflow_id/runs --paginate
  run_ids=( $(gh api repos/$owner/$repo/actions/workflows/$workflow_id/runs --paginate | jq '.workflow_runs[].id') )
  for run_id in "${run_ids[@]}"
  do
    echo "Deleting Run ID $run_id"
    #gh api repos/$owner/$repo/actions/runs/$run_id -X DELETE >/dev/null
  done
done
