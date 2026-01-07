@docling @document @pending
Feature: Docling Document Creation and Manipulation
  As a developer
  I want to create and manipulate Docling documents
  So that I can work with document structures in a functional way

  Rule: Documents are immutable

    Scenario: Creating a new document does not affect original
      Given a docling document named "Original"
      When I add metadata "author" with value "Alice" creating a new document
      Then the original document should have no metadata
      And the new document should have metadata "author" with value "Alice"

    Scenario: Adding items creates new document instances
      Given a docling document named "Test"
      When I add a text item with ref "text1" and content "Hello"
      Then the original document should have 0 items
      And the new document should have 1 item

  Rule: Documents can contain multiple item types

    Scenario: Document with various item types
      Given a docling document named "MultiType"
      When I add the following items:
        | ref    | type    | content         |
        | text1  | text    | Hello World     |
        | table1 | table   | 3x4             |
        | pic1   | picture | image/png       |
      Then the document should have 3 items
      And the document should have 1 text item
      And the document should have 1 table item
      And the document should have 1 picture item

  Rule: Documents support hierarchical structure

    Scenario: Creating a document tree
      Given a docling document named "Tree"
      When I create the following hierarchy:
        | ref      | type    | parent   | content    |
        | root     | group   |          |            |
        | section1 | node    | root     |            |
        | para1    | text    | section1 | First      |
        | para2    | text    | section1 | Second     |
      Then item "root" should have 1 child
      And item "section1" should have 2 children
      And item "para1" should have parent "section1"
      And item "para2" should have parent "section1"

  Rule: Documents can have metadata

    Scenario: Adding document metadata
      Given a docling document named "Metadata"
      When I add the following document metadata:
        | key      | value         |
        | author   | John Doe      |
        | version  | 1.0           |
        | language | en            |
      Then the document metadata should contain "author" with value "John Doe"
      And the document metadata should contain "version" with value "1.0"
      And the document metadata should contain "language" with value "en"
