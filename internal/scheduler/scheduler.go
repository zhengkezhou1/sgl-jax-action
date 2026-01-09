package scheduler

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"

	appsv1 "k8s.io/api/apps/v1"
	corev1 "k8s.io/api/core/v1"
	"k8s.io/apimachinery/pkg/api/errors"
	"k8s.io/apimachinery/pkg/api/resource"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/util/intstr"
	"k8s.io/client-go/kubernetes"
)

// JobRequest defines the payload for submitting a TPU job
type JobRequest struct {
	UserName    string `json:"user_name"`
	SSHPubKey   string `json:"ssh_pub_key"`
	TPUType     string `json:"tpu_type"`     // e.g., "tpu-v6e-slice"
	TPUTopology string `json:"tpu_topology"` // e.g., "1x1"
	TPUCount    int64  `json:"tpu_count"`    // e.g., 1
}

// HandleListPods returns a list of pod names in the default namespace
func HandleListPods(clientset *kubernetes.Clientset) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet {
			http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
			return
		}
		pods, err := clientset.CoreV1().Pods("default").List(context.Background(), metav1.ListOptions{})
		if err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}
		names := make([]string, 0, len(pods.Items))
		for _, p := range pods.Items {
			names = append(names, p.Name)
		}
		json.NewEncoder(w).Encode(map[string]interface{}{"count": len(names), "pods": names})
	}
}

// HandleGetJobStatus retrieves the IP and runtime status of a TPU job
func HandleGetJobStatus(clientset *kubernetes.Clientset) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet {
			http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
			return
		}

		userName := r.URL.Query().Get("user_name")
		if userName == "" {
			http.Error(w, "Missing user_name query parameter", http.StatusBadRequest)
			return
		}

		ctx := context.Background()
		namespace := "default"
		svcName := fmt.Sprintf("sgl-svc-%s", userName)
		deployName := fmt.Sprintf("sgl-tpu-%s", userName)

		// Fetch Service to get External IP
		svc, err := clientset.CoreV1().Services(namespace).Get(ctx, svcName, metav1.GetOptions{})
		if errors.IsNotFound(err) {
			http.Error(w, "Job resources not found", http.StatusNotFound)
			return
		} else if err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}

		// Fetch Deployment to check readiness
		deploy, err := clientset.AppsV1().Deployments(namespace).Get(ctx, deployName, metav1.GetOptions{})
		deployReady := false
		if err == nil {
			deployReady = deploy.Status.ReadyReplicas > 0
		}

		// Extract External IP and determine overall status
		var externalIP string
		status := "Provisioning" // Waiting for IP

		if len(svc.Status.LoadBalancer.Ingress) > 0 {
			externalIP = svc.Status.LoadBalancer.Ingress[0].IP
			if deployReady {
				status = "Ready"
			} else {
				status = "Booting" // IP allocated, container starting
			}
		}

		response := map[string]interface{}{
			"job_id":      userName,
			"status":      status,
			"external_ip": externalIP,
			"ssh_command": "",
		}

		if externalIP != "" {
			response["ssh_command"] = fmt.Sprintf("ssh root@%s", externalIP)
		}

		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(response)
	}
}

