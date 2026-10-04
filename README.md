# Enterprise Azure Cloud Security Labs

An end-to-end cloud security architecture built entirely using **Azure Bicep (Infrastructure as Code)**. This repository demonstrates modern cloud engineering principles, zero-trust network segmentation, identity governance, and automated vulnerability tracking.

##   Architecture and Blueprint
This project simulates a secure hybrid enterprise environment.

```mermaid
graph TD
    %% Subscription Level
    subgraph Subscription ["Azure Subscription Scope"]
        RG["Resource Group: rg-security-lab-prod"]
        
        %% Resource Group Level
        subgraph RG ["Resource Group: rg-security-lab-prod"]
            
            %% Network Security Group
            NSG["NSG: nsg-core-prod"]
            Rule1["Rule: Deny-All-Inbound <br> (Priority 4000, * to *)"]
            NSG --> Rule1
            
            %% Virtual Network
            subgraph VNet ["VNet: vnet-secure-prod (10.0.0.0/16)"]
                Subnet["Subnet: snet-secure-prod (10.0.0.0/24)"]
            end
            
            %% Association Link
            Subnet -.->|Protected By| NSG
        end
    end

    %% Traffic Flow Visual
    Internet((Internet Traffic))
    Internet -->|X Blocked X| Rule1
    
    %% Styling
    style Subscription fill:#f5f5f5,stroke:#333,stroke-width:2px;
    style RG fill:#e1f5fe,stroke:#0288d1,stroke-width:2px;
    style VNet fill:#e8f5e9,stroke:#388e3c,stroke-width:2px;
    style Subnet fill:#c8e6c9,stroke:#4caf50,stroke-width:1px;
    style NSG fill:#ffe0b2,stroke:#f57c00,stroke-width:2px;
    style Rule1 fill:#ffcdd2,stroke:#d32f2f,stroke-width:1px;
```

* **Hub-and-Spoke Network Topology:** Completely isolates backend compute resources from the public internet.
* **Default-Deny Perimeter Security:** Network Security Groups (NSGs) explicitly drop all unauthenicated inbound traffic.
* **Hybrid Identity Lifecycle:** Outlines the core framework for secure Active Directory to Microsoft Entra ID integration.

### Infrastructure Components
* **Resource Group:** `rg-security-lab-prod`
* **Virtual Network:** `vnet-secure-prod` (Address Space: `10.0.0.0/16`)
* **Core Subnet:** `snet-secure-prod` (`10.0.1.0/24`) bound to a zero-trust NSG.