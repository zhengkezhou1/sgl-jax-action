package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"

	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/rest"
)

func main() {
	// 1. 初始化 Kubernetes Client
	// 使用 InClusterConfig，这要求 Pod 必须绑定了正确的 ServiceAccount
	config, err := rest.InClusterConfig()
	if err != nil {
		log.Fatalf("Failed to get in-cluster config: %v", err)
	}

	clientset, err := kubernetes.NewForConfig(config)
	if err != nil {
		log.Fatalf("Failed to create clientset: %v", err)
	}

	// 2. 注册路由处理函数
	http.HandleFunc("/healthz", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		w.Write([]byte("ok"))
	})

	http.HandleFunc("/api/pods", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet {
			http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
			return
		}

		// 列出 default 命名空间下的所有 Pod
		// 在实际业务中，这里应该接收参数或列出特定 Selector 的 Pod
		pods, err := clientset.CoreV1().Pods("default").List(context.Background(), metav1.ListOptions{})
		if err != nil {
			log.Printf("Error listing pods: %v", err)
			http.Error(w, fmt.Sprintf("Failed to list pods: %v", err), http.StatusInternalServerError)
			return
		}

		response := make([]string, 0, len(pods.Items))
		for _, pod := range pods.Items {
			response = append(response, pod.Name)
		}

		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]interface{}{
			"count": len(pods.Items),
			"pods":  response,
		})
	})

	// 3. 启动 HTTP 服务
	port := "8080"
	log.Printf("Starting middleware server on port %s", port)

	// Server 会一直阻塞在这里，直到出错
	if err := http.ListenAndServe(":"+port, nil); err != nil {
		log.Fatalf("Server failed: %v", err)
	}
}
