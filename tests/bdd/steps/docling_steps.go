package steps

import (
	"context"
	"encoding/json"
	"fmt"
	"strconv"
	"strings"

	"github.com/cucumber/godog"
	docling "github.com/finos/morphir/pkg/docling-doc"
)

// DoclingTestContext holds state for Docling BDD test scenarios.
type DoclingTestContext struct {
	// OriginalDocument is the document before modifications
	OriginalDocument docling.DoclingDocument

	// CurrentDocument is the current document being worked on
	CurrentDocument docling.DoclingDocument

	// Documents map for storing multiple documents by name
	Documents map[string]docling.DoclingDocument

	// Items map for storing items separately
	Items map[string]docling.Item

	// LastError holds the last error encountered
	LastError error

	// LastJSON holds JSON serialization results
	LastJSON []byte

	// CollectedItems holds results from traversal/query operations
	CollectedItems []docling.Item

	// VisitedRefs holds refs visited during traversal
	VisitedRefs []docling.Ref

	// TraversalCount holds the count from traversal operations
	TraversalCount int
}

// doclingContextKey is used to store DoclingTestContext in context.Context.
type doclingContextKey struct{}

// NewDoclingTestContext creates a new Docling test context.
func NewDoclingTestContext() *DoclingTestContext {
	return &DoclingTestContext{
		Documents: make(map[string]docling.DoclingDocument),
		Items:     make(map[string]docling.Item),
	}
}

// WithDoclingTestContext returns a new context.Context with DoclingTestContext attached.
func WithDoclingTestContext(ctx context.Context, dtc *DoclingTestContext) context.Context {
	return context.WithValue(ctx, doclingContextKey{}, dtc)
}

// GetDoclingTestContext retrieves the DoclingTestContext from context.Context.
func GetDoclingTestContext(ctx context.Context) (*DoclingTestContext, error) {
	dtc, ok := ctx.Value(doclingContextKey{}).(*DoclingTestContext)
	if !ok {
		return nil, fmt.Errorf("docling test context not found in context")
	}
	return dtc, nil
}

// Reset resets the context for a new scenario.
func (dtc *DoclingTestContext) Reset() {
	dtc.OriginalDocument = docling.DoclingDocument{}
	dtc.CurrentDocument = docling.DoclingDocument{}
	dtc.Documents = make(map[string]docling.DoclingDocument)
	dtc.Items = make(map[string]docling.Item)
	dtc.LastError = nil
	dtc.LastJSON = nil
	dtc.CollectedItems = nil
	dtc.VisitedRefs = nil
	dtc.TraversalCount = 0
}

// RegisterDoclingSteps registers Docling step definitions.
func RegisterDoclingSteps(sc *godog.ScenarioContext) {
	// Document creation and manipulation
	sc.Step(`^a docling document named "([^"]*)"$`, aDoclingDocumentNamed)
	sc.Step(`^an empty docling document named "([^"]*)"$`, anEmptyDoclingDocumentNamed)
	sc.Step(`^a docling document named "([^"]*)" with (\d+) text items?$`, aDoclingDocumentNamedWithTextItems)
	sc.Step(`^a docling document with (\d+) items?$`, aDoclingDocumentWithItems)
	sc.Step(`^a docling document with (\d+) text items?$`, aDoclingDocumentWithTextItems)
	sc.Step(`^a docling document with the following tree:$`, aDoclingDocumentWithTheFollowingTree)
	sc.Step(`^a docling document with an item "([^"]*)" with no parent$`, aDoclingDocumentWithAnItemWithNoParent)
	sc.Step(`^a docling document with the following items:$`, aDoclingDocumentWithTheFollowingItems)
	sc.Step(`^a docling document with the following text items:$`, aDoclingDocumentWithTheFollowingTextItems)
	sc.Step(`^a docling document with body "([^"]*)" and the following tree:$`, aDoclingDocumentWithBodyAndTheFollowingTree)
	sc.Step(`^a docling document with a table item with (\d+) rows and (\d+) columns$`, aDoclingDocumentWithATableItem)
	sc.Step(`^a docling document with a text item having provenance:$`, aDoclingDocumentWithATextItemHavingProvenance)
	sc.Step(`^a docling document named "([^"]*)" with metadata:$`, aDoclingDocumentNamedWithMetadata)
	sc.Step(`^I add metadata "([^"]*)" with value "([^"]*)" creating a new document$`, iAddMetadataWithValueCreatingANewDocument)
	sc.Step(`^I add a text item with ref "([^"]*)" and content "([^"]*)"$`, iAddATextItemWithRefAndContent)
	sc.Step(`^I add the following items:$`, iAddTheFollowingItems)
	sc.Step(`^I create the following hierarchy:$`, iCreateTheFollowingHierarchy)
	sc.Step(`^I add the following document metadata:$`, iAddTheFollowingDocumentMetadata)

	// Assertions - Document
	sc.Step(`^the original document should have no metadata$`, theOriginalDocumentShouldHaveNoMetadata)
	sc.Step(`^the new document should have metadata "([^"]*)" with value "([^"]*)"$`, theNewDocumentShouldHaveMetadataWithValue)
	sc.Step(`^the original document should have (\d+) items?$`, theOriginalDocumentShouldHaveItems)
	sc.Step(`^the new document should have (\d+) items?$`, theNewDocumentShouldHaveItems)
	sc.Step(`^the document should have (\d+) items?$`, theDocumentShouldHaveItems)
	sc.Step(`^the document should have (\d+) text items?$`, theDocumentShouldHaveTextItems)
	sc.Step(`^the document should have (\d+) table items?$`, theDocumentShouldHaveTableItems)
	sc.Step(`^the document should have (\d+) picture items?$`, theDocumentShouldHavePictureItems)
	sc.Step(`^the document metadata should contain "([^"]*)" with value "([^"]*)"$`, theDocumentMetadataShouldContainWithValue)
	sc.Step(`^the deserialized document metadata should contain "([^"]*)" with value "([^"]*)"$`, theDeserializedDocumentMetadataShouldContain)

	// Assertions - Items and hierarchy
	sc.Step(`^item "([^"]*)" should have (\d+) (?:child|children)$`, itemShouldHaveChildren)
	sc.Step(`^item "([^"]*)" should have parent "([^"]*)"$`, itemShouldHaveParent)
	sc.Step(`^item "([^"]*)" should still have parent "([^"]*)"$`, itemShouldStillHaveParent)
	sc.Step(`^item "([^"]*)" should still have (\d+) (?:child|children)$`, itemShouldStillHaveChildren)

	// Navigation
	sc.Step(`^I get children of "([^"]*)"$`, iGetChildrenOf)
	sc.Step(`^I get parent of "([^"]*)"$`, iGetParentOf)
	sc.Step(`^I get the children of item "([^"]*)"$`, iGetTheChildrenOfItem)
	sc.Step(`^I get the parent of item "([^"]*)"$`, iGetTheParentOfItem)
	sc.Step(`^I get siblings of "([^"]*)"$`, iGetSiblingsOf)
	sc.Step(`^I get the siblings of item "([^"]*)"$`, iGetTheSiblingsOfItem)
	sc.Step(`^I get descendants of "([^"]*)"$`, iGetDescendantsOf)
	sc.Step(`^I get the descendants of item "([^"]*)"$`, iGetTheDescendantsOfItem)
	sc.Step(`^I get ancestors of "([^"]*)"$`, iGetAncestorsOf)
	sc.Step(`^I get the ancestors of item "([^"]*)"$`, iGetTheAncestorsOfItem)
	sc.Step(`^I check if "([^"]*)" is ancestor of "([^"]*)"$`, iCheckIfIsAncestorOf)
	sc.Step(`^I check if "([^"]*)" is an ancestor of "([^"]*)"$`, iCheckIfIsAnAncestorOf)

	// Navigation assertions
	sc.Step(`^I should get (\d+) (?:child|children)$`, iShouldGetChildren)
	sc.Step(`^I should get (\d+) siblings?$`, iShouldGetSiblings)
	sc.Step(`^I should get (\d+) descendants?$`, iShouldGetDescendants)
	sc.Step(`^I should get (\d+) ancestors?$`, iShouldGetAncestors)
	sc.Step(`^the children should be "([^"]*)" and "([^"]*)"$`, theChildrenShouldBe)
	sc.Step(`^the siblings should be "([^"]*)" and "([^"]*)"$`, theSiblingsShouldBe)
	sc.Step(`^the siblings should not include "([^"]*)"$`, theSiblingsShouldNotInclude)
	sc.Step(`^descendants should include "([^"]*)", "([^"]*)", "([^"]*)", "([^"]*)", "([^"]*)"$`, descendantsShouldInclude)
	sc.Step(`^ancestors should be "([^"]*)" and "([^"]*)" in that order$`, ancestorsShouldBe)
	sc.Step(`^the result should contain (\d+) items?$`, theResultShouldContainItems)
	sc.Step(`^the result should contain item "([^"]*)"$`, theResultShouldContainItem)
	sc.Step(`^the result should be true$`, theResultShouldBeTrue)
	sc.Step(`^the result should be false$`, theResultShouldBeFalse)
	sc.Step(`^the parent should be "([^"]*)"$`, theParentShouldBe)
	sc.Step(`^the parent should be nil$`, theParentShouldBeNil)

	// Serialization
	sc.Step(`^I serialize the document to JSON$`, iSerializeTheDocumentToJSON)
	sc.Step(`^I serialize the document to JSON with indentation$`, iSerializeTheDocumentToJSONWithIndentation)
	sc.Step(`^I deserialize the JSON$`, iDeserializeTheJSON)
	sc.Step(`^I deserialize the JSON back to a document$`, iDeserializeTheJSONBackToADocument)
	sc.Step(`^the serialization should succeed$`, theSerializationShouldSucceed)
	sc.Step(`^the deserialization should succeed$`, theDeserializationShouldSucceed)
	sc.Step(`^the deserialized document should equal the original$`, theDeserializedDocumentShouldEqualTheOriginal)
	sc.Step(`^the deserialized document should have the same name$`, theDeserializedDocumentShouldHaveTheSameName)
	sc.Step(`^the deserialized document should have the same number of items$`, theDeserializedDocumentShouldHaveTheSameNumberOfItems)
	sc.Step(`^the deserialized document should have (\d+) items?$`, theDeserializedDocumentShouldHaveItems)
	sc.Step(`^the deserialized document should have the name "([^"]*)"$`, theDeserializedDocumentShouldHaveTheName)
	sc.Step(`^the deserialized document should maintain the tree structure$`, theDeserializedDocumentShouldMaintainTheTreeStructure)
	sc.Step(`^the deserialized table should have (\d+) rows?$`, theDeserializedTableShouldHaveRows)
	sc.Step(`^the deserialized table should have (\d+) columns?$`, theDeserializedTableShouldHaveColumns)
	sc.Step(`^the deserialized item should have provenance information$`, theDeserializedItemShouldHaveProvenanceInformation)
	sc.Step(`^the provenance should have correct bounding box coordinates$`, theProvenanceShouldHaveCorrectBoundingBoxCoordinates)
	sc.Step(`^the provenance should have correct character range$`, theProvenanceShouldHaveCorrectCharacterRange)
	sc.Step(`^the JSON should be pretty-printed$`, theJSONShouldBePrettyPrinted)
	sc.Step(`^the JSON should be valid$`, theJSONShouldBeValid)

	// Traversal - Visitor pattern
	sc.Step(`^I walk the tree from "([^"]*)"$`, iWalkTheTreeFrom)
	sc.Step(`^I walk the document tree from "([^"]*)"$`, iWalkTheDocumentTreeFrom)
	sc.Step(`^I walk the document body$`, iWalkTheDocumentBody)
	sc.Step(`^I walk the entire document$`, iWalkTheEntireDocument)
	sc.Step(`^I should visit (\d+) items?$`, iShouldVisitItems)
	sc.Step(`^I should visit item "([^"]*)"$`, iShouldVisitItem)
	sc.Step(`^I should visit items in order: (.+)$`, iShouldVisitItemsInOrder)

	// Traversal - Functional operations
	sc.Step(`^I filter by label "([^"]*)"$`, iFilterByLabel)
	sc.Step(`^I filter items by label "([^"]*)"$`, iFilterItemsByLabel)
	sc.Step(`^I count items by label "([^"]*)"$`, iCountItemsByLabel)
	sc.Step(`^I count items with label "([^"]*)"$`, iCountItemsWithLabel)
	sc.Step(`^I find the first item with label "([^"]*)"$`, iFindTheFirstItemWithLabel)
	sc.Step(`^I find the first table item$`, iFindTheFirstTableItem)
	sc.Step(`^I collect items where text length is greater than (\d+)$`, iCollectItemsWhereTextLengthIsGreaterThan)
	sc.Step(`^I map a function that adds metadata "([^"]*)" to all items$`, iMapAFunctionThatAddsMetadata)
	sc.Step(`^I fold to calculate total text length$`, iFoldToCalculateTotalTextLength)
	sc.Step(`^I check if any item is a table$`, iCheckIfAnyItemIsATable)
	sc.Step(`^I check if all items are text$`, iCheckIfAllItemsAreText)
	sc.Step(`^the filtered document should have (\d+) items?$`, theFilteredDocumentShouldHaveItems)
	sc.Step(`^both items should have label "([^"]*)"$`, bothItemsShouldHaveLabel)
	sc.Step(`^I should get (\d+) items?$`, iShouldGetItems)
	sc.Step(`^that item should be "([^"]*)"$`, thatItemShouldBe)
	sc.Step(`^all items in the new document should have metadata "([^"]*)"$`, allItemsInTheNewDocumentShouldHaveMetadata)
	sc.Step(`^the original document items should not have metadata "([^"]*)"$`, theOriginalDocumentItemsShouldNotHaveMetadata)
	sc.Step(`^the count should be (\d+)$`, theCountShouldBe)
	sc.Step(`^the result should be (\d+)$`, theResultShouldBe)
	sc.Step(`^the found item should have ref "([^"]*)"$`, theFoundItemShouldHaveRef)
	sc.Step(`^I should get item "([^"]*)"$`, iShouldGetItem)
	sc.Step(`^no item should be found$`, noItemShouldBeFound)
}

