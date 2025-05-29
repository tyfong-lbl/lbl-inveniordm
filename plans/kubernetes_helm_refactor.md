# Kubernetes Production Deployment Plan - LBNL Data Repository

## Overview

This document outlines the transition from localhost-only development to a production Kubernetes deployment where external users can access the LBNL Data Repository web service. This involves significant architectural and security changes from the current Docker Compose setup.

## Key Architectural Shifts

### 1. Network Security Model

**Current Development Setup:**
- All services bound to 127.0.0.1 only
- No external network access
- Single-host Docker networking

**Production Kubernetes Requirements:**
- Ingress controllers for external access
- Load balancers for high availability
- Network policies for micro-segmentation
- Service mesh for advanced traffic management

**Example Network Policy:**
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: invenio-network-policy
  namespace: lbnl-data-repository
spec:
  podSelector:
    matchLabels:
      app: invenio-web
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: nginx-ingress
    ports:
    - protocol: TCP
      port: 5000
  egress:
  - to:
    - podSelector:
        matchLabels:
          app: opensearch
    ports:
    - protocol: TCP
      port: 9200
```

### 2. Certificate Management

**Current Development Setup:**
- Self-signed certificates in `~/.config/lbnl-data-repository/ssl/`
- Manual certificate generation script
- Browser trust configuration required

**Production Kubernetes Requirements:**
- CA-signed certificates from trusted authority
- Automated certificate management with cert-manager
- Certificate rotation and renewal
- Multiple certificate types (ingress, inter-service, client)

**Example cert-manager Configuration:**
```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: lbnl-data-repository-tls
  namespace: lbnl-data-repository
spec:
  secretName: lbnl-tls-secret
  issuerRef:
    name: letsencrypt-prod
    kind: ClusterIssuer
  dnsNames:
  - data.lbl.gov
  - api.data.lbl.gov
```

### 3. Secret Management

**Current Development Setup:**
- Environment variables in shell scripts
- Credentials stored in user home directory
- No centralized secret management

**Production Kubernetes Requirements:**
- Kubernetes Secrets with encryption at rest
- External secret management system integration
- Secret rotation capabilities
- Least privilege access to secrets

**Example Secret Configuration:**
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: opensearch-credentials
  namespace: lbnl-data-repository
type: Opaque
data:
  username: YWRtaW4=  # base64 encoded 'admin'
  password: <base64-encoded-secure-password>
---
apiVersion: v1
kind: Secret
metadata:
  name: database-credentials
  namespace: lbnl-data-repository
type: Opaque
data:
  postgres-user: <base64-encoded>
  postgres-password: <base64-encoded>
  postgres-database: <base64-encoded>
```

## Critical Production Requirements

### Authentication & Authorization

**Key Questions:**
- How will users authenticate? (LDAP, OIDC, SAML, OAuth2?)
- Integration with existing LBNL identity systems?
- Multi-factor authentication requirements?
- Role-based access control (RBAC) model?
- Guest access vs. authenticated user permissions?

**Recommended Approach:**
```yaml
# OIDC Integration Example
apiVersion: v1
kind: ConfigMap
metadata:
  name: invenio-auth-config
data:
  auth.py: |
    OAUTHCLIENT_REMOTE_APPS = {
        'lbnl_oidc': {
            'title': 'LBNL SSO',
            'description': 'LBNL Single Sign-On',
            'icon': '',
            'params': {
                'request_token_params': {'scope': 'openid email profile'},
                'base_url': 'https://sso.lbl.gov/',
                'request_token_url': None,
                'access_token_url': 'https://sso.lbl.gov/oauth/token',
                'authorize_url': 'https://sso.lbl.gov/oauth/authorize',
            }
        }
    }
```

### Data Persistence & Backup

