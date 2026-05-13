# Field Definitions


## Reporting entity

Report in this field the relevant entity name. The list of reportable entities is specific to each
reporting firm (see Who Must Report). Coordinate entity naming conventions with the
supervisory team.

- For products or exposures that span multiple reporting entities, allocate balances to each reporting entity in a manner consistent with internal risk management and reporting practices. For example, consolidated exposures, such as unfunded commitments to multinational entities, that are not normally attributed to a specific reporting entity may be allocated pro-rata to multiple reporting entities, provided that the allocation better represents the reporting firm’s contingent funding profile and is consistent with internal risk management practices. Discuss with the supervisory team as necessary.

## Currency

The following firms may report all assets, liabilities, and other informational data elements in
USD millions: U.S. firms that are identified as Category III banking organizations with average
weighted short-term wholesale funding of less than $75 billion; U.S. firms that are identified as
Category IV banking organizations; FBOs that are identified as Category III foreign banking
organizations with average weighted short-term wholesale funding of less than $75 billion; and
FBOs that are identified as Category IV foreign banking organizations.

For all other firms, each numerical field (e.g., [Market Value], [Maturity Amount], etc.) has an
associated currency attribute, which should be used to identify the currency denomination of
all assets, liabilities, and other informational data elements. All currency-denominated values
should be reported in millions (e.g., U.S. dollar-denominated transactions in USD millions,
sterling-denominated transactions in GBP millions). Use the following currency codes: USD,
EUR, GBP, CHF, JPY, AUD, and CAD.7

- For all other currencies, convert to USD according to the closing exchange rate (i.e., 6:30pm EST) on the as-of date (T) using the same currency conversion convention.

7 U.S. Dollar (USD); Euro (EUR); Australian Dollar (AUD); Canadian Dollar (CAD); Swiss Franc (CHF); Pound Sterling
(GBP); Japanese Yen (JPY).


## Converted

Report this field as “True” if the data element values have been converted to USD-equivalent
values.

## Product

Refer to the product definitions section for specific guidance on the classification of inflows,
outflows, and supplemental items. Unless otherwise specified, do not report the same
transaction more than one time for each reporting entity.

## Sub-Product

The sub-product field is used in conjunction with the product field to further differentiate
similar data elements.

- The sub-product is only a required field for certain products.
- For a full listing of acceptable product and sub-product combinations, see Appendix II.

## Counterparty

The following counterparty types are used across all tables except the Inflow-Assets,
Supplemental-Informational, and Comment tables.8 The definitions for these types should align
with the classification of the legal counterparty to a given exposure and not the counterparty’s
ultimate parent; however two product-specific exceptions to this approach are detailed below
in the definitions of the Debt Issuing SPE and Bank counterparty types.

- Retail Refers to a counterparty who is a natural person. Retail includes a living or testamentary trust that is solely for the benefit of natural persons, does not have a corporate trustee, and terminates within 21 years and 10 months after the death of grantors or beneficiaries of the trust living on the effective date of the trust or within 25 years, if applicable under state law. Retail does not include other legal entities, sole proprietorships, or partnerships. Other legal entities, proprietorships and partnerships should be reported, as appropriate, in one of the sub-products as defined below.

- Small Business Refers to entities managed as retail exposures that exhibit the same liquidity risk characteristics as retail customers. The total aggregate funding raised from these entities should not exceed $1.5 million from the perspective of the consolidated

8 This listing does not include “Municipalities for VRDNs”, which is applicable only to O.O.5: Liquidity Facilities and
is defined in that section.


    reporting entity. Under circumstances where small business entities are affiliated, the
    $1.5 million threshold should be assessed against the aggregate funding exposures of
    the affiliated group.

- Non-Financial Corporate Refers to commercial entities that are not owned by central governments, local governments or local authorities with revenue-raising powers, and that are non- financial in nature (i.e., do not meet the definition of Pension Fund, Bank, Broker-Dealer, Investment Company or Advisor, Financial Market Utility, Other Supervised Non-Bank Financial Entity, or Non-Regulated Fund as identified in the sections below).

- Sovereign Refers to a central government or an agency, department or ministry.

