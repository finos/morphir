# Trade Auto-Approval Risk Logic

## Overview

We need to build some basic logic for auto-approving trades based on the type of asset being traded. For now, we’re dealing with equities, bonds, and derivatives. Each type has a different risk profile, so the approval logic should reflect that. Equities should be auto-approved if their risk score is under 0.5. Bonds are more conservative, so only auto-approve if the risk score is under 0.3. For derivatives, we want to auto-approve only if the notional is under one million and the leverage is less than 2.

```yaml
substrate:
  types:
    asset:
      one-of: 
        - tag: equity
          src: "equities"
        - tag: bond
          src: "bonds"
        - tag: derivative
          src: "derivatives"
        - tag: crypto
          src: "crypto"
        src: "type of asset"
  values:
    auto-approve:
      match:
        on: asset
        cases:
          - when: equity
            then:
              - if: 
                  less-than:
                    - risk_score
                    - 0.5
                  src: "risk score is under 0.5."   
                then: true
                else: false
            src: "Equities should be auto-approved if their risk score is under 0.5."                     
          - when: bond
            then:
              - if: 
                  less-than:
                    - risk_score
                    - 0.3
                  src: "risk score is under 0.3."  
                then: true
                else: false
            src: "Bonds are more conservative, so only auto-approve if the risk score is under 0.3."                     
          - when: derivative
            then:
              - if:
                  all-of:
                    less-than:
                      - notional
                      - 1,000,000
                    less-than:
                      - leverage
                      - 2
                then: true
                else: false      
            src: "For derivatives, we want to auto-approve only if the notional is under one million and the leverage is less than 2."
        src: "Each type has a different risk profile"            
```