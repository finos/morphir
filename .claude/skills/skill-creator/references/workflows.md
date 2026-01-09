# Workflow Patterns

Use these patterns when skills involve multi-step processes.

## Sequential Workflows

For tasks that follow a linear process, document each step clearly:

```markdown
## PDF Form Filling Workflow

1. **Analyze the form** - Identify all fillable fields and their types
2. **Validate input data** - Ensure all required data is available
3. **Map data to fields** - Match input data to form field names
4. **Fill the form** - Use the appropriate library to populate fields
5. **Verify output** - Confirm all fields are correctly filled
```

## Conditional Workflows

For tasks with branching paths based on context or user input:

```markdown
## Document Processing Workflow

**Creating new content?**
→ Use the document creation workflow in [CREATE.md](CREATE.md)

**Editing existing content?**
→ Use the document editing workflow in [EDIT.md](EDIT.md)

**Extracting information?**
→ Use the extraction workflow in [EXTRACT.md](EXTRACT.md)
```

Provide Claude with an upfront overview of the process structure so it can navigate appropriately.
