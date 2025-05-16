

```markdown
# InvenioRDM Containerization Specification

## Executive Summary
This document outlines the specifications for transitioning from a hybrid InvenioRDM v.12 installation (containerized services with application on bare metal) to a fully containerized solution that can be deployed on a self-hosted Kubernetes cluster running on Proxmox. The goal is to maintain development on a local environment while enabling deployment to production with minimal friction.

## Current Architecture
- **InvenioRDM Version**: v.12
- **Currently Containerized**: Cache (Redis), Database (PostgreSQL), Message Queue (RabbitMQ), Search (OpenSearch), OpenSearch-Dashboards, PGAdmin
- **Currently on Bare Metal**: InvenioRDM application (in Python virtual environment)
- **Authentication**: Currently password-based in development

## Target Architecture

### Components to Containerize
1. **InvenioRDM Application**
   - Custom container image with application code and specific theme/template customizations
   - Based on InvenioRDM v.12
   - Container resource allocation: Scale based on load

2. **Database (PostgreSQL)**
   - Continue using containerized PostgreSQL
   - Persistent data storage via PVC with RWX access

3. **Cache (Redis)**
   - Continue using containerized Redis
   - Persistent data storage if needed

4. **Message Queue (RabbitMQ)**
   - Continue using containerized RabbitMQ
   - Persistent data storage via PVC

5. **Search (OpenSearch)**
   - Continue using containerized OpenSearch
   - Security enhancements as outlined in security plan
   - Persistent data storage via PVC

6. **OpenSearch Dashboards**
   - Continue using containerized OpenSearch Dashboards
   - Security enhancements as outlined in security plan

### Kubernetes-Specific Resources
- **Namespace**: Dedicated namespace for InvenioRDM
- **Deployments**: For stateless components
- **StatefulSets**: For stateful components (DB, Redis, RabbitMQ, OpenSearch)
- **Services**: Internal ClusterIP services for all components except web UI
- **Ingress**: For web UI, with TLS termination
- **PersistentVolumeClaims**: For database, file storage, search indices
- **ConfigMaps**: For non-sensitive configuration
- **Secrets**: For credentials, certificates, and sensitive configuration
- **NetworkPolicies**: To restrict pod-to-pod communication
- **ServiceAccounts**: With minimal permissions

## Detailed Requirements

### Performance Requirements
- **Hardware Resources**: Scale to efficiently use available resources
  - Production: Available resources on Proxmox cluster
  - Development: Up to 12 CPU cores, 30 GB RAM
- **Storage**: Initially hundreds of GB, eventually multiple TB
- **User Load**: Initially light (alpha testing)
- **Auto-scaling**: Implement based on load

### Security Requirements
1. **Authentication**:
   - Development: Simple password authentication
   - Production: SAML2 integration with LBL's SSO service

2. **Authorization**:
   - Follow InvenioRDM's built-in role-based access controls

3. **Container Security**:
   - Container image scanning in build pipeline
   - Use non-root users in containers
   - Read-only file systems where possible
   - Drop unnecessary capabilities
   
4. **Network Security**:
   - Only web UI exposed externally on standard HTTPS port
   - Internal services restricted to pod-to-pod communication
   - Network policies to limit pod communication paths
   - OpenSearch security features enabled as per separate security plan

5. **Secrets Management**:
   - Use Kubernetes Secrets for all credentials
   - Proper secret rotation procedures
   - No hard-coded secrets in container images

6. **Database Security**:
   - Strong passwords stored in Kubernetes Secrets
   - Network access limited to application pods

### Networking Requirements
- **Externally Accessible**: Only web UI
- **Domain**: invenio.lbl.gov for production
- **TLS**: HTTPS for all external access
- **Internal Communication**: All services communicate via internal Kubernetes network

### Data Persistence Requirements
- **Database Data**: Stored in PVC with RWX access
- **OpenSearch Indices**: Stored in PVC
- **Uploaded Files**: Stored in PVC with RWX access
- **Backup**: Daily backups
- **RPO (Recovery Point Objective)**: 1 day
- **RTO (Recovery Time Objective)**: 1 week

### Monitoring and Logging
- Use stock InvenioRDM logging/monitoring tools
- Additional requirement: Ability to track and view largest files uploaded across communities

### Maintenance Requirements
- **Application Updates**: Monthly during early development
- **Base Images**: Minimal updates (staying on v.12)
- **Security Patches**: Apply expeditiously

### Development Workflow
- Local development continues with hybrid setup
- Build custom images with specific configurations, templates, and themes
- Push updated images to container registry
- Deploy new versions to Kubernetes

## Implementation Details

### Container Image Strategy
1. **Base Image**: Official InvenioRDM v.12 or Python base with InvenioRDM installed

2. **Customizations**: Add templates, themes, and configuration files

3. **Build Process**: Local build with push to container registry

4. **Registry**: Public registry with secrets protected



### Configuration Management

1. **Environment Variables**: For basic configuration

2. **ConfigMaps**: For more complex configuration files

3. **Secrets**: For sensitive information



### Data Migration Strategy

No significant data migration needed as current installation is in early development.



### Storage Configuration

- **Storage Class**: Default available in Proxmox Kubernetes

- **Access Mode**: ReadWriteMany (RWX) for shared volumes

- **Volume Size**: Start with estimates based on current usage, allow for expansion



### Backup Strategy

1. **Database Backup**: Daily PostgreSQL dumps

2. **File Storage Backup**: Daily snapshots

3. **OpenSearch Backup**: Daily index snapshots

4. **Backup Storage**: External to the Kubernetes cluster

5. **Backup Validation**: Monthly restore tests

6. **Retention**: 30 days of daily backups



### Network Isolation

1. **NetworkPolicies**: Limit pod-to-pod communication paths

2. **Ingress**: Only expose the web UI

3. **Services**: ClusterIP for internal services



### Security Implementation

Detailed security implementation for OpenSearch as per separate security plan document.



## Kubernetes Deployment Specification



### Namespace

```yaml