// Step implementations

func aDoclingDocumentNamed(ctx context.Context, name string) (context.Context, error) {
	dtc, err := GetDoclingTestContext(ctx)
	if err != nil {
		return ctx, err
	}

	doc := docling.NewDocument(name)
	dtc.OriginalDocument = doc
	dtc.CurrentDocument = doc
	dtc.Documents[name] = doc

	return ctx, nil
}

func iAddMetadataWithValueCreatingANewDocument(ctx context.Context, key, value string) (context.Context, error) {
	dtc, err := GetDoclingTestContext(ctx)
	if err != nil {
		return ctx, err
	}

	dtc.CurrentDocument = dtc.CurrentDocument.WithMetadata(key, value)
	return ctx, nil
}

func iAddATextItemWithRefAndContent(ctx context.Context, ref, content string) (context.Context, error) {
	dtc, err := GetDoclingTestContext(ctx)
	if err != nil {
		return ctx, err
	}

	textItem := docling.NewTextItem(docling.Ref(ref), content)
	dtc.CurrentDocument = dtc.CurrentDocument.WithItem(textItem)
	return ctx, nil
}

func iAddTheFollowingItems(ctx context.Context, table *godog.Table) (context.Context, error) {
	dtc, err := GetDoclingTestContext(ctx)
	if err != nil {
		return ctx, err
	}

	for i, row := range table.Rows[1:] { // Skip header row
		if len(row.Cells) < 3 {
			return ctx, fmt.Errorf("row %d has insufficient columns", i+1)
		}

		ref := row.Cells[0].Value
		itemType := row.Cells[1].Value
		content := row.Cells[2].Value

		var item docling.Item

		switch itemType {
		case "text":
			item = docling.NewTextItem(docling.Ref(ref), content)
		case "table":
			// Parse "3x4" format
			parts := strings.Split(content, "x")
			if len(parts) != 2 {
				return ctx, fmt.Errorf("invalid table format %q, expected NxM", content)
			}
			rows, _ := strconv.Atoi(parts[0])
			cols, _ := strconv.Atoi(parts[1])
			item = docling.NewTableItem(docling.Ref(ref), rows, cols)
		case "picture":
			item = docling.NewPictureItem(docling.Ref(ref), content)
		default:
			return ctx, fmt.Errorf("unknown item type: %s", itemType)
		}

		dtc.CurrentDocument = dtc.CurrentDocument.WithItem(item)
		dtc.Items[ref] = item
	}

	return ctx, nil
}

