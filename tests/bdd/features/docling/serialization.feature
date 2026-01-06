@docling @serialization
Feature: Docling Document Serialization
  As a developer
  I want to serialize and deserialize Docling documents
  So that I can store and exchange document data

  Rule: JSON serialization

    Scenario: Simple document JSON round-trip
      Given a docling document named "Test" with 1 text item
      When I serialize the document to JSON
      And I deserialize the JSON back to a document
      Then the deserialized document should have the same name
      And the deserialized document should have the same number of items

    Scenario: Complex document tree JSON round-trip
      Given a docling document with the following tree:
        | ref      | type  | parent   | content |
        | root     | group |          |         |
        | section1 | node  | root     |         |
        | para1    | text  | section1 | Hello   |
        | para2    | text  | section1 | World   |
      When I serialize the document to JSON
      And I deserialize the JSON back to a document
      Then the deserialized document should maintain the tree structure
      And item "para1" should still have parent "section1"
      And item "root" should still have 1 child

    Scenario: Document with metadata JSON round-trip
      Given a docling document named "Meta" with metadata:
        | key      | value     |
        | author   | Jane Doe  |
        | version  | 1.0       |
      When I serialize the document to JSON
      And I deserialize the JSON back to a document
      Then the deserialized document metadata should contain "author" with value "Jane Doe"
      And the deserialized document metadata should contain "version" with value "1.0"

    Scenario: Document with table item JSON round-trip
      Given a docling document with a table item with 3 rows and 4 columns
      When I serialize the document to JSON
      And I deserialize the JSON back to a document
      Then the deserialized table should have 3 rows
      And the deserialized table should have 4 columns

    Scenario: Document with provenance JSON round-trip
      Given a docling document with a text item having provenance:
        | page | left | top | width | height | char_start | char_end |
        | 1    | 10   | 20  | 100   | 50     | 0          | 10       |
      When I serialize the document to JSON
      And I deserialize the JSON back to a document
      Then the deserialized item should have provenance information
      And the provenance should have correct bounding box coordinates
      And the provenance should have correct character range

  Rule: JSON formatting

    Scenario: JSON with indentation
      Given a docling document with 2 items
      When I serialize the document to JSON with indentation
      Then the JSON should be pretty-printed
      And the JSON should be valid

  Rule: Empty documents

    Scenario: Empty document JSON round-trip
      Given an empty docling document named "Empty"
      When I serialize the document to JSON
      And I deserialize the JSON back to a document
      Then the deserialized document should have 0 items
      And the deserialized document should have the name "Empty"
