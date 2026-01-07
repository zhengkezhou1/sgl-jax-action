---
# TPU Development Environment Kubernetes Configuration
# Variables to replace before deployment:
#   ${USER_NAME}: Developer username (for resource isolation)
#   ${SSH_PUB_KEY}: SSH public key content (for SSH authentication)
#   ${TPU_TYPE}: TPU accelerator type (e.g., tpu-v6e-slice)
#   ${TPU_TOPOLOGY}: TPU topology (e.g., 1x1, 2x2, 4x4)
#   ${TPU_COUNT}: Number of TPU chips (default: 1)
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: sgl-ssh-key-${USER_NAME}
  namespace: ${K8S_NAMESPACE}
  labels:
    app: sgl-tpu
    developer: ${USER_NAME}
data:
  authorized_keys: "${SSH_PUB_KEY}"
---
apiVersion: v1
kind: Service
metadata:
  name: sgl-svc-${USER_NAME}
  namespace: ${K8S_NAMESPACE}
  labels:
    app: sgl-tpu
    developer: ${USER_NAME}
spec:
  type: LoadBalancer
  sessionAffinity: ClientIP
  selector:
    app: sgl-tpu
    developer: ${USER_NAME}
  ports:
  - name: ssh
    port: 22
    targetPort: 22
    protocol: TCP
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: sgl-tpu-${USER_NAME}
  namespace: ${K8S_NAMESPACE}
  labels:
    app: sgl-tpu
    developer: ${USER_NAME}
spec:
  replicas: 1
  strategy:
    type: Recreate
  selector:
    matchLabels:
      app: sgl-tpu
      developer: ${USER_NAME}
  template:
    metadata:
      labels:
        app: sgl-tpu
        developer: ${USER_NAME}
    spec:
      serviceAccountName: ${K8S_SERVICE_ACCOUNT_NAME}
      nodeSelector:
        cloud.google.com/gke-tpu-accelerator: ${TPU_TYPE}
        cloud.google.com/gke-tpu-topology: ${TPU_TOPOLOGY}
      containers:
      - name: sgl-jax
        image: ghcr.io/zhengkezhou1/sgl-jax-action:v0.0.4
        stdin: true
        tty: true
        securityContext:
          privileged: true
        lifecycle:
          postStart:
            exec:
              command:
                - /bin/bash
                - -c
                - |
                  # Create TPU environment file from container environment variables
                  cat > /etc/profile.d/tpu-env.sh << TPUEOF
                  # TPU Environment Variables (auto-generated from container env)
                  export TPU_ACCELERATOR_TYPE="$${TPU_ACCELERATOR_TYPE}"
                  export TPU_CHIPS_PER_HOST_BOUNDS="$${TPU_CHIPS_PER_HOST_BOUNDS}"
                  export TPU_HOST_BOUNDS="$${TPU_HOST_BOUNDS}"
                  export TPU_RUNTIME_METRICS_PORTS="$${TPU_RUNTIME_METRICS_PORTS}"
                  export TPU_SKIP_MDS_QUERY="$${TPU_SKIP_MDS_QUERY}"
                  export TPU_TOPOLOGY_ALT="$${TPU_TOPOLOGY_ALT}"
                  export TPU_TOPOLOGY_WRAP="$${TPU_TOPOLOGY_WRAP}"
                  export TPU_TOPOLOGY="$${TPU_TOPOLOGY}"
                  export TPU_WORKER_HOSTNAMES="$${TPU_WORKER_HOSTNAMES}"
                  export TPU_WORKER_ID="$${TPU_WORKER_ID}"
                  export VBAR_CONTROL_SERVICE_URL="$${VBAR_CONTROL_SERVICE_URL}"
                  export JAX_COMPILATION_CACHE_DIR="$${JAX_COMPILATION_CACHE_DIR:-/tmp/jit_cache}"
                  TPUEOF

                  # Auto-load TPU environment for all login shells
                  if ! grep -q 'source /etc/profile.d/tpu-env.sh' /root/.bashrc 2>/dev/null; then
                    echo '# Auto-load TPU environment variables' >> /root/.bashrc
                    echo 'source /etc/profile.d/tpu-env.sh' >> /root/.bashrc
                  fi
        resources:
          requests:
            cpu: "12"
            memory: "60Gi"
            google.com/tpu: ${TPU_COUNT}
          limits:
            cpu: "24"
            memory: "120Gi"
            google.com/tpu: ${TPU_COUNT}
        ports:
        - name: ssh
          containerPort: 22
          protocol: TCP
        livenessProbe:
          tcpSocket:
            port: 22
          initialDelaySeconds: 30
          periodSeconds: 10
          timeoutSeconds: 5
          failureThreshold: 3
        readinessProbe:
          tcpSocket:
            port: 22
          initialDelaySeconds: 10
          periodSeconds: 5
          timeoutSeconds: 3
          successThreshold: 1
        volumeMounts:
        - name: ssh-key
          mountPath: /tmp/ssh-keys
          readOnly: true
      volumes:
      - name: ssh-key
        configMap:
          name: sgl-ssh-key-${USER_NAME}
          defaultMode: 420