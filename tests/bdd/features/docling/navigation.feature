@docling @navigation
Feature: Docling Document Navigation
  As a developer
  I want to navigate document hierarchies
  So that I can access related items efficiently

  Rule: Parent-child navigation

    Scenario: Getting children of an item
      Given a docling document with the following tree:
        | ref      | type  | parent   |
        | root     | group |          |
        | child1   | text  | root     |
        | child2   | text  | root     |
      When I get children of "root"
      Then I should get 2 children
      And the children should be "child1" and "child2"

    Scenario: Getting parent of an item
      Given a docling document with the following tree:
        | ref    | type  | parent |
        | parent | group |        |
        | child  | text  | parent |
      When I get parent of "child"
      Then the parent should be "parent"

    Scenario: Getting parent of root item
      Given a docling document with an item "root" with no parent
      When I get parent of "root"
      Then the parent should be nil

  Rule: Sibling navigation

    Scenario: Getting siblings of an item
      Given a docling document with the following tree:
        | ref      | type  | parent |
        | parent   | group |        |
        | child1   | text  | parent |
        | child2   | text  | parent |
        | child3   | text  | parent |
      When I get siblings of "child2"
      Then I should get 2 siblings
      And the siblings should not include "child2"
      And the siblings should be "child1" and "child3"

  Rule: Descendant navigation

    Scenario: Getting all descendants
      Given a docling document with the following tree:
        | ref      | type  | parent   |
        | root     | group |          |
        | section1 | node  | root     |
        | para1    | text  | section1 |
        | para2    | text  | section1 |
        | section2 | node  | root     |
        | para3    | text  | section2 |
      When I get descendants of "root"
      Then I should get 5 descendants
      And descendants should include "section1", "section2", "para1", "para2", "para3"

  Rule: Ancestor navigation

    Scenario: Getting all ancestors
      Given a docling document with the following tree:
        | ref      | type  | parent   |
        | root     | group |          |
        | section1 | node  | root     |
        | para1    | text  | section1 |
      When I get ancestors of "para1"
      Then I should get 2 ancestors
      And ancestors should be "section1" and "root" in that order

  Rule: Ancestry checking

    Scenario: Checking if item is ancestor of another
      Given a docling document with the following tree:
        | ref      | type  | parent   |
        | root     | group |          |
        | section1 | node  | root     |
        | para1    | text  | section1 |
      When I check if "root" is ancestor of "para1"
      Then the result should be true

    Scenario: Checking non-ancestor relationship
      Given a docling document with the following tree:
        | ref      | type  | parent   |
        | root     | group |          |
        | section1 | node  | root     |
        | para1    | text  | section1 |
      When I check if "para1" is ancestor of "root"
      Then the result should be false
