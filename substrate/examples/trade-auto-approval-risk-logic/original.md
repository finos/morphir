# Trade Auto-Approval Risk Logic

## Overview

We need to build some basic logic for auto-approving trades based on the type of asset being traded. For now, we’re dealing with equities, bonds, and derivatives. Each type has a different risk profile, so the approval logic should reflect that. Equities should be auto-approved if their risk score is under 0.5. Bonds are more conservative, so only auto-approve if the risk score is under 0.3. For derivatives, we want to auto-approve only if the notional is under one million and the leverage is less than 2.