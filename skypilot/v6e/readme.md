#单机测试

创建集群
```
terrafrom init

terrafrom apply
```

配置 sky config
```zsh
cat config.yaml > ~/.sky/config.yaml
```

启动 Ray Cluster
```
sky launch -r job.yaml
```