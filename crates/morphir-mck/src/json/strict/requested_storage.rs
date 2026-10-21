//! Requested-capacity bound for the private Darwin operation-port codec.
//! Qualified source pins: Rust1.98.1, serde_json1.0.151, serde1.0.229.
//! Arithmetic only, no parsing/allocation or allocator-header/RSS/CPU claim.
use super::Document;
use std::alloc::Layout;
use std::mem::{MaybeUninit, size_of};
use std::ptr::NonNull;

fn add(left: usize, right: usize) -> Option<usize> {
    left.checked_add(right)
}

fn mul(left: usize, right: usize) -> Option<usize> {
    left.checked_mul(right)
}

// Bound all source fields and every possible inter-field alignment gap,
// followed by trailing alignment. This deliberately does not assert the
// private Rust-repr LeafNode's actual size or field order.
fn source_fields_upper_layout(fields: &[Layout]) -> Option<Layout> {
    let mut bytes = 0usize;
    let mut alignment = 1usize;
    for field in fields {
        bytes = add(bytes, add(field.size(), field.align().checked_sub(1)?)?)?;
        alignment = alignment.max(field.align());
    }
    let padded = add(bytes, alignment.checked_sub(1)?)? & !(alignment - 1);
    Layout::from_size_align(padded, alignment).ok()
}

fn pinned_btree_node_upper_layout() -> Option<Layout> {
    // Rust 1.98.1 alloc/collections/btree/node.rs: B=6; CAPACITY=11.
    // BTreeSet<String> uses V=(). Leaf fields: parent, parent_idx, len,
    // keys[11], vals[11]. InternalNode is repr(C): leaf + edges[12].
    let leaf = source_fields_upper_layout(&[
        Layout::new::<Option<NonNull<()>>>(),
        Layout::new::<MaybeUninit<u16>>(),
        Layout::new::<u16>(),
        Layout::array::<MaybeUninit<String>>(11).ok()?,
        Layout::array::<MaybeUninit<()>>(11).ok()?,
    ])?;
    let edges = Layout::array::<MaybeUninit<NonNull<()>>>(12).ok()?;
    Some(leaf.extend(edges).ok()?.0.pad_to_align())
}

/// Precharge the cumulative requested storage for the strict document's
/// materialization buffers. Structural cardinalities conservatively bound
/// object members and array elements independently. No syntax scan,
/// second decoder, retained literal copy or codec typed copy occurs here.
///
/// Add requested_diagnostic_storage_bound before parsing, including N=0.
pub(crate) fn requested_document_storage_bound(input_bytes: usize) -> Option<usize> {
    // Pinned RawVec min nonzero capacity is four for these element sizes;
    // doubling gives sum(requested capacities) <= 4 * element_count.
    let object_member_buffers = mul(
        4,
        add(
            size_of::<(String, &serde_json::value::RawValue)>(),
            size_of::<(String, Document)>(),
        )?,
    )?;
    let array_element_buffers = mul(
        4,
        add(
            size_of::<&serde_json::value::RawValue>(),
            size_of::<Document>(),
        )?,
    )?;

    // Insert-only duplicate-key sets allocate no more nodes than inserted
    // keys; each key owns at most its decoded byte length. Count every node
    // as the larger internal-node upper layout, including leaf allocations.
    let duplicate_key_nodes = pinned_btree_node_upper_layout()?.size();

    // Decoded keys + string values total <= input_bytes. Their String copies
    // consume that span once, and the BTreeSet cloned keys at most once more.
    let decoded_strings_and_key_clones = 2usize;
    // Serde's escaped-string scratch Vec<u8> starts empty: minimum capacity
    // eight, then doubling. Across fresh readers its cumulative requests are
    // <= 8 * total nonempty decoded string bytes (empty strings need none).
    let escaped_string_scratch = 8usize;

    // serde_json arbitrary_precision parse_any_number starts with capacity16.
    // There are <= input_bytes numeric tokens. Its exponent normalization
    // can add one '+' per token, hence total normalized lengths <= 2*N.
    // Geometric requests beyond the initial request are <=4*normalized_len.
    // Number's resulting owned text needs <=2*N including that normalization.
    let number_initial_buffers = 16usize;
    let number_growth_buffers = mul(4, 2)?;
    let resulting_number_text = 2usize;

    // Distinct object syntax needs >=4 bytes per member, even empty keys.
    // Distinct array syntax plus item tokens needs >=2 bytes per element.
    // Count both maxima independently; their simultaneous use overcounts.
    let object_metadata = mul(
        input_bytes / 4,
        add(object_member_buffers, duplicate_key_nodes)?,
    )?;
    let array_metadata = mul(input_bytes / 2, array_element_buffers)?;
    let mut per_byte = 0usize;
    for term in [
        decoded_strings_and_key_clones,
        escaped_string_scratch,
        number_initial_buffers,
        number_growth_buffers,
        resulting_number_text,
    ] {
        per_byte = add(per_byte, term)?;
    }

    // RawValue's ignore_value uses the deserializer scratch Vec as a nesting
    // stack. The first whole-document validation may fail on N opening bytes,
    // so fund8*N requests. Once valid, each container needs two distinct source
    // braces/brackets. Descendant raw scans can repeat a container under at
    // most127 materialized ancestors (strict.rs's existing depth guard).
    let first_raw_stack = mul(8, input_bytes)?;
    let nested_raw_stacks = mul(8, mul(127, input_bytes / 2)?)?;
    add(
        add(object_metadata, array_metadata)?,
        add(
            mul(input_bytes, per_byte)?,
            add(first_raw_stack, nested_raw_stacks)?,
        )?,
    )
}