- Central Bank Refers to a bank responsible for implementing its jurisdiction’s monetary policy.

- Government Sponsored Entity (GSE) Refers to entities established or chartered by the Federal government to serve public purposes specified by the United States Congress, but whose debt obligations are not explicitly guaranteed by the full faith and credit of the United States government.

- Public Sector Entity (PSE) Refers to a state, local authority, or other governmental subdivision below the sovereign level.

- Multilateral Development Bank (MDB) Refers to the International Bank for Reconstruction and Development, the Multilateral Investment Guarantee Agency, the International Finance Corporation, the Inter- American Development Bank, the Asian Development Bank, the African Development Bank, the European Bank for Reconstruction and Development, the European Investment Bank, the European Investment Fund, the Nordic Investment Bank, the Caribbean Development Bank, the Islamic Development Bank, the Council of Europe Development Bank, and any other entity that provides financing for national or regional development in which the U.S. government is a shareholder or contributing member or which the appropriate Federal banking agency determines poses comparable risk.


- Other Supranational International or regional organizations or subordinate or affiliated agencies thereof, created by treaty or convention between sovereign states that are not multilateral development banks, including the International Monetary Fund, the Bank for International Settlements, and the United Nations.

- Pension Fund Refers to an employee benefit plan as defined in paragraphs (3) and (32) of section 3 of the Employee Retirement Income and Security Act of 1974 (29 U.S.C. 1001 et seq.), a “governmental plan” (as defined in 29 U.S.C. 1002(32)) that complies with the tax deferral qualification requirements provided in the Internal Revenue Code, or any similar employee benefit plan established under the laws of a foreign jurisdiction.

- Bank Refers to a depository institution; bank holding company or savings and loan holding company; foreign bank; credit union; industrial loan company, industrial bank, or other similar institution described in section 2 of the Bank Holding Company Act of 1956, as amended (12 U.S.C. 1841 et seq.); national bank, state member bank, or state non- member bank that is not a depository institution. This term does not include non-bank financial entities that have an affiliated banking entity, except for exposures reported in the Outflows-Other table under products O.O.4: Credit Facilities and O.O.5: Liquidity Facilities. Any company that is not a bank but is included in the organization chart of a bank holding company or savings and loan holding company on the Form FR Y-6, as listed in the hierarchy report of the bank holding company or savings and loan holding company produced by the National Information Center (NIC) Web site, must be designated as a Bank for products O.O.4 and O.O.5. This term does not include bridge financial companies as defined in 12 U.S.C. 5381(a)(3), or new depository institutions or bridge depository institutions as defined in 12 U.S.C. 1813(i).

- Broker-Dealer Refers to a securities holding company as defined in section 618 of the Dodd-Frank Act (12 U.S.C. 1850a); broker or dealer registered with the SEC under section 15 of the Securities Exchange Act (15 U.S.C. 78o); futures commission merchant as defined in section 1a of the Commodity Exchange Act of 1936 (7 U.S.C. 1 et seq.); swap dealer as defined in section 1a of the Commodity Exchange Act (7 U.S.C. 1a); security-based swap dealer as defined in section 3 of the Securities Exchange Act (15 U.S.C. 78c); or any company not domiciled in the United States (or a political subdivision thereof) that is


    supervised and regulated in a manner similar to these entities.

- Investment Company or Advisor Refers to a person or company registered with the SEC under the Investment Company Act of 1940 (15 U.S.C. 80a-1 et seq.); a company registered with the SEC as an investment adviser under the Investment Advisers Act of 1940 (15 U.S.C. 80b-1 et seq.); or foreign equivalents of such persons or companies. An investment company or advisor does not include small business investment companies, as defined in section 102 of the Small Business Investment Act of 1958 (15 U.S.C. 661 et seq.).

- Financial Market Utility Refers to a designated financial market utility, as defined in section 803 of the Dodd- Frank Act (12 U.S.C. 5462) and any company not domiciled in the United States (or a political subdivision thereof) that is supervised and regulated in a similar manner.

