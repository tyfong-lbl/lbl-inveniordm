# InvenioRDM Containerization Blueprint

This document provides a detailed, step-by-step plan for implementing the InvenioRDM containerization project using Helm charts. Each step is broken down into manageable chunks with corresponding prompts for code-generation LLMs to implement in a test-driven manner.

## Project Overview

We're transitioning from a hybrid InvenioRDM v.12 installation (where services are containerized but the application runs on bare metal) to a fully containerized solution deployed on Kubernetes using Helm charts. The implementation follows the specifications in `shift_plan.md`.

## Implementation Phases

### Phase 1: Foundation Setup

#### Step 1.1: Project Structure and Initial Helm Chart Setup

**Context:** Create the basic Helm chart structure following best practices.

**Prompt:**
```
I need to create a Helm chart for deploying InvenioRDM v.12 to Kubernetes. I'm transitioning from a hybrid setup where services (PostgreSQL, Redis, RabbitMQ, OpenSearch) are already containerized, but the InvenioRDM application itself runs on bare metal.

Please help me set up the initial Helm chart structure with:
1. The main chart directory structure with Chart.yaml and values.yaml
2. A proper .helmignore file
3. Basic template directory structure
4. Initial documentation in README.md

The chart should be named "invenio-rdm" and should follow Helm best practices. Don't include any actual templates yet - we'll add those step by step.
```

#### Step 1.2: Define Chart Dependencies

**Context:** Declare dependencies on existing Helm charts for backend services.

**Prompt:**
```
Building on our initial Helm chart structure for InvenioRDM, I now need to configure dependencies for the backend services:
1. PostgreSQL (using Bitnami's PostgreSQL chart)
2. Redis (using Bitnami's Redis chart)
3. RabbitMQ (using Bitnami's RabbitMQ chart)
4. OpenSearch (we'll create a custom chart for this)

Please update the Chart.yaml to include these dependencies with appropriate version constraints. Also, update the values.yaml file to include relevant configuration sections for each dependency.

For the OpenSearch dependency, let's create a placeholder since we'll implement a custom chart for it later.

Please include comments explaining key configuration options and how they map to our InvenioRDM requirements.
```

#### Step 1.3: Configure Values and Defaults

**Context:** Set up the values.yaml file with appropriate defaults and structure.

**Prompt:**
```
Let's enhance our InvenioRDM Helm chart by properly setting up the values.yaml file. I need to define sensible defaults and structure for:

1. Global values that affect multiple components (like domain, storage class, environment)
2. InvenioRDM application-specific values (image settings, replicas, resources)
3. Service-specific configurations for all backend services
4. Networking and security settings

Please organize the values.yaml file with clear sections and helpful comments. Make sure to include:
- Configuration for RWX persistent volumes
- Resource allocation defaults (reflecting resource requirements in shift_plan.md)
- Security-related configuration options
- Environment-specific toggles

Don't include actual secrets in the values.yaml, but provide placeholders and comments explaining how secrets should be managed.
```

#### Step 1.4: Helper Templates

**Context:** Create helper templates for common functions.

**Prompt:**
```
Let's create helper templates for our InvenioRDM Helm chart. I need a comprehensive _helpers.tpl file that provides:

1. Name templates for consistent resource naming (fullname, chart name, etc.)
2. Label helpers for generating consistent Kubernetes labels and selectors
3. Service account name helper
4. Helpers for constructing domain names and URLs
5. Functions to determine if certain features are enabled/disabled
6. Any other useful helper functions for our templates

These helpers should follow Helm best practices and be well-documented with comments explaining their purpose and usage.
```

### Phase 2: Core Application Templates

#### Step 2.1: Create ConfigMap Templates

**Context:** Create templates for ConfigMaps to store configuration.

**Prompt:**
```
Now, let's implement the ConfigMap templates for our InvenioRDM Helm chart. I need templates that:

1. Create a main application ConfigMap containing environment variables and basic configuration
2. Handle optional feature-specific ConfigMaps (based on enabled features in values.yaml)
3. Include proper templating to pull values from our values.yaml file
4. Follow best practices for naming and labeling

The main configuration should include settings for connecting to PostgreSQL, Redis, RabbitMQ, and OpenSearch services. Don't include any sensitive information in these ConfigMaps as they'll be handled by Secrets later.

The templates should use the helper functions we defined previously for naming and labels.
```

#### Step 2.2: Create Secret Templates

**Context:** Create templates for Kubernetes Secrets to store sensitive information.

**Prompt:**
```
Let's implement the Secret templates for our InvenioRDM Helm chart. I need templates that:

1. Create a main secret for the InvenioRDM application containing sensitive configuration
2. Generate random secrets for first-time deployments (like INVENIO_SECRET_KEY) when not provided
3. Reference external secrets where appropriate
4. Handle TLS secrets for secure communication
5. Follow best practices for secure handling of sensitive data in Helm charts

The secrets should include settings like database passwords, API keys, and encryption keys. Don't hard-code any actual secret values in the templates.

The templates should use our helper functions for naming and labels, and should properly extract values from our values.yaml file.
```

