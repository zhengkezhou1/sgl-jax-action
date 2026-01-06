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
        resources:
          requests:
            cpu: "2"
            memory: "8Gi"
            google.com/tpu: ${TPU_COUNT}
          limits:
            cpu: "4"
            memory: "12Gi"
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