- Other Supervised Non-Bank Financial Entity (1) A company that the Financial Stability Oversight Council has determined under section 113 of the Dodd-Frank Act (12 U.S.C. 5323) shall be supervised by the Board of Governors of the Federal Reserve System and for which such determination is still in effect; (2) A company that is not a bank, broker-dealer, investment company or advisor or financial market utility, but is included in the organization chart of a bank holding company or savings and loan holding company on the Form FR Y-6, as listed in the hierarchy report of the bank holding company or savings and loan holding company produced by the National Information Center (NIC) Web site; (3) An insurance company; and (4) Any company not domiciled in the United States (or a political subdivision thereof) that is supervised and regulated in a manner similar to entities described in paragraphs (1) through (3) of this definition (e.g., a non-bank subsidiary of a foreign banking organization, foreign insurance company, etc.). (5) A supervised non-bank financial entity does not include: a. U.S. government-sponsored enterprises; b. Entities designated as Community Development Financial Institutions (CDFIs) under 12 U.S.C. 4701 et seq. and 12 CFR part 1805; or c. Central banks, the Bank for International Settlements, the International Monetary Fund, or multilateral development banks.


- Debt Issuing Special Purpose Entity (SPE) Refers to an SPE9 that issues or has issued commercial paper or securities (other than equity securities issued to a company of which the SPE is a consolidated subsidiary) to finance its purchases or operations. This counterparty type should only be used to identify stand-alone SPEs that issue debt and are not consolidated on an affiliated entity’s balance sheet for purposes of financial reporting, except for exposures reported in the Outflows-Other table under products O.O.4: Credit Facilities and O.O.5: Liquidity Facilities. All debt issuing SPEs should be identified as Debt Issuing SPEs for products O.O.4 and O.O.5, regardless of whether they are consolidated by an affiliate for financial reporting.

- Non-Regulated Fund Refers to a hedge fund or private equity fund whose investment advisor is required to file SEC Form PF (Reporting Form for Investment Advisers to Private Funds and Certain Commodity Pool Operators and Commodity Trading Advisors), other than a small business investment company as defined in section 102 of the Small Business Investment Act of 1958 (15 U.S.C. 661 et seq.)).

- Other Refers to any counterparty that does not fall into any of the above categories. Consult with your supervisory team before reporting balances using this counterparty type. Use the comments table to provide description of the counterparty on at least a monthly basis and in the event of a material change in reported values.

## Collateral Class

Use the asset category table in Appendix III to identify the type of collateral for all relevant
inflows, outflows, and informational items.

- For securities that have multiple credit risk profiles, report the transaction or asset based on the lowest quality.

- Use the standardized risk weightings as specified under subpart D of Regulation Q (12 CFR part 217).

9 An SPE refers to a company organized for a specific purpose, the activities of which are significantly limited to
those appropriate to accomplish a specific purpose, and the structure of which is intended to isolate the credit risk
of the SPE.


- Work with supervisory teams to address questions on the categorization of specific assets.

## Collateral Value

Refers to the fair value under GAAP of the referenced asset or pool of collateral, gross of any
haircuts, according to the close-of-business marks on the as-of date. For pledged loans that are
accounted for on an accrual basis, report the most recent available fair valuation.

## Maturity Bucket

Report the appropriate maturity time bucket value for each data element, based on the listing
provided in Appendix IV.

- Report all information based on the contractual maturity of each data element. o In general, report maturities based upon the actual settlement of cash flows. For example, if a payment is scheduled to occur on a weekend or bank holiday, but will not actually settle until the next good business day, the maturity bucket must correspond to the date on which the payment will actually settle. o Do not report based on behavioral or projected assumptions.

- “Day” buckets refer to the number of calendar days following the as-of date (T). For example, “Day 1” (Calendar Day 1) represents balances on T+1 (maturing the next calendar day from T).

- Report transactions and balances that do not have a contractual maturity, but could be contractually realized on demand (e.g., demand deposits) as “Open”.

- Report transactions and balances as “Perpetual” to the extent that they do not have a contractual maturity (or where the maturity is explicitly defined as perpetual), could not be contractually realized on demand or with notice at the inception of the transaction, and would not be subject to the maturity acceleration requirements of sections 31(a)(1)(i) or (iii) of the LRM Standards. For example, common equity included in regulatory capital should be reported with a [Maturity Bucket] value of “Perpetual”.

