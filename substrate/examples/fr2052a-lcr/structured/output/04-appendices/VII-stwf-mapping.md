# Appendix VII: Short-Term Wholesale Funding (STWF) to FR 2052a Mapping

> Preserved verbatim from the source PDF. Tables in this appendix
> are drawn with positioned text and ruling lines; the fenced block
> below retains the original column alignment.

```
Staff of the Board of Governors of the Federal Reserve System (Board) has developed this document to
assist reporting firms that must file Schedule G or N (STWF Indicator) of the FR Y‐15 (Banking
Organization Systemic Risk Report) in mapping the specific line items on Schedule G or N to the unique
data identifiers reported on the FR 2052a. This mapping document is not a part of any regulation nor a
component of official guidance related to the FR 2052a or FR Y‐15 reports. Firms may use this mapping
document solely at their discretion. From time to time, to ensure accuracy, an updated mapping
document may be published and reporting firms will be notified of these changes.

Key

*    Values relevant to Schedule G or N of the FR Y‐15

#    Values not relevant to Schedule G or N of the FR Y‐15

NULL Should not have an associated value

FR 2052a to FR Y‐15, Schedule G Map

Item 1.a: Funding secured by level 1 liquid assets (sum of tables 1‐3)

   Field                  (1) O.D. PIDs for item 1.a
   Reporting Entity                        Value
   PID                                     FR Y‐15 Firm
   Product                                 O.D.5, 6, 8, 9, 10, 11, 13, 14 ,15
   Counterparty                            Matches PID
                                           Not Retail or Small Business

   G-SIB                                     #
   Maturity Amount                           *
   Maturity Bucket                           Column A: <=30 days
                                             Column B: 31 to 90 days
   Maturity Optionality                      Column C: 91 to 180 days
   Collateral Class                          Column D: 181 days to 1 yr
   Collateral Value                          #
   Insured                                   Level 1 HQLA
   Trigger                                   #
   Rehypothecated                            #
   Business Line                             #
   Internal                                  #
   Internal Counterparty                     #
                                             #
                                             #

                                          1

Field                  (2) O.S. PIDs for item 1.a
Reporting Entity                        Value
PID                                     FR Y‐15 Firm
Product                                 O.S.1, 2, 3, 5, 6, 7 and 11
Sub‐product                             Matches PID
                                        For O.S.7, cannot be Unsettled (Regular Way) or
Maturity Amount                         Unsettled (Forward), # otherwise
Maturity Bucket                         *
                                        Column A: <=30 days
Maturity Optionality                    Column B: 31 to 90 days
Forward Start Amount                    Column C: 91 to 180 days
Forward Start Bucket                    Column D: 181 days to 1 yr
Collateral Class                        #
Collateral Value                        NULL
Treasury Control                        NULL
Internal                                Level 1 HQLA
Internal Counterparty                   #
Risk Weight                             #
Business Line                           #
Settlement                              #
Rehypothecated                          #
Counterparty                            #
                                        #
G-SIB                                   #
                                        Not Retail or Small Business
Field
Reporting Entity                        #
Currency
Converted              (3) O.W. PIDs for item 1.a
PID                                     Value
Product                                 FR Y‐15 Firm
Counterparty                            *
G-SIB                                   #
Maturity Amount                         O.W.1‐7, 9‐19
Maturity Bucket                         Matches PID
                                        #
Maturity Optionality                    #
Collateral Class                        *
Collateral Value                        Column A: <=30 days
                                        Column B: 31 to 90 days
                                        Column C: 91 to 180 days
                                        Column D: 181 days to 1 yr
                                        #
                                        Level 1 HQLA
                                        #

                                     2

Forward Start Amount      NULL
Forward Start Bucket      NULL
Internal                  #
Internal Counterparty     #
Loss Absorbency           #
Business Line             #

Item 1.b: Retail brokered deposits and sweeps (table 4)

Field                  (4) O.D. PIDs for item 1.b
Reporting Entity                        Value
PID                                     FR Y‐15 Firm
Product                                 O.D.8, 9, 10, 11 and 13
Counterparty                            Matches PID
G-SIB                                   Retail or Small Business
Maturity Amount                         #
Maturity Bucket                         *
                                        Column A: <=30 days
Maturity Optionality                    Column B: 31 to 90 days
Collateral Class                        Column C: 91 to 180 days
Collateral Value                        Column D: 181 days to 1 yr
Insured                                 #
Trigger                                 #
Rehypothecated                          #
Business Line                           #
Internal                                #
Internal Counterparty                   #
                                        #
                                        #
                                        #

Item 1.c: Unsecured wholesale funding obtained outside of the financial sector (sum of
tables 5 and 6)

Field                  (5) O.D. PIDs for item 1.c
Reporting Entity                       Value
PID                                    FR Y‐15 Firm
Product                                O.D.5, 6, 8, 9, 10, 11, 13, 14, 15
CID                                    Matches PID
Counterparty                           Matches Counterparty

Maturity Amount                        Non‐Financial Corporate, Sovereign, Central
                                       Bank, GSE, PSE, MDB, Other Supranational, Debt
                                       Issuing SPE, Other
                                       *

                       3

Maturity Bucket                         Column A: <=30 days
                                        Column B: 31 to 90 days
Maturity Optionality                    Column C: 91 to 180 days
Collateral Class                        Column D: 181 days to 1 yr
Collateral Value
Insured                                 #
Trigger                                 NULL or Other
Rehypothecated                          #
Loss Absorbency
Business Line                           #
Internal                                #
Internal Counterparty                   #
                                        #
Field                                   #
Reporting Entity                        #
PID                                     #
Product
Counterparty           (6) O.W. PIDs for item 1.c
                                        Value
G-SIB                                   FR Y‐15 Firm
Maturity Amount                         O.W.9, 10, 17, 18, 19
Maturity Bucket                         Matches PID
                                        Non‐Financial Corporate, Sovereign, Central
Maturity Optionality                    Bank, GSE, PSE, MDB, Other Supranational, Debt
Collateral Class                        Issuing SPE, Other
Collateral Value                        #
Forward Start Amount                    *
Forward Start Bucket                    Column A: <=30 days
Internal                                Column B: 31 to 90 days
Internal Counterparty                   Column C: 91 to 180 days
Loss Absorbency                         Column D: 181 days to 1 yr
Business Line                           #
                                        NULL or Other
Field                                   NULL
Reporting Entity
PID                                     NULL
Product                                 NULL
Sub‐product                             #
                                        #
Maturity Amount                         #
                                        #

                       (7) O.S. PIDs for item 1.c
                                        Value
                                        FR Y‐15 Firm
                                        O.S.1, 2, 3, 5, 6, 7 and 11
                                        Matches PID
                                        For O.S.7, cannot be Unsettled (Regular Way) or
                                        Unsettled (Forward), # otherwise
                                        *

                                     4

Maturity Bucket                             Column A: <=30 days
                                            Column B: 31 to 90 days
Maturity Optionality                        Column C: 91 to 180 days
Forward Start Amount                        Column D: 181 days to 1 yr
Forward Start Bucket                        #
Collateral Class                            NULL
Collateral Value                            NULL
Treasury Control                            Other
Internal                                    #
Internal Counterparty                       #
Risk Weight
Business Line                               #
Settlement                                  #
Rehypothecated                              #
Counterparty                                #
                                            #
G-SIB                                       #
                                            Non‐Financial Corporate, Sovereign, Central
Field                                       Bank, GSE, PSE, MDB, Other Supranational, Debt
Reporting Entity                            Issuing SPE, Other
PID
Product                                     #
Sub‐Product
Maturity Amount            (8) I.S. PIDs for item 1.c
Maturity Bucket                             Value
                                            FR Y‐15 Firm
Maturity Optionality                        I.S.4
Effective Maturity Bucket                   Matches PID
Encumbrance Type                            No Collateral Pledged
Forward Start Amount                        #
Forward Start Bucket                        Column A: <=30 days
Collateral Class                            Column B: 31 to 90 days
Collateral Value                            Column C: 91 to 180 days
Unencumbered                                Column D: 181 days to 1 yr
Treasury Control                            #
Internal                                    #
Internal Counterparty                       #
Risk Weight                                 NULL
Business Line                               NULL
Settlement                                  #
Counterparty                                *
                                            #
                                            #
                                            #
                                            #
                                            #
                                            #
                                            #
                                            Non‐Financial Corporate, Sovereign, Central

                                         5

G-SIB                  Bank, GSE, PSE, MDB, Other Supranational, Debt
                       Issuing SPE, Other
                       #

Item 1.d: Firm short positions involving level 2B liquid assets or non‐HQLA (table 7)

Field                  (9) O.S. PIDs for item 1.d
Reporting Entity                       Value
Currency                               FR Y‐15 Firm
Converted                              *
PID                                    #
Product                                O.S.8
Sub‐Product                            Matches PID
                                       External Cash Transaction, External Non-Cash
Maturity Amount                        Transaction, Customer Longs
Maturity Bucket                        *
                                       #

Maturity Optionality   #
Forward Start Amount   #
Forward Start Bucket   #
Collateral Class       Level 2B HQLA or Non-HQLA
Collateral Value       #
Collateral Currency    #
Treasury Control       #
Internal               #
Internal Counterparty  #
Business Line          #
Settlement             #
Rehypothecated         #
Counterparty           #

G-SIB                  #

Item 2.a: Funding secured by level 2A liquid assets (sum of tables 8‐10)

Field                  (10) O.D. PIDs for item 2.a
Reporting Entity                        Value
PID                                     FR Y‐15 Firm
Product                                 O.D.5, 6, 8, 9, 10, 11, 13, 14, 15
Counterparty                            Matches PID
                                        Not Retail or Small Business
G-SIB                                   #

                                    6

Maturity Amount                        *
Maturity Bucket                        Column A: <=30 days
                                       Column B: 31 to 90 days
Maturity Optionality                   Column C: 91 to 180 days
Collateral Class                       Column D: 181 days to 1 yr
Collateral Value                       #
Insured                                Level 2A HQLA
Trigger                                #
Rehypothecated                         #
Business Line                          #
Internal                               #
Internal Counterparty                  #
                                       #
Field                                  #
Reporting Entity
PID                    (11) O.S. PIDs for item 2.a
Product                                Value
Sub‐Product                            FR Y‐15 Firm
                                       O.S.1, 2, 3, 5, 6, 7 and 11
Maturity Amount                        Matches PID
Maturity Bucket                        For O.S.7, cannot be Unsettled (Regular Way) or
                                       Unsettled (Forward), # otherwise
Maturity Optionality                   *
Forward Start Amount                   Column A: <=30 days
Forward Start Bucket                   Column B: 31 to 90 days
Collateral Class                       Column C: 91 to 180 days
Collateral Value                       Column D: 181 days to 1 yr
Treasury Control                       #
Internal                               NULL
Internal Counterparty                  NULL
Business Line                          Level 2A HQLA
Settlement                             #
Rehypothecated                         #
Counterparty                           #
                                       #
G-SIB                                  #
                                       #
                                       #
                                       Not Retail or Small Business

                                       #

                                    7

Field                  (12) O.W. PIDs for item 2.a
Reporting Entity                         Value
PID                                      FR Y‐15 Firm
Product                                  O.W.1‐7, 9‐19
Counterparty                             Matches PID
G-SIB                                    #
Maturity Amount                          #
Maturity Bucket                          *
                                         Column A: <=30 days
Maturity Optionality                     Column B: 31 to 90 days
Collateral Class                         Column C: 91 to 180 days
Collateral Value                         Column D: 181 days to 1 yr
Forward Start Amount                     #
Forward Start Bucket                     Level 2A HQLA
Internal                                 #
Internal Counterparty
Loss Absorbency                          NULL
Business Line                            NULL
                                         #
                                         #
                                         #
                                         #

Item 2.b: Covered asset exchanges (level 1 to level 2A) (table 11)

Field                  (13) O.S. PIDs for item 2.b
Reporting Entity                        Value
PID                                     FR Y‐15 Firm
Product                                 O.S.4
Sub‐Product                             Matches PID
Maturity Amount                         Level 1 Received
Maturity Bucket                         *
                                        Column A: <=30 days
Maturity Optionality                    Column B: 31 to 90 days
Forward Start Amount                    Column C: 91 to 180 days
Forward Start Bucket                    Column D: 181 days to 1 yr
Collateral Class                        #
Collateral Value                        NULL
Unencumbered                            NULL
Treasury Control                        Level 2A HQLA
Internal                                #
Internal Counterparty                   #
Business Line                           #
Settlement                              #
Rehypothecated                          #
                                        #
                                        #
                                        #

                                     8

Counterparty           #

G-SIB                  #

Item 3.a: Funding secured by level 2B liquid assets (sum of tables 12‐14)

Field                  (14) O.D. PIDs for item 3.a
Reporting Entity                        Value
PID                                     FR Y‐15 Firm
Product                                 O.D.5, 6, 8, 9, 10, 11, 13, 14 and 15
Counterparty                            Matches PID
G-SIB                                   Not Retail or Small Business
Maturity Amount
Maturity Bucket                         #
                                        *
Maturity Optionality                    Column A: <=30 days
Collateral Class                        Column B: 31 to 90 days
Collateral Value                        Column C: 91 to 180 days
Insured                                 Column D: 181 days to 1 yr
Trigger                                 #
Rehypothecated                          Level 2B HQLA
Business Line                           #
Internal                                #
Internal Counterparty                   #
                                        #
                                        #
                                        #
                                        #

Field                  (15) O.S. PIDs for item 3.a
Reporting Entity                        Value
PID                                     FR Y‐15 Firm
Product                                 O.S.1, 2, 3, 5, 6, 7 and 11
Sub‐Product                             Matches PID
                                        For O.S.7, cannot be Unsettled (Regular Way) or
Maturity Amount                         Unsettled (Forward), # otherwise
Maturity Bucket                         *
                                        Column A: <=30 days
Maturity Optionality                    Column B: 31 to 90 days
Forward Start Amount                    Column C: 91 to 180 days
Forward Start Bucket                    Column D: 181 days to 1 yr
Collateral Class                        #
Collateral Value
Treasury Control                        NULL
Internal                                NULL
Internal Counterparty                   Level 2B HQLA
                                        #
                                        #
                                        #
                                        #

                                     9

Business Line              #
Settlement                 #
Rehypothecated             #
Counterparty               Not Retail or Small Business

G-SIB                      #

Field                      (16) O.W. PIDs for item 3.a
Reporting Entity                             Value
PID                                          FR Y‐15 Firm
Product                                      O.W.1‐7, 9‐19
Counterparty                                 Matches PID
G-SIB                                        #
Maturity Amount                              #
Maturity Bucket                              *
                                             Column A: <=30 days
Maturity Optionality                         Column B: 31 to 90 days
Collateral Class                             Column C: 91 to 180 days
Collateral Value                             Column D: 181 days to 1 yr
Forward Start Amount                         #
Forward Start Bucket                         Level 2B HQLA
Internal                                     #
Internal Counterparty                        NULL
Loss Absorbency                              NULL
Business Line                                #
                                             #
                                             #
                                             #

Item 3.b: Other covered asset exchanges (table 15)

Field                      (17) I.S. PIDs for item 3.b
Reporting Entity                            Value
PID                                         FR Y‐15 Firm
Product                                     I.S.4
Sub‐Product                                 Matches PID
Maturity Amount                             Level 2b Pledged, Non-HQLA Pledged
Maturity Bucket                             #
                                            Column A: <=30 days
Maturity Optionality                        Column B: 31 to 90 days
Effective Maturity Bucket                   Column C: 91 to 180 days
Encumbrance Type                            Column D: 181 days to 1 yr
                                            #
                                            #
                                            #

                                         10

Forward Start Amount   NULL
Forward Start Bucket   NULL
Collateral Class       For Sub-Product value of Level 2b Pledged: Level 1
                       or Level 2A HQLA; For Sub-Product values of Non-
Collateral Value       HQLA Pledged: all HQLA
Unencumbered           *
Treasury Control       #
Internal               #
Internal Counterparty  #
Risk Weight            #
Business Line          #
Settlement             #
Counterparty           #
G-SIB                  #
                       #

Item 3.c: Unsecured wholesale funding obtained within the financial sector (sum of tables
16 and 17)

Field                  (18) O.D. PIDs for item 3.c
Reporting Entity                        Value
PID                                     FR Y‐15 Firm
Product                                 O.D.5, 6, 8, 9, 10, 11, 13, 14, 15
Counterparty                            Matches PID
                                        Pension Fund, Bank, Broker-Dealer, Investment
G-SIB                                   Company or Advisor, Financial Market Utility,
Maturity Amount                         Other Supervised Non-Bank Financial Entity, Non-
Maturity Bucket                         Regulated Fund
                                        #
Maturity Optionality                    *
Collateral Class
Collateral Value                        Column A: <=30 days
Insured                                 Column B: 31 to 90 days
Trigger                                 Column C: 91 to 180 days
Rehypothecated                          Column D: 181 days to 1 yr
Business Line
Internal                                #
Internal Counterparty                   NULL or Other
                                        #
                                        #
                                        #
                                        #
                                        #
                                        #
                                        #

Field                  (19) O.W. PIDs for item 3.c
Reporting Entity                         Value
PID                                      FR Y‐15 Firm
                                         O.W.1‐19

                                     11

Product                                Matches PID
Counterparty                           For O.W.1 - 8, 11 ‐ 16: #; For O.W.9, 10, 17, 18, 19:
                                       Pension Fund, Bank, Broker-Dealer, Investment
G-SIB                                  Company or Advisor, Financial Market Utility,
Maturity Amount                        Other Supervised Non-Bank Financial Entity,
Maturity Bucket                        Non-Regulated Fund, or NULL
                                       #
Maturity Optionality                   *
Collateral Class                       Column A: <=30 days
Collateral Value                       Column B: 31 to 90 days
Forward Start Amount                   Column C: 91 to 180 days
Forward Start Bucket                   Column D: 181 days to 1 yr
Internal                               #
Internal Counterparty                  NULL or Other
Loss Absorbency                        #
Business Line                          NULL
                                       NULL
Field                                  #
Reporting Entity                       #
PID                                    #
Product                                #
Sub‐Product
                       (20) O.S. PIDs for item 3.c
Maturity Amount                        Value
Maturity Bucket                        FR Y‐15 Firm
                                       O.S.1, 2, 3, 7 and 11
Maturity Optionality                   Matches PID
Forward Start Amount                   For O.S.7, cannot be Unsettled (Regular Way) or
Forward Start Bucket                   Unsettled (Forward), # otherwise
Collateral Class                       *
Collateral Value                       Column A: <=30 days
Treasury Control                       Column B: 31 to 90 days
Internal                               Column C: 91 to 180 days
Internal Counterparty                  Column D: 181 days to 1 yr
Business Line                          #
Settlement                             NULL
Rehypothecated                         NULL
Counterparty                           Other
                                       #
                                       #
                                       #
                                       #
                                       #
                                       #
                                       #
                                       Pension Fund, Bank, Broker-Dealer, Investment
                                       Company or Advisor, Financial Market Utility,
                                       Other Supervised Non-Bank Financial Entity, Non-

                                    12

G-SIB                                       Regulated Fund
                                            #
Field
Reporting Entity           (21) I.S. PIDs for item 3.c
PID                                         Value
Product                                     FR Y‐15 Firm
Sub‐Product                                 I.S.4
Maturity Amount                             Matches PID
Maturity Bucket                             No Collateral Pledged
                                            #
Maturity Optionality                        Column A: <=30 days
Effective Maturity Bucket                   Column B: 31 to 90 days
Encumbrance Type                            Column C: 91 to 180 days
Forward Start Amount                        Column D: 181 days to 1 yr
Forward Start Bucket                        #
Collateral Class                            #
Collateral Value                            #
Unencumbered                                NULL
Treasury Control                            NULL
Internal                                    #
Internal Counterparty                       *
Risk Weight                                 #
Business Line                               #
Settlement                                  #
Counterparty                                #
                                            #
G-SIB                                       #
                                            #
                                            Pension Fund, Bank, Broker-Dealer, Investment
                                            Company or Advisor, Financial Market Utility,
                                            Other Supervised Non-Bank Financial Entity, Non-
                                            Regulated Fund
                                            #

Item 4: All other components of short‐term wholesale funding (sum of tables 18‐20)

Field                      (22) O.D. PIDs for item 4
Reporting Entity                           Value
PID                                        FR Y‐15 Firm
Product                                    O.D.5, 6, 8, 9, 10, 11, 13, 14, 15
Counterparty                               Matches PID
                                            Not Retail or Small Business

G-SIB                          #

Maturity Amount                *

                           13

Maturity Bucket                         Column A: <=30 days
                                        Column B: 31 to 90 days
Maturity Optionality                    Column C: 91 to 180 days
Collateral Class                        Column D: 181 days to 1 yr
Collateral Value                        #
Insured                                 Non-HQLA
Trigger
Rehypothecated                          #
Business Line                           #
Internal                                #
Internal Counterparty                   #
                                        #
Field                                   #
Reporting Entity
PID                    (23) O.S. PIDs for item 4
Product                                 Value
Sub‐Product                             FR Y‐15 Firm
                                        O.S.1, 2, 5, 6, 7 and 11
Maturity Amount                         Matches PID
Maturity Bucket                         For O.S.7, cannot be Unsettled (Regular Way) or
                                        Unsettled (Forward), # otherwise
Maturity Optionality                    *
Forward Start Amount                    Column A: <=30 days
Forward Start Bucket                    Column B: 31 to 90 days
Collateral Class                        Column C: 91 to 180 days
Collateral Value                        Column D: 181 days to 1 yr
Treasury Control                        #
Internal                                NULL
Internal Counterparty                   NULL
Business Line                           Non-HQLA
Settlement                              #
Rehypothecated                          #
Counterparty                            #
G-SIB                                   #
                                        #
Field                                   #
Reporting Entity                        #
PID                                     Not Retail or Small Business
Product                                 #
Counterparty
Maturity Amount        (24) O.W. PIDs for item 4
                                        Value
                                        FR Y‐15 Firm
                                        O.W.1‐7
                                        Matches PID
                                        #
                                        *

                                    14

Maturity Bucket            Column A: <=30 days
                           Column B: 31 to 90 days
Maturity Optionality       Column C: 91 to 180 days
Collateral Class           Column D: 181 days to 1 yr
Collateral Value           #
Forward Start Amount       Non-HQLA
Forward Start Bucket       #
Internal                   NULL
Internal Counterparty      NULL
Loss Absorbency            #
Business Line              #
                           #
                           #

                       15
```
