# Salesforce Repository

## Branches

* master                    - Production
* develop                   - Next project release
* feature/ABC-123-keywords  - User story and bug fix branches
* release/n.n.n             - Semversion release branches
* deploy/environmentName    - Branches to trigger deployments to environments
* build/keywords            - Build maintenance branches

## Build

* Checkout repository
* ant setup     - Connect to Salesforce
* ant retrieve  - Retrieve metadata from Salesforce
* ant test      - Validate metadata against Salesforce
* ant deploy    - Deploy metadata to Salesforce