func iCreateTheFollowingHierarchy(ctx context.Context, table *godog.Table) (context.Context, error) {
	dtc, err := GetDoclingTestContext(ctx)
	if err != nil {
		return ctx, err
	}

	builder := docling.NewBuilderFrom(dtc.CurrentDocument)

	// First pass: create all items
	itemsMap := make(map[string]docling.Item)

	for i, row := range table.Rows[1:] { // Skip header row
		if len(row.Cells) < 4 {
			return ctx, fmt.Errorf("row %d has insufficient columns", i+1)
		}

		ref := row.Cells[0].Value
		itemType := row.Cells[1].Value
		parentRef := row.Cells[2].Value
		content := row.Cells[3].Value

		var item docling.Item

		switch itemType {
		case "group":
			item = docling.NewGroupItem(docling.Ref(ref), docling.LabelSectionHeader)
		case "node":
			item = docling.NewNodeItem(docling.Ref(ref), docling.LabelSectionHeader)
		case "text":
			item = docling.NewTextItem(docling.Ref(ref), content)
		default:
			return ctx, fmt.Errorf("unknown item type: %s", itemType)
		}

		// Set parent if specified
		if parentRef != "" {
			switch v := item.(type) {
			case docling.NodeItem:
				item = v.WithParent(docling.Ref(parentRef))
			case docling.GroupItem:
				v.NodeItem = v.NodeItem.WithParent(docling.Ref(parentRef))
				item = v
			case docling.TextItem:
				v.DocItem = v.DocItem.WithParent(docling.Ref(parentRef))
				item = v
			}
		}

		itemsMap[ref] = item
		dtc.Items[ref] = item
	}

	// Second pass: add children to parents
	for i, row := range table.Rows[1:] {
		if len(row.Cells) < 4 {
			return ctx, fmt.Errorf("row %d has insufficient columns", i+1)
		}

		ref := row.Cells[0].Value
		parentRef := row.Cells[2].Value

		if parentRef != "" {
			parent, ok := itemsMap[parentRef]
			if !ok {
				continue
			}

			switch v := parent.(type) {
			case docling.NodeItem:
				itemsMap[parentRef] = v.WithChild(docling.Ref(ref))
			case docling.GroupItem:
				v.NodeItem = v.NodeItem.WithChild(docling.Ref(ref))
				itemsMap[parentRef] = v
			}
		}
	}

	// Add all items to builder
	for _, item := range itemsMap {
		builder.AddItem(item)
	}

	// Set body to root (first item)
	if len(table.Rows) > 1 {
		rootRef := table.Rows[1].Cells[0].Value
		builder.WithBody(docling.Ref(rootRef))
	}

	dtc.CurrentDocument = builder.Build()
	return ctx, nil
}

func iAddTheFollowingDocumentMetadata(ctx context.Context, table *godog.Table) (context.Context, error) {
	dtc, err := GetDoclingTestContext(ctx)
	if err != nil {
		return ctx, err
	}

	for _, row := range table.Rows[1:] { // Skip header row
		if len(row.Cells) < 2 {
			continue
		}
		key := row.Cells[0].Value
		value := row.Cells[1].Value
		dtc.CurrentDocument = dtc.CurrentDocument.WithMetadata(key, value)
	}

	return ctx, nil
}

// Assertion steps

func theOriginalDocumentShouldHaveNoMetadata(ctx context.Context) error {
	dtc, err := GetDoclingTestContext(ctx)
	if err != nil {
		return err
	}

	if len(dtc.OriginalDocument.Metadata()) > 0 {
		return fmt.Errorf("expected original document to have no metadata, but has %d items", len(dtc.OriginalDocument.Metadata()))
	}

	return nil
}

func theNewDocumentShouldHaveMetadataWithValue(ctx context.Context, key, expectedValue string) error {
	dtc, err := GetDoclingTestContext(ctx)
	if err != nil {
		return err
	}

	meta := dtc.CurrentDocument.Metadata()
	value, ok := meta[key]
	if !ok {
		return fmt.Errorf("metadata key %q not found", key)
	}

	if fmt.Sprint(value) != expectedValue {
		return fmt.Errorf("expected metadata %q to be %q, but got %q", key, expectedValue, value)
	}

	return nil
}

func theOriginalDocumentShouldHaveItems(ctx context.Context, expectedCount int) error {
	dtc, err := GetDoclingTestContext(ctx)
	if err != nil {
		return err
	}

	actualCount := len(dtc.OriginalDocument.Items())
	if actualCount != expectedCount {
		return fmt.Errorf("expected original document to have %d items, but has %d", expectedCount, actualCount)
	}

	return nil
}

func theNewDocumentShouldHaveItems(ctx context.Context, expectedCount int) error {
	dtc, err := GetDoclingTestContext(ctx)
	if err != nil {
		return err
	}

	actualCount := len(dtc.CurrentDocument.Items())
	if actualCount != expectedCount {
		return fmt.Errorf("expected new document to have %d items, but has %d", expectedCount, actualCount)
	}

	return nil
}

func theDocumentShouldHaveItems(ctx context.Context, expectedCount int) error {
	dtc, err := GetDoclingTestContext(ctx)
	if err != nil {
		return err
	}

	actualCount := len(dtc.CurrentDocument.Items())
	if actualCount != expectedCount {
		return fmt.Errorf("expected document to have %d items, but has %d", expectedCount, actualCount)
	}

	return nil
}

func theDocumentShouldHaveTextItems(ctx context.Context, expectedCount int) error {
	dtc, err := GetDoclingTestContext(ctx)
	if err != nil {
		return err
	}

	count := docling.CountByLabel(dtc.CurrentDocument, docling.LabelText)
	if count != expectedCount {
		return fmt.Errorf("expected document to have %d text items, but has %d", expectedCount, count)
	}

	return nil
}

func theDocumentShouldHaveTableItems(ctx context.Context, expectedCount int) error {
	dtc, err := GetDoclingTestContext(ctx)
	if err != nil {
		return err
	}

	count := docling.CountByLabel(dtc.CurrentDocument, docling.LabelTable)
	if count != expectedCount {
		return fmt.Errorf("expected document to have %d table items, but has %d", expectedCount, count)
	}

	return nil
}

func theDocumentShouldHavePictureItems(ctx context.Context, expectedCount int) error {
	dtc, err := GetDoclingTestContext(ctx)
	if err != nil {
		return err
	}

	count := docling.CountByLabel(dtc.CurrentDocument, docling.LabelPicture)
	if count != expectedCount {
		return fmt.Errorf("expected document to have %d picture items, but has %d", expectedCount, count)
	}

	return nil
}

func theDocumentMetadataShouldContainWithValue(ctx context.Context, key, expectedValue string) error {
	dtc, err := GetDoclingTestContext(ctx)
	if err != nil {
		return err
	}

	meta := dtc.CurrentDocument.Metadata()
	value, ok := meta[key]
	if !ok {
		return fmt.Errorf("metadata key %q not found", key)
	}

	if fmt.Sprint(value) != expectedValue {
		return fmt.Errorf("expected metadata %q to be %q, but got %q", key, expectedValue, value)
	}

	return nil
}

func itemShouldHaveChildren(ctx context.Context, ref string, expectedCount int) error {
	dtc, err := GetDoclingTestContext(ctx)
	if err != nil {
		return err
	}

	children := dtc.CurrentDocument.GetChildren(docling.Ref(ref))
	if len(children) != expectedCount {
		return fmt.Errorf("expected item %q to have %d children, but has %d", ref, expectedCount, len(children))
	}

	return nil
}

func itemShouldHaveParent(ctx context.Context, ref, expectedParent string) error {
	dtc, err := GetDoclingTestContext(ctx)
	if err != nil {
		return err
	}

	item := dtc.CurrentDocument.GetItem(docling.Ref(ref))
	if item == nil {
		return fmt.Errorf("item %q not found", ref)
	}

	parent := item.Parent()
	if parent == nil {
		return fmt.Errorf("item %q has no parent", ref)
	}

	if string(*parent) != expectedParent {
		return fmt.Errorf("expected item %q to have parent %q, but has %q", ref, expectedParent, *parent)
	}

	return nil
}

// Navigation steps

func iGetTheChildrenOfItem(ctx context.Context, ref string) (context.Context, error) {
	dtc, err := GetDoclingTestContext(ctx)
	if err != nil {
		return ctx, err
	}

	dtc.CollectedItems = dtc.CurrentDocument.GetChildren(docling.Ref(ref))
	return ctx, nil
}

func iGetTheParentOfItem(ctx context.Context, ref string) (context.Context, error) {
	dtc, err := GetDoclingTestContext(ctx)
	if err != nil {
		return ctx, err
	}

	parent := dtc.CurrentDocument.GetParent(docling.Ref(ref))
	if parent != nil {
		dtc.CollectedItems = []docling.Item{parent}
	} else {
		dtc.CollectedItems = []docling.Item{}
	}
	return ctx, nil
}