// HandleSubmitJob orchestrates the creation of TPU workload resources
func HandleSubmitJob(clientset *kubernetes.Clientset) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
			return
		}

		var req JobRequest
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			log.Printf("Error decoding request: %v", err)
			http.Error(w, "Invalid request body", http.StatusBadRequest)
			return
		}

		log.Printf("Received job submission for user: %s", req.UserName)

		if req.UserName == "" || req.SSHPubKey == "" {
			http.Error(w, "user_name and ssh_pub_key are required", http.StatusBadRequest)
			return
		}

		// Apply default values if not specified
		if req.TPUType == "" {
			req.TPUType = "tpu-v6e-slice"
		}
		if req.TPUTopology == "" {
			req.TPUTopology = "1x1"
		}
		if req.TPUCount <= 0 {
			req.TPUCount = 1
		}

		ctx := context.Background()
		namespace := "default"
		labels := map[string]string{"app": "sgl-tpu", "developer": req.UserName}

		// 1. Ensure ConfigMap for SSH Keys exists
		cmName := fmt.Sprintf("sgl-ssh-key-%s", req.UserName)
		configMap := &corev1.ConfigMap{
			ObjectMeta: metav1.ObjectMeta{Name: cmName, Labels: labels},
			Data:       map[string]string{"authorized_keys": req.SSHPubKey},
		}
		if err := EnsureConfigMap(ctx, clientset, namespace, configMap); err != nil {
			log.Printf("Failed to ensure ConfigMap: %v", err)
			http.Error(w, fmt.Sprintf("ConfigMap error: %v", err), http.StatusInternalServerError)
			return
		}

		// 2. Ensure Service for SSH access exists
		svcName := fmt.Sprintf("sgl-svc-%s", req.UserName)
		service := &corev1.Service{
			ObjectMeta: metav1.ObjectMeta{Name: svcName, Labels: labels},
			Spec: corev1.ServiceSpec{
				Selector: labels,
				Type:     corev1.ServiceTypeLoadBalancer,
				Ports:    []corev1.ServicePort{{Name: "ssh", Port: 22, TargetPort: intstr.FromInt(22), Protocol: corev1.ProtocolTCP}},
			},
		}
		if err := EnsureService(ctx, clientset, namespace, service); err != nil {
			log.Printf("Failed to ensure Service: %v", err)
			http.Error(w, fmt.Sprintf("Service error: %v", err), http.StatusInternalServerError)
			return
		}

		// 3. Ensure Deployment for TPU Workload exists
		deployName := fmt.Sprintf("sgl-tpu-%s", req.UserName)
		tpuResourceName := corev1.ResourceName("google.com/tpu")
		tpuQty := resource.NewQuantity(req.TPUCount, resource.DecimalSI)

		deployment := &appsv1.Deployment{
			ObjectMeta: metav1.ObjectMeta{Name: deployName, Labels: labels},
			Spec: appsv1.DeploymentSpec{
				Replicas: Int32Ptr(1),
				Selector: &metav1.LabelSelector{MatchLabels: labels},
				Template: corev1.PodTemplateSpec{
					ObjectMeta: metav1.ObjectMeta{Labels: labels},
					Spec: corev1.PodSpec{
						NodeSelector: map[string]string{
							"cloud.google.com/gke-tpu-accelerator": req.TPUType,
							"cloud.google.com/gke-tpu-topology":    req.TPUTopology,
						},
						Containers: []corev1.Container{
							{
								Name:            "dev-container-tpu",
								Image:           "ghcr.io/zhengkezhou1/sgl-jax-action/dev-container-tpu:sha-600456e",
								SecurityContext: &corev1.SecurityContext{Privileged: BoolPtr(true)},
								Resources: corev1.ResourceRequirements{
									Requests: corev1.ResourceList{
										corev1.ResourceCPU:    resource.MustParse("16"),
										corev1.ResourceMemory: resource.MustParse("64Gi"),
										tpuResourceName:       *tpuQty,
									},
									Limits: corev1.ResourceList{
										corev1.ResourceCPU:    resource.MustParse("32"),
										corev1.ResourceMemory: resource.MustParse("64Gi"),
										tpuResourceName:       *tpuQty,
									},
								},
								Ports: []corev1.ContainerPort{{Name: "ssh", ContainerPort: 22}},
								Lifecycle: &corev1.Lifecycle{
									PostStart: &corev1.LifecycleHandler{
										Exec: &corev1.ExecAction{
											Command: []string{
												"/bin/bash",
												"-c",
												`
cat > /etc/profile.d/tpu-env.sh << TPUEOF
# TPU Environment Variables (auto-generated from container env)
export TPU_ACCELERATOR_TYPE="${TPU_ACCELERATOR_TYPE}"
export TPU_CHIPS_PER_HOST_BOUNDS="${TPU_CHIPS_PER_HOST_BOUNDS}"
export TPU_HOST_BOUNDS="${TPU_HOST_BOUNDS}"
export TPU_RUNTIME_METRICS_PORTS="${TPU_RUNTIME_METRICS_PORTS}"
export TPU_SKIP_MDS_QUERY="${TPU_SKIP_MDS_QUERY}"
export TPU_TOPOLOGY_ALT="${TPU_TOPOLOGY_ALT}"
export TPU_TOPOLOGY_WRAP="${TPU_TOPOLOGY_WRAP}"
export TPU_TOPOLOGY="${TPU_TOPOLOGY}"
export TPU_WORKER_HOSTNAMES="${TPU_WORKER_HOSTNAMES}"
export TPU_WORKER_ID="${TPU_WORKER_ID}"
export VBAR_CONTROL_SERVICE_URL="${VBAR_CONTROL_SERVICE_URL}"
export JAX_COMPILATION_CACHE_DIR="${JAX_COMPILATION_CACHE_DIR:-/tmp/jit_cache}"
TPUEOF

# Auto-load TPU environment for all login shells
if ! grep -q 'source /etc/profile.d/tpu-env.sh' /root/.bashrc 2>/dev/null; then
  echo '# Auto-load TPU environment variables' >> /root/.bashrc
  echo 'source /etc/profile.d/tpu-env.sh' >> /root/.bashrc
fi
`,
											},
										},
									},
								},
								LivenessProbe: &corev1.Probe{
									ProbeHandler:        corev1.ProbeHandler{TCPSocket: &corev1.TCPSocketAction{Port: intstr.FromInt(22)}},
									InitialDelaySeconds: 30,
									PeriodSeconds:       10,
								},
								VolumeMounts: []corev1.VolumeMount{{Name: "ssh-key", MountPath: "/tmp/ssh-keys", ReadOnly: true}},
							},
						},
						Volumes: []corev1.Volume{
							{
								Name: "ssh-key",
								VolumeSource: corev1.VolumeSource{
									ConfigMap: &corev1.ConfigMapVolumeSource{
										LocalObjectReference: corev1.LocalObjectReference{Name: cmName},
										DefaultMode:          Int32Ptr(0644),
									},
								},
							},
						},
					},
				},
			},
		}
		if err := EnsureDeployment(ctx, clientset, namespace, deployment); err != nil {
			log.Printf("Failed to ensure Deployment: %v", err)
			http.Error(w, fmt.Sprintf("Deployment error: %v", err), http.StatusInternalServerError)
			return
		}

		log.Printf("Successfully processed job for %s", req.UserName)
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]string{
			"status":    "submitted",
			"job_id":    req.UserName,
			"check_url": fmt.Sprintf("/api/jobs/status?user_name=%s", req.UserName),
			"message":   "Job resources created. Poll the check_url for external IP.",
		})
	}
}

