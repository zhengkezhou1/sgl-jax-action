package main

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
	"k8s.io/client-go/rest"
)

type JobRequest struct {
	UserName    string `json:"user_name"`
	SSHPubKey   string `json:"ssh_pub_key"`
	TPUType     string `json:"tpu_type"`
	TPUTopology string `json:"tpu_topology"`
	TPUCount    int64  `json:"tpu_count"`
}

func main() {
	config, err := rest.InClusterConfig()
	if err != nil {
		log.Fatalf("Failed to get in-cluster config: %v", err)
	}

	clientset, err := kubernetes.NewForConfig(config)
	if err != nil {
		log.Fatalf("Failed to create clientset: %v", err)
	}

	http.HandleFunc("/healthz", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		w.Write([]byte("ok"))
	})

	http.HandleFunc("/api/jobs", handleSubmitJob(clientset))
	http.HandleFunc("/api/jobs/status", handleGetJobStatus(clientset))

	port := "8080"
	log.Printf("Starting middleware server on port %s", port)
	if err := http.ListenAndServe(":"+port, nil); err != nil {
		log.Fatalf("Server failed: %v", err)
	}
}

func handleSubmitJob(clientset *kubernetes.Clientset) http.HandlerFunc {
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

		// 1. ConfigMap
		cmName := fmt.Sprintf("sgl-ssh-key-%s", req.UserName)
		configMap := &corev1.ConfigMap{
			ObjectMeta: metav1.ObjectMeta{Name: cmName, Labels: labels},
			Data:       map[string]string{"authorized_keys": req.SSHPubKey},
		}
		if err := ensureConfigMap(ctx, clientset, namespace, configMap); err != nil {
			log.Printf("Failed to ensure ConfigMap: %v", err)
			http.Error(w, fmt.Sprintf("ConfigMap error: %v", err), http.StatusInternalServerError)
			return
		}

		// 2. Service
		svcName := fmt.Sprintf("sgl-svc-%s", req.UserName)
		service := &corev1.Service{
			ObjectMeta: metav1.ObjectMeta{Name: svcName, Labels: labels},
			Spec: corev1.ServiceSpec{
				Selector: labels,
				Type:     corev1.ServiceTypeLoadBalancer,
				Ports:    []corev1.ServicePort{{Name: "ssh", Port: 22, TargetPort: intstr.FromInt(22)}},
			},
		}
		if err := ensureService(ctx, clientset, namespace, service); err != nil {
			log.Printf("Failed to ensure Service: %v", err)
			http.Error(w, fmt.Sprintf("Service error: %v", err), http.StatusInternalServerError)
			return
		}

		// 3. Deployment
		deployName := fmt.Sprintf("sgl-tpu-%s", req.UserName)
		tpuQty := resource.NewQuantity(req.TPUCount, resource.DecimalSI)
		deployment := &appsv1.Deployment{
			ObjectMeta: metav1.ObjectMeta{Name: deployName, Labels: labels},
			Spec: appsv1.DeploymentSpec{
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
								Name:  "sgl-jax",
								Image: "ghcr.io/zhengkezhou1/sgl-jax-action:v0.0.4",
								Resources: corev1.ResourceRequirements{
									Limits: corev1.ResourceList{"google.com/tpu": *tpuQty},
								},
								Ports:        []corev1.ContainerPort{{ContainerPort: 22}},
								VolumeMounts: []corev1.VolumeMount{{Name: "ssh-key", MountPath: "/tmp/ssh-keys"}},
							},
						},
						Volumes: []corev1.Volume{
							{
								Name: "ssh-key",
								VolumeSource: corev1.VolumeSource{
									ConfigMap: &corev1.ConfigMapVolumeSource{
										LocalObjectReference: corev1.LocalObjectReference{Name: cmName},
									},
								},
							},
						},
					},
				},
			},
		}
		if err := ensureDeployment(ctx, clientset, namespace, deployment); err != nil {
			log.Printf("Failed to ensure Deployment: %v", err)
			http.Error(w, fmt.Sprintf("Deployment error: %v", err), http.StatusInternalServerError)
			return
		}

		log.Printf("Successfully processed job for %s", req.UserName)
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]string{"status": "submitted", "job_id": req.UserName})
	}
}

// Helper functions with error returning
func ensureConfigMap(ctx context.Context, c *kubernetes.Clientset, ns string, cm *corev1.ConfigMap) error {
	_, err := c.CoreV1().ConfigMaps(ns).Create(ctx, cm, metav1.CreateOptions{})
	if errors.IsAlreadyExists(err) {
		_, err = c.CoreV1().ConfigMaps(ns).Update(ctx, cm, metav1.UpdateOptions{})
	}
	return err
}

func ensureService(ctx context.Context, c *kubernetes.Clientset, ns string, svc *corev1.Service) error {
	_, err := c.CoreV1().Services(ns).Create(ctx, svc, metav1.CreateOptions{})
	if errors.IsAlreadyExists(err) {
		return nil // Service updates are complex, skip if exists
	}
	return err
}

func ensureDeployment(ctx context.Context, c *kubernetes.Clientset, ns string, d *appsv1.Deployment) error {
	_, err := c.AppsV1().Deployments(ns).Create(ctx, d, metav1.CreateOptions{})
	if errors.IsAlreadyExists(err) {
		_, err = c.AppsV1().Deployments(ns).Update(ctx, d, metav1.UpdateOptions{})
	}
	return err
}

// ... handleGetJobStatus simplified ...
func handleGetJobStatus(c *kubernetes.Clientset) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		userName := r.URL.Query().Get("user_name")
		svc, _ := c.CoreV1().Services("default").Get(context.Background(), fmt.Sprintf("sgl-svc-%s", userName), metav1.GetOptions{})
		ip := ""
		if len(svc.Status.LoadBalancer.Ingress) > 0 {
			ip = svc.Status.LoadBalancer.Ingress[0].IP
		}
		json.NewEncoder(w).Encode(map[string]string{"status": "Ready", "external_ip": ip})
	}
}
