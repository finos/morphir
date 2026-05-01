# Appendix III: FR 2052a Asset Category Table

> This file is **hand-curated** with the help of human visual annotations
> recorded in [`../../human-annotations.md`](../../human-annotations.md).
> The splitter (`scripts/extract.py`) does not overwrite this file on re-run.

The `-Q` suffix indicates that assets meet all the asset-specific tests
detailed in section 20 of Regulation WW (e.g., risk profile and
market-based characteristics).

The original appendix is laid out as three tables in the source PDF (HQLA
categories, Non-HQLA mirroring the HQLA codes for assets that fail the
section-20 tests, and Non-HQLA "other"). Rendered here as a single nested
bullet list keyed by asset category code.

- **HQLA Level 1**
  - A-0-Q — Cash
  - A-1-Q — Debt issued by the U.S. Treasury
  - A-2-Q — U.S. Government Agency-issued debt (excluding the US Treasury) with a US Government guarantee
  - A-3-Q — Vanilla debt (including pass-through MBS) guaranteed by a U.S. Government Agency, where the U.S. Government Agency has a full U.S. Government guarantee
  - A-4-Q — Structured debt (excluding pass-through MBS) guaranteed by a U.S. Government Agency, where the U.S. Government Agency has a full U.S. Government guarantee
  - A-5-Q — Other debt with a U.S. Government guarantee
  - S-1-Q — Debt issued by non-U.S. Sovereigns (excluding central banks) with a 0% RW
  - S-2-Q — Debt issued by multilateral development banks or other supranationals with a 0% RW
  - S-3-Q — Debt with a non-U.S. sovereign (excluding central banks) or multilateral development bank or other supranational guarantee, where guaranteeing entity has a 0% RW
  - S-4-Q — Debt issued or guaranteed by a non-U.S. Sovereign (excluding central banks) that does not have a 0% RW, but supports outflows that are in the same jurisdiction of the sovereign and are denominated in the home currency of the sovereign
  - CB-1-Q — Securities issued or guaranteed by a central bank with a 0% RW
  - CB-2-Q — Securities issued or guaranteed by a non-U.S. central bank that does not have a 0% RW, but supports outflows that are in the same jurisdiction of the central bank and are denominated in the home currency of the central bank[^1]
- **HQLA Level 2a**
  - G-1-Q — Senior to preferred debt issued by a U.S. Government Sponsored Entity (GSE)
  - G-2-Q — Vanilla debt (including pass-through MBS) guaranteed by a U.S. GSE
  - G-3-Q — Structured debt (excluding pass-through MBS) guaranteed by a U.S. GSE
  - S-5-Q — Debt issued by non-U.S. Sovereigns (excluding central banks) with a 20% RW, not otherwise included
  - S-6-Q — Debt issued by multilateral development banks or other supranationals with a 20% RW, not otherwise included
  - S-7-Q — Debt with a non-U.S. sovereign (excluding central banks) or multilateral development bank or other supranational guarantee, where guaranteeing entity has a 20% RW, not otherwise included
  - CB-3-Q — Securities issued or guaranteed by a non-U.S. central bank with a 20% RW, not otherwise included
- **HQLA Level 2b**
  - E-1-Q — U.S. equities - Russell 1000
  - E-2-Q — Non-U.S. Equities listed on a foreign index designated to by the local supervisor as qualifying for the LCR, and denominated in USD or the currency of outflows that the foreign entity is supporting
  - IG-1-Q — Investment grade corporate debt
  - IG-2-Q — Investment grade municipal obligations
