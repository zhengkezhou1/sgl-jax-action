package main

import (
	"log"
	"net/http"

	"github.com/sgl-jax-action/internal/scheduler"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/rest"
)

func main() {
	// 1. Initialize Kubernetes In-Cluster Client
	config, err := rest.InClusterConfig()
	if err != nil {
		log.Fatalf("Failed to get in-cluster config: %v", err)
	}

	clientset, err := kubernetes.NewForConfig(config)
	if err != nil {
		log.Fatalf("Failed to create clientset: %v", err)
	}

	// 2. Register Routes
	http.HandleFunc("/healthz", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		w.Write([]byte("ok"))
	})

	http.HandleFunc("/api/pods", scheduler.HandleListPods(clientset))
	http.HandleFunc("/api/jobs", scheduler.HandleSubmitJob(clientset))
	http.HandleFunc("/api/jobs/status", scheduler.HandleGetJobStatus(clientset))

	// 3. Start HTTP Server
	port := "8080"
	log.Printf("Starting middleware server on port %s", port)
	if err := http.ListenAndServe(":"+port, nil); err != nil {
		log.Fatalf("Server failed: %v", err)
	}
}
