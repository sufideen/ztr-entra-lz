# GDPR alignment

This page maps the controls in this repository to the UK GDPR / GDPR articles they
support. It describes design intent for a proof of concept. It is **not** a
compliance certification, and controls marked *to confirm* depend on how the
platform is configured in a real tenant.

| GDPR requirement | What this repo provides | Where |
|---|---|---|
| Art. 5(1)(f) integrity and confidentiality | Conditional Access, MFA and device-based access for all identity populations | `bicep/` Conditional Access modules |
| Art. 25 data protection by design and by default | Identity control plane as code, reviewed and versioned; least-privilege custom RBAC roles | `bicep/modules/`, custom role definitions |
| Art. 32 security of processing | PIM just-in-time privileged access, Defender for Cloud plans, central logging | `bicep/modules/pim.bicep`, Defender configuration |
| Art. 30 records of processing | Every change is a Git commit and a pipeline run, giving an audit trail of who changed which control | Git history, GitHub Actions runs |
| Art. 33 breach detection and notification | Sentinel analytics rules on the central Log Analytics workspace to detect identity attacks | Sentinel analytics rules |
| Art. 5(1)(e) storage limitation | Log retention set on the workspace. *To confirm* the retention period against your data-retention policy | Log Analytics workspace settings |
| Art. 44 to 49 international transfers | Choose UK or EU regions for the workspace and Sentinel. *To confirm* the region used in your deployment | Deployment parameters |
| Art. 28 processors | Microsoft is a processor. Review the Microsoft DPA and data-residency options for your tenant | Outside this repo |

Related: `docs/compliance-mapping.md` maps the same controls to ISO 27001 Annex A.
