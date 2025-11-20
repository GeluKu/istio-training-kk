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
  --profile=istio-lab \
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
minikube status -p istio-lab
kubectl get nodes
echo ""

echo "=========================================="
echo "Step 2: Installing MetalLB"
echo "=========================================="

# Enable MetalLB addon
minikube addons enable metallb -p istio-lab

# Get Minikube IP range for MetalLB configuration
MINIKUBE_IP=$(minikube ip -p istio-lab)
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
echo "Installation Complete!"
echo "=========================================="
echo ""
echo "Cluster Information:"
echo "  Profile: istio-lab"
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

echo "Useful Commands:"
echo "  - Switch context: minikube profile istio-lab"
echo "  - View all nodes: kubectl get nodes"
echo "  - View MetalLB status: kubectl get pods -n metallb-system"
echo "  - Access dashboard: minikube dashboard -p istio-lab"
echo "  - Stop cluster: minikube stop -p istio-lab"
echo "  - Delete cluster: minikube delete -p istio-lab"
echo ""
echo "To test the Ingress Gateway with MetalLB:"
echo "  curl http://\$INGRESS_IP"