#### Step 2.3: Create Deployment Template

**Context:** Create the main deployment template for InvenioRDM application.

**Prompt:**
```
Let's create the Deployment template for our InvenioRDM application in the Helm chart. I need a template that:

1. Creates a proper Kubernetes Deployment for the InvenioRDM web application
2. Configures the correct container image, pulled from values
3. Sets up environment variables from ConfigMaps and Secrets
4. Configures resource requests and limits
5. Sets up proper volume mounts for persistent data
6. Implements readiness and liveness probes
7. Configures security context for the containers
8. Adds appropriate annotations and labels

Make sure to use the helper templates we've created for naming and labeling. The deployment should be configurable through values.yaml, including the ability to set replicas, image details, and resource allocations.
```

#### Step 2.4: Create Service Template

**Context:** Create service template for exposing the InvenioRDM application.

**Prompt:**
```
Now, let's create the Service template for our InvenioRDM application. I need a template that:

1. Creates a Kubernetes Service to expose the InvenioRDM application internally
2. Configures the correct port mappings (the app listens on port 5000)
3. Sets up appropriate selectors to target the application pods
4. Includes configurable service type (ClusterIP by default)
5. Adds appropriate annotations and labels
6. Configures any service-specific options needed

Make sure to use the helper templates for naming and labeling. The service should be configurable through values.yaml, especially regarding service type and annotations.
```

#### Step 2.5: Create Ingress Template

**Context:** Create ingress template for external access to InvenioRDM.

**Prompt:**
```
Let's create the Ingress template for exposing our InvenioRDM application externally. I need a template that:

1. Creates a Kubernetes Ingress resource with proper configuration for external access
2. Sets up TLS configuration for HTTPS
3. Configures the correct host name (invenio.lbl.gov for production)
4. Adds appropriate annotations for the ingress controller (nginx)
5. Includes path configurations to route traffic to the application service
6. Handles different ingress configurations based on environment

Make sure to use the helper templates for naming and labeling. The ingress should be highly configurable through values.yaml, including the ability to enable/disable TLS, set the hostname, and configure annotations.
```

#### Step 2.6: Create PVC Templates

**Context:** Create PVC templates for persistent storage.

**Prompt:**
```
Let's create the PersistentVolumeClaim templates for our InvenioRDM application. I need templates that:

1. Create PVCs for all required persistent storage:
   - Data storage for uploaded files (RWX access required)
   - Instance directory for application instance data
2. Configure appropriate storage class, access modes, and sizes
3. Add labels and annotations as needed
4. Make storage configurations customizable through values.yaml

The templates should use our helper functions for naming and labels. The PVCs should be configurable through values.yaml, including storage class, size, and access modes.

Note that we don't need to create PVCs for the database, Redis, RabbitMQ, or OpenSearch as those are handled by their respective charts.
```

#### Step 2.7: Create NetworkPolicy Template

**Context:** Create NetworkPolicy templates for enhancing security.

**Prompt:**
```
Let's create NetworkPolicy templates for our InvenioRDM deployment. I need templates that:

1. Create a NetworkPolicy for the InvenioRDM application pods that:
   - Restricts incoming traffic to only necessary sources
   - Limits outgoing traffic to only required destinations (database, Redis, RabbitMQ, OpenSearch)
   - Allows necessary communication with the Kubernetes API
2. Make the policies configurable through values.yaml
3. Include conditional creation based on whether network policies are enabled
4. Add appropriate labels and annotations

The templates should use our helper functions for naming and labels. Make sure to follow best practices for Kubernetes network security.
```

### Phase 3: Custom OpenSearch Chart

#### Step 3.1: OpenSearch Chart Structure

**Context:** Create the base structure for a custom OpenSearch chart.

**Prompt:**
```
Let's create a custom Helm chart for OpenSearch as a subchart of our InvenioRDM chart. This custom chart needs to implement the security requirements specified in our plan.

Please help me set up:
1. The basic chart structure in the "charts/opensearch" directory
2. Chart.yaml with appropriate metadata
3. Initial values.yaml with OpenSearch configuration options, including security settings
4. README.md documenting the chart

The OpenSearch version should be 2.17.1 to match our current deployment. The chart should support configuring:
- Cluster configuration (single-node for development)
- Resource allocation
- Persistence configuration
- Security features (SSL/TLS, authentication)
- JVM settings

Include the security configuration we discussed in our plan (SSL certificates, authentication, etc.).
```

#### Step 3.2: OpenSearch Templates

**Context:** Create templates for the OpenSearch deployment.

**Prompt:**
```
Let's implement the core templates for our custom OpenSearch chart. I need templates for:

1. StatefulSet for deploying OpenSearch with proper configuration
2. ConfigMap for OpenSearch configuration
3. Secret for storing certificates and credentials
4. Service for internal access to OpenSearch
5. ServiceAccount for OpenSearch pods

The templates should implement the security features we discussed:
- SSL/TLS for HTTP and transport
- Basic authentication
- Proper permissions and security contexts

Make sure the StatefulSet includes:
- Proper volume mounts for data and certificates
- Resource limits and requests
- Appropriate init containers for setup tasks
- Readiness and liveness probes
- Security context configuration

These templates should use helper functions (which you can create in a _helpers.tpl file) and should be configurable through values.yaml.
```

