# Azure Cloud Security Labs

Hands-on cloud security labs built with **Azure Bicep (Infrastructure as Code)**. The repository focuses on repeatable, parameter-driven deployments and a zero-trust approach to network segmentation.

> **Status:** active lab. Sections marked *Planned* are on the roadmap and not yet implemented.

## Architecture

Current deployed state: a single VNet with one subnet bound to a deny-by-default NSG.

```mermaid
flowchart TD
    Internet(("Internet"))

    subgraph SUB["Azure Subscription"]
        subgraph RG["Resource Group: rg-security-lab-prod"]
            subgraph VNET["VNet: vnet-seclab-prod (10.0.0.0/16)"]
                SNET["Subnet: snet-secure-prod<br/>10.0.0.0/24"]
            end
            NSG["NSG: nsg-seclab-prod"]
            INB["Inbound: Deny-All-Inbound<br/>priority 4096"]
            OUTB["Outbound: allow Azure DNS, Entra ID,<br/>Azure Monitor, then Deny-All-Outbound<br/>priority 4096"]
        end
    end

    Internet -->|Blocked| INB
    NSG --- INB
    NSG --- OUTB
    SNET -.->|Protected by| NSG

    style SUB fill:#f5f5f5,stroke:#333,stroke-width:2px
    style RG fill:#e1f5fe,stroke:#0288d1,stroke-width:2px
    style VNET fill:#e8f5e9,stroke:#388e3c,stroke-width:2px
    style SNET fill:#c8e6c9,stroke:#4caf50,stroke-width:1px
    style NSG fill:#ffe0b2,stroke:#f57c00,stroke-width:2px
    style INB fill:#ffcdd2,stroke:#d32f2f,stroke-width:1px
    style OUTB fill:#ffcdd2,stroke:#d32f2f,stroke-width:1px
```

## What's implemented

### Network baseline (`main.bicep` + `network.bicep`)

`main.bicep` is a thin, resource-group-scope entry point that owns naming, tags and parameters, and calls a reusable `network.bicep` module built on [Azure Verified Modules](https://aka.ms/avm). Together they deploy:

| Component | Name | Notes |
|---|---|---|
| Resource group | `rg-security-lab-prod` | Created once outside the pipeline; the template deploys into it |
| Network security group | `nsg-seclab-prod` | Zero-trust rule baseline, attached to every subnet |
| Virtual network | `vnet-seclab-prod` | Address space `10.0.0.0/16` |
| Subnet | `snet-secure-prod` | `10.0.0.0/24`, bound to the NSG |

Names, address prefixes, subnets and rules are all parameters, so the same template scales to more subnets or environments without code changes.

### Zero-trust NSG design

Traffic is denied by default in **both directions**, and only explicitly defined flows are allowed.

| Priority band | Purpose |
|---|---|
| 100-499 | Platform and baseline allows (e.g. Azure DNS / VM agent) |
| 500-999 | Shared services (Microsoft Entra ID, Azure Monitor) using service tags |
| 1000-3999 | Workload-specific rules supplied through the `customRules` parameter |
| 4096 | Explicit `Deny-All-Inbound` and `Deny-All-Outbound` |

Design choices:

- Rules use arrays for address prefixes and port ranges, so a single rule can cover multiple ranges.
- Service tags are preferred over hard-coded IPs where possible.
- A `CanNotDelete` lock is applied to the NSG and VNet by default.

> **Scope note:** NSGs filter at layers 3 and 4. They do not evaluate identity or authentication, so they are one layer of a defense-in-depth design, not a complete zero-trust solution.

## Deployment

Prerequisites: Azure CLI with Bicep, and Contributor (or higher) on the target resource group.

```bash
# Preview changes
az deployment group what-if \
  --resource-group rg-security-lab-prod \
  --template-file main.bicep

# Deploy
az deployment group create \
  --resource-group rg-security-lab-prod \
  --template-file main.bicep
```

> Denying all outbound traffic will block anything not explicitly allowed (package repositories, extensions, updates). Validate with `what-if` and test on a non-production subnet first.

## Roadmap (Planned)

### Planned topology: hub-and-spoke

```mermaid
flowchart LR
    subgraph HUB["Hub VNet (planned)"]
        SHARED["Shared services subnet"]
    end
    subgraph SP1["Spoke 1: workloads (planned)"]
        WL["Workload subnet + NSG"]
    end
    subgraph SP2["Spoke 2: management (planned)"]
        MG["Management subnet + NSG"]
    end

    HUB <-->|VNet peering| SP1
    HUB <-->|VNet peering| SP2

    style HUB fill:#e1f5fe,stroke:#0288d1,stroke-dasharray: 5 5
    style SP1 fill:#e8f5e9,stroke:#388e3c,stroke-dasharray: 5 5
    style SP2 fill:#e8f5e9,stroke:#388e3c,stroke-dasharray: 5 5
```

Peering and NSGs add little to no cost. Hourly-billed services such as Azure Firewall and Bastion are intentionally left out and can be added for short, time-boxed demos.


- [ ] Hub-and-spoke topology with VNet peering
- [ ] Azure Firewall or NVA for centralized egress control
- [ ] Application security groups for role-based micro-segmentation
- [ ] VNet flow logs and diagnostic settings into Log Analytics
- [ ] Microsoft Sentinel integration (see the honeypot lab)
- [ ] Private endpoints for PaaS services
- [ ] Hybrid identity: Active Directory to Microsoft Entra ID integration walkthrough
- [ ] Automated vulnerability tracking with Defender for Cloud

## Repository notes

- Don't commit secrets, subscription or tenant IDs, or real corporate IP ranges. Use documentation ranges such as `203.0.113.0/24` in examples, and pass sensitive values as `@secure()` parameters sourced from Key Vault.
