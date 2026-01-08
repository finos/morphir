---
id: json-schema-backend-test2
tile: Config. Test plan
sidebar_position: 9
---

# Json SChema Backend Config Test Plan
This document outlines the test plan for the 
Json Schema backend initial configuration processing.

The decision table for a complete test coverage is given below:

| Test Case | Config Flag(s) | Config File | CLI Parameters |
|:---------:|:--------------:|:-----------:|:---------------|
|    #1     |       No       |     No      | No             |
|    #2     |       No       |     No      | Yes            | 
|    #3     |       No       |     Yes     | No             |
|    #4     |       No       |     Yes     | Yes            |
|    #5     |      Yes       |     No      | No             |
|    #6     |      Yes       |     No      | Yes            |
|    #7     |      Yes       |     Yes     | No             |
|    #8     |      Yes       |     Yes     | Yes            |


These would be unit tests of the inferBackendConfig() function defined in
[config-processing.ts](../../../cli2/config-processing.ts)

## Test Cases #5 and #6
In these two test cases, the users intends to use a configuration
file (by providing the flag) but the configuration file does not 
exist. A number of possibilities exists to handle this:
* ensure config file exist before the json-schema-gen command can be run
* build up a config file at this point
* completely ignore the user flag and proceed as in Test Cases #1 to #4 \
For these test cases, we use default configuration but
notify the user of absense of a cofig file


## Test Cases #7 and #8
In these two test cases, the user specifies to use a 
configuration file and the configuration file exist.
At this point, there are three possible routes.
* configuration file exists unmodified by user
* configuration file exists modified by user
* configuration file exists but is invalid \
The first point basically equates to Test cases #1 to #4 \
So for these test cases, we would assume the config file
was modified by the user (second point) \
Further test cases would be written to cover the third
point (invalid config file)