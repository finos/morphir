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

	// Assertions - Items and hierarchy
	sc.Step(`^item "([^"]*)" should have (\d+) (?:child|children)$`, itemShouldHaveChildren)
	sc.Step(`^item "([^"]*)" should have parent "([^"]*)"$`, itemShouldHaveParent)

	// Navigation
	sc.Step(`^I get the children of item "([^"]*)"$`, iGetTheChildrenOfItem)
	sc.Step(`^I get the parent of item "([^"]*)"$`, iGetTheParentOfItem)
	sc.Step(`^I get the siblings of item "([^"]*)"$`, iGetTheSiblingsOfItem)
	sc.Step(`^I get the descendants of item "([^"]*)"$`, iGetTheDescendantsOfItem)
	sc.Step(`^I get the ancestors of item "([^"]*)"$`, iGetTheAncestorsOfItem)
	sc.Step(`^I check if "([^"]*)" is an ancestor of "([^"]*)"$`, iCheckIfIsAnAncestorOf)

	// Navigation assertions
	sc.Step(`^the result should contain (\d+) items?$`, theResultShouldContainItems)
	sc.Step(`^the result should contain item "([^"]*)"$`, theResultShouldContainItem)
	sc.Step(`^the result should be true$`, theResultShouldBeTrue)
	sc.Step(`^the result should be false$`, theResultShouldBeFalse)
	sc.Step(`^the parent should be "([^"]*)"$`, theParentShouldBe)

	// Serialization
	sc.Step(`^I serialize the document to JSON$`, iSerializeTheDocumentToJSON)
	sc.Step(`^I deserialize the JSON$`, iDeserializeTheJSON)
	sc.Step(`^the serialization should succeed$`, theSerializationShouldSucceed)
	sc.Step(`^the deserialization should succeed$`, theDeserializationShouldSucceed)
	sc.Step(`^the deserialized document should equal the original$`, theDeserializedDocumentShouldEqualTheOriginal)

	// Traversal - Visitor pattern
	sc.Step(`^I walk the document tree from "([^"]*)"$`, iWalkTheDocumentTreeFrom)
	sc.Step(`^I walk the entire document$`, iWalkTheEntireDocument)
	sc.Step(`^I should visit (\d+) items?$`, iShouldVisitItems)
	sc.Step(`^I should visit item "([^"]*)"$`, iShouldVisitItem)

	// Traversal - Functional operations
	sc.Step(`^I filter items by label "([^"]*)"$`, iFilterItemsByLabel)
	sc.Step(`^I count items by label "([^"]*)"$`, iCountItemsByLabel)
	sc.Step(`^I find the first item with label "([^"]*)"$`, iFindTheFirstItemWithLabel)
	sc.Step(`^the count should be (\d+)$`, theCountShouldBe)
	sc.Step(`^the found item should have ref "([^"]*)"$`, theFoundItemShouldHaveRef)
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
