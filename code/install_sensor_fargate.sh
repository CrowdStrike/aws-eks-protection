#!/bin/bash
echo "Creating kubeconfig for $CLUSTER"
aws eks update-kubeconfig --region $AWS_REGION --name $CLUSTER
pods=$(kubectl get pods -A)
case "$pods" in 
    *kpagent*) 
        echo "Protection Agent already installed on cluster: $CLUSTER" 
        ;;
    *)
        echo "Installing Protection Agent..."
        helm upgrade --install -f kpa_config.value --create-namespace -n falcon-kubernetes-protection kpagent crowdstrike/cs-k8s-protection-agent
        ;;
esac
case "$pods" in 
    *falcon-operator*) 
        echo "Operator already installed on cluster: $CLUSTER" 
        ;;
    *)
        echo "Installing Operator..."
        eksctl create fargateprofile --region $AWS_REGION --cluster $CLUSTER --name fp-falcon-operator --namespace falcon-operator
        kubectl apply -f https://github.com/CrowdStrike/falcon-operator/releases/latest/download/falcon-operator.yaml
        ;;
esac
case "$pods" in 
    *falcon-sidecar-sensor*) 
        echo "Sensor already installed on cluster: $CLUSTER" 
        ;;
    *)
        echo "Installing sensor..."
        eksctl create fargateprofile --region $AWS_REGION --cluster $CLUSTER --name fp-falcon-system --namespace falcon-system
        kubectl create -f sidecar_sensor.yaml
        ;;
esac
if [ $ENABLE_KAC == "true" ]; then
    case "$pods" in 
        *falcon-admission*) 
            echo "Admission Controller already installed on cluster: $CLUSTER" 
            ;;
        *)
            echo "Installing Admission Controller..."
            eksctl create fargateprofile --region $AWS_REGION --cluster $CLUSTER --name fp-falcon-kac --namespace falcon-kac
            kubectl create -f falcon_admission.yaml
            ;;
    esac
fi
