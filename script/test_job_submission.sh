#!/bin/bash

# Configuration
USER_NAME="homao-tpu-pod"
# Replace with your actual public key if needed
SSH_PUB_KEY="ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQC+vMDT6CSbHyQkJUa0xgIlVbdLVNx/+SN1fEHjtIx5Wq3ymozY3u9fW0cuFDl+8YQzraezAj/a4cnFq8oouGQwPbakzwMiYqam8IYoT2O9RGH+DmmvbNW4eb2CLxDHHiorZvNt3Kc1e6P39nzhdGKRBVMDlDxLzs+0C6bgkHo/7hoHz27UPINHt79a7Cy6RM56EbAhldFRpbTi6wGn74BBsx076G/TWsx74Wk8DdVO8Gu/D1Z0WxJ9cPoM66404skKqwNPjSL5+AbimiiFErmcc0wR3ungmiF5myFEsFENqxPkIwOpvUxoYedcf5605oS6gZDpImvSNcaApIz8VUAr3Wkn0sqHubenitZhW994froyFXNZvOFzn6Ekcb6YWlgZPtbv5+CAwyKO7GL4oNxE3rQmcB9kMZTaW9j1qIWxZ/WbscuLMf8IX5Wux5iXxjxqfExLhpc48rWp5FydR1DPxAmBSvYUW2313TaEslsIaO03YU/mxjIRYIM+/hHsZto9mxsQpBkEohuAgHaJ/D+fe4c2HJlAzdYc4JQY7X4DAq5Ghfh/1I8vH6LDhYF2Xnp50PTwOwISCdqJAQKRAgr7GuhpKjWjcn+aGdcGRTmvo4aCwZuvV6tGC/kTLY/czFU87R/J0xXWieAGNJ47cWAxTsW0Imzy3S/Ov5lADMDHrQ== zhengke.zhou.dev@gmail.com"
TPU_TYPE="tpu-v6e-slice"
TPU_TOPOLOGY="4x4"
TPU_COUNT=16

# 1. Get Scheduler IP
echo "Fetching Scheduler External IP..."
SCHEDULER_IP=$(kubectl get svc sgl-scheduler -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

if [ -z "$SCHEDULER_IP" ]; then
    echo "Error: Could not find external IP for sgl-scheduler. Please check 'kubectl get svc'."
    exit 1
fi

echo "Scheduler IP found: $SCHEDULER_IP"

# 2. Submit Job
echo "Submitting TPU Job for $USER_NAME..."
SUBMIT_RESPONSE=$(curl -s -X POST "http://$SCHEDULER_IP:8080/api/jobs" \
  -H "Content-Type: application/json" \
  -d "{
    \"user_name\": \"$USER_NAME\",
    \"ssh_pub_key\": \"$SSH_PUB_KEY\",
    \"tpu_type\": \"$TPU_TYPE\",
    \"tpu_topology\": \"$TPU_TOPOLOGY\",
    \"tpu_count\": $TPU_COUNT
  }" ｜ jq)

echo "Response: $SUBMIT_RESPONSE"

# 3. Instruction for status check
echo -e "\nTo check the status of your job, run:"
echo "curl \"http://$SCHEDULER_IP:8080/api/jobs/status?user_name=$USER_NAME\""
source /etc/profile.d/tpu-env.sh