- For transactions and balances with embedded optionality, report the maturity in accordance with sections 31(a)(1) and 31(a)(2) of the LRM Standards. For deferred tax liabilities, report the maturity in accordance with section 101(d) of the LRM Standards. o For transactions and balances with embedded optionality that are executed between affiliated reporting entities, where neither reporting entity is subject to the LRM Standards on a standalone basis, report the maturity according to the earliest possible date the transaction or balance could contractually be repaid.

- In the case of forward starting transactions with an open maturity, report the [Maturity Bucket] value equal to the [Forward Start Bucket] value until the forward start date


         arrives. Do not report the record with a [Maturity Bucket] value of “Open” until the
         forward starting leg actually settles.
- Report all executed transactions, including transactions that have traded but have not settled.

             o Do not report transactions that are anticipated, but have not yet been executed.
- Further guidance that is only relevant to specific products is provided in the product

         definitions section.

## Effective Maturity Bucket

This field is only relevant for data elements in the Inflows-Assets, Inflows-Unsecured, Inflows-
Secured, Supplemental-Derivatives & Collateral and Supplemental-Balance Sheet tables. Report
a maturity time bucket value in this field for all Inflows-Secured data elements where the asset
has been re-used to secure or otherwise settle another transaction or exposure.

- The effective maturity date must align with the remaining period of encumbrance, irrespective of the original maturity of the transaction or exposure.

- With respect to an asset pledged to a collateral swap, if the asset received in the collateral swap has been rehypothecated to secure another transaction, in accordance with section 106(d)(2) of the LRM Standards, the effective maturity date of the on- balance sheet asset pledged to the collateral swap must align with the longer of the two encumbrances (i.e., either the maturity of the collateral swap, or the maturity of the transaction to which the asset received in the collateral swap has been pledged).

- For transactions where the collateral received has been rehypothecated and delivered into a firm short position, report an effective maturity date of “Open”. Do not report an effective maturity date of “Open” if the collateral received has been delivered into any other type of transaction. Under circumstances where the collateral received via a secured lending transaction with an “Open” maturity date has been rehypothecated and delivered into another transaction with an “Open” maturity date that is not a firm short position, report a “Day 1” value in the [Effective Maturity Bucket] field.

- For transactions where the collateral received is generally re-used throughout the day to satisfy intraday collateral requirements for access to payment, clearance and settlement systems, report a “Day 1” value in the [Effective Maturity Bucket] field.

## Maturity Amount

Report the notional amount contractually due to be paid or received at maturity for each data
element.

- All notional currency-denominated values should be reported in millions (e.g., U.S. dollar-denominated transactions in USD millions, sterling-denominated transactions in GBP millions).


- This amount represents the aggregate balance of trades, positions or accounts that share common data characteristics (i.e., common non-numerical field values). If the aggregate amount rounds to less than ten thousand currency units (i.e., 0.01 for this report), the record should not be reported. o Example: The banking entity has corporate customers with a total of $2.25 billion in operational and non-operational deposits, of which:
- $1 billion is operational and fully FDIC insured with an open maturity;
- $500 million is non-operational uninsured with an open maturity; and
- $750 million is non-operational uninsured maturing on calendar day 5. o Table 1 below illustrates how the total operational and non-operational corporate deposit balance should be disaggregated and reported across these three distinct combinations of fields in the deposit table (O.D).

                            Table 1 – Example: maturity amount aggregation

## Forward Start Bucket

This field is only relevant for data elements with a forward-starting leg (i.e., the trade settles at
a future date). Report the appropriate maturity bucket for the forward-starting settlement date
of each applicable data element, based on the maturity buckets provided in Appendix IV. See
the Supplemental-Foreign Exchange table guidance in the product definitions section for
further instruction on how to report forward-starting foreign exchange transactions.

## Forward Start Amount

This field is only relevant for data elements with a forward-starting leg. In conjunction with the
forward start bucket, report the notional amount due to be paid or received on the opening
trade settlement date of forward starting transactions. See the Supplemental-Foreign Exchange
table guidance in the product definitions section for further instruction on how to report
forward-starting foreign exchange transactions.