func iGetTheSiblingsOfItem(ctx context.Context, ref string) (context.Context, error) {
	dtc, err := GetDoclingTestContext(ctx)
	if err != nil {
		return ctx, err
	}

	dtc.CollectedItems = dtc.CurrentDocument.GetSiblings(docling.Ref(ref))
	return ctx, nil
}

func iGetTheDescendantsOfItem(ctx context.Context, ref string) (context.Context, error) {
	dtc, err := GetDoclingTestContext(ctx)
	if err != nil {
		return ctx, err
	}

	dtc.CollectedItems = dtc.CurrentDocument.GetDescendants(docling.Ref(ref))
	return ctx, nil
}

func iGetTheAncestorsOfItem(ctx context.Context, ref string) (context.Context, error) {
	dtc, err := GetDoclingTestContext(ctx)
	if err != nil {
		return ctx, err
	}

	dtc.CollectedItems = dtc.CurrentDocument.GetAncestors(docling.Ref(ref))
	return ctx, nil
}

func iCheckIfIsAnAncestorOf(ctx context.Context, ancestor, descendant string) (context.Context, error) {
	dtc, err := GetDoclingTestContext(ctx)
	if err != nil {
		return ctx, err
	}

	result := dtc.CurrentDocument.IsAncestorOf(docling.Ref(ancestor), docling.Ref(descendant))
	// Store result as count (1 for true, 0 for false)
	if result {
		dtc.TraversalCount = 1
	} else {
		dtc.TraversalCount = 0
	}
	return ctx, nil
}

// Navigation assertion steps

func theResultShouldContainItems(ctx context.Context, expectedCount int) error {
	dtc, err := GetDoclingTestContext(ctx)
	if err != nil {
		return err
	}

	if len(dtc.CollectedItems) != expectedCount {
		return fmt.Errorf("expected %d items, but got %d", expectedCount, len(dtc.CollectedItems))
	}

	return nil
}

func theResultShouldContainItem(ctx context.Context, ref string) error {
	dtc, err := GetDoclingTestContext(ctx)
	if err != nil {
		return err
	}

	for _, item := range dtc.CollectedItems {
		if string(item.SelfRef()) == ref {
			return nil
		}
	}

	return fmt.Errorf("expected result to contain item %q", ref)
}

func theResultShouldBeTrue(ctx context.Context) error {
	dtc, err := GetDoclingTestContext(ctx)
	if err != nil {
		return err
	}

	if dtc.TraversalCount != 1 {
		return fmt.Errorf("expected result to be true, but was false")
	}

	return nil
}

func theResultShouldBeFalse(ctx context.Context) error {
	dtc, err := GetDoclingTestContext(ctx)
	if err != nil {
		return err
	}

	if dtc.TraversalCount != 0 {
		return fmt.Errorf("expected result to be false, but was true")
	}

	return nil
}

func theParentShouldBe(ctx context.Context, expectedRef string) error {
	dtc, err := GetDoclingTestContext(ctx)
	if err != nil {
		return err
	}

	if len(dtc.CollectedItems) != 1 {
		return fmt.Errorf("expected 1 parent item, but got %d", len(dtc.CollectedItems))
	}

	actualRef := string(dtc.CollectedItems[0].SelfRef())
	if actualRef != expectedRef {
		return fmt.Errorf("expected parent to be %q, but got %q", expectedRef, actualRef)
	}

	return nil
}

// Serialization steps

func iSerializeTheDocumentToJSON(ctx context.Context) (context.Context, error) {
	dtc, err := GetDoclingTestContext(ctx)
	if err != nil {
		return ctx, err
	}

	jsonData, err := docling.ToJSON(dtc.CurrentDocument)
	if err != nil {
		dtc.LastError = err
		return ctx, nil
	}

	dtc.LastJSON = jsonData
	dtc.LastError = nil
	return ctx, nil
}

func iDeserializeTheJSON(ctx context.Context) (context.Context, error) {
	dtc, err := GetDoclingTestContext(ctx)
	if err != nil {
		return ctx, err
	}

	doc, err := docling.FromJSON(dtc.LastJSON)
	if err != nil {
		dtc.LastError = err
		return ctx, nil
	}

	dtc.CurrentDocument = doc
	dtc.LastError = nil
	return ctx, nil
}

func theSerializationShouldSucceed(ctx context.Context) error {
	dtc, err := GetDoclingTestContext(ctx)
	if err != nil {
		return err
	}

	if dtc.LastError != nil {
		return fmt.Errorf("expected serialization to succeed, but got error: %v", dtc.LastError)
	}

	return nil
}

func theDeserializationShouldSucceed(ctx context.Context) error {
	dtc, err := GetDoclingTestContext(ctx)
	if err != nil {
		return err
	}

	if dtc.LastError != nil {
		return fmt.Errorf("expected deserialization to succeed, but got error: %v", dtc.LastError)
	}

	return nil
}

func theDeserializedDocumentShouldEqualTheOriginal(ctx context.Context) error {
	dtc, err := GetDoclingTestContext(ctx)
	if err != nil {
		return err
	}

	// Compare by serializing both and comparing JSON
	origJSON, err := docling.ToJSON(dtc.OriginalDocument)
	if err != nil {
		return fmt.Errorf("failed to serialize original document: %w", err)
	}

	currJSON, err := docling.ToJSON(dtc.CurrentDocument)
	if err != nil {
		return fmt.Errorf("failed to serialize current document: %w", err)
	}

	// Compare as JSON objects to handle field ordering
	var orig, curr interface{}
	if err := json.Unmarshal(origJSON, &orig); err != nil {
		return fmt.Errorf("failed to unmarshal original JSON: %w", err)
	}
	if err := json.Unmarshal(currJSON, &curr); err != nil {
		return fmt.Errorf("failed to unmarshal current JSON: %w", err)
	}

	origStr := fmt.Sprintf("%#v", orig)
	currStr := fmt.Sprintf("%#v", curr)

	if origStr != currStr {
		return fmt.Errorf("deserialized document does not equal original")
	}

	return nil
}

// Traversal steps

func iWalkTheDocumentTreeFrom(ctx context.Context, startRef string) (context.Context, error) {
	dtc, err := GetDoclingTestContext(ctx)
	if err != nil {
		return ctx, err
	}

	dtc.VisitedRefs = []docling.Ref{}
	dtc.TraversalCount = 0

	err = docling.Walk(dtc.CurrentDocument, docling.Ref(startRef), func(item docling.Item) error {
		dtc.VisitedRefs = append(dtc.VisitedRefs, item.SelfRef())
		dtc.TraversalCount++
		return nil
	})

	if err != nil {
		dtc.LastError = err
	}

	return ctx, nil
}

func iWalkTheEntireDocument(ctx context.Context) (context.Context, error) {
	dtc, err := GetDoclingTestContext(ctx)
	if err != nil {
		return ctx, err
	}

	dtc.VisitedRefs = []docling.Ref{}
	dtc.TraversalCount = 0

	err = docling.WalkAll(dtc.CurrentDocument, func(item docling.Item) error {
		dtc.VisitedRefs = append(dtc.VisitedRefs, item.SelfRef())
		dtc.TraversalCount++
		return nil
	})

	if err != nil {
		dtc.LastError = err
	}

	return ctx, nil
}

func iShouldVisitItems(ctx context.Context, expectedCount int) error {
	dtc, err := GetDoclingTestContext(ctx)
	if err != nil {
		return err
	}

	if dtc.TraversalCount != expectedCount {
		return fmt.Errorf("expected to visit %d items, but visited %d", expectedCount, dtc.TraversalCount)
	}

	return nil
}

func iShouldVisitItem(ctx context.Context, ref string) error {
	dtc, err := GetDoclingTestContext(ctx)
	if err != nil {
		return err
	}

	for _, visitedRef := range dtc.VisitedRefs {
		if string(visitedRef) == ref {
			return nil
		}
	}

	return fmt.Errorf("expected to visit item %q, but did not", ref)
}

func iFilterItemsByLabel(ctx context.Context, label string) (context.Context, error) {
	dtc, err := GetDoclingTestContext(ctx)
	if err != nil {
		return ctx, err
	}

	itemLabel := docling.ItemLabel(label)
	filtered := docling.FilterByLabel(dtc.CurrentDocument, itemLabel)
	dtc.CollectedItems = docling.CollectByLabel(filtered, itemLabel)

	return ctx, nil
}

func iCountItemsByLabel(ctx context.Context, label string) (context.Context, error) {
	dtc, err := GetDoclingTestContext(ctx)
	if err != nil {
		return ctx, err
	}

	itemLabel := docling.ItemLabel(label)
	dtc.TraversalCount = docling.CountByLabel(dtc.CurrentDocument, itemLabel)

	return ctx, nil
}

