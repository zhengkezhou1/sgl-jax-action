package scheduler

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"text/template"

	appsv1 "k8s.io/api/apps/v1"
	corev1 "k8s.io/api/core/v1"
	"k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/kubernetes"
	"sigs.k8s.io/yaml"
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

		// 1. Ensure ConfigMap for SSH Keys exists
		var configMap corev1.ConfigMap
		if err := loadResourceFromTemplate("config/templates/dev-container-tpu/configmap.yaml", req, &configMap); err != nil {
			log.Printf("Failed to load ConfigMap template: %v", err)
			http.Error(w, fmt.Sprintf("Template error: %v", err), http.StatusInternalServerError)
			return
		}
		if err := EnsureConfigMap(ctx, clientset, namespace, &configMap); err != nil {
			log.Printf("Failed to ensure ConfigMap: %v", err)
			http.Error(w, fmt.Sprintf("ConfigMap error: %v", err), http.StatusInternalServerError)
			return
		}

		// 2. Ensure Service for SSH access exists
		var service corev1.Service
		if err := loadResourceFromTemplate("config/templates/dev-container-tpu/service.yaml", req, &service); err != nil {
			log.Printf("Failed to load Service template: %v", err)
			http.Error(w, fmt.Sprintf("Template error: %v", err), http.StatusInternalServerError)
			return
		}
		if err := EnsureService(ctx, clientset, namespace, &service); err != nil {
			log.Printf("Failed to ensure Service: %v", err)
			http.Error(w, fmt.Sprintf("Service error: %v", err), http.StatusInternalServerError)
			return
		}

		// 3. Ensure Deployment for TPU Workload exists
		var deployment appsv1.Deployment
		if err := loadResourceFromTemplate("config/templates/dev-container-tpu/deployment.yaml", req, &deployment); err != nil {
			log.Printf("Failed to load Deployment template: %v", err)
			http.Error(w, fmt.Sprintf("Template error: %v", err), http.StatusInternalServerError)
			return
		}
		if err := EnsureDeployment(ctx, clientset, namespace, &deployment); err != nil {
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

// loadResourceFromTemplate reads a template file, executes it with data, and unmarshals the result into out.
func loadResourceFromTemplate(path string, data interface{}, out interface{}) error {
	tmplContent, err := os.ReadFile(path)
	if err != nil {
		return fmt.Errorf("failed to read template %s: %w", path, err)
	}

	tmpl, err := template.New(filepath.Base(path)).Parse(string(tmplContent))
	if err != nil {
		return fmt.Errorf("failed to parse template %s: %w", path, err)
	}

	var buf bytes.Buffer
	if err := tmpl.Execute(&buf, data); err != nil {
		return fmt.Errorf("failed to execute template %s: %w", path, err)
	}

	if err := yaml.Unmarshal(buf.Bytes(), out); err != nil {
		return fmt.Errorf("failed to unmarshal resource from %s: %w", path, err)
	}
	return nil
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