**Critical Considerations:**
- **PostgreSQL Storage**: PersistentVolumeClaims vs. managed cloud database
- **OpenSearch Indices**: Snapshot and restore strategy
- **File Storage**: Research data uploads, potentially TB+ scale
- **Backup Frequency**: RTO/RPO requirements
- **Cross-region Replication**: Disaster recovery

**Storage Architecture Options:**
```yaml
# Option 1: Self-managed with PVCs
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: postgres-storage
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 100Gi
  storageClassName: fast-ssd
---
# Option 2: Managed Database Reference
apiVersion: v1
kind: Secret
metadata:
  name: managed-db-connection
data:
  connection-string: <base64-encoded-cloud-db-url>
```

### Scalability & Performance

**Capacity Planning Questions:**
- Expected concurrent users? (10s, 100s, or 1000s?)
- Data volume growth projections?
- Peak upload/download patterns?
- Geographic distribution of users?

**Scaling Strategy:**
```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: invenio-web-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: invenio-web
  minReplicas: 2
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: 80
```

### Compliance & Security

**Security Requirements:**
- Data classification and handling requirements
- Audit logging for compliance (SOX, HIPAA, etc.)
- Network segmentation and zero-trust principles
- Vulnerability scanning and patch management
- Container image security and signing

**Pod Security Standards:**
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: invenio-web
  labels:
    pod-security.kubernetes.io/enforce: restricted
spec:
  securityContext:
    runAsNonRoot: true
    runAsUser: 1000
    fsGroup: 2000
    seccompProfile:
      type: RuntimeDefault
  containers:
  - name: invenio
    image: lbnl-data-repository:latest
    securityContext:
      allowPrivilegeEscalation: false
      readOnlyRootFilesystem: true
      capabilities:
        drop:
        - ALL
```

### Operations & Monitoring

**Observability Stack Requirements:**
- **Logging**: Centralized log aggregation (ELK, Loki, or cloud logging)
- **Metrics**: Prometheus/Grafana or cloud monitoring
- **Tracing**: Distributed tracing for complex request flows
- **Alerting**: PagerDuty, Slack, or email notifications
- **Dashboards**: Application and infrastructure monitoring

**Example Monitoring Configuration:**
```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: invenio-metrics
spec:
  selector:
    matchLabels:
      app: invenio-web
  endpoints:
  - port: metrics
    interval: 30s
    path: /metrics