## Internal

This field is only relevant for data elements reporting transactions between FR 2052a reporting
entities and designated internal counterparties (i.e., affiliated transactions). Flag all data
elements representing these transactions with a “Yes” in this field. Affiliated transactions are


defined as all transactions between the reporting entity and any other entity external to the
reporting entity that falls under the “Scope of the Consolidated Entity” as defined in these
instructions (e.g., branches, subsidiaries, affiliates, VIEs, and IBFs).

## Internal Counterparty

This field is only relevant for data elements reporting affiliated transactions. Report the internal
counterparty for affiliated transactions referenced above in this field.

## Treasury Control

This field is only applicable to the Inflows-Assets, Inflows-Secured, Inflows-Other, Outflows-
Secured and Supplemental-Derivatives & Collateral tables. Use this field to flag (“Yes”) assets, or
transactions secured by assets that meet the operational requirements for eligible HQLA in the
LRM Standards other than the requirement to be unencumbered, which addresses: the
operational capability to monetize; policies that require control by the function of the bank
charged with managing liquidity risk; policies and procedures that determine the composition;
and not being client pool securities or designated to cover operational costs.

Do not set [Treasury Control]=”Yes” in the Secured-Inflows table where the collateral received
has been rehypothecated and pledged to secure a collateral swap where the collateral that
must be returned at the maturity of the swap transaction does not qualify as HQLA per the FR
2052a Asset Category Table (Appendix III).

## Market Value

This field is only applicable to the Inflows-Assets, Supplemental-Derivatives & Collateral,
Supplemental-LRM, Supplemental-Balance sheet and Supplemental-Informational tables.
Report the fair value under GAAP for each applicable data element.

- In general, report values according to the close-of-business marks on the as-of date. For loans that are accounted for on an accrual basis, report the most recent available fair valuation.

## Lendable Value

This field is only applicable to the Inflows-Assets table. Report the lendable value of collateral
for each applicable data element in the assets table.

- Lendable value is the value that the reporting entity could obtain for assets in secured funding markets after adjusting for haircuts due to factors such as liquidity, credit and market risks.


## Business Line

This field is applicable to all tables except the Supplemental-LRM and Comments tables. U.S.
firms that are identified as Category I banking organizations are required to report this field.

Use this field to designate the business line responsible for or associated with all applicable
exposures. Coordinate with the supervisory team to determine the appropriate representative
values for this field.

## Settlement

This field is only applicable to the Inflows-Secured, Outflows-Secured and Supplemental-Foreign
Exchange tables. Use this field to identify the settlement mechanisms used for Secured and
Foreign Exchange products.