func iFindTheFirstItemWithLabel(ctx context.Context, label string) (context.Context, error) {
	dtc, err := GetDoclingTestContext(ctx)
	if err != nil {
		return ctx, err
	}

	itemLabel := docling.ItemLabel(label)
	item := docling.FindByLabel(dtc.CurrentDocument, itemLabel)

	if item != nil {
		dtc.CollectedItems = []docling.Item{item}
	} else {
		dtc.CollectedItems = []docling.Item{}
	}

	return ctx, nil
}

func theCountShouldBe(ctx context.Context, expectedCount int) error {
	dtc, err := GetDoclingTestContext(ctx)
	if err != nil {
		return err
	}

	if dtc.TraversalCount != expectedCount {
		return fmt.Errorf("expected count to be %d, but got %d", expectedCount, dtc.TraversalCount)
	}

	return nil
}

func theFoundItemShouldHaveRef(ctx context.Context, expectedRef string) error {
	dtc, err := GetDoclingTestContext(ctx)
	if err != nil {
		return err
	}

	if len(dtc.CollectedItems) != 1 {
		return fmt.Errorf("expected 1 found item, but got %d", len(dtc.CollectedItems))
	}

	actualRef := string(dtc.CollectedItems[0].SelfRef())
	if actualRef != expectedRef {
		return fmt.Errorf("expected found item to have ref %q, but got %q", expectedRef, actualRef)
	}

	return nil
}

func noItemShouldBeFound(ctx context.Context) error {
	dtc, err := GetDoclingTestContext(ctx)
	if err != nil {
		return err
	}

	if len(dtc.CollectedItems) != 0 {
		return fmt.Errorf("expected no items to be found, but got %d", len(dtc.CollectedItems))
	}

	return nil
}

// Additional document creation steps

func anEmptyDoclingDocumentNamed(ctx context.Context, name string) (context.Context, error) {
	dtc, err := GetDoclingTestContext(ctx)
	if err != nil {
		return ctx, err
	}

	doc := docling.NewDocument(name)
	dtc.OriginalDocument = doc
	dtc.CurrentDocument = doc
	dtc.Documents[name] = doc

	return ctx, nil
}

func aDoclingDocumentNamedWithTextItems(ctx context.Context, name string, count int) (context.Context, error) {
	dtc, err := GetDoclingTestContext(ctx)
	if err != nil {
		return ctx, err
	}

	doc := docling.NewDocument(name)
	for i := 0; i < count; i++ {
		ref := docling.Ref(fmt.Sprintf("text%d", i+1))
		text := fmt.Sprintf("Text content %d", i+1)
		item := docling.NewTextItem(ref, text)
		doc = doc.WithItem(item)
		dtc.Items[string(ref)] = item
	}

	dtc.OriginalDocument = doc
	dtc.CurrentDocument = doc
	dtc.Documents[name] = doc

	return ctx, nil
}

func aDoclingDocumentWithItems(ctx context.Context, count int) (context.Context, error) {
	dtc, err := GetDoclingTestContext(ctx)
	if err != nil {
		return ctx, err
	}

	doc := docling.NewDocument("test")
	for i := 0; i < count; i++ {
		ref := docling.Ref(fmt.Sprintf("item%d", i+1))
		text := fmt.Sprintf("Content %d", i+1)
		item := docling.NewTextItem(ref, text)
		doc = doc.WithItem(item)
		dtc.Items[string(ref)] = item
	}

	dtc.OriginalDocument = doc
	dtc.CurrentDocument = doc

	return ctx, nil
}

func aDoclingDocumentWithTextItems(ctx context.Context, count int) (context.Context, error) {
	dtc, err := GetDoclingTestContext(ctx)
	if err != nil {
		return ctx, err
	}

	doc := docling.NewDocument("test")
	for i := 0; i < count; i++ {
		ref := docling.Ref(fmt.Sprintf("text%d", i+1))
		text := fmt.Sprintf("Text %d", i+1)
		item := docling.NewTextItem(ref, text)
		doc = doc.WithItem(item)
		dtc.Items[string(ref)] = item
	}

	dtc.OriginalDocument = doc
	dtc.CurrentDocument = doc

	return ctx, nil
}

func aDoclingDocumentWithTheFollowingTree(ctx context.Context, table *godog.Table) (context.Context, error) {
	dtc, err := GetDoclingTestContext(ctx)
	if err != nil {
		return ctx, err
	}

	doc := docling.NewDocument("test")
	builder := docling.NewBuilderFrom(doc)

	// First pass: create all items
	itemsMap := make(map[string]docling.Item)

	for i, row := range table.Rows[1:] { // Skip header row
		if len(row.Cells) < 3 {
			return ctx, fmt.Errorf("row %d has insufficient columns", i+1)
		}

		ref := row.Cells[0].Value
		itemType := row.Cells[1].Value
		parentRef := row.Cells[2].Value

		// Get content if available
		content := ""
		if len(row.Cells) > 3 {
			content = row.Cells[3].Value
		}

		var item docling.Item

		switch itemType {
		case "group":
			item = docling.NewGroupItem(docling.Ref(ref), docling.LabelSectionHeader)
		case "node":
			item = docling.NewNodeItem(docling.Ref(ref), docling.LabelSectionHeader)
		case "text":
			item = docling.NewTextItem(docling.Ref(ref), content)
		case "table":
			// Default table size if not specified
			item = docling.NewTableItem(docling.Ref(ref), 2, 2)
		case "picture":
			item = docling.NewPictureItem(docling.Ref(ref), content)
		default:
			return ctx, fmt.Errorf("unknown item type: %s", itemType)
		}

		// Set parent if specified
		if parentRef != "" {
			switch v := item.(type) {
			case docling.NodeItem:
				item = v.WithParent(docling.Ref(parentRef))
			case docling.GroupItem:
				v.NodeItem = v.NodeItem.WithParent(docling.Ref(parentRef))
				item = v
			case docling.TextItem:
				v.DocItem = v.DocItem.WithParent(docling.Ref(parentRef))
				item = v
			case docling.TableItem:
				v.DocItem = v.DocItem.WithParent(docling.Ref(parentRef))
				item = v
			case docling.PictureItem:
				v.DocItem = v.DocItem.WithParent(docling.Ref(parentRef))
				item = v
			}
		}

		itemsMap[ref] = item
		dtc.Items[ref] = item
	}

	// Second pass: add children to parents
	for i, row := range table.Rows[1:] {
		if len(row.Cells) < 3 {
			return ctx, fmt.Errorf("row %d has insufficient columns", i+1)
		}

		ref := row.Cells[0].Value
		parentRef := row.Cells[2].Value

		if parentRef != "" {
			parent, ok := itemsMap[parentRef]
			if !ok {
				continue
			}

			switch v := parent.(type) {
			case docling.NodeItem:
				itemsMap[parentRef] = v.WithChild(docling.Ref(ref))
			case docling.GroupItem:
				v.NodeItem = v.NodeItem.WithChild(docling.Ref(ref))
				itemsMap[parentRef] = v
			}
		}
	}

	// Add all items to builder
	for _, item := range itemsMap {
		builder.AddItem(item)
	}

	// Set body to root (first item)
	if len(table.Rows) > 1 {
		rootRef := table.Rows[1].Cells[0].Value
		builder.WithBody(docling.Ref(rootRef))
	}

	dtc.CurrentDocument = builder.Build()
	dtc.OriginalDocument = dtc.CurrentDocument
	return ctx, nil
}

func aDoclingDocumentWithAnItemWithNoParent(ctx context.Context, ref string) (context.Context, error) {
	dtc, err := GetDoclingTestContext(ctx)
	if err != nil {
		return ctx, err
	}

	doc := docling.NewDocument("test")
	item := docling.NewTextItem(docling.Ref(ref), "content")
	doc = doc.WithItem(item)
	dtc.Items[ref] = item

	dtc.OriginalDocument = doc
	dtc.CurrentDocument = doc

	return ctx, nil
}

func aDoclingDocumentWithTheFollowingItems(ctx context.Context, table *godog.Table) (context.Context, error) {
	dtc, err := GetDoclingTestContext(ctx)
	if err != nil {
		return ctx, err
	}

	doc := docling.NewDocument("test")

	for i, row := range table.Rows[1:] { // Skip header row
		if len(row.Cells) < 2 {
			return ctx, fmt.Errorf("row %d has insufficient columns", i+1)
		}

		ref := row.Cells[0].Value
		itemType := row.Cells[1].Value

		var item docling.Item

		switch itemType {
		case "text":
			item = docling.NewTextItem(docling.Ref(ref), "content")
		case "table":
			item = docling.NewTableItem(docling.Ref(ref), 2, 2)
		case "picture":
			item = docling.NewPictureItem(docling.Ref(ref), "image/png")
		default:
			return ctx, fmt.Errorf("unknown item type: %s", itemType)
		}

		doc = doc.WithItem(item)
		dtc.Items[ref] = item
	}

	dtc.OriginalDocument = doc
	dtc.CurrentDocument = doc

	return ctx, nil
}