/// Separate codec term: its only variable typed container is
/// Items<wire::Operand>; try_reserve_exact uses its element count, <=N.
/// Every owned typed string corresponds to one disjoint source string value,
/// so their total decoded byte lengths are <=N. The literal payload copy and
/// cache vector growth retain their existing separate actual-capacity charges.
pub(crate) fn requested_codec_typed_storage_bound(
    input_bytes: usize,
    operand_size: usize,
) -> Option<usize> {
    mul(input_bytes, add(operand_size, 1)?)
}

/// The codec's ONE additional raw_members top-object traversal. It allocates
/// member references/keys and the duplicate set, but no new Document tree.
/// Precharge this together with the initial parse, before either traversal.
pub(crate) fn requested_raw_members_storage_bound(input_bytes: usize) -> Option<usize> {
    // In a valid object, each member needs two key quotes, colon, and a comma
    // or its share of the two object braces. Even empty keys/values cannot
    // make member_count exceed floor(input_bytes / 4).
    let members = input_bytes / 4;
    let member_vec = mul(4, size_of::<(String, &serde_json::value::RawValue)>())?;
    let member_nodes = pinned_btree_node_upper_layout()?.size();
    let metadata = mul(members, add(member_vec, member_nodes)?)?;
    // Decoded key + duplicate-set clone + escaped-key scratch, as above.
    let key_buffers = mul(input_bytes, add(2, 8)?)?;
    // A wrong-kind numeric top token is parsed before deserialize_map rejects
    // its type. Include the same numeric scratch/result bound for that path.
    let wrong_kind_number = mul(input_bytes, add(16, add(mul(4, 2)?, 2)?)?)?;
    // This extra pass receives an already validated RawValue; each nested
    // container has two distinct delimiters, so its stack needs <=N/2 entries.
    let raw_stack = mul(8, input_bytes / 2)?;
    add(
        add(metadata, key_buffers)?,
        add(wrong_kind_number, raw_stack)?,
    )
}

fn pinned_serde_error_impl_upper_layout() -> Option<Layout> {
    // error.rs ErrorCode's only data variants are Message(Box<str>) and
    // Io(std::io::Error). Its other variants are fieldless. Bound the enum by
    // an explicit usize tag + largest payload, without relying on niches.
    let message = Layout::new::<Box<str>>();
    let io = Layout::new::<std::io::Error>();
    let payload = Layout::from_size_align(
        message.size().max(io.size()),
        message.align().max(io.align()),
    )
    .ok()?
    .pad_to_align();
    let code = source_fields_upper_layout(&[Layout::new::<usize>(), payload])?;
    source_fields_upper_layout(&[code, Layout::new::<usize>(), Layout::new::<usize>()])
}

