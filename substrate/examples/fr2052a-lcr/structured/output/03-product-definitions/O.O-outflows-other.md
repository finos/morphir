# O.O: Outflows-Other


Collateralized facilities: For products O.O.4 through O.O.7 use the [Collateral Value] and
[Collateral Class] fields to report both the amount and type of collateral that has been posted
by the counterparty to secure the used portions of committed facilities according to the
appropriate instructions for these fields or where the counterparty is contractually obligated to


post collateral when drawing down the facility (e.g., if a liquidity facility is structured as a repo
facility). Only report collateral if the bank is legally entitled and operationally capable to re-use
the collateral in new cash raising transactions once the facility is drawn. If the range of
acceptable collateral spans multiple categories as defined in the Asset Category Table
(Appendix III), report using the lowest possible category.

### O.O.1: Derivative Payables

Refers to the maturing outgoing cash flows related to uncollateralized derivatives (e.g.,
interest rate, equity, commodity, and option premiums). Report contractually known payables
for fixed and floating rate payables. If a floating rate has not been set, report the undiscounted
anticipated cash flow by maturity. Do not include brokerage commission fees, exchange fees, or
cash flows from unexercised in the money options. Netting receivables and payables by
counterparty and maturity date is allowed if a valid netting agreement is in place, allowing for
the net settlement of contractual flows. Do not include payables related to the exchange of
principal amounts for foreign exchange transactions, as these should be reported in the
Supplemental-Foreign Exchange table under products S.FX.1 through S.FX.3.

### O.O.2: Collateral Called for Delivery

Refers to the fair value of collateral due to the reporting entity’s counterparties that has been
called as of date T (i.e., the collateral flow). This product does not represent the entire stock of
collateral posted. Collateral called for delivery should be related to the outstanding
collateralized contracts which include, but are not limited to, derivative transactions with
bilateral counterparties, central counterparties, or exchanges. Use the Maturity Bucket field to
identify the expected settlement date. For collateral calls with same-day settlement (i.e., the
collateral is both called and received on the as-of date T), report using the “Open” value in the
Maturity Bucket field.

### O.O.3: TBA Purchases

Refers to all purchases of TBA contracts for market making or liquidity providing. Do not include
TBA purchases which are part of a Dollar Roll, as defined under products I.S.3 or O.S.3.

### O.O.4: Credit Facilities

Refers to committed credit facilities, as defined in the LRM Standards. Do not include
committed liquidity facilities, as defined in the LRM Standards, which should be reported using
product O.O.5: Liquidity Facility or O.O.18: Unfunded Term Margin. Do not include excess
margin, which should be reported using product O.O.17: Excess Margin, or retail mortgage
commitments, which should be reported using product O.O.6: Retail Mortgage Commitments.


Use the O.O.[Maturity Bucket] field to indicate the earliest date the commitment could be
drawn.

Use the O.O.[Counterparty] field to distinguish between facilities to different counterparties:

- Retail
- Small Business
- Non-Financial Corporate
- Sovereign
- Central Bank
- GSE
- PSE
- MDB
- Other Supranational
- Pension Fund
- Bank
- Broker-Dealer
- Investment Company or Advisor
- Financial Market Utility
- Other Supervised Non-Bank Financial Entity
- Debt Issuing SPE
- Non-Regulated Fund
- Other

### O.O.5: Liquidity Facilities

Refers to committed liquidity facilities, as defined in the LRM Standards; however, exclude
unfunded term margin, which should be reported under O.O.18: Unfunded Term Margin.

If facilities have aspects of both credit and liquidity facilities, the facility must be classified as a
liquidity facility.

Use the O.O.[Maturity Bucket] field to indicate the earliest date the commitment could be
drawn.

Use the O.O.[Counterparty] field to distinguish between facilities to different counterparties:

- Retail
- Small Business
- Non-Financial Corporate
- Sovereign
- Central Bank
- GSE


- PSE, except Municipalities for VRDN structures
- MDB
- Other Supranational
- Pension Fund
- Bank
- Broker-Dealer
- Investment Company or Advisor
- Financial Market Utility
- Other Supervised Non-Bank Financial Entity
- Debt Issuing SPE
- Non-Regulated Fund
- Municipalities for VRDN structures

                  o Includes standby purchase agreements that backstop remarketing
                      obligations, as well as direct‐pay LOCs that provide credit enhancement. If a
                      VRDN is not supported by an SBPA or LOC, then the remarketing obligation
                      should also be considered as a liquidity facility under this product.

- Other

### O.O.6: Retail Mortgage Commitments

Refers to contractual commitments made by the reporting entity to originate retail mortgages.
Use the O.O.[Maturity Bucket] field to indicate the earliest date the commitment could be
drawn.

### O.O.7: Trade Finance Instruments

Refers to documentary trade letters of credit, documentary and clean collection, import bills
and export bills, and guarantees directly related to trade finance obligations, such as shipping
guarantees.

Lending commitments, such as direct import or export financing for non-financial firms, should
be included in O.O.4: Credit Facilities and O.O.5: Liquidity Facilities, as appropriate.

### O.O.8: MTM Impact on Derivative Positions