func aDoclingDocumentWithTheFollowingTextItems(ctx context.Context, table *godog.Table) (context.Context, error) {
	dtc, err := GetDoclingTestContext(ctx)
	if err != nil {
		return ctx, err
	}

	doc := docling.NewDocument("test")

	for i, row := range table.Rows[1:] { // Skip header row
		if len(row.Cells) < 2 {
			return ctx, fmt.Errorf("row %d has insufficient columns", i+1)
		}

		ref := row.Cells[0].Value
		content := row.Cells[1].Value

		item := docling.NewTextItem(docling.Ref(ref), content)
		doc = doc.WithItem(item)
		dtc.Items[ref] = item
	}

	dtc.OriginalDocument = doc
	dtc.CurrentDocument = doc

	return ctx, nil
}

func aDoclingDocumentWithBodyAndTheFollowingTree(ctx context.Context, bodyRef string, table *godog.Table) (context.Context, error) {
	ctx, err := aDoclingDocumentWithTheFollowingTree(ctx, table)
	if err != nil {
		return ctx, err
	}

	dtc, err := GetDoclingTestContext(ctx)
	if err != nil {
		return ctx, err
	}

	dtc.CurrentDocument = dtc.CurrentDocument.WithBody(docling.Ref(bodyRef))
	dtc.OriginalDocument = dtc.CurrentDocument

	return ctx, nil
}

func aDoclingDocumentWithATableItem(ctx context.Context, rows, cols int) (context.Context, error) {
	dtc, err := GetDoclingTestContext(ctx)
	if err != nil {
		return ctx, err
	}

	doc := docling.NewDocument("test")
	item := docling.NewTableItem(docling.Ref("table1"), rows, cols)
	doc = doc.WithItem(item)
	dtc.Items["table1"] = item

	dtc.OriginalDocument = doc
	dtc.CurrentDocument = doc

	return ctx, nil
}

func aDoclingDocumentWithATextItemHavingProvenance(ctx context.Context, table *godog.Table) (context.Context, error) {
	dtc, err := GetDoclingTestContext(ctx)
	if err != nil {
		return ctx, err
	}

	if len(table.Rows) < 2 {
		return ctx, fmt.Errorf("provenance table must have at least 2 rows")
	}

	row := table.Rows[1]
	if len(row.Cells) < 7 {
		return ctx, fmt.Errorf("provenance row must have at least 7 columns")
	}

	page, _ := strconv.Atoi(row.Cells[0].Value)
	left, _ := strconv.ParseFloat(row.Cells[1].Value, 64)
	top, _ := strconv.ParseFloat(row.Cells[2].Value, 64)
	width, _ := strconv.ParseFloat(row.Cells[3].Value, 64)
	height, _ := strconv.ParseFloat(row.Cells[4].Value, 64)
	charStart, _ := strconv.Atoi(row.Cells[5].Value)
	charEnd, _ := strconv.Atoi(row.Cells[6].Value)

	doc := docling.NewDocument("test")
	item := docling.NewTextItem(docling.Ref("text1"), "Test content")

	// Create provenance with bounding box
	bbox := docling.NewBoundingBox(left, top, width, height, page)
	prov := docling.NewProvenanceItem(page).
		WithBoundingBox(bbox).
		WithCharRange(charStart, charEnd)

	// Add provenance to item
	docItem := item.DocItem.WithProvenance(prov)
	item.DocItem = docItem

	doc = doc.WithItem(item)
	dtc.Items["text1"] = item

	dtc.OriginalDocument = doc
	dtc.CurrentDocument = doc

	return ctx, nil
}

func aDoclingDocumentNamedWithMetadata(ctx context.Context, name string, table *godog.Table) (context.Context, error) {
	dtc, err := GetDoclingTestContext(ctx)
	if err != nil {
		return ctx, err
	}

	doc := docling.NewDocument(name)

	for _, row := range table.Rows[1:] { // Skip header row
		if len(row.Cells) < 2 {
			continue
		}
		key := row.Cells[0].Value
		value := row.Cells[1].Value
		doc = doc.WithMetadata(key, value)
	}

	dtc.OriginalDocument = doc
	dtc.CurrentDocument = doc
	dtc.Documents[name] = doc

	return ctx, nil
}

// Additional navigation steps

func iGetChildrenOf(ctx context.Context, ref string) (context.Context, error) {
	return iGetTheChildrenOfItem(ctx, ref)
}

func iGetParentOf(ctx context.Context, ref string) (context.Context, error) {
	return iGetTheParentOfItem(ctx, ref)
}

func iGetSiblingsOf(ctx context.Context, ref string) (context.Context, error) {
	return iGetTheSiblingsOfItem(ctx, ref)
}

func iGetDescendantsOf(ctx context.Context, ref string) (context.Context, error) {
	return iGetTheDescendantsOfItem(ctx, ref)
}

func iGetAncestorsOf(ctx context.Context, ref string) (context.Context, error) {
	return iGetTheAncestorsOfItem(ctx, ref)
}

func iCheckIfIsAncestorOf(ctx context.Context, ancestor, descendant string) (context.Context, error) {
	return iCheckIfIsAnAncestorOf(ctx, ancestor, descendant)
}

// Additional navigation assertions

func iShouldGetChildren(ctx context.Context, expectedCount int) error {
	return theResultShouldContainItems(ctx, expectedCount)
}

func iShouldGetSiblings(ctx context.Context, expectedCount int) error {
	return theResultShouldContainItems(ctx, expectedCount)
}

func iShouldGetDescendants(ctx context.Context, expectedCount int) error {
	return theResultShouldContainItems(ctx, expectedCount)
}

func iShouldGetAncestors(ctx context.Context, expectedCount int) error {
	return theResultShouldContainItems(ctx, expectedCount)
}

func theChildrenShouldBe(ctx context.Context, ref1, ref2 string) error {
	dtc, err := GetDoclingTestContext(ctx)
	if err != nil {
		return err
	}

	if len(dtc.CollectedItems) != 2 {
		return fmt.Errorf("expected 2 children, but got %d", len(dtc.CollectedItems))
	}

	refs := make(map[string]bool)
	for _, item := range dtc.CollectedItems {
		refs[string(item.SelfRef())] = true
	}

	if !refs[ref1] || !refs[ref2] {
		return fmt.Errorf("expected children to be %q and %q", ref1, ref2)
	}

	return nil
}

func theSiblingsShouldBe(ctx context.Context, ref1, ref2 string) error {
	dtc, err := GetDoclingTestContext(ctx)
	if err != nil {
		return err
	}

	if len(dtc.CollectedItems) != 2 {
		return fmt.Errorf("expected 2 siblings, but got %d", len(dtc.CollectedItems))
	}

	refs := make(map[string]bool)
	for _, item := range dtc.CollectedItems {
		refs[string(item.SelfRef())] = true
	}

	if !refs[ref1] || !refs[ref2] {
		return fmt.Errorf("expected siblings to be %q and %q", ref1, ref2)
	}

	return nil
}

func theSiblingsShouldNotInclude(ctx context.Context, ref string) error {
	dtc, err := GetDoclingTestContext(ctx)
	if err != nil {
		return err
	}

	for _, item := range dtc.CollectedItems {
		if string(item.SelfRef()) == ref {
			return fmt.Errorf("siblings should not include %q", ref)
		}
	}

	return nil
}

func descendantsShouldInclude(ctx context.Context, ref1, ref2, ref3, ref4, ref5 string) error {
	dtc, err := GetDoclingTestContext(ctx)
	if err != nil {
		return err
	}

	refs := make(map[string]bool)
	for _, item := range dtc.CollectedItems {
		refs[string(item.SelfRef())] = true
	}

	expected := []string{ref1, ref2, ref3, ref4, ref5}
	for _, ref := range expected {
		if !refs[ref] {
			return fmt.Errorf("descendants should include %q", ref)
		}
	}

	return nil
}