/// Precharge reachable slice-reader diagnostics even for an empty payload.
/// It covers a single terminal error, including the additional raw-members
/// pass: `?` ends the operation at its first failure; recursion moves the same
/// String/Result rather than formatting one message per nesting level.
pub(crate) fn requested_diagnostic_storage_bound(input_bytes: usize) -> Option<usize> {
    // Source-pinned ErrorCode::Display literals. The longest covers every
    // fixed syntax/EOF/number/recursion message reachable from this slice path.
    let syntax_literal = [
        "EOF while parsing a list",
        "EOF while parsing an object",
        "EOF while parsing a string",
        "EOF while parsing a value",
        "expected `:`",
        "expected `,` or `]`",
        "expected `,` or `}`",
        "expected ident",
        "expected value",
        "expected `\"`",
        "invalid escape",
        "invalid number",
        "number out of range",
        "invalid unicode code point",
        "control character (\\u0000-\\u001F) found while parsing a string",
        "key must be a string",
        "invalid value: expected key to be a number in quotes",
        "float key must be finite (got NaN or +/-inf)",
        "lone leading surrogate in hex escape",
        "trailing comma",
        "trailing characters",
        "unexpected end of hex escape",
        "recursion limit exceeded",
    ]
    .iter()
    .map(|text| text.len())
    .max()?;

    // Strict MembersSeed's duplicate-key Display is verbatim, not Debug.
    let duplicate_key = add("duplicate key ".len(), input_bytes)?;

    // The extra raw_members call may receive a non-object. For a string,
    // serde::Unexpected uses Debug escaping. One Unicode scalar uses <=10
    // bytes in the longest '\u{10ffff}' spelling, and at least one input
    // byte; quotes are separate. Number spellings fit this same10*N term.
    // Sum alternative fixed prefixes rather than assuming their lengths equal.
    let unexpected_prefix = add(
        add("invalid type: ".len(), "invalid value: ".len())?,
        add(
            add("string ".len(), "floating point ``".len())?,
            add(
                add(2, ", expected ".len())?,
                "JSON without duplicate members".len(),
            )?,
        )?,
    )?;
    let unexpected = add(mul(input_bytes, "\\u{10ffff}".len())?, unexpected_prefix)?;
    let read_work = "JSON work limits must be positive"
        .len()
        .max("JSON input exceeds its cumulative checker work budget".len());
    let message = syntax_literal
        .max(duplicate_key)
        .max(unexpected)
        .max(read_work);

    // ErrorImpl::Display appends exactly these literal pieces and two usize
    // decimal values. No widths/precisions or allocating integer to_string.
    let digits = add(usize::MAX.ilog10() as usize, 1)?;
    let position_suffix = add(add(" at line ".len(), " column ".len())?, mul(2, digits)?)?;
    let displayed_message = add(message, position_suffix)?;

    // At most four owned text stages on the longest reachable path:
    // 1 duplicate format! OR ReadWork::to_string;
    // 2 de::Error::custom -> make_error(msg.to_string());
    // 3 into_boxed_str's optional shrinking allocation;
    // 4 seeded/from_slice/number map_err(e.to_string()).
    // Other failure paths omit stages. parse_line_col only borrows/truncates.
    // For each String stage, fmt's initial estimate is <=2*message output;
    // later RawVec requests double. Sum <=4*output, with mincapacity8 covered.
    let per_text_stage = mul(4, displayed_message)?.max(8);
    let diagnostic_text = mul(4, per_text_stage)?;

    // One boxed ErrorImpl from syntax/custom, plus at most one replacement
    // when fix_position changes line0 to the slice's actual line>=1. Further
    // recursive propagation keeps that position and moves the same error.
    let error_boxes = mul(2, pinned_serde_error_impl_upper_layout()?.size())?;
    add(diagnostic_text, error_boxes)
}
