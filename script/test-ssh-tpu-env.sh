#!/bin/bash
# Test script to verify TPU environment variables are available via SSH

set -e

echo "=== Testing SSH TPU Environment Setup ==="
echo ""

# Get LoadBalancer IP
echo "1. Getting LoadBalancer IP..."
EXTERNAL_IP=$(kubectl get svc sgl-svc-$(whoami) -n default -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)

if [ -z "$EXTERNAL_IP" ]; then
  echo "ERROR: LoadBalancer IP not found"
  echo "Run: kubectl get svc -n default"
  exit 1
fi

echo "   LoadBalancer IP: $EXTERNAL_IP"
echo ""

# Wait for pod to be ready
echo "2. Waiting for pod to be ready..."
kubectl wait --for=condition=ready pod -l app=sgl-tpu -n default --timeout=120s

POD_NAME=$(kubectl get pods -n default -l app=sgl-tpu -o jsonpath='{.items[0].metadata.name}')
echo "   Pod: $POD_NAME"
echo ""

# Test via kubectl exec first (should always work)
echo "3. Testing via kubectl exec..."
kubectl exec $POD_NAME -n default -- bash -c 'source /etc/profile.d/tpu-env.sh 2>/dev/null || true; env | grep -E "(TPU|VBAR|JAX)" | wc -l' > /tmp/kubectl_env_count.txt
KUBECTL_COUNT=$(cat /tmp/kubectl_env_count.txt)
echo "   TPU environment variables found: $KUBECTL_COUNT"

if [ "$KUBECTL_COUNT" -lt 10 ]; then
  echo "   WARNING: Expected at least 10 TPU variables"
fi
echo ""

# Test via SSH (this is what we're fixing)
echo "4. Testing via SSH..."
echo "   Checking /etc/profile.d/tpu-env.sh exists..."
kubectl exec $POD_NAME -n default -- test -f /etc/profile.d/tpu-env.sh && echo "   ✓ File exists" || echo "   ✗ File missing"

echo "   Checking .bashrc includes source command..."
kubectl exec $POD_NAME -n default -- grep -q 'source /etc/profile.d/tpu-env.sh' /root/.bashrc && echo "   ✓ .bashrc configured" || echo "   ✗ .bashrc not configured"

echo "   Checking SSH authorized_keys..."
kubectl exec $POD_NAME -n default -- test -f /root/.ssh/authorized_keys && echo "   ✓ SSH keys configured" || echo "   ✗ SSH keys missing"
echo ""

# Show sample of TPU env variables
echo "5. Sample TPU environment variables:"
kubectl exec $POD_NAME -n default -- bash -c 'source /etc/profile.d/tpu-env.sh; env | grep -E "(TPU|VBAR)" | head -5'
echo ""

echo "=== Manual SSH Test ==="
echo "Run the following commands to test:"
echo ""
echo "  ssh root@$EXTERNAL_IP"
echo "  env | grep TPU"
echo "  pip install -U "jax[tpu]" "
echo "  python3 -c \"import jax; print(jax.devices())\""
echo ""