// EnsureConfigMap creates or updates the ConfigMap idempotently
func EnsureConfigMap(ctx context.Context, client *kubernetes.Clientset, ns string, cm *corev1.ConfigMap) error {
	_, err := client.CoreV1().ConfigMaps(ns).Create(ctx, cm, metav1.CreateOptions{})
	if errors.IsAlreadyExists(err) {
		_, err = client.CoreV1().ConfigMaps(ns).Update(ctx, cm, metav1.UpdateOptions{})
	}
	return err
}

// EnsureService creates the Service if it doesn't exist
func EnsureService(ctx context.Context, client *kubernetes.Clientset, ns string, svc *corev1.Service) error {
	_, err := client.CoreV1().Services(ns).Create(ctx, svc, metav1.CreateOptions{})
	if errors.IsAlreadyExists(err) {
		return nil // Service updates are complex, skip if exists
	}
	return err
}

// EnsureDeployment creates or updates the Deployment idempotently
func EnsureDeployment(ctx context.Context, client *kubernetes.Clientset, ns string, d *appsv1.Deployment) error {
	_, err := client.AppsV1().Deployments(ns).Create(ctx, d, metav1.CreateOptions{})
	if errors.IsAlreadyExists(err) {
		_, err = client.AppsV1().Deployments(ns).Update(ctx, d, metav1.UpdateOptions{})
	}
	return err
}

func Int32Ptr(i int32) *int32 { return &i }
func BoolPtr(b bool) *bool    { return &b }
