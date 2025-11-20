#!/bin/bash

# Istio on Minikube Setup Script with MetalLB
# This script creates a Minikube cluster with KVM2 driver and installs Istio + MetalLB

set -e

echo "=========================================="
echo "Step 1: Creating Minikube Cluster"
echo "=========================================="

# Clean up any existing cluster with the same name
minikube delete -p istio-lab 2>/dev/null || true

# Start Minikube cluster with specified configuration
minikube start \
  --profile=istio-lab-ambient \
  --nodes=3 \
  --cpus=2 \
  --memory=4096 \
  --disk-size=30g \
  --driver=kvm2 \
  --container-runtime=containerd \
  --kubernetes-version=stable

echo "Cluster created successfully!"
echo ""

# Verify cluster is running
echo "=========================================="
echo "Verifying Cluster Status"
echo "=========================================="
minikube status -p istio-lab-ambient
kubectl get nodes
echo ""

echo "set minikube profile to istio-lab-ambient"
minikube profile istio-lab-ambient

echo "=========================================="
echo "Step 2: Installing MetalLB"
echo "=========================================="

# Enable MetalLB addon
minikube addons enable metallb -p istio-lab-ambient

# Get Minikube IP range for MetalLB configuration
MINIKUBE_IP=$(minikube ip -p istio-lab-ambient)
echo "Minikube IP: $MINIKUBE_IP"

# Extract the first three octets for IP range
IP_PREFIX=$(echo $MINIKUBE_IP | cut -d'.' -f1-3)
METALLB_START="${IP_PREFIX}.200"
METALLB_END="${IP_PREFIX}.250"

echo "Configuring MetalLB IP range: ${METALLB_START} - ${METALLB_END}"

# Configure MetalLB IP address pool
kubectl create namespace metallb-system --dry-run=client -o yaml | kubectl apply -f -

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  namespace: metallb-system
  name: config
data:
  config: |
    address-pools:
    - name: default
      protocol: layer2
      addresses:
      - ${METALLB_START}-${METALLB_END}
EOF

echo "MetalLB configured with IP range: ${METALLB_START} - ${METALLB_END}"
echo ""

# Wait for MetalLB pods to be ready
echo "Waiting for MetalLB pods to be ready..."
kubectl wait --for=condition=ready --timeout=120s pod -l app=metallb -n metallb-system 2>/dev/null || true
sleep 10

echo ""
echo "=========================================="
echo "Step 3: Downloading Istio"
echo "=========================================="

# Download and install Istio
cd ~
curl -L https://istio.io/downloadIstio | sh -

# Move to the Istio package directory
ISTIO_VERSION=$(ls -d istio-* | head -n 1)
cd $ISTIO_VERSION

# Add istioctl to PATH for current session
export PATH=$PWD/bin:$PATH

echo "Istio downloaded to: $(pwd)"
echo "istioctl version: $(istioctl version --remote=false)"
echo ""

echo "=========================================="
echo "Step 4: Installing Istio"
echo "=========================================="

# Install Istio with demo profile (suitable for testing)
istioctl install --set profile=ambient -y

echo ""
echo "=========================================="
echo "Step 5: Enabling Istio Injection"
echo "=========================================="

# Label the default namespace for automatic sidecar injection
kubectl label namespace default istio-injection=enabled --overwrite

echo ""
echo "=========================================="
echo "Step 6: Verifying Istio Installation"
echo "=========================================="

# Wait for Istio components to be ready
echo "Waiting for Istio components to be ready..."
kubectl wait --for=condition=available --timeout=300s deployment --all -n istio-system

# Check Istio components
echo ""
echo "Istio Pods:"
kubectl get pods -n istio-system

echo ""
echo "Istio Services:"
kubectl get svc -n istio-system

echo ""
echo "=========================================="
echo "Step 7: Verifying MetalLB Integration"
echo "=========================================="

# Show LoadBalancer services
echo "LoadBalancer Services (with external IPs from MetalLB):"
kubectl get svc -n istio-system -l istio=ingressgateway

echo ""
echo "=========================================="
echo "Installation Complete!"
echo "=========================================="
echo ""
echo "Cluster Information:"
echo "  Profile: istio-lab-ambient"
echo "  Driver: kvm2"
echo "  Container Runtime: containerd"
echo "  Nodes: 3"
echo "  CPU per node: 2"
echo "  Memory per node: 4GB"
echo "  Disk per node: 30GB"
echo ""
echo "MetalLB Configuration:"
echo "  IP Range: ${METALLB_START} - ${METALLB_END}"
echo ""
echo "Istio Components Installed:"
kubectl get deployments -n istio-system
echo ""
echo "Istio Ingress Gateway External IP:"
INGRESS_IP=$(kubectl get svc istio-ingressgateway -n istio-system -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
if [ -n "$INGRESS_IP" ]; then
  echo "  $INGRESS_IP"
else
  echo "  Pending... (wait a few moments and check with: kubectl get svc -n istio-system)"
fi
echo ""
echo "Useful Commands:"
echo "  - Switch context: minikube profile istio-lab-am"
echo "  - View all nodes: kubectl get nodes"
echo "  - View MetalLB status: kubectl get pods -n metallb-system"
echo "  - Access dashboard: minikube dashboard -p istio-lab-ambient"
echo "  - View Istio config: istioctl analyze"
echo "  - Access Kiali: kubectl port-forward svc/kiali -n istio-system 20001:20001"
echo "  - Access Grafana: kubectl port-forward svc/grafana -n istio-system 3000:3000"
echo "  - Access Prometheus: kubectl port-forward svc/prometheus -n istio-system 9090:9090"
echo "  - Stop cluster: minikube stop -p istio-lab-ambient"
echo "  - Delete cluster: minikube delete -p istio-lab-ambient"
echo ""
echo "Note: Add istioctl to your PATH permanently:"
echo "  export PATH=\$HOME/$ISTIO_VERSION/bin:\$PATH"
echo "  (Add this line to your ~/.bashrc or ~/.zshrc)"
echo ""
echo "To test the Ingress Gateway with MetalLB:"
echo "  curl http://\$INGRESS_IP"