apiVersion: v1

kind: Namespace

metadata:

  name: invenio-rdm

```



### ConfigMaps

```yaml

apiVersion: v1

kind: ConfigMap

metadata:

  name: invenio-config

  namespace: invenio-rdm

data:

  INVENIO_INSTANCE_PATH: "/var/invenio/instance"

  INVENIO_SEARCH_HOSTS: '["https://search:9200"]'

  # Additional configuration parameters

```



### Secrets

```yaml

apiVersion: v1

kind: Secret

metadata:

  name: invenio-secrets

  namespace: invenio-rdm

type: Opaque

data:

  INVENIO_SECRET_KEY: <base64-encoded-secret>

  INVENIO_POSTGRESQL_PASSWORD: <base64-encoded-password>

  INVENIO_OPENSEARCH_PASSWORD: <base64-encoded-password>

  # Additional secrets

```



### Database StatefulSet

```yaml

apiVersion: apps/v1

kind: StatefulSet

metadata:

  name: postgresql

  namespace: invenio-rdm

spec:

  serviceName: "postgresql"

  replicas: 1

  selector:

    matchLabels:

      app: postgresql

  template:

    metadata:

      labels:

        app: postgresql

    spec:

      containers:

      - name: postgresql

        image: postgres:14.13

        env:

        - name: POSTGRES_USER

          value: "lbnl-data-repository"

        - name: POSTGRES_PASSWORD

          valueFrom:

            secretKeyRef:

              name: invenio-secrets

              key: INVENIO_POSTGRESQL_PASSWORD

        - name: POSTGRES_DB

          value: "lbnl-data-repository"

        ports:

        - containerPort: 5432

        volumeMounts:

        - name: postgresql-data

          mountPath: /var/lib/postgresql/data

  volumeClaimTemplates:

  - metadata:

      name: postgresql-data

    spec:

      accessModes: ["ReadWriteOnce"]

      storageClassName: "default"

      resources:

        requests:

          storage: 10Gi

