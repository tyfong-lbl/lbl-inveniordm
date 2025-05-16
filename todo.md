# InvenioRDM Containerization and Deployment TODO List

## Executive Summary
- [ ] Review and finalize the executive summary section.

## Current Architecture
- [ ] Verify the current architecture details.
- [ ] Update any outdated information.

## Target Architecture
### Components to Containerize
- [ ] Finalize the list of components to containerize.
- [ ] Define resource allocation for the InvenioRDM application.
- [ ] Ensure all necessary services are included.
- [ ] Confirm persistent data storage requirements.
- [ ] Review security enhancements for OpenSearch and OpenSearch Dashboards.

### Kubernetes-Specific Resources
- [ ] Define namespaces for InvenioRDM.
- [ ] Create deployments for stateless components.
- [ ] Create stateful sets for stateful components.
- [ ] Define services for internal communication.
- [ ] Set up ingress for web UI with TLS termination.
- [ ] Configure persistent volume claims for data storage.
- [ ] Create config maps for non-sensitive configuration.
- [ ] Set up secrets for credentials and sensitive configuration.
- [ ] Implement network policies to restrict pod-to-pod communication.
- [ ] Define service accounts with minimal permissions.

## Detailed Requirements
### Performance Requirements
- [ ] Define hardware resource scaling.
- [ ] Estimate storage needs.
- [ ] Plan for user load.
- [ ] Implement auto-scaling based on load.
### Security Requirements
- [ ] Plan for authentication in development and production.
- [ ] Implement authorization using InvenioRDM's built-in role-based access controls.
- [ ] Integrate container image scanning in the build pipeline.
- [ ] Use non-root users in containers.
- [ ] Implement read-only file systems where possible.
- [ ] Drop unnecessary capabilities.
- [ ] Restrict external access to only the web UI.
- [ ] Enable OpenSearch security features.
- [ ] Use Kubernetes Secrets for all credentials.
- [ ] Implement proper secret rotation procedures.
- [ ] Ensure no hard-coded secrets in container images.
- [ ] Store strong passwords in Kubernetes Secrets.
- [ ] Limit database network access to application pods.
### Networking Requirements
- [ ] Ensure only the web UI is externally accessible.
- [ ] Set up domain for production.
- [ ] Configure TLS for all external access.
- [ ] Ensure internal services communicate via the Kubernetes network.
### Data Persistence Requirements
- [ ] Store database data in PVC with RWX access.
- [ ] Store OpenSearch indices in PVC.
- [ ] Store uploaded files in PVC with RWX access.
- [ ] Set up daily backups.
- [ ] Define RPO and RTO.
### Monitoring and Logging
- [ ] Use stock InvenioRDM logging/monitoring tools.
- [ ] Implement tracking and viewing of largest files uploaded across communities.
### Maintenance Requirements
- [ ] Schedule application updates monthly.
- [ ] Minimize base image updates.
- [ ] Apply security patches expeditiously.
### Development Workflow
- [ ] Continue local development with hybrid setup.
- [ ] Build custom images with specific configurations, templates, and themes.
- [ ] Push updated images to container registry.
- [ ] Deploy new versions to Kubernetes.

## Implementation Details
### Container Image Strategy
- [ ] Choose base image (official InvenioRDM v.12 or Python base with InvenioRDM installed).
- [ ] Add templates, themes, and configuration files.
- [ ] Define build process.
- [ ] Choose container registry.
### Configuration Management
- [ ] Use environment variables for basic configuration.
- [ ] Use config maps for complex configuration files.
- [ ] Use secrets for sensitive information.
### Data Migration Strategy
- [ ] Plan for data migration if necessary.
### Storage Configuration
- [ ] Choose storage class.
- [ ] Define access mode.
- [ ] Estimate volume size.
### Backup Strategy
- [ ] Set up daily database backups.
- [ ] Set up daily file storage backups.
- [ ] Set up daily OpenSearch backups.
- [ ] Choose backup storage location.
- [ ] Validate backups monthly.
- [ ] Define backup retention policy.
### Network Isolation
- [ ] Implement network policies.
- [ ] Expose only the web UI.
- [ ] Use ClusterIP for internal services.
### Security Implementation
- [ ] Follow detailed security implementation for OpenSearch.

