---
status: accepted
---

# ADR-0006: Keep Morphir observability local by default

Morphir CLI and Desktop enable bounded structured file logging by default beneath Morphir Home and correlate acquisition, activation, launch, and crash events with user-visible operation IDs. Users can locate logs and create an inspectable, sanitized diagnostic bundle from either interface. Metrics, traces, crash dumps, and logs do not leave the machine unless the user explicitly configures an exporter or chooses to share a bundle.

Disabling local logs by default would leave first-use installation and detached Desktop startup failures with too little evidence. Automatic remote reporting would improve aggregate visibility but would create a privacy and governance commitment before Morphir has settled data ownership, consent, retention, and hosting. Local evidence with strict redaction gives users and support engineers a useful failure record without making network telemetry a condition of reliable troubleshooting.