#### Step 3.3: OpenSearch Dashboards Integration

**Context:** Integrate OpenSearch Dashboards into the custom chart.

**Prompt:**
```
Let's extend our custom OpenSearch chart to include OpenSearch Dashboards. I need templates for:

1. Deployment for OpenSearch Dashboards
2. ConfigMap for Dashboards configuration
3. Secret for storing Dashboards credentials
4. Service for accessing Dashboards
5. Ingress for external access to Dashboards (optional, based on configuration)

The Dashboards deployment should:
- Connect securely to OpenSearch
- Use proper authentication
- Be configurable through values.yaml
- Have appropriate resource limits and requests

The integration should ensure that Dashboards can securely connect to OpenSearch using the security features we've implemented. Make sure to handle certificates and credentials properly.
```

#### Step 3.4: OpenSearch Security Configuration

**Context:** Finalize security configurations for OpenSearch.

**Prompt:**
```
Let's complete the security configuration for our OpenSearch chart. I need templates and configurations for:

1. Certificate generation or mounting for SSL/TLS
2. Authentication and authorization setup
3. Network security settings
4. Proper secret management for credentials

Specifically, I need:
- A template or initialization script to handle certificate generation if not provided
- Configuration for internal users and roles
- Network security settings to restrict access
- Integration with Kubernetes secrets for credential management

The security configuration should be flexible enough to work in both development and production environments, with appropriate defaults for each.
```

### Phase 4: Integration and Testing

#### Step 4.1: Create Test Values Files

**Context:** Create environment-specific values files for testing.

**Prompt:**
```
Let's create environment-specific values files for testing our InvenioRDM Helm chart. I need:

1. A values-dev.yaml file for development environment with:
   - Minimal resource requests
   - Single replicas
   - Development-appropriate security settings
   - Local domain configuration

2. A values-test.yaml file for testing environment with:
   - Moderate resources
   - Multiple replicas where appropriate
   - Test security configuration
   - Test domain settings

3. A values-prod.yaml file for production with:
   - Production-grade resource allocation
   - Appropriate replica counts
   - Strict security settings
   - Production domain (invenio.lbl.gov)

Each file should include appropriate comments explaining the settings and any environment-specific considerations. Don't include actual secrets in these files, but provide clear placeholders.
```

#### Step 4.2: Create Helper Scripts

**Context:** Create helper scripts for common deployment tasks.

**Prompt:**
```
Let's create helper scripts to simplify working with our InvenioRDM Helm chart. I need bash scripts for:

1. install.sh - Installing the chart with appropriate values based on environment
2. upgrade.sh - Upgrading an existing installation
3. rollback.sh - Rolling back to a previous release
4. test-chart.sh - Running helm lint and template testing
5. secrets-setup.sh - A helper script for generating and managing required secrets

Each script should:
- Accept command-line arguments for customization
- Include clear documentation and usage instructions
- Implement error handling and validation
- Include helpful log messages

Make these scripts robust and user-friendly, as they'll be used by the operations team for managing deployments.
```

#### Step 4.3: Create Chart Tests

**Context:** Create Helm tests to validate the deployment.

**Prompt:**
```
Let's create Helm tests for our InvenioRDM chart to validate deployments. I need test templates in the tests/ directory that:

1. Test the InvenioRDM web application is responding correctly
2. Test database connectivity
3. Test Redis connectivity
4. Test RabbitMQ connectivity
5. Test OpenSearch connectivity
6. Test basic application functionality

Each test should:
- Create a pod that runs appropriate test commands
- Use minimal resources
- Provide clear pass/fail results
- Clean up after itself
- Include appropriate annotations for Helm test

These tests will be run using `helm test` after deployment to validate that everything is working correctly.
```

#### Step 4.4: Documentation Finalization

**Context:** Finalize documentation for the Helm chart.

**Prompt:**
```
Let's finalize the documentation for our InvenioRDM Helm chart. I need:

1. A comprehensive README.md with:
   - Overview and purpose
   - Prerequisites
   - Installation instructions
   - Configuration guide
   - Upgrading instructions
   - Troubleshooting tips
   - Architecture diagram(s)

2. A NOTES.txt template that provides:
   - Post-installation instructions
   - URLs to access the application
   - Next steps for configuration
   - Common commands for interacting with the deployment

3. A values-schema.json file that documents:
   - All available configuration options
   - Data types and constraints
   - Default values
   - Descriptions for each value

The documentation should be clear, comprehensive, and follow best practices for Helm chart documentation.
```

### Phase 5: CI/CD Integration 

#### Step 5.1: CI Pipeline Setup

**Context:** Create CI pipeline configuration for chart validation and testing.

**Prompt:**
```
Let's create a CI pipeline configuration for our InvenioRDM Helm chart. I need configuration files for a CI system (like GitHub Actions or GitLab CI) that:

1. Lint the Helm chart for syntax and best practices
2. Validate the chart against the Helm schema
3. Run