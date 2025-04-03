# Azure CLI commands to create the AKS cluster and deploy RabbitMQ

# Define variables
$RESOURCE_GROUP = "yourresourcegroupnamehere"
$LOCATION = "westeurope"
$CLUSTER_NAME = "YourAKSClusterName"
$NODE_COUNT = 3
$ADMIN_USER = "admin"
$ADMIN_PASSWORD = "rabbitmqpassword"
$VHOST_NAME = "/outsystems"
$RABBITMQ_VERSION = "3.13.0"


# Create Resource Group
az group create --name $RESOURCE_GROUP --location $LOCATION

# Create AKS Cluster
az aks create --resource-group $RESOURCE_GROUP --name $CLUSTER_NAME --node-count $NODE_COUNT --enable-managed-identity --generate-ssh-keys

# Get AKS Credentials to connect with kubectl
az aks get-credentials --resource-group $RESOURCE_GROUP --name $CLUSTER_NAME --overwrite-existing

# Verify the cluster is running
kubectl get nodes

# Deploy RabbitMQ Cluster Operator from official GitHub release
kubectl apply -f https://github.com/rabbitmq/cluster-operator/releases/latest/download/cluster-operator.yml

# Wait for the operator to be fully running
kubectl wait --for=condition=available deployment/rabbitmq-cluster-operator -n rabbitmq --timeout=120s

# Create rabbitmq namespace if not exists
kubectl create namespace rabbitmq

# Update rabbitmq-cluster.yaml with desired values
# Inject dynamic values into rabbitmq-cluster.yaml
(Get-Content "rabbitmq-cluster.yaml") `
    -replace '(?<=image:\s+rabbitmq:).*', $RABBITMQ_VERSION `
    -replace '(?<=name:\s+RABBITMQ_DEFAULT_USER\s+value:\s+).*', '"' + $ADMIN_USER + '"' `
    -replace '(?<=name:\s+RABBITMQ_DEFAULT_PASS\s+value:\s+).*', '"' + $ADMIN_PASSWORD + '"' `
    | Set-Content "rabbitmq-cluster.yaml"

# Apply RabbitMQ cluster and service
kubectl apply -f rabbitmq-cluster.yaml
kubectl apply -f rabbitmq-service.yaml

# Wait for pods to be ready
kubectl rollout status statefulset/rabbitmq-server -n rabbitmq --timeout=300s

# Set admin user tags and permissions
kubectl exec -it rabbitmq-server-0 -n rabbitmq -c rabbitmq -- rabbitmqctl set_user_tags $ADMIN_USER administrator
kubectl exec -it rabbitmq-server-0 -n rabbitmq -c rabbitmq -- rabbitmqctl delete_user guest
kubectl exec -it rabbitmq-server-0 -n rabbitmq -c rabbitmq -- rabbitmqctl add_vhost $VHOST_NAME
kubectl exec -it rabbitmq-server-0 -n rabbitmq -c rabbitmq -- rabbitmqctl set_permissions -p $VHOST_NAME $ADMIN_USER ".*" ".*" ".*"

# Get RabbitMQ Service IP information
kubectl get svc rabbitmq-service -n rabbitmq