```

## Migration Strategy

### Phase 1: Containerization & Helm Charts

**Objectives:**
- Convert Docker Compose to Kubernetes manifests
- Create Helm charts for templating and configuration management
- Establish CI/CD pipeline for image building

**Deliverables:**
- `helm/lbnl-data-repository/` chart structure
- Kubernetes Deployments for all services
- ConfigMaps for externalized configuration
- Initial PersistentVolumeClaims for data storage

**Timeline:** 2-3 weeks

### Phase 2: Security Hardening

**Objectives:**
- Implement Pod Security Standards
- Create service accounts with minimal RBAC permissions
- Deploy network policies for micro-segmentation
- Implement image vulnerability scanning

**Deliverables:**
- Security contexts for all pods
- RBAC policies and service accounts
- Network policies limiting inter-service communication
- Container image signing and verification

**Timeline:** 2-3 weeks

### Phase 3: Production Services

**Objectives:**
- Deploy ingress controllers with proper SSL termination
- Implement certificate management with cert-manager
- Set up managed databases or highly available self-hosted databases
- Configure load balancing and auto-scaling

**Deliverables:**
- NGINX Ingress Controller or cloud load balancer configuration
- cert-manager with Let's Encrypt or enterprise CA integration
- Database high availability setup
- HorizontalPodAutoscaler configurations

**Timeline:** 3-4 weeks

### Phase 4: Operations & Monitoring

**Objectives:**
- Implement comprehensive monitoring and alerting
- Set up log aggregation and analysis
- Deploy GitOps workflow for automated deployments
- Establish backup and disaster recovery procedures

**Deliverables:**
- Prometheus/Grafana monitoring stack
- ELK or Loki logging infrastructure
- ArgoCD or Flux GitOps setup
- Velero backup system or equivalent

**Timeline:** 2-3 weeks

## Technology Stack Decisions

### Container Orchestration

- **Kubernetes**: Industry standard, extensive ecosystem
- **Helm**: Package management and templating
- **Version**: Kubernetes 1.28+ for latest security features

### Ingress & Load Balancing

**Options:**
- **NGINX Ingress Controller**: Most common, well-tested
- **Traefik**: Modern, automatic service discovery
- **Cloud Load Balancers**: AWS ALB, GCP GLB, Azure AppGW

### Certificate Management

- **cert-manager**: Automated certificate lifecycle
- **Let's Encrypt**: Free certificates for public domains
- **Enterprise CA**: Integration with LBNL certificate authority

### Database Strategy

**PostgreSQL Options:**
- **Self-managed**: PostgreSQL Operator (Zalando, Crunchy Data)
- **Cloud Managed**: AWS RDS, GCP Cloud SQL, Azure Database
- **Hybrid**: Primary in cloud, read replicas in cluster

**OpenSearch Options:**
- **Self-managed**: OpenSearch Operator
- **Cloud Managed**: AWS OpenSearch Service, Elastic Cloud
- **Considerations**: Data locality, compliance requirements

### Monitoring & Observability

- **Metrics**: Prometheus + Grafana
- **Logging**: ELK Stack or Grafana Loki
- **Tracing**: Jaeger or Zipkin
- **APM**: Application Performance Monitoring integration

## Deployment Environment Options

### Option 1: LBNL Internal Kubernetes

**Pros:**
- Data remains within LBNL infrastructure
- Direct integration with LBNL identity systems
- Lower data transfer costs
- Compliance with internal policies

**Cons:**
- Limited scalability compared to cloud
- Self-managed infrastructure overhead
- Potential availability limitations

### Option 2: Public Cloud (AWS/GCP/Azure)

**Pros:**
- Unlimited scalability
- Managed services reduce operational overhead
- Global CDN and edge locations
- Advanced security and compliance certifications

**Cons:**
- Data egress costs
- Potential compliance complexities
- Vendor lock-in considerations

### Option 3: Hybrid Architecture

**Approach:**
- Core services in LBNL infrastructure
- CDN and edge caching in public cloud
- Disaster recovery in cloud
- Burst scaling to cloud during peak loads

## Next Steps & Decision Points

### Immediate Questions to Resolve

1. **Target Environment**: LBNL internal Kubernetes vs. public cloud?
2. **Authentication Method**: Integration with existing LBNL SSO systems?
3. **Expected Scale**: Concurrent users, data volume, geographic distribution?
4. **Compliance Requirements**: Data classification, audit logging needs?
5. **Budget Constraints**: Infrastructure costs, managed services budget?

### Recommended First Phase

**Start with Helm Chart Creation:**
1. Convert existing `docker-compose.yml` to Kubernetes manifests
2. Create Helm chart with configurable values
3. Test deployment in development Kubernetes cluster
4. Establish CI/CD pipeline for automated testing

**Deliverables for Review:**
- Initial Helm chart structure
- Kubernetes manifests for all services
- Documentation for local development setup
- Migration timeline and resource requirements

## Risk Assessment

### High Risk Items

- **Data Migration**: PostgreSQL and OpenSearch data transfer
- **Authentication Integration**: SSO system compatibility
- **Performance**: Application behavior under load
- **Security**: Network policies and access controls

### Mitigation Strategies

- **Parallel Environment**: Run both systems during transition
- **Load Testing**: Comprehensive performance validation
- **Security Audits**: Third-party security assessment
- **Rollback Plan**: Quick reversion to current system

### Success Metrics

- **Availability**: 99.9% uptime SLA
- **Performance**: <2s page load times
- **Security**: Zero security incidents in first 6 months
- **User Experience**: Positive feedback from research community