- **Non-HQLA — Assets that do not meet the asset-specific tests detailed in section 20 of Regulation WW**
  - A-2 — U.S. Government Agency-issued debt (excluding the US Treasury) with a US Government guarantee
  - A-3 — Vanilla debt (including pass-through MBS) guaranteed by a U.S. Government Agency, where the U.S. Government Agency has a full U.S. Government guarantee
  - A-4 — Structured debt (excluding pass-through MBS) guaranteed by a U.S. Government Agency, where the U.S. Government Agency has a full U.S. Government guarantee
  - A-5 — Other debt with a U.S. Government guarantee
  - S-1 — Debt issued by non-U.S. Sovereigns (excluding central banks) with a 0% RW
  - S-2 — Debt issued by multilateral development banks or other supranationals with a 0% RW
  - S-3 — Debt with a non-U.S. sovereign (excluding central banks) or multilateral development bank or other supranational guarantee, where guaranteeing entity has a 0% RW
  - S-4 — Debt issued or guaranteed by a non-U.S. Sovereign (excluding central banks) that does not have a 0% RW, but supports outflows that are in the same jurisdiction of the sovereign and are denominated in the home currency of the sovereign
  - CB-1 — Securities issued or guaranteed by a central bank with a 0% RW
  - CB-2 — Securities issued or guaranteed by a non-U.S. central bank that does not have a 0% RW, but supports outflows that are in the same jurisdiction of the central bank and are denominated in the home currency of the central bank[^1]
  - G-1 — Senior to preferred debt issued by a U.S. Government Sponsored Entity (GSE)
  - G-2 — Vanilla debt (including pass-through MBS) guaranteed by a U.S. GSE
  - G-3 — Structured debt (excluding pass-through MBS) guaranteed by a U.S. GSE
  - S-5 — Debt issued by Non-U.S. Sovereigns with a 20% RW, not otherwise included
  - S-6 — Debt issued by multilateral development banks or other supranationals with a 20% RW, not otherwise included
  - S-7 — Debt with a non-U.S. sovereign or multilateral development bank or other supranational guarantee, where guaranteeing entity has a 20% RW, not otherwise included
  - CB-3 — Securities issued or guaranteed by a non-U.S. central bank with a 20% RW, not otherwise included
  - E-1 — U.S. equities - Russell 1000
  - E-2 — Non-U.S. Equities listed on a foreign index designated to by the local supervisor as qualifying for the LCR, and denominated in USD or the currency of outflows that the foreign entity is supporting
  - IG-1 — Investment grade corporate debt
  - IG-2 — Investment grade U.S. municipal general obligations
- **Non-HQLA — Other**
  - S-8 — All other debt issued by sovereigns (excluding central banks) and supranational entities, not otherwise included
  - CB-4 — All other securities issued by central banks, not otherwise included
  - G-4 — Debt, other than senior or preferred, issued by a U.S. GSE
  - E-3 — All other U.S.-listed common equity securities
  - E-4 — All other non-US-listed common equity securities
  - E-5 — ETFs listed on US exchanges
  - E-6 — ETFs listed on non-US exchanges
  - E-7 — US mutual fund shares
  - E-8 — Non-US mutual fund shares
  - E-9 — All other US equity investments (including preferred shares, warrants and options)
  - E-10 — All other non-US equity investments (including preferred shares, warrants and options)
  - IG-3 — Investment grade Vanilla ABS
  - IG-4 — Investment grade Structured ABS
  - IG-5 — Investment grade Private label Pass-thru CMBS/RMBS
  - IG-6 — Investment grade Private label Structured CMBS/RMBS
  - IG-7 — Investment grade covered bonds
  - IG-8 — Investment grade obligations of municipals/PSEs (excluding U.S. general obligations)
  - N-1 — Non-investment grade general obligations issued by U.S. municipals/PSEs
  - N-2 — Non-investment grade corporate debt
  - N-3 — Non-investment grade Vanilla ABS
  - N-4 — Non-investment grade structured ABS
  - N-5 — Non-investment grade Private label Pass-thru CMBS/RMBS
  - N-6 — Non-investment grade Private label Structured CMBS/RMBS
  - N-7 — Non-investment grade covered bonds
  - N-8 — Non-investment grade obligations of municipals/PSEs (excluding U.S. general obligations)
  - L-1 — GSE-eligible conforming residential mortgages
  - L-2 — Other GSE-eligible loans
  - L-3 — Other 1-4 family residential mortgages
  - L-4 — Other multi family residential mortgages
  - L-5 — Home equity loans
  - L-6 — Credit card loans
  - L-7 — Auto loans and leases
  - L-8 — Other consumer loans and leases
  - L-9 — Commercial real estate loans
  - L-10 — Commercial and industrial loans
  - L-11 — All other loans, except loans guaranteed by U.S. government agencies
  - L-12 — Loans guaranteed by U.S. government agencies
  - Y-1 — Debt issued by reporting firm - parent
  - Y-2 — Debt issued by reporting firm - bank
  - Y-3 — Debt issued by reporting firm - all other (incl. conduits)
  - Y-4 — Equity investment in affiliates
  - C-1 — Commodities
  - P-1 — Residential property
  - P-2 — All other physical property
  - LC-1 — Letters of credit issued by a GSE
  - LC-2 — All other letters of credit, including bankers' acceptances
  - Z-1 — All other assets

[^1]: The source PDF spells "currrency" (three r's) in the CB-2-Q and CB-2
    descriptions. Corrected to "currency" here. See
    `../../human-annotations.md` for details.
