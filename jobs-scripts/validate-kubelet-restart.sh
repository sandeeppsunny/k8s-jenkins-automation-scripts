#!/bin/bash
  
set -o errexit
set -o pipefail
set -o nounset

total_time=0
wait_duration=10
num_nodes=$NUM_NODES

search_string='Ready' # Matches both 'Ready' and 'NotReady' nodes.
output_string='nodes'
if [[ "${NODE_READINESS_CHECK:-}" == "y" ]]; then
  search_string=' Ready ' # Only matches 'Ready' nodes.
  output_string='healthy nodes'
fi

while true; do
  total_time=$(( ${total_time} + ${wait_duration} ))
  hcount=$(kubectl get nodes 2>/dev/null | grep ${search_string} | wc -l) || true
  echo "Validation: Expected ${num_nodes} (workers + master) ${output_string}; found ${hcount}. (${total_time}s elapsed)"

  [[ "${hcount}" -ge "${num_nodes}" ]] && echo "Validation: Success!" && exit

  # Time out after 20 minutes
  if [[ "${total_time}" -ge 1200 ]]; then
    echo "Timeout exceeded."
    exit 1
  fi

  sleep ${wait_duration}
done

echo "Cluster is Ready!"
