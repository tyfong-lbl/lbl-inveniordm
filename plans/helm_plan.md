```markdown
# Helm Chart Implementation Plan for InvenioRDM

## Benefits of Using Helm for This Deployment

1. **Simplified Deployment and Updates**
   - Package all Kubernetes resources into a single deployable unit
   - Enable simple `helm install/upgrade` commands instead of managing multiple YAML files
   - Provide consistent deployment across environments (development, staging, production)

2. **Templating and Configuration Management**
   - Use Helm's templating system to parameterize configurations
   - Maintain environment-specific values files (`values-dev.yaml`, `values-prod.yaml`)
   - Reduce duplication across Kubernetes manifests

3. **Release Management**
   - Track revision history of deployments
   - Enable easy rollbacks to previous versions
   - Manage application lifecycle with Helm hooks

4. **Dependency Management**
   - Manage dependencies between components
   - Potentially leverage existing Helm charts for components like PostgreSQL, Redis, etc.
   - Composite chart structure with subcharts for each major component

## Helm Chart Structure Recommendation

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

## Implementation Approach

1. **Initial Development**
   - Either create a custom Helm chart from scratch based on our Kubernetes manifests
   - Or use `helm create` as a starting point and adapt to our needs

2. **Dependencies Management**
   - Evaluate using official Bitnami charts for PostgreSQL, Redis, and RabbitMQ
   - Create custom chart for OpenSearch with required security configurations
   - Define appropriate dependencies in Chart.yaml

3. **Configuration Strategy**
   - Move all environment-specific configs to values files
   - Use templates for generating consistent resources
   - Implement proper secret handling (potentially with external secret management)

4. **Deployment Process with Helm**
   ```bash
   # Initial installation
   helm install invenio-rdm ./invenio-rdm -f values-prod.yaml -n invenio-rdm --create-namespace

   # Configuration updates
   helm upgrade invenio-rdm ./invenio-rdm -f values-prod.yaml -n invenio-rdm

   # Application updates (after building new container image)
   helm upgrade invenio-rdm ./invenio-rdm --set image.tag=v12-custom-latest -n invenio-rdm
   ```

5. **CI/CD Integration**
   - Include Helm chart in version control
   - Automate chart linting and testing in CI pipeline
   - Consider automated deployments via GitOps approach (ArgoCD or Flux)

## Additional Considerations

1. **Secrets Management**
   - Avoid storing sensitive values in values.yaml
   - Consider external-secrets operator or sealed-secrets for secure secrets management
   - Document clear process for secrets rotation

2. **Pre/Post Deployment Actions**
   - Use Helm hooks for database migrations
   - Implement health checks before completing deployment
   - Configure proper initialization for stateful components

3. **Resource Management**
   - Allow resource allocation to be configured via values
   - Set reasonable defaults based on component requirements
   - Implement HorizontalPodAutoscaler templates

## Key Values to Parameterize

1. **Global Values**
   - Application version/tag
   - Environment type (dev/prod)
   - Domain name
   - Storage class name

2. **InvenioRDM Application Values**
   - Replica count
   - Resource requests/limits
   - Application-specific configuration parameters
   - Mount paths for persistent data

3. **Component-Specific Values**
   - Database configuration (size, version)
   - Redis configuration (memory, persistence)
   - OpenSearch configuration (JVM heap, plugins)
   - RabbitMQ configuration (resource allocation)

## Sample values.yaml Structure

```yaml
global:
  environment: development
  storageClass: default
  domain: invenio.lbl.gov

invenioApp:
  image:
    repository: your-registry/invenio-rdm
    tag: v12-custom
  replicas: 2
  resources:
    requests:
      memory: 2Gi
      cpu: 1
    limits:
      memory: 4Gi
      cpu: 2
  config:
    instancePath: /var/invenio/instance
    # Other app-specific configurations

postgresql:
  enabled: true
  auth:
    username: lbnl-data-repository
    database: lbnl-data-repository
  primary:
    persistence:
      size: 10Gi
  # Other PostgreSQL configurations

redis:
  enabled: true
  # Redis-specific configurations

rabbitmq:
  enabled: true
  # RabbitMQ-specific configurations

opensearch:
  enabled: true
  replicas: 1
  security:
    enabled: true
    # Security-specific configurations
  persistence:
    size: 20Gi
  # Other OpenSearch configurations

opensearchDashboards:
  enabled: true
  # Dashboard-specific configurations
```

## Timeline and Implementation Strategy

1. **Phase 1: Basic Chart Structure (Week 1)**
   - Set up basic chart structure
   - Define dependencies and relationships
   - Create templates for core components

2. **Phase 2: Configuration and Values (Week 2)**
   - Define comprehensive values structure
   - Implement templating for configuration
   - Set up environment-specific value files

3. **Phase 3: Security and Networking (Week 3)**
   - Implement network policies
   - Set up secure OpenSearch configuration
   - Configure ingress with TLS

4. **Phase 4: Testing and Validation (Week 4)**
   - Test deployments in non-production environment
   - Validate all functionality
   - Document deployment process

## Conclusion

Creating a Helm chart for the InvenioRDM deployment provides significant advantages for managing the application lifecycle. The structured approach outlined above will result in a maintainable, version-controlled deployment solution that accommodates the requirements for transitioning from development to production environments.

By parameterizing configuration values and leveraging existing charts where appropriate, we can create a robust deployment solution that simplifies ongoing maintenance while providing flexibility for future changes.