```



### Similar StatefulSets for Redis, RabbitMQ, and OpenSearch



### InvenioRDM Deployment

```yaml

apiVersion: apps/v1

kind: Deployment

metadata:

  name: invenio-web

  namespace: invenio-rdm

spec:

  replicas: 2

  selector:

    matchLabels:

      app: invenio-web

  template:

    metadata:

      labels:

        app: invenio-web

    spec:

      containers:

      - name: invenio-web

        image: <your-registry>/invenio-rdm:v12

        env:

        - name: INVENIO_SECRET_KEY

          valueFrom:

            secretKeyRef:

              name: invenio-secrets

              key: INVENIO_SECRET_KEY

        # Additional environment variables from ConfigMap and Secrets

        ports:

        - containerPort: 5000

        volumeMounts:

        - name: invenio-data

          mountPath: /var/invenio/data

        - name: invenio-instance

          mountPath: /var/invenio/instance

      volumes:

      - name: invenio-data

        persistentVolumeClaim:

          claimName: invenio-data-pvc

      - name: invenio-instance

        persistentVolumeClaim:

          claimName: invenio-instance-pvc

```



### PersistentVolumeClaims

```yaml

apiVersion: v1

kind: PersistentVolumeClaim

metadata:

  name: invenio-data-pvc

  namespace: invenio-rdm

spec:

  accessModes:

    - ReadWriteMany

  storageClassName: "default"

  resources:

    requests:

      storage: 100Gi

```



### Services

```yaml

apiVersion: v1

kind: Service

metadata:

  name: invenio-web

  namespace: invenio-rdm

spec:

  selector:

    app: invenio-web

  ports:

  - port: 80

    targetPort: 5000

```



### Ingress

```yaml

apiVersion: networking.k8s.io/v1

kind: Ingress

metadata:

  name: invenio-ingress

  namespace: invenio-rdm

  annotations:

    kubernetes.io/ingress.class: "nginx"

    nginx.ingress.kubernetes.io/ssl-redirect: "true"

spec:

  tls:

  - hosts:

    - invenio.lbl.gov

    secretName: invenio-tls

  rules:

  - host: invenio.lbl.gov

    http:

      paths:

      - path: /

        pathType: Prefix

        backend:

          service:

            name: invenio-web

            port:

              number: 80

```



### NetworkPolicy

```yaml

apiVersion: networking.k8s.io/v1

kind: NetworkPolicy

metadata:

  name: invenio-network-policy

  namespace: invenio-rdm

spec:

  podSelector:

    matchLabels:

      app: invenio-web

  policyTypes:

  - Ingress

  - Egress

  ingress:

  - from:

    - namespaceSelector:

        matchLabels:

          name: kube-system

    ports:

    - protocol: TCP

      port: 5000

  egress:

  - to:

    - podSelector:

        matchLabels:

          app: postgresql

    ports:

    - protocol: TCP

      port: 5432

  # Additional egress rules for Redis, RabbitMQ, OpenSearch

```



## Development Workflow



### Local Development

1. Continue developing on local machine with hybrid setup

2. Make template, theme, and configuration changes



### Building and Deploying

1. **Build Image**: 

   ```bash

   docker build -t your-registry/invenio-rdm:v12-custom .

   ```



2. **Push Image**:

   ```bash

   docker push your-registry/invenio-rdm:v12-custom

   ```



3. **Update Kubernetes Deployment**:

   ```bash

   kubectl set image deployment/invenio-web invenio-web=your-registry/invenio-rdm:v12-custom -n invenio-rdm

   ```



### Testing Process

1. Local testing on hybrid environment

2. Deployment to test environment (subset of Kubernetes cluster)

3. Verification of functionality

4. Deployment to production



## Backup and Restore Procedures



### Database Backup

```bash

