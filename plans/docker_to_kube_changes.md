**Yes, but it's more of a transformation than a direct edit.**

Docker Compose and Kubernetes serve similar purposes but use completely different syntax and concepts:

**Key Changes Required:**

1. **File Structure**: 
   - `docker-compose.yml` → Multiple K8s YAML files (Deployments, Services, ConfigMaps, etc.)
   - Single compose file → Helm chart directory structure

2. **Service Definitions**:
   - `services:` → `kind: Deployment` + `kind: Service`
   - `volumes:` → `PersistentVolumeClaim` + `volumeMounts`
   - `environment:` → `ConfigMap` or `Secret`

3. **Networking**:
   - Compose automatic service discovery → Explicit Kubernetes Services
   - `ports: "127.0.0.1:5432:5432"` → LoadBalancer or NodePort Services

**What Transfers Directly:**
- Container images (`image: postgres:14.13`)
- Environment variable values
- Volume mount paths
- Resource limits

**What Changes Completely:**
- YAML structure and syntax
- Service networking model
- Secret management approach
- Health checks and restart policies

**Practical Approach:**
1. Start with your current compose file as a reference
2. Use `kompose convert` tool for initial transformation
3. Manually refactor the output into proper Helm templates
4. Add Kubernetes-specific features (ConfigMaps, Secrets, Ingress)

The logic and configuration values remain similar, but you're essentially rebuilding the deployment architecture for a different orchestration platform.