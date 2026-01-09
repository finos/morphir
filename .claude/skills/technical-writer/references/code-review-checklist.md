# Documentation Code Review Checklist

Use this checklist when reviewing PRs for documentation completeness.

## Public API Documentation

### For New Public Functions/Methods
- [ ] Function has a doc comment explaining its purpose
- [ ] Parameters are documented with their types and meanings
- [ ] Return values are documented
- [ ] Error conditions are documented
- [ ] Example usage is provided for complex APIs

### For New Types
- [ ] Type has a doc comment explaining what it represents
- [ ] Important fields are documented
- [ ] Related types are cross-referenced

### For Breaking Changes
- [ ] Migration guide is provided or updated
- [ ] Changelog entry is added
- [ ] Deprecated APIs are marked and alternatives documented

## User-Facing Features

### For New Features
- [ ] Feature is documented in appropriate user guide
- [ ] Getting started content is updated if applicable
- [ ] Examples demonstrate the feature
- [ ] CLI commands are documented (if applicable)

### For Configuration Options
- [ ] Option is documented with default value
- [ ] Valid values/ranges are specified
- [ ] Example configuration is provided

### For CLI Changes
- [ ] Command help text is clear and accurate
- [ ] Man page or CLI docs are updated
- [ ] Examples show common use cases

## Tutorial Review

### Structure
- [ ] Clear learning objectives stated
- [ ] Prerequisites are listed
- [ ] Logical progression of concepts
- [ ] Summary/next steps at the end

### Content Quality
- [ ] Code examples are complete and runnable
- [ ] Steps are numbered and clear
- [ ] Screenshots are current (if included)
- [ ] Links work and point to correct resources

### Accessibility
- [ ] Images have alt text
- [ ] Code blocks specify language
- [ ] Headings follow proper hierarchy

## General Documentation Quality

### Consistency
- [ ] Follows project style guide
- [ ] Uses consistent terminology
- [ ] Matches tone of existing docs
- [ ] Proper frontmatter (title, sidebar_position)

### Links and References
- [ ] Internal links use relative paths
- [ ] External links are valid
- [ ] No orphaned pages (unreachable content)
- [ ] Table of contents updated if needed

### Technical Accuracy
- [ ] Code examples have been tested
- [ ] Commands produce expected output
- [ ] Version numbers are correct
- [ ] No outdated information

## Review Process

### Before Approving
1. **Read the documentation** as if you were a new user
2. **Try the examples** to verify they work
3. **Check cross-references** to ensure they link correctly
4. **Consider the audience** - is it appropriate for the target section?

### Common Issues to Watch For
- Broken internal links
- Missing frontmatter
- Code blocks without language specification
- Outdated screenshots
- Incomplete instructions
- Assumed knowledge not covered by prerequisites

## Documentation Debt Indicators

Flag these for future improvement:
- [ ] TODO comments in documentation
- [ ] Placeholder content
- [ ] "Coming soon" sections
- [ ] Links to non-existent pages
- [ ] Stale API examples

## PR Description Requirements

Documentation PRs should include:
- Summary of what was added/changed
- Related issue numbers
- Preview link (if available)
- List of pages affected