- Products in the secured tables should be classified using the following flags: o FICC: secured financing transactions that are cleared and novated to the Fixed Income Clearing Corporation (FICC) o Triparty: secured financing transactions settled on the US-based tri-party platform, excluding transactions that originate on the tri-party platform, but are novated to FICC (e.g., the General Collateral Finance repo service). o Other: secured financing transactions settled on other (e.g., non-US) third-party platforms (includes transactions that are initiated bilaterally, but are subsequently cleared through a CCP) o Bilateral: secured financing transactions settled bilaterally (excludes transactions that are initiated bilaterally, but subsequently cleared (e.g., FICC delivery-vs- payment transactions)

- Products in the foreign exchange table should be classified using the following flags: o CLS: FX transactions centrally cleared via CLS o Other: FX transactions settled via other (non-CLS) central clearinghouses o Bilateral: FX transactions settled bilaterally

## Rehypothecated

This field is only applicable to the Outflows-Secured and Outflows-Deposits tables. Use this field
to flag (“Yes”) data elements representing transactions or accounts secured by collateral that
has been rehypothecated. Transactions should not be flagged as rehypothecated if they have
not yet settled.

## Unencumbered

This field is only applicable to the Inflows-Secured table. Use this field to flag (“Yes”) secured
transactions where the collateral received is held unencumbered in inventory and: (i) the assets


are free of legal, regulatory, contractual, or other restrictions on the ability of the reporting
entity to monetize the assets; and (ii) the assets are not pledged, explicitly or implicitly, to
secure or to provide credit enhancement to any transaction. Transactions should not be flagged
as unencumbered if they have not yet settled. Do not flag secured transactions as
unencumbered if the collateral received has been pre-positioned at a central bank or Federal
Home Loan Bank (FHLB), as that collateral should also be reported under product I.A.2:
Capacity.

## Insured

This field is only applicable to the Outflows-Deposits table. Use this field to identify
balances that are fully insured by the FDIC or other foreign government-sponsored deposit
insurance systems.

- FDIC Refers to deposits fully insured by FDIC deposit insurance.

- Other Refers to deposits that are fully insured by non-US local-jurisdiction government deposit insurance.

- Uninsured Refers to deposits that are not fully insured by FDIC deposit insurance or other non- US local-jurisdiction government deposit insurance.

## Trigger

This field is only applicable to the Outflows-Deposits table. Use this field to flag (“Yes”)
deposit accounts that include a provision requiring the deposit to be segregated or
withdrawn in the event of a specific change or “trigger”, such as a change in a reporting
entity’s credit rating.

## Risk Weight

This field is only applicable to the Inflows-Unsecured, Inflows-Secured and Supplemental-
Balance Sheet tables.

U.S. firms that are identified as Category IV banking organizations with average weighted short-
term wholesale funding of less than $50 billion and FBOs that are identified as Category IV
foreign banking organizations with average weighted short-term wholesale funding of less than
$50 billion are not required to report on this field.


Use this field to designate the standardized risk weight of unsecured and secured lending
transactions, as per 12 CFR §217 subpart D, along with any associated adjustments
necessary to establish the balance sheet carrying value of these transactions.

## Collection Reference

This field is only applicable to the Supplemental-Balance Sheet table. Use this field to
indicate the [Collection] (i.e., table) designation applicable to a reported adjustment.
Adjustments should be designated using the following values: I.A., I.S, I.U, I.O, O.D, O.S,
O.W., O.O and S.DC.

## Product Reference

This field is only applicable to the Supplemental-Balance Sheet table. Use this field to
indicate the [Product] designation applicable to the reported adjustment.

## Sub-Product Reference

This field is only applicable to the Supplemental-Balance Sheet table. Use this field to
indicate the [Sub-Product] designation applicable to the reported adjustment.

## Netting Eligible

This field is only applicable to the Derivatives & Collateral table. Use this field to identify
the balances of variation margin posted and received under S.DC.8 through S.DC.10 that
are eligible for netting per the conditions referenced in section 107(f)(1) of the LRM
Standards.

## Encumbrance Type

This field is only applicable to the Inflows-Assets, Inflows-Unsecured, Inflows-Secured and
Supplemental-Derivatives & Collateral tables. Use this field to categorize asset
encumbrances according to the following types:

- Securities Financing Transaction Refers to the encumbrance of assets to transactions reportable in the O.D., O.S and O.W tables, except for assets pledged to secure Covered Federal Reserve Facility Funding.

- Derivative VM Refers to the encumbrance of assets delivered to satisfy calls for variation margin in response to change in the value of derivative positions.

- Derivative IM and DFC


         Refers to the encumbrance of assets delivered to satisfy initial margin, default fund
         contributions or other comparable requirements, where the activity supported by
         these encumbrances includes derivatives.

- Other IM and DFC Refers to the encumbrance of assets delivered to satisfy initial margin, default fund contributions or other comparable requirements, where the activity supported by these encumbrances does not include derivatives.

- Segregated for Customer Protection Refers to encumbrances due to the segregation of assets held to satisfy customer protection requirements (e.g., 15c3-3, CFTC residual interest and other customer money protection requirements).

- Covered Federal Reserve Facility Funding Refers to encumbrance reportable using product O.S.6: Exceptional Central Bank Operations with a sub-product of Covered Federal Reserve Facility Funding.

- Other Refers to all other types of encumbrance. Use the comments table to provide additional detail on the underlying type of encumbrance on at least a monthly basis and in the event of a material change in reported values.

## Collateral Level

This field is only applicable to the Supplemental-Derivatives & Collateral table. Use this
field to differentiate the derivative asset and liability values (S.DC.1 and 2) and the
balances of variation margin posted and received (S.DC.8 through 10) for all derivative
contracts (e.g., based on the collateralization requirements stipulated in the contractual
terms of a derivative’s credit support annex (CSA)):

- Uncollateralized Refers to derivative asset and liability values that do not require exchange of variation margin (i.e., the transactions or netting sets are not governed by a CSA or the applicable CSA does not require the out-of-the-money counterparty, based on current market values, to provide variation margin).

- Undercollateralized Refers to derivative asset and liability values and any associated balances of variation margin posted and received where the value of margin exchanged is less than the derivative asset or liability value for the transaction or associated derivative transaction


         or qualifying master netting agreement netting set (e.g., due to thresholds or minimum
         transfer amounts).

- Fully Collateralized Refers to derivative asset and liability values and any associated balances of variation margin posted and received where the value of margin exchanged is equal to the derivative asset or liability value for the transaction or associated derivative transaction or qualifying master netting agreement netting set. Derivative asset and liability values may be considered “fully collateralized” to the extent there are short-term timing mismatches between margin calls and margin settlement that result in temporarily undercollateralized exposures or minimum transfer amounts are set at de minimus levels (e.g., $1 million).

- Overcollateralized Refers to derivative asset and liability values and the portion of variation margin posted and received where the value of margin exchanged is greater than the derivative asset or liability value for the transaction or associated derivative transaction or qualifying master netting agreement netting set. For variation margin posted and received, use this value to designate only the portion of margin that exceeds the derivative asset or liability value.

## Accounting Designation

This field is only applicable to the Inflows-Assets table. Use this field to identify the
accounting designation applicable to each asset reported under products I.A.1:
Unencumbered Assets and I.A.2: Capacity. Use the following values:

- Available-for-Sale
- Held-to-Maturity
- Trading Asset
- Not Applicable: For example, use this designation to the extent assets received via a

         secured lending transaction are reported under I.A.2: Capacity.

## Loss Absorbency

This field is only applicable to the Wholesale table.

U.S. firms that are identified as Category IV banking organizations with average weighted short-
term wholesale funding of less than $50 billion and FBOs that are identified as Category IV


foreign banking organizations with average weighted short-term wholesale funding of less than
$50 billion are not required to report on this field.

Use this field to identify the extent to which instruments reported in the Outflows-
Wholesale table qualify as capital or Total Loss Absorbing Capacity (TLAC) instruments
under 12 CFR §217 Subpart C or 12 CFR §252 Subparts G and P, respectively. Use the
following values:

- Capital
- TLAC

## G-SIB

This field is applicable in all cases where the Counterparty field is populated.

U.S. firms that are identified as Category I banking organizations are required to report this
field.

Use this field to identify data elements where the underlying counterparty is a G-SIB
according to the most recent list of G-SIBs published by the Financial Stability Board (FSB).
Report in this field the G-SIB name, as it appears on the FSB list.

## Maturity Optionality

This field is applicable to the Inflows-Secured, Inflows-Unsecured, Outflows-Deposits,
Outflows-Secured and Outflows-Wholesale tables. Use this field to identify transactions
with the following types of embedded optionality:

- Evergreen Refers to transactions that require either or both parties to provide a minimum number of days’ notice before the transaction can contractually mature.

- Extendible Refers to transactions that include options to extend the maturity beyond its originally scheduled date.

- Accelerated-Counterparty Refers to transactions where the counterparty holds an option to accelerate maturity (e.g., a liability with a put option), and the maturity is assumed to be accelerated as per the requirements for reporting of the [Maturity Bucket] field. Include transactions where the counterparty’s exercise of the option would require the reporting entity’s mutual consent.


- Accelerated-Firm

    Refers to transactions where the reporting entity holds an option to accelerate maturity
    (e.g., a liability with a call option), and the maturity is assumed to be accelerated as per
    the requirements for reporting of the [Maturity Bucket] field.
- Not Accelerated Refers to all other transactions with embedded optionality that could accelerate the maturity of an instrument, but that maturity is not assumed to be accelerated as per the requirements for reporting of the [Maturity Bucket] field.
