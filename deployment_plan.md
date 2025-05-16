# Tasks to Prepare Repository for Kubernetes/Rancher Deployment

## 1. Create Custom Dockerfile for Kubernetes
**Task**: Develop a Dockerfile optimized for Kubernetes deployment (`Dockerfile.k8s`).  
**Subtasks**:  
- Use a minimal base image (e.g., `python:3.9-slim`).  
- Install dependencies from `Pipfile` or `requirements.txt`.  
- Copy application code, static assets, and configuration files.  
- Set environment variables (e.g., `FLASK_ENV=production`).  
- Expose port `5000` (default for Invenio).  
- Define entrypoint/command (e.g., `uwsgi --ini /app/docker/uwsgi/uwsgi_ui.ini`).  

---

## 2. Build and Push Docker Image  
**Task**: Build the Docker image and push it to a container registry (e.g., Docker Hub, AWS ECR, or GCR).  
**Subtasks**:  
- Tag the image with your registry path (e.g., `docker tag lbnl-data-repo:latest your-registry.com/lbnl-data-repo:latest`).  
- Push the image to the registry (`docker push your-registry.com/lbnl-data-repo:latest`).  
- Update `deployment.yaml` to reference the registry path.  

---

## 3. Configure Kubernetes Manifests  
**Task**: Create Kubernetes manifests (`deployment.yaml`, `service.yaml`, etc.).  
**Subtasks**:  
- Define the Deployment with the pushed image (from Step 2).  
- Configure PVC for persistent storage (`pvc.yaml`).  
- Set up ConfigMaps/Secrets for configuration and secrets (`configmap.yaml`, `secret.yaml`).  
- Create an Ingress resource for external access (`ingress.yaml`).  

---

## 4. Local Testing  
**Task**: Validate the setup in a local Kubernetes cluster (Minikube/Kind).  
**Subtasks**:  
- Run `kubectl apply -f [manifests]`.  
- Test connectivity and persistence.  

---

## 5. Deploy to Kubernetes/Rancher  
**Task**: Deploy to the production cluster.  
**Subtasks**:  
- Update image tags if using versioned releases.  
- Apply manifests to the remote cluster.  
- Verify pod health and ingress access.  

---

### Key Clarifications:  
- **Docker Image Workflow**:  
  1. Modify `Dockerfile.k8s` → 2. Build/Push → 3. Update `deployment.yaml` → 4. Deploy  
- **Example Build Commands**:  
  ```bash  
  # Build image  
  docker build -t lbnl-data-repo:latest -f Dockerfile.k8s .  
  
  # Push to registry (replace with your registry)  
  docker tag lbnl-data-repo:latest your-registry.com/lbnl-data-repo:latest  
  docker push your-registry.com/lbnl-data-repo:latest