kubectl exec -n invenio-rdm postgresql-0 -- pg_dump -U lbnl-data-repository lbnl-data-repository > backup-$(date +%Y%m%d).sql

```



### Restore Procedure

```bash

cat backup-20250516.sql | kubectl exec -i -n invenio-rdm postgresql-0 -- psql -U lbnl-data-repository lbnl-data-repository

```



### File Storage Backup

Use appropriate volume snapshot or rsync-based approach for file storage backup.



## Error Handling Strategies



### Container Failures

- Implement readiness and liveness probes

- Configure appropriate restart policies

- Set resource limits to prevent resource starvation



### Database Failures

- Regular backups

- Consider implementing replication for higher availability in future



### Network Issues

- Implement appropriate timeouts

- Add retry logic where applicable

- Configure reasonable connection pools



### Application Errors

- Comprehensive logging

- Monitoring for error rates

- Alerting on critical errors



## Testing Plan



### Functional Testing

1. Verify all InvenioRDM features work as expected

2. Test SAML2 authentication with LBL SSO

3. Verify file uploads, especially large files



### Performance Testing

1. Test with expected initial load

2. Verify auto-scaling functionality



### Security Testing

1. Verify network policies restrict unauthorized access

2. Test that secrets are properly managed

3. Verify HTTPS is properly configured



### Backup/Restore Testing

1. Perform test restores monthly

2. Verify data integrity after restore



## Helm Chart Implementation



After evaluating the complexity of the deployment, a Helm chart approach is recommended for managing the InvenioRDM deployment on Kubernetes.



### Benefits of Helm for This Deployment

- Package all Kubernetes resources into a single deployable unit

- Provide consistent deployment across environments

- Enable simple version control and rollbacks

- Manage dependencies between components

- Simplify configuration through parameterized values



### Recommended Helm Chart Structure

```

invenio-rdm/

├── Chart.yaml             # Main chart metadata

├── values.yaml            # Default configuration values

├── values-prod.yaml       # Production-specific overrides

├── templates/

│   ├── _helpers.tpl       # Template helpers

│   ├── configmap.yaml     # ConfigMaps

│   ├── deployment.yaml    # InvenioRDM web application

│   ├── ingress.yaml       # Ingress configuration

│   ├── networkpolicy.yaml # Network policies

│   ├── secrets.yaml       # Secret definitions (templates only, not values)

│   ├── service.yaml       # Services

│   └── pvc.yaml           # Persistent volume claims

└── charts/                # Subcharts

    ├── postgresql/        # Database subchart

    ├── redis/             # Cache subchart

    ├── rabbitmq/          # Message queue subchart

    └── opensearch/        # Search subchart

```



### Implementation Approach

1. Leverage official Bitnami charts for PostgreSQL, Redis, and RabbitMQ

2. Create custom chart for OpenSearch with required security configurations

3. Parameterize all environment-specific configurations in values files

4. Implement proper secret handling through Kubernetes secrets



### Deployment Process with Helm

```bash

# Initial installation

helm install invenio-rdm ./invenio-rdm -f values-prod.yaml -n invenio-rdm



# Configuration updates

helm upgrade invenio-rdm ./invenio-rdm -f values-prod.yaml -n invenio-rdm



# Application updates (after building new container image)

helm upgrade invenio-rdm ./invenio-rdm --set image.tag=v12-custom-latest -n invenio-rdm

```



### Key Parameterized Values

- Application version/tag

- Environment type (dev/prod)

- Domain name

- Replica counts

- Resource allocations

- Storage class and size requirements

- Authentication configuration



## Conclusion

This specification provides a comprehensive plan for containerizing the InvenioRDM v.12 installation and deploying it to a self-hosted Kubernetes cluster. The approach prioritizes security, maintainability, and a smooth development workflow.

