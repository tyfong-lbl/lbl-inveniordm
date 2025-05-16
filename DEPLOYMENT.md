# Deployment Guide for Kubernetes/Rancher

## Overview

This guide provides step-by-step instructions to deploy the application to a remote Kubernetes or Rancher instance.

## Prerequisites

- Kubernetes cluster (e.g., GKE, EKS, AKS, Minikube, Kind)
- `kubectl` configured to interact with the cluster
- Docker installed and configured to push images to a container registry

## Steps

### 1. Create a Kubernetes Deployment Configuration

Create a `deployment.yaml` file to define the deployment of the application.

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: lbnl-data-repository-deployment
spec:
  replicas: 3
  selector:
    matchLabels:
      app: lbnl-data-repository
  template:
    metadata:
      labels:
        app: lbnl-data-repository
    spec:
      containers:
      - name: lbnl-data-repository
        image: your-container-registry/lbnl-data-repository:latest
        ports:
        - containerPort: 5000
        env:
        - name: INVENIO_INSTANCE_PATH
          value: /opt/invenio-instance
        - name: FLASK_APP
          value: invenio_app_rdm:create_app
        - name: FLASK_ENV
          value: production
        volumeMounts:
        - name: app-storage
          mountPath: /opt/invenio-instance
      volumes:
      - name: app-storage
        persistentVolumeClaim:
          claimName: lbnl-data-repository-pvc
```

### 2. Create a Kubernetes Service Configuration

Create a `service.yaml` file to expose the application within the cluster.

```yaml
apiVersion: v1
kind: Service
metadata:
  name: lbnl-data-repository-service
spec:
  selector:
    app: lbnl-data-repository
  ports:
    - protocol: TCP
      port: 80
      targetPort: 5000
  type: ClusterIP
```

### 3. Parameterize Configuration Using ConfigMaps and Secrets

Create `configmap.yaml` and `secret.yaml` files to manage configuration and sensitive data.

**configmap.yaml**

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: lbnl-data-repository-config
data:
  invenio.cfg: |
    # Configuration settings
    SECRET_KEY: your-secret-key
    SQLALCHEMY_DATABASE_URI: postgresql+psycopg2://user:password@db:5432/invenio
```

**secret.yaml**

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: lbnl-data-repository-secrets
type: Opaque
data:
  SECRET_KEY: your-base64-encoded-secret-key
  DATABASE_PASSWORD: your-base64-encoded-database-password
```

Update the application to read configuration from these ConfigMaps and Secrets.

### 4. Create a Persistent Volume Claim (PVC) for Data Storage

Create a `pvc.yaml` file to define storage requirements for the application.

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: lbnl-data-repository-pvc
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
```

Update the application to use the PVC for persistent data storage.

### 5. Set Up Ingress for External Access

Create an `ingress.yaml` file to expose the application externally.

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: lbnl-data-repository-ingress
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  rules:
  - host: your-domain.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: lbnl-data-repository-service
            port:
              number: 80
```

Configure the ingress controller to route traffic to the service.

### 6. Test the Deployment Locally

Use Minikube or Kind to test the deployment locally.

```bash
minikube start
kubectl apply -f deployment.yaml
kubectl apply -f service.yaml
kubectl apply -f configmap.yaml
kubectl apply -f secret.yaml
kubectl apply -f pvc.yaml
kubectl apply -f ingress.yaml
minikube ip
```

Verify that the application runs correctly and is accessible.

### 7. Deploy to Kubernetes/Rancher

Apply the Kubernetes manifests to the remote cluster.

```bash
kubectl apply -f deployment.yaml
kubectl apply -f service.yaml
kubectl apply -f configmap.yaml
kubectl apply -f secret.yaml
kubectl apply -f pvc.yaml
kubectl apply -f ingress.yaml
```

Monitor the deployment for any issues and resolve them.

### 8. Monitor and Scale the Application

Set up monitoring and logging for the application.

```bash
kubectl get pods
kubectl logs <pod-name>
```

Configure horizontal pod autoscaling to handle varying loads.

```bash
kubectl autoscale deployment lbnl-data-repository-deployment --cpu-percent=50 --min=1 --max=10
```

### 9. Document the Deployment Process

Create a `DEPLOYMENT.md` file to document the deployment process.

Include instructions for setting up the environment, deploying the application, and troubleshooting common issues.