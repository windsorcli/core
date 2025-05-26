apiVersion: v1
kind: Config
clusters:
- name: ${cluster_name}
  cluster:
    server: ${cluster_endpoint}
    certificate-authority-data: ${cluster_ca}
contexts:
- name: ${cluster_name}
  context:
    cluster: ${cluster_name}
    user: ${cluster_name}
current-context: ${cluster_name}
users:
- name: ${cluster_name}
  user:
    exec:
      apiVersion: client.authentication.k8s.io/v1beta1
      command: aws
      args:
        - eks
        - get-token
        - --cluster-name
        - ${cluster_name}
        - --region
        - ${region}