## Kubernetes Deployment Specification
### Namespace
- [ ] Define namespace for InvenioRDM.
### ConfigMaps
- [ ] Create config maps for necessary configuration.
### Secrets
- [ ] Create secrets for sensitive information.
### Database StatefulSet
- [ ] Define StatefulSet for PostgreSQL.
- [ ] Define similar StatefulSets for Redis, RabbitMQ, and OpenSearch.
### InvenioRDM Deployment
- [ ] Define deployment for InvenioRDM web application.
### PersistentVolumeClaims
- [ ] Define persistent volume claims for data storage.
### Services
- [ ] Define services for internal communication.
### Ingress
- [ ] Define ingress for web UI with TLS termination.
### NetworkPolicy
- [ ] Define network policy for restricting pod-to-pod communication.

## Development Workflow
### Local Development
- [ ] Continue developing on local machine with hybrid setup.
- [ ] Make template, theme, and configuration changes.
### Building and Deploying
- [ ] Build image.
- [ ] Push image to container registry.
- [ ] Update Kubernetes deployment.
### Testing Process
- [ ] Perform local testing on hybrid environment.
- [ ] Deploy to test environment.
- [ ] Verify functionality.
- [ ] Deploy to production.

## Backup and Restore Procedures
### Database Backup
- [ ] Set up database backup procedure.
### Restore Procedure
- [ ] Set up database restore procedure.
### File Storage Backup
- [ ] Set up file storage backup procedure.

## Error Handling Strategies
### Container Failures
- [ ] Implement readiness and liveness probes.
- [ ] Configure appropriate restart policies.
- [ ] Set resource limits to prevent resource starvation.
### Database Failures
- [ ] Regularly back up databases.
- [ ] Consider implementing replication for higher availability.
### Network Issues
- [ ] Implement appropriate timeouts.
- [ ] Add retry logic where applicable.
- [ ] Configure reasonable connection pools.
### Application Errors
- [ ] Implement comprehensive logging.
- [ ] Monitor for error rates.
- [ ] Set up alerting for critical errors.

## Testing Plan
### Functional Testing
- [ ] Verify all InvenioRDM features.
- [ ] Test SAML2 authentication with LBL SSO.
- [ ] Verify file uploads, especially large files.
### Performance Testing
- [ ] Test with expected initial load.
- [ ] Verify auto-scaling functionality.
### Security Testing
- [ ] Verify network policies restrict unauthorized access.
- [ ] Test that secrets are properly managed.
- [ ] Verify HTTPS is properly configured.
### Backup/Restore Testing
- [ ] Perform test restores monthly.
- [ ] Verify data integrity after restore.

## Helm Chart Implementation
### Benefits of Helm for This Deployment
- [ ] Understand benefits of using Helm.
### Recommended Helm Chart Structure
- [ ] Define Helm chart structure.
### Implementation Approach
- [ ] Leverage official Bitnami charts for PostgreSQL, Redis, and RabbitMQ.
- [ ] Create custom chart for OpenSearch.
- [ ] Parameterize all environment-specific configurations.
- [ ] Implement proper secret handling.
### Deployment Process with Helm
- [ ] Set up initial installation.
- [ ] Configure updates.
- [ ] Set up application updates.
### Key Parameterized Values
- [ ] Define application version/tag.
- [ ] Define environment type.
- [ ] Define domain name.
- [ ] Define replica counts.
- [ ] Define resource allocations.
- [ ] Define storage class and size requirements.
- [ ] Define authentication configuration.

## Conclusion
- [ ] Review and finalize the entire plan.
- [ ] Ensure all tasks are completed.
- [ ] Document any additional findings or issues.