Refers to the absolute value of the largest 30-consecutive calendar day cumulative net mark-to-
market collateral outflow or inflow realized during the preceding 24 months resulting from
derivative transaction valuation changes, as set forth in the LRM Standards. The cumulative
collateral outflow or inflow should be measured on a portfolio basis, which should include both
3rd party and affiliated transactions (for subsidiary reporting entities) that are external to the
reporting entity’s scope of consolidation. However, as this product should be measured on a
portfolio basis, the [Internal] and [Internal Counterparty] flags should not be used. The absolute
amount should be determined across all currencies and reported in USD.


### O.O.9: Loss of Rehypothecation Rights Due to a 1 Notch Downgrade

Refers to the total fair value of the collateral over which the reporting entity would lose
rehypothecation rights due to a 1 notch credit rating downgrade.

### O.O.10: Loss of Rehypothecation Rights Due to a 2 Notch Downgrade

Refers to the total fair value of the collateral over which the reporting entity would lose
rehypothecation rights due to a 2 notch credit rating downgrade.

### O.O.11: Loss of Rehypothecation Rights Due to a 3 Notch Downgrade

Refers to the total fair value of the collateral over which the reporting entity would lose
rehypothecation rights due to a 3 notch credit rating downgrade.

### O.O.12: Loss of Rehypothecation Rights Due to a Change in Financial Condition

Refers to the total fair value of the collateral over which the reporting entity would lose
rehypothecation rights due to a change in financial condition, which includes a downgrade of
the reporting entity’s rating up to but not including default.

### O.O.13: Total Collateral Required Due to a 1 Notch Downgrade

Refers to the total cumulative fair value of additional collateral the reporting entity’s
counterparties will require the reporting entity to post as a result of a 1- notch credit rating
downgrade. Report figures based on contractual commitments. Collateral required includes,
but is not limited to, collateral called from OTC derivative transactions and exchanges. Include
outflows due to additional termination events, but do not include inflows from netting sets that
are in a net receivable position. Do not double count balances reported in O.O.9.

### O.O.14: Total Collateral Required Due to a 2 Notch Downgrade

Refers to the total cumulative fair value of additional collateral the reporting entity’s
counterparties will require the reporting entity to post as a result of a 2- notch credit rating
downgrade. Report figures based on contractual commitments. Collateral required includes,
but is not limited to, collateral called from OTC derivative transactions and exchanges. Include
outflows due to additional termination events, but do not include inflows from netting sets that
are in a net receivable position. Do not double count balances reported in O.O.10.

### O.O.15: Total Collateral Required Due to a 3 Notch Downgrade

Refers to the total cumulative fair value of additional collateral the reporting entity’s
counterparties will require the reporting entity to post as a result of a 3- notch credit rating
downgrade. Report figures based on contractual commitments. Collateral required includes,
but is not limited to, collateral called from OTC derivative transactions and exchanges. Include
outflows due to additional termination events, but do not include inflows from netting sets that
are in a net receivable position. Do not double count balances reported in O.O.11.


### O.O.16: Total Collateral Required Due to a Change in Financial Condition

Refers to the total cumulative fair value of additional collateral the reporting entity’s
counterparties will require the reporting entity to post as a result of a change in the reporting
entity’s financial condition, which includes a downgrade of the reporting entity’s rating up to
but not including default. Report figures based on contractual commitments. Collateral
required includes, but is not limited to, collateral called from OTC derivative transactions and
exchanges. Include outflows due to additional termination events, but do not include inflows
from netting sets that are in a net receivable position. Do not double count balances reported
in O.O.12.

### O.O.17: Excess Margin

Refers to the total capacity of the reporting entity’s customer to generate funding for additional
purchases or short sales of securities (i.e., the reporting entity’s obligation to fund client
positions) for the following day based on the net equity in the customer’s margin account. This
capacity can generally be revoked or reduced on demand (i.e., uncommitted).

### O.O.18: Unfunded Term Margin

Refers to any unfunded contractual commitment to lend to a brokerage customer on margin for
a specified duration greater than one day. Report the minimum contractually committed term
that would be in effect upon a customer draw from the margin facility using the O.O.[Maturity
Bucket] field.

### O.O.19: Interest & Dividends Payable

Refers to interest and dividends contractually payable on the reporting entity’s liabilities and
equity. For equity dividends, report a [Collateral Class] of “Y-4”. Do not include payables related
to unsecured derivative transactions, which should be reported under product O.O.1:
Derivatives Payables and which should be included in the calculation of O.O.20: Net 30-day
Derivative Payables. Under circumstances where the interest and dividend payments receivable
are uncertain (e.g., floating rate payment has not yet been set), forecast payables for a
minimum of 30 calendar days beyond the as-of date (T). Exclude interest payable on Covered
Federal Reserve Facility Funding.

### O.O.20: Net 30-Day Derivative Payables

Refers to the net derivative cash outflow amount, as set forth in the LRM Standards.

### O.O.21: Other Outflows Related to Structured Transactions

Refers to any incremental potential outflows under 32(b) of the LRM Standards related to
structured transactions sponsored but not consolidated by the reporting entity that are not
otherwise reported in O.O.4 or O.O.5.


### O.O.22: Other Cash Outflows

Refers to any other material cash outflows not reported in any other line that can impact the
liquidity of the reporting entity. Do not report ‘business as usual’ expenses such as rents,
salaries, utilities and other similar payments. Include cash needs that arise out of an extra-
ordinary situation (e.g., a significant cash flow needed to address a legal suit settlement or
pending transaction). Use the comments table to provide a general description of other
cash outflows included in this product on at least a monthly basis and in the event of a material
change in reported values.
