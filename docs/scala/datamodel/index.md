---
id: datamodel
title: Data Model
---

The Morphir data model (MDM) was created to simplify integration between data formats and the Morphir IR. Most data 
formats have no concept of logic, and as such, a significant portion of the Morphir IR is not relevant if your
intention is to provide a front-end or back-end for a data format.

The Morphir data model implements a front-end and back-end to the Morphir IR and allows those integrating data formats
to only have to integrate with MDM, which closer resembles other data format integration activities.
