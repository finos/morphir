@docling @traversal @pending
Feature: Docling Document Traversal
  As a developer
  I want to traverse Docling documents
  So that I can process document items in various ways

  Rule: Visitor pattern traversal

    Scenario: Walking a document tree depth-first
      Given a docling document with the following tree:
        | ref      | type    | parent   |
        | root     | group   |          |
        | section1 | node    | root     |
        | para1    | text    | section1 |
        | para2    | text    | section1 |
      When I walk the tree from "root"
      Then I should visit items in order: root, section1, para1, para2

    Scenario: Walking document body
      Given a docling document with body "root" and the following tree:
        | ref   | type  | parent |
        | root  | group |        |
        | child | text  | root   |
      When I walk the document body
      Then I should visit 2 items

  Rule: Functional filtering

    Scenario: Filtering items by label
      Given a docling document with the following items:
        | ref    | type    |
        | text1  | text    |
        | table1 | table   |
        | text2  | text    |
        | pic1   | picture |
      When I filter by label "text"
      Then the filtered document should have 2 items
      And both items should have label "text"

    Scenario: Collecting items by predicate
      Given a docling document with the following text items:
        | ref   | content      |
        | text1 | Short        |
        | text2 | Long content |
        | text3 | Hi           |
      When I collect items where text length is greater than 5
      Then I should get 1 item
      And that item should be "text2"

  Rule: Functional transformations

    Scenario: Mapping over document items
      Given a docling document with 3 text items
      When I map a function that adds metadata "processed" to all items
      Then all items in the new document should have metadata "processed"
      And the original document items should not have metadata "processed"

    Scenario: Folding document items
      Given a docling document with the following text items:
        | ref   | content |
        | text1 | Hello   |
        | text2 | World   |
        | text3 | Test    |
      When I fold to calculate total text length
      Then the result should be 14

  Rule: Finding and checking

    Scenario: Finding an item by predicate
      Given a docling document with the following items:
        | ref    | type    |
        | text1  | text    |
        | table1 | table   |
        | text2  | text    |
      When I find the first table item
      Then I should get item "table1"

    Scenario: Checking if any item matches
      Given a docling document with the following items:
        | ref    | type    |
        | text1  | text    |
        | text2  | text    |
      When I check if any item is a table
      Then the result should be false

    Scenario: Checking if all items match
      Given a docling document with the following items:
        | ref   | type |
        | text1 | text |
        | text2 | text |
        | text3 | text |
      When I check if all items are text
      Then the result should be true

  Rule: Counting

    Scenario: Counting items by label
      Given a docling document with the following items:
        | ref    | type    |
        | text1  | text    |
        | text2  | text    |
        | text3  | text    |
        | table1 | table   |
      When I count items with label "text"
      Then the count should be 3