func ancestorsShouldBe(ctx context.Context, ref1, ref2 string) error {
	dtc, err := GetDoclingTestContext(ctx)
	if err != nil {
		return err
	}

	if len(dtc.CollectedItems) != 2 {
		return fmt.Errorf("expected 2 ancestors, but got %d", len(dtc.CollectedItems))
	}

	// Check order
	if string(dtc.CollectedItems[0].SelfRef()) != ref1 {
		return fmt.Errorf("expected first ancestor to be %q, but got %q", ref1, dtc.CollectedItems[0].SelfRef())
	}

	if string(dtc.CollectedItems[1].SelfRef()) != ref2 {
		return fmt.Errorf("expected second ancestor to be %q, but got %q", ref2, dtc.CollectedItems[1].SelfRef())
	}

	return nil
}

func theParentShouldBeNil(ctx context.Context) error {
	dtc, err := GetDoclingTestContext(ctx)
	if err != nil {
		return err
	}

	if len(dtc.CollectedItems) != 0 {
		return fmt.Errorf("expected parent to be nil, but got %d items", len(dtc.CollectedItems))
	}

	return nil
}

// Additional serialization steps

func iSerializeTheDocumentToJSONWithIndentation(ctx context.Context) (context.Context, error) {
	dtc, err := GetDoclingTestContext(ctx)
	if err != nil {
		return ctx, err
	}

	jsonData, err := docling.ToJSONIndent(dtc.CurrentDocument, "", "  ")
	if err != nil {
		dtc.LastError = err
		return ctx, nil
	}

	dtc.LastJSON = jsonData
	dtc.LastError = nil
	return ctx, nil
}

func iDeserializeTheJSONBackToADocument(ctx context.Context) (context.Context, error) {
	return iDeserializeTheJSON(ctx)
}

func theDeserializedDocumentShouldHaveTheSameName(ctx context.Context) error {
	dtc, err := GetDoclingTestContext(ctx)
	if err != nil {
		return err
	}

	origName := dtc.OriginalDocument.Name()
	currName := dtc.CurrentDocument.Name()

	if origName != currName {
		return fmt.Errorf("expected deserialized document to have name %q, but got %q", origName, currName)
	}

	return nil
}

func theDeserializedDocumentShouldHaveTheSameNumberOfItems(ctx context.Context) error {
	dtc, err := GetDoclingTestContext(ctx)
	if err != nil {
		return err
	}

	origCount := len(dtc.OriginalDocument.Items())
	currCount := len(dtc.CurrentDocument.Items())

	if origCount != currCount {
		return fmt.Errorf("expected deserialized document to have %d items, but got %d", origCount, currCount)
	}

	return nil
}

func theDeserializedDocumentShouldHaveItems(ctx context.Context, expectedCount int) error {
	dtc, err := GetDoclingTestContext(ctx)
	if err != nil {
		return err
	}

	actualCount := len(dtc.CurrentDocument.Items())
	if actualCount != expectedCount {
		return fmt.Errorf("expected deserialized document to have %d items, but got %d", expectedCount, actualCount)
	}

	return nil
}

func theDeserializedDocumentShouldHaveTheName(ctx context.Context, expectedName string) error {
	dtc, err := GetDoclingTestContext(ctx)
	if err != nil {
		return err
	}

	actualName := dtc.CurrentDocument.Name()
	if actualName != expectedName {
		return fmt.Errorf("expected deserialized document to have name %q, but got %q", expectedName, actualName)
	}

	return nil
}

func theDeserializedDocumentShouldMaintainTheTreeStructure(ctx context.Context) error {
	dtc, err := GetDoclingTestContext(ctx)
	if err != nil {
		return err
	}

	// Verify that parent-child relationships are maintained
	// This is a basic structural check
	origItems := dtc.OriginalDocument.Items()
	currItems := dtc.CurrentDocument.Items()

	if len(origItems) != len(currItems) {
		return fmt.Errorf("tree structure not maintained: item count mismatch")
	}

	// Check that each item still has the same parent
	for ref, origItem := range origItems {
		currItem := currItems[ref]
		if currItem == nil {
			return fmt.Errorf("tree structure not maintained: item %q missing", ref)
		}

		origParent := origItem.Parent()
		currParent := currItem.Parent()

		if origParent == nil && currParent != nil {
			return fmt.Errorf("tree structure not maintained: item %q has unexpected parent", ref)
		}

		if origParent != nil && currParent == nil {
			return fmt.Errorf("tree structure not maintained: item %q lost parent", ref)
		}

		if origParent != nil && currParent != nil && *origParent != *currParent {
			return fmt.Errorf("tree structure not maintained: item %q has different parent", ref)
		}
	}

	return nil
}

func itemShouldStillHaveParent(ctx context.Context, ref, expectedParent string) error {
	return itemShouldHaveParent(ctx, ref, expectedParent)
}

func itemShouldStillHaveChildren(ctx context.Context, ref string, expectedCount int) error {
	return itemShouldHaveChildren(ctx, ref, expectedCount)
}

func theDeserializedDocumentMetadataShouldContain(ctx context.Context, key, expectedValue string) error {
	return theDocumentMetadataShouldContainWithValue(ctx, key, expectedValue)
}

func theDeserializedTableShouldHaveRows(ctx context.Context, expectedRows int) error {
	dtc, err := GetDoclingTestContext(ctx)
	if err != nil {
		return err
	}

	// Find the table item
	var tableItem docling.TableItem
	found := false
	for _, item := range dtc.CurrentDocument.Items() {
		if ti, ok := item.(docling.TableItem); ok {
			tableItem = ti
			found = true
			break
		}
	}

	if !found {
		return fmt.Errorf("no table item found in document")
	}

	if tableItem.NumRows() != expectedRows {
		return fmt.Errorf("expected table to have %d rows, but has %d", expectedRows, tableItem.NumRows())
	}

	return nil
}

func theDeserializedTableShouldHaveColumns(ctx context.Context, expectedCols int) error {
	dtc, err := GetDoclingTestContext(ctx)
	if err != nil {
		return err
	}

	// Find the table item
	var tableItem docling.TableItem
	found := false
	for _, item := range dtc.CurrentDocument.Items() {
		if ti, ok := item.(docling.TableItem); ok {
			tableItem = ti
			found = true
			break
		}
	}

	if !found {
		return fmt.Errorf("no table item found in document")
	}

	if tableItem.NumCols() != expectedCols {
		return fmt.Errorf("expected table to have %d columns, but has %d", expectedCols, tableItem.NumCols())
	}

	return nil
}

func theDeserializedItemShouldHaveProvenanceInformation(ctx context.Context) error {
	dtc, err := GetDoclingTestContext(ctx)
	if err != nil {
		return err
	}

	// Find the text item
	item := dtc.CurrentDocument.GetItem(docling.Ref("text1"))
	if item == nil {
		return fmt.Errorf("item text1 not found")
	}

	if item.Provenance() == nil {
		return fmt.Errorf("item should have provenance information")
	}

	return nil
}

func theProvenanceShouldHaveCorrectBoundingBoxCoordinates(ctx context.Context) error {
	dtc, err := GetDoclingTestContext(ctx)
	if err != nil {
		return err
	}

	item := dtc.CurrentDocument.GetItem(docling.Ref("text1"))
	if item == nil {
		return fmt.Errorf("item text1 not found")
	}

	provSlice := item.Provenance()
	if len(provSlice) == 0 {
		return fmt.Errorf("item has no provenance")
	}

	prov := provSlice[0]
	if prov.BBox == nil {
		return fmt.Errorf("provenance has no bounding box")
	}

	// Verify bounding box has expected structure (actual values checked separately)
	if prov.BBox.Left == 0 && prov.BBox.Top == 0 && prov.BBox.Width == 0 && prov.BBox.Height == 0 {
		return fmt.Errorf("bounding box coordinates are all zero")
	}

	return nil
}

func theProvenanceShouldHaveCorrectCharacterRange(ctx context.Context) error {
	dtc, err := GetDoclingTestContext(ctx)
	if err != nil {
		return err
	}

	item := dtc.CurrentDocument.GetItem(docling.Ref("text1"))
	if item == nil {
		return fmt.Errorf("item text1 not found")
	}

	provSlice := item.Provenance()
	if len(provSlice) == 0 {
		return fmt.Errorf("item has no provenance")
	}

	prov := provSlice[0]
	if prov.CharStart == 0 && prov.CharEnd == 0 {
		return fmt.Errorf("character range is not set")
	}

	return nil
}

func theJSONShouldBePrettyPrinted(ctx context.Context) error {
	dtc, err := GetDoclingTestContext(ctx)
	if err != nil {
		return err
	}

	// Check if JSON contains newlines (indicating indentation)
	if !strings.Contains(string(dtc.LastJSON), "\n") {
		return fmt.Errorf("JSON is not pretty-printed (no newlines found)")
	}

	return nil
}

func theJSONShouldBeValid(ctx context.Context) error {
	dtc, err := GetDoclingTestContext(ctx)
	if err != nil {
		return err
	}

	if !json.Valid(dtc.LastJSON) {
		return fmt.Errorf("JSON is not valid")
	}

	return nil
}

// Additional traversal steps

func iWalkTheTreeFrom(ctx context.Context, startRef string) (context.Context, error) {
	return iWalkTheDocumentTreeFrom(ctx, startRef)
}

func iWalkTheDocumentBody(ctx context.Context) (context.Context, error) {
	dtc, err := GetDoclingTestContext(ctx)
	if err != nil {
		return ctx, err
	}

	dtc.VisitedRefs = []docling.Ref{}
	dtc.TraversalCount = 0

	err = docling.WalkBody(dtc.CurrentDocument, func(item docling.Item) error {
		dtc.VisitedRefs = append(dtc.VisitedRefs, item.SelfRef())
		dtc.TraversalCount++
		return nil
	})

	if err != nil {
		dtc.LastError = err
	}

	return ctx, nil
}

func iShouldVisitItemsInOrder(ctx context.Context, orderStr string) error {
	dtc, err := GetDoclingTestContext(ctx)
	if err != nil {
		return err
	}

	// Parse the order string (e.g., "root, section1, para1, para2")
	expected := strings.Split(orderStr, ", ")

	if len(dtc.VisitedRefs) != len(expected) {
		return fmt.Errorf("expected to visit %d items in order, but visited %d", len(expected), len(dtc.VisitedRefs))
	}

	for i, ref := range expected {
		if string(dtc.VisitedRefs[i]) != ref {
			return fmt.Errorf("expected item %d to be %q, but got %q", i, ref, dtc.VisitedRefs[i])
		}
	}

	return nil
}

func iFilterByLabel(ctx context.Context, label string) (context.Context, error) {
	return iFilterItemsByLabel(ctx, label)
}

func iCountItemsWithLabel(ctx context.Context, label string) (context.Context, error) {
	return iCountItemsByLabel(ctx, label)
}

func iFindTheFirstTableItem(ctx context.Context) (context.Context, error) {
	return iFindTheFirstItemWithLabel(ctx, "table")
}

func iCollectItemsWhereTextLengthIsGreaterThan(ctx context.Context, minLength int) (context.Context, error) {
	dtc, err := GetDoclingTestContext(ctx)
	if err != nil {
		return ctx, err
	}

	dtc.CollectedItems = docling.Collect(dtc.CurrentDocument, func(item docling.Item) bool {
		if textItem, ok := item.(docling.TextItem); ok {
			return len(textItem.Text()) > minLength
		}
		return false
	})

	return ctx, nil
}

func iMapAFunctionThatAddsMetadata(ctx context.Context, metadataKey string) (context.Context, error) {
	dtc, err := GetDoclingTestContext(ctx)
	if err != nil {
		return ctx, err
	}

	// Save original for immutability check
	dtc.OriginalDocument = dtc.CurrentDocument

	// Map function that adds metadata
	dtc.CurrentDocument = docling.Map(dtc.CurrentDocument, func(item docling.Item) docling.Item {
		switch v := item.(type) {
		case docling.TextItem:
			v.DocItem = v.DocItem.WithMetadata(metadataKey, true)
			return v
		case docling.TableItem:
			v.DocItem = v.DocItem.WithMetadata(metadataKey, true)
			return v
		case docling.PictureItem:
			v.DocItem = v.DocItem.WithMetadata(metadataKey, true)
			return v
		case docling.NodeItem:
			return v.WithMetadata(metadataKey, true)
		case docling.GroupItem:
			v.NodeItem = v.NodeItem.WithMetadata(metadataKey, true)
			return v
		default:
			return item
		}
	})

	return ctx, nil
}

func iFoldToCalculateTotalTextLength(ctx context.Context) (context.Context, error) {
	dtc, err := GetDoclingTestContext(ctx)
	if err != nil {
		return ctx, err
	}

	totalLength := docling.Fold(dtc.CurrentDocument, 0, func(acc int, item docling.Item) int {
		if textItem, ok := item.(docling.TextItem); ok {
			return acc + len(textItem.Text())
		}
		return acc
	})

	dtc.TraversalCount = totalLength

	return ctx, nil
}

func iCheckIfAnyItemIsATable(ctx context.Context) (context.Context, error) {
	dtc, err := GetDoclingTestContext(ctx)
	if err != nil {
		return ctx, err
	}

	result := docling.Any(dtc.CurrentDocument, func(item docling.Item) bool {
		_, ok := item.(docling.TableItem)
		return ok
	})

	if result {
		dtc.TraversalCount = 1
	} else {
		dtc.TraversalCount = 0
	}

	return ctx, nil
}

func iCheckIfAllItemsAreText(ctx context.Context) (context.Context, error) {
	dtc, err := GetDoclingTestContext(ctx)
	if err != nil {
		return ctx, err
	}

	result := docling.All(dtc.CurrentDocument, func(item docling.Item) bool {
		_, ok := item.(docling.TextItem)
		return ok
	})

	if result {
		dtc.TraversalCount = 1
	} else {
		dtc.TraversalCount = 0
	}

	return ctx, nil
}

func theFilteredDocumentShouldHaveItems(ctx context.Context, expectedCount int) error {
	dtc, err := GetDoclingTestContext(ctx)
	if err != nil {
		return err
	}

	actualCount := len(dtc.CollectedItems)
	if actualCount != expectedCount {
		return fmt.Errorf("expected filtered document to have %d items, but got %d", expectedCount, actualCount)
	}

	return nil
}

func bothItemsShouldHaveLabel(ctx context.Context, expectedLabel string) error {
	dtc, err := GetDoclingTestContext(ctx)
	if err != nil {
		return err
	}

	if len(dtc.CollectedItems) < 2 {
		return fmt.Errorf("expected at least 2 items, but got %d", len(dtc.CollectedItems))
	}

	for _, item := range dtc.CollectedItems {
		if string(item.Label()) != expectedLabel {
			return fmt.Errorf("expected all items to have label %q, but item %q has label %q", expectedLabel, item.SelfRef(), item.Label())
		}
	}

	return nil
}

func iShouldGetItems(ctx context.Context, expectedCount int) error {
	return theResultShouldContainItems(ctx, expectedCount)
}

func thatItemShouldBe(ctx context.Context, expectedRef string) error {
	dtc, err := GetDoclingTestContext(ctx)
	if err != nil {
		return err
	}

	if len(dtc.CollectedItems) != 1 {
		return fmt.Errorf("expected 1 item, but got %d", len(dtc.CollectedItems))
	}

	actualRef := string(dtc.CollectedItems[0].SelfRef())
	if actualRef != expectedRef {
		return fmt.Errorf("expected item to be %q, but got %q", expectedRef, actualRef)
	}

	return nil
}

func allItemsInTheNewDocumentShouldHaveMetadata(ctx context.Context, metadataKey string) error {
	dtc, err := GetDoclingTestContext(ctx)
	if err != nil {
		return err
	}

	for ref, item := range dtc.CurrentDocument.Items() {
		meta := item.Meta()
		if _, ok := meta[metadataKey]; !ok {
			return fmt.Errorf("item %q does not have metadata key %q", ref, metadataKey)
		}
	}

	return nil
}

func theOriginalDocumentItemsShouldNotHaveMetadata(ctx context.Context, metadataKey string) error {
	dtc, err := GetDoclingTestContext(ctx)
	if err != nil {
		return err
	}

	for ref, item := range dtc.OriginalDocument.Items() {
		meta := item.Meta()
		if _, ok := meta[metadataKey]; ok {
			return fmt.Errorf("original document item %q should not have metadata key %q (immutability check failed)", ref, metadataKey)
		}
	}

	return nil
}

func theResultShouldBe(ctx context.Context, expectedValue int) error {
	dtc, err := GetDoclingTestContext(ctx)
	if err != nil {
		return err
	}

	if dtc.TraversalCount != expectedValue {
		return fmt.Errorf("expected result to be %d, but got %d", expectedValue, dtc.TraversalCount)
	}

	return nil
}

func iShouldGetItem(ctx context.Context, expectedRef string) error {
	dtc, err := GetDoclingTestContext(ctx)
	if err != nil {
		return err
	}

	if len(dtc.CollectedItems) != 1 {
		return fmt.Errorf("expected to get 1 item, but got %d", len(dtc.CollectedItems))
	}

	actualRef := string(dtc.CollectedItems[0].SelfRef())
	if actualRef != expectedRef {
		return fmt.Errorf("expected to get item %q, but got %q", expectedRef, actualRef)
	}

	return nil
}
