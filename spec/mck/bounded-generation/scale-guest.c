// Copyright 2026 FINOS
// SPDX-License-Identifier: Apache-2.0
// Additive scale guest. Helpers adapted from the frozen Orders guest at d2804e50.
// See scale-guest.md for build, scope and verification limits.
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

#define KERNEL(name) __attribute__((import_module("extism:host/env"), import_name(#name)))
KERNEL(input_length) uint64_t input_length(void);
KERNEL(input_load_u8) uint32_t input_load_u8(uint64_t offset);
KERNEL(alloc) uint64_t alloc(uint64_t length);
KERNEL(store_u8) void store_u8(uint64_t offset, uint32_t byte);
KERNEL(output_set) void output_set(uint64_t handle, uint64_t length);

// Clang can emit these for structure copies and initializers.
void *memcpy(void *dst, const void *src, size_t n) {
    for (size_t i = 0; i < n; ++i)
        ((char *)dst)[i] = ((const char *)src)[i];
    return dst;
}
void *memset(void *dst, int value, size_t n) {
    for (size_t i = 0; i < n; ++i)
        ((char *)dst)[i] = (char)value;
    return dst;
}

enum { FRAME = 131072, DOC = 32768, TOKENS = 1024, DEPTH = 64, ID_BYTES = 256 };
typedef struct {
    const char *p;
    unsigned n;
} Text;
#define S(literal) ((Text){literal, sizeof(literal) - 1})
static bool same(Text a, Text b) {
    if (a.n != b.n)
        return false;
    for (unsigned i = 0; i < a.n; ++i)
        if (a.p[i] != b.p[i])
            return false;
    return true;
}
typedef struct {
    unsigned n;
    char bytes[ID_BYTES];
} Saved;
static Text saved(const Saved *s) {
    return (Text){s->bytes, s->n};
}
static bool fits(Text s) {
    return s.n && s.n <= ID_BYTES;
}
static void save(Saved *dst, Text src) {
    dst->n = src.n;
    memcpy(dst->bytes, src.p, src.n);
}

typedef struct {
    unsigned start, end, next;
    Text text;
    char kind;
} Token;
typedef struct {
    const char *src;
    char *strings;
    unsigned len, at, used, count, max_nodes, max_depth;
    Token tokens[TOKENS + 1];
} Json;

static char frame[FRAME], frame_strings[FRAME], document[DOC], doc_strings[DOC];
static Json wire, doc;
static char peek(const Json *j) {
    return j->at < j->len ? j->src[j->at] : 0;
}
static void space(Json *j) {
    while (peek(j) == ' ' || peek(j) == '\t' || peek(j) == '\r' || peek(j) == '\n')
        ++j->at;
}
static bool take(Json *j, char c) {
    if (peek(j) != c)
        return false;
    ++j->at;
    return true;
}
static int hex(char c) {
    if (c >= '0' && c <= '9')
        return c - '0';
    if (c >= 'a' && c <= 'f')
        return c - 'a' + 10;
    if (c >= 'A' && c <= 'F')
        return c - 'A' + 10;
    return -1;
}
static int unicode_escape(Json *j) {
    int cp = 0;
    for (int i = 0; i < 4; ++i) {
        int digit = hex(peek(j));
        if (digit < 0)
            return -1;
        cp = cp * 16 + digit;
        ++j->at;
    }
    return cp;
}
static int escaped(Json *j) {
    char c = peek(j);
    if (!c)
        return -1;
    ++j->at;
    switch (c) {
    case '"':
    case '\\':
    case '/':
        return c;
    case 'b':
        return '\b';
    case 'f':
        return '\f';
    case 'n':
        return '\n';
    case 'r':
        return '\r';
    case 't':
        return '\t';
    case 'u': {
        int cp = unicode_escape(j);
        if (cp < 0 || (cp >= 0xdc00 && cp <= 0xdfff))
            return -1;
        if (cp < 0xd800 || cp > 0xdbff)
            return cp;
        if (!take(j, '\\') || !take(j, 'u'))
            return -1;
        int low = unicode_escape(j);
        if (low < 0xdc00 || low > 0xdfff)
            return -1;
        return 0x10000 + ((cp - 0xd800) << 10) + low - 0xdc00;
    }
    default:
        return -1;
    }
}
static int utf8(Json *j, unsigned first) {
    if (first < 0x80)
        return (int)first;
    if (first < 0xc2 || first > 0xf4)
        return -1;
    unsigned extra = first < 0xe0 ? 1 : first < 0xf0 ? 2 : 3;
    unsigned cp = first & (0x7f >> (extra + 1));
    for (unsigned i = 0; i < extra; ++i) {
        unsigned c = (unsigned char)peek(j);
        if ((c & 0xc0) != 0x80)
            return -1;
        cp = (cp << 6) | (c & 63);
        ++j->at;
    }
    if ((extra == 2 && cp < 0x800) || (extra == 3 && cp < 0x10000) ||
        (cp >= 0xd800 && cp <= 0xdfff) || cp > 0x10ffff)
        return -1;
    return (int)cp;
}
static void write_utf8(Json *j, unsigned cp) {
    if (cp < 0x80) {
        j->strings[j->used++] = (char)cp;
        return;
    }
    unsigned extra = cp < 0x800 ? 1 : cp < 0x10000 ? 2 : 3;
    j->strings[j->used++] = (char)((0xf0 << (3 - extra)) | (cp >> (6 * extra)));
    while (extra) {
        --extra;
        j->strings[j->used++] = (char)(0x80 | ((cp >> (6 * extra)) & 63));
    }
}
static bool string(Json *j, Token *t) {
    unsigned start = j->used;
    while (!take(j, '"')) {
        unsigned c = (unsigned char)peek(j);
        if (c < 32)
            return false;
        ++j->at;
        int cp = c == '\\' ? escaped(j) : utf8(j, c);
        if (cp < 0)
            return false;
        // Decoding cannot use more bytes than the original string's token.
        write_utf8(j, (unsigned)cp);
    }
    t->text = (Text){j->strings + start, j->used - start};
    return true;
}
static bool digit(char c) {
    return c >= '0' && c <= '9';
}
static bool digits(Json *j) {
    unsigned start = j->at;
    while (digit(peek(j)))
        ++j->at;
    return j->at != start;
}
static bool number(Json *j) {
    take(j, '-');
    if (!take(j, '0') && !digits(j))
        return false;
    if (take(j, '.') && !digits(j))
        return false;
    if (take(j, 'e') || take(j, 'E')) {
        if (!take(j, '+'))
            take(j, '-');
        return digits(j);
    }
    return true;
}
static bool word(Json *j, Text s) {
    for (unsigned i = 0; i < s.n; ++i)
        if (!take(j, s.p[i]))
            return false;
    return true;
}
static unsigned value(Json *j, unsigned depth);
static bool compound(Json *j, unsigned parent, unsigned depth, bool object) {
    char close = object ? '}' : ']';
    space(j);
    if (take(j, close))
        return true;
    do {
        space(j);
        if (object) {
            if (peek(j) != '"')
                return false;
            unsigned key = value(j, depth + 1);
            if (!key)
                return false;
            for (unsigned earlier = parent + 1; earlier < key;
                 earlier = j->tokens[earlier + 1].next)
                if (same(j->tokens[earlier].text, j->tokens[key].text))
                    return false;
            space(j);
            if (!take(j, ':'))
                return false;
        }
        if (!value(j, depth + 1))
            return false;
        space(j);
    } while (take(j, ','));
    return take(j, close);
}
static unsigned value(Json *j, unsigned depth) {
    if (depth > j->max_depth || j->count == j->max_nodes)
        return 0;
    space(j);
    unsigned n = ++j->count;
    Token *t = &j->tokens[n];
    t->start = j->at;
    char c = peek(j);
    bool valid;
    t->kind = c;
    switch (c) {
    case '{':
    case '[':
        ++j->at;
        valid = compound(j, n, depth, c == '{');
        break;
    case '"':
        ++j->at;
        valid = string(j, t);
        break;
    case 't':
        valid = word(j, S("true"));
        break;
    case 'f':
        valid = word(j, S("false"));
        break;
    case 'n':
        valid = word(j, S("null"));
        break;
    default:
        t->kind = '0';
        valid = number(j);
        break;
    }
    if (!valid)
        return 0;
    t->end = j->at;
    t->next = j->count + 1;
    return n;
}
static bool parse(Json *j, const char *src, char *strings, unsigned len, unsigned depth,
                  unsigned nodes) {
    j->src = src;
    j->strings = strings;
    j->len = len;
    j->at = j->used = j->count = 0;
    j->max_depth = depth;
    j->max_nodes = nodes;
    if (!value(j, 1))
        return false;
    space(j);
    return j->at == len;
}
static char kind(const Json *j, unsigned token) {
    return j->tokens[token].kind;
}
static bool empty(const Json *j, unsigned token, char shape) {
    return kind(j, token) == shape && j->tokens[token].next == token + 1;
}
static Text str(const Json *j, unsigned token) {
    return kind(j, token) == '"' ? j->tokens[token].text : (Text){0};
}
static Text raw(const Json *j, unsigned token) {
    Token t = j->tokens[token];
    return (Text){j->src + t.start, t.end - t.start};
}
static unsigned field(const Json *j, unsigned obj, Text name) {
    if (kind(j, obj) != '{')
        return 0;
    for (unsigned i = obj + 1; i < j->tokens[obj].next; i = j->tokens[i + 1].next)
        if (same(j->tokens[i].text, name))
            return i + 1;
    return 0;
}
static unsigned only(const Json *j, unsigned container, char shape) {
    if (kind(j, container) != shape)
        return 0;
    unsigned item = container + 1;
    if (shape == '{')
        ++item;
    if (item >= j->tokens[container].next || j->tokens[item].next != j->tokens[container].next)
        return 0;
    return item;
}
static Text get(const Json *j, unsigned obj, Text name) {
    return str(j, field(j, obj, name));
}
static bool uint_token(const Json *j, unsigned token, uint64_t *out) {
    if (kind(j, token) != '0')
        return false;
    Text s = raw(j, token);
    uint64_t n = 0;
    for (unsigned i = 0; i < s.n; ++i) {
        if (!digit(s.p[i]) || n > 900719925474099ULL)
            return false;
        n = n * 10 + (unsigned)(s.p[i] - '0');
    }
    if (n > 9007199254740991ULL)
        return false;
    *out = n;
    return true;
}
static bool lower_digest(Text s) {
    if (s.n != 64)
        return false;
    for (unsigned i = 0; i < s.n; ++i)
        if (!digit(s.p[i]) && (s.p[i] < 'a' || s.p[i] > 'f'))
            return false;
    return true;
}

static const char base64[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
static int sextet(char c) {
    for (int i = 0; i < 64; ++i)
        if (base64[i] == c)
            return i;
    return -1;
}
static bool decode64(Text s, unsigned length) {
    if (s.n != 4 * ((length + 2) / 3))
        return false;
    unsigned at = 0;
    for (unsigned i = 0; i < s.n; i += 4) {
        unsigned remaining = length - at;
        int a = sextet(s.p[i]), b = sextet(s.p[i + 1]);
        int c = remaining > 1 ? sextet(s.p[i + 2]) : 0;
        int d = remaining > 2 ? sextet(s.p[i + 3]) : 0;
        if (a < 0 || b < 0 || c < 0 || d < 0)
            return false;
        if (remaining == 1 && ((b & 15) || s.p[i + 2] != '='))
            return false;
        if (remaining < 3 && ((c & 3) || s.p[i + 3] != '='))
            return false;
        document[at++] = (char)((a << 2) | (b >> 4));
        if (remaining > 1)
            document[at++] = (char)((b << 4) | (c >> 2));
        if (remaining > 2)
            document[at++] = (char)((c << 6) | d);
    }
    return true;
}
static unsigned encode64(Text s, char *out) {
    unsigned at = 0;
    for (unsigned i = 0; i < s.n; i += 3) {
        unsigned a = (unsigned char)s.p[i], b = i + 1 < s.n ? (unsigned char)s.p[i + 1] : 0;
        unsigned c = i + 2 < s.n ? (unsigned char)s.p[i + 2] : 0;
        out[at++] = base64[a >> 2];
        out[at++] = base64[((a & 3) << 4) | (b >> 4)];
        out[at++] = i + 1 < s.n ? base64[((b & 15) << 2) | (c >> 6)] : '=';
        out[at++] = i + 2 < s.n ? base64[c & 63] : '=';
    }
    return at;
}

// FIPS 180-4 SHA-256. Both received documents and artifact bytes use this path.
static uint32_t rotate(uint32_t n, unsigned s) {
    return (n >> s) | (n << (32 - s));
}
static void sha256(Text s, char out[64]) {
    static const uint32_t k[64] = {
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4,
        0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe,
        0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f,
        0x4a7484aa, 0x5cb0a9dc, 0x76f988da, 0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
        0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc,
        0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b,
        0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070, 0x19a4c116,
        0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7,
        0xc67178f2};
    uint32_t h[] = {0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
                    0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19};
    unsigned padded = ((s.n + 9 + 63) / 64) * 64;
    for (unsigned block = 0; block < padded; block += 64) {
        uint32_t w[64];
        for (unsigned i = 0; i < 16; ++i) {
            uint32_t chunk = 0;
            for (unsigned j = 0; j < 4; ++j) {
                unsigned at = block + i * 4 + j;
                unsigned byte = at < s.n           ? (unsigned char)s.p[at]
                                : at == s.n        ? 0x80
                                : at >= padded - 4 ? ((s.n * 8) >> (8 * (padded - 1 - at))) & 255
                                                   : 0;
                chunk = (chunk << 8) | byte;
            }
            w[i] = chunk;
        }
        for (unsigned i = 16; i < 64; ++i) {
            uint32_t a = w[i - 15], b = w[i - 2];
            w[i] = w[i - 16] + (rotate(a, 7) ^ rotate(a, 18) ^ (a >> 3)) + w[i - 7] +
                   (rotate(b, 17) ^ rotate(b, 19) ^ (b >> 10));
        }
        uint32_t a = h[0], b = h[1], c = h[2], d = h[3], e = h[4], f = h[5], g = h[6], hh = h[7];
        for (unsigned i = 0; i < 64; ++i) {
            uint32_t t = hh + (rotate(e, 6) ^ rotate(e, 11) ^ rotate(e, 25)) +
                         ((e & f) ^ (~e & g)) + k[i] + w[i];
            uint32_t m =
                (rotate(a, 2) ^ rotate(a, 13) ^ rotate(a, 22)) + ((a & b) ^ (a & c) ^ (b & c));
            hh = g;
            g = f;
            f = e;
            e = d + t;
            d = c;
            c = b;
            b = a;
            a = t + m;
        }
        h[0] += a;
        h[1] += b;
        h[2] += c;
        h[3] += d;
        h[4] += e;
        h[5] += f;
        h[6] += g;
        h[7] += hh;
    }
    for (unsigned i = 0; i < 64; ++i)
        out[i] = "0123456789abcdef"[(h[i / 8] >> (28 - 4 * (i % 8))) & 15];
}

// The guest has one admitted target and tuple. Limits in this table are ceilings.
#define LIMITS(X)                                                                                  \
    X(maxFrameBytes, FRAME)                                                                        \
    X(maxEncodedBytesPerExchange, FRAME) X(maxDecodedBytesPerExchange, DOC * 2)                    \
        X(maxDocumentsPerBatch, 1) X(maxDepth, DEPTH) X(maxNodes, TOKENS)                          \
            X(maxDiagnosticsPerExchange, 1) X(maxOutstandingRequests, 1)                           \
                X(maxGuestStateBytes, 1048576) X(maxHostCacheBytes, 1048576)                       \
                    X(maxArtifactChunkBytes, DOC) X(maxArtifactBytes, 2147483647ULL)               \
                        X(maxTotalArtifactBytes, 9007199254740991ULL)                              \
                            X(maxSessionDiskBytes, 9007199254740991ULL)                            \
                                X(maxSessionWorkUnits, 9007199254740991ULL) X(maxRounds, 10000000) \
                                    X(maxCallMilliseconds, 1000)                                   \
                                        X(maxSessionMilliseconds, 2147483647)
#define ENUM(name, ceiling) name,
enum { LIMITS(ENUM) LIMIT_COUNT };
#undef ENUM
#define ENTRY(name, ceiling) {S(#name), ceiling},
static const struct {
    Text name;
    uint64_t ceiling;
} limit_specs[] = {LIMITS(ENTRY)};
#undef ENTRY
static const struct {
    Text key, val;
} tuple[] = {{S("protocolVersion"), S("0.2.0-draft.2")},
             {S("accessVersion"), S("0.1.0-draft.1")},
             {S("operation"), S("morphir.backend.generateModel")},
             {S("irVersion"), S("4.0.0")},
             {S("profile"), S("morphir-ir")},
             {S("codec"), S("morphir-json")},
             {S("layout"), S("document-tree")},
             {S("contextualEncoding"), S("plain")}};
static const Text package_name = S("acme/orders");
static const Text final_name = S("total-in-USD"), output_type = S("morphir/SDK:string#string");
static bool exact_tuple(unsigned object) {
    for (unsigned i = 0; i < sizeof(tuple) / sizeof(tuple[0]); ++i)
        if (!same(get(&wire, object, tuple[i].key), tuple[i].val))
            return false;
    return true;
}
static uint64_t offered[LIMIT_COUNT], active[LIMIT_COUNT];
static bool read_limits(unsigned object, uint64_t out[LIMIT_COUNT], const uint64_t *ceiling) {
    for (unsigned i = 0; i < LIMIT_COUNT; ++i) {
        uint64_t n;
        if (!uint_token(&wire, field(&wire, object, limit_specs[i].name), &n) || !n)
            return false;
        uint64_t max = ceiling ? ceiling[i] : limit_specs[i].ceiling;
        if (ceiling && n > max)
            return false;
        out[i] = n > max ? max : n;
    }
    return true;
}
static bool includes_version(unsigned list) {
    if (kind(&wire, list) != '[')
        return false;
    for (unsigned i = list + 1; i < wire.tokens[list].next; i = wire.tokens[i].next)
        if (same(str(&wire, i), tuple[0].val))
            return true;
    return false;
}
static bool match_offer(unsigned support) {
    unsigned list = field(&wire, support, S("tuples"));
    if (kind(&wire, list) != '[')
        return false;
    for (unsigned i = list + 1; i < wire.tokens[list].next; i = wire.tokens[i].next)
        if (exact_tuple(i))
            return read_limits(field(&wire, support, S("limits")), offered, 0);
    return false;
}

enum { REPLY = 131072 };
static char reply[REPLY];
static unsigned reply_len;
static bool overflow;
static void emit(Text s) {
    if (s.n > REPLY - reply_len) {
        overflow = true;
        return;
    }
    memcpy(reply + reply_len, s.p, s.n);
    reply_len += s.n;
}
#define OUT(literal) emit(S(literal))
static void quote(Text s) {
    OUT("\"");
    for (unsigned i = 0; i < s.n; ++i) {
        unsigned c = (unsigned char)s.p[i];
        if (c == '"' || c == '\\')
            OUT("\\");
        if (c < 32) {
            const char *hex_digits = "0123456789abcdef";
            char code[] = {'\\', 'u', '0', '0', hex_digits[c >> 4], hex_digits[c & 15]};
            emit((Text){code, sizeof code});
        } else
            emit((Text){s.p + i, 1});
    }
    OUT("\"");
}
static void decimal(uint64_t n) {
    char digits[20];
    unsigned end = sizeof digits, at = end;
    do {
        digits[--at] = (char)('0' + n % 10);
        n /= 10;
    } while (n);
    emit((Text){digits + at, end - at});
}
static void emit_access(void) {
    OUT("{\"tuples\":[{");
    for (unsigned i = 0; i < sizeof(tuple) / sizeof(tuple[0]); ++i) {
        if (i)
            OUT(",");
        quote(tuple[i].key);
        OUT(":");
        quote(tuple[i].val);
    }
    OUT("}],\"limits\":{");
    for (unsigned i = 0; i < LIMIT_COUNT; ++i) {
        if (i)
            OUT(",");
        quote(limit_specs[i].name);
        OUT(":");
        decimal(offered[i]);
    }
    OUT("}}");
}

// All retained collections have page-size bounds. No table grows with the model.
typedef struct {
    Saved name, id;
    bool is_value;
} Member;
typedef struct {
    Saved path, selection;
} Module;
typedef enum {
    ROOT_PAGE,
    MEMBER_PAGE,
    MEMBER_DOCUMENT,
    LOOKUP_PAGE,
    REFERENCE_DOCUMENT,
    DONE
} Stage;
typedef struct {
    Stage stage;
    Saved session, snapshot, root_cursor, cursor, selection, module_path, wanted_id, wanted_name,
        reference_name;
    Module modules[16];
    Member members[16];
    unsigned module_count, module_at, member_count, member_at, module_ordinal, values;
    bool type_seen, final_seen, chunk_end;
    uint64_t offset, total_bytes;
} Operation;
static Operation op;
static Saved sessions[8];
static unsigned session_count, round;
static enum { COLD, READY, CLOSED } phase;
static bool admitted;
static Text session(void) {
    return saved(&op.session);
}
static void release_operation(void) {
    round = 0;
    memset(&op, 0, sizeof op);
}
static bool start(unsigned params) {
    Text id = get(&wire, params, S("sessionId"));
    unsigned view = field(&wire, params, S("snapshot"));
    Text snap = get(&wire, view, S("snapshotId"));
    if (round || session_count == 8 || !fits(id) || !fits(snap) ||
        !get(&wire, view, S("modelId")).n || !get(&wire, view, S("revision")).n ||
        !get(&wire, view, S("scope")).n || !lower_digest(get(&wire, view, S("contextDigest"))) ||
        !exact_tuple(field(&wire, params, S("input"))) ||
        !same(get(&wire, params, S("target")), S("text")) ||
        !empty(&wire, field(&wire, params, S("options")), '{') ||
        !empty(&wire, field(&wire, params, S("requiredGuarantees")), '['))
        return false;
    for (unsigned i = 0; i < session_count; ++i)
        if (same(id, saved(&sessions[i])))
            return false;
    uint64_t chosen[LIMIT_COUNT];
    if (!read_limits(field(&wire, params, S("limits")), chosen, offered) ||
        chosen[maxGuestStateBytes] < 1048576 || wire.len > chosen[maxFrameBytes])
        return false;
    memcpy(active, chosen, sizeof active);
    memset(&op, 0, sizeof op);
    save(&sessions[session_count++], id);
    save(&op.session, id);
    save(&op.snapshot, snap);
    op.stage = ROOT_PAGE;
    round = 1;
    return true;
}
static unsigned payload(unsigned entry, Text variant) {
    unsigned token = only(&wire, entry, '{');
    return token && token == field(&wire, entry, variant) && kind(&wire, token) == '{' ? token : 0;
}
static bool role(unsigned obj, Text name) {
    return same(get(&wire, obj, S("role")), name);
}
static bool domain(unsigned obj) {
    return same(get(&wire, obj, S("packageName")), package_name) &&
           same(get(&wire, obj, S("modulePath")), saved(&op.module_path));
}
static bool next_cursor(unsigned delivery, Saved *into) {
    unsigned next = field(&wire, delivery, S("nextCursor"));
    if (!next) {
        into->n = 0;
        return true;
    }
    Text s = str(&wire, next);
    if (!fits(s) || same(s, saved(into)))
        return false;
    save(into, s);
    return true;
}
static Text ordinal(char *out, Text prefix, unsigned n) {
    memcpy(out, prefix.p, prefix.n);
    for (unsigned i = 0; i < 6; ++i) {
        out[prefix.n + 5 - i] = '0' + n % 10;
        n /= 10;
    }
    return (Text){out, prefix.n + 6};
}
static void choose_module(void) {
    if (op.module_at < op.module_count) {
        Module *m = &op.modules[op.module_at++];
        op.module_path = m->path;
        op.selection = m->selection;
        op.cursor.n = 0;
        op.type_seen = op.final_seen = false;
        op.values = 0;
        op.offset = 0;
        op.stage = MEMBER_PAGE;
    } else
        op.stage = op.root_cursor.n ? ROOT_PAGE : DONE;
}
static bool root_page(unsigned delivery, unsigned entries) {
    op.module_at = op.module_count = 0;
    unsigned count = 0;
    if (!next_cursor(delivery, &op.root_cursor))
        return false;
    for (unsigned i = entries + 1; i < wire.tokens[entries].next; i = wire.tokens[i].next) {
        unsigned mod = payload(i, S("module"));
        if (++count > 16 || !mod || !fits(get(&wire, mod, S("documentId"))) ||
            field(&wire, mod, S("name")) || !get(&wire, mod, S("packageName")).n ||
            !get(&wire, mod, S("modulePath")).n ||
            (!role(mod, S("definition")) && !role(mod, S("specification"))))
            return false;
        if (same(get(&wire, mod, S("packageName")), S("morphir/SDK")) &&
            role(mod, S("specification")))
            continue;
        char expected[7];
        Text path = get(&wire, mod, S("modulePath")),
             selection = get(&wire, mod, S("memberSelection"));
        if (!same(get(&wire, mod, S("packageName")), package_name) || !role(mod, S("definition")) ||
            !same(path, ordinal(expected, S("m"), op.module_ordinal++)) || !fits(selection))
            return false;
        Module *m = &op.modules[op.module_count++];
        save(&m->path, path);
        save(&m->selection, selection);
    }
    choose_module();
    return true;
}
static void choose_member(void) {
    if (op.member_at < op.member_count) {
        Member *m = &op.members[op.member_at];
        op.wanted_id = m->id;
        op.wanted_name = m->name;
        op.stage = MEMBER_DOCUMENT;
    } else
        op.stage = MEMBER_PAGE;
}
static bool member_page(unsigned delivery, unsigned entries, bool lookup) {
    if (!next_cursor(delivery, &op.cursor))
        return false;
    op.member_count = op.member_at = 0;
    unsigned count = 0;
    bool found = false;
    for (unsigned i = entries + 1; i < wire.tokens[entries].next; i = wire.tokens[i].next) {
        unsigned token = payload(i, S("value"));
        bool is_value = token != 0;
        if (!token)
            token = payload(i, S("type"));
        Text name = get(&wire, token, S("name")), id = get(&wire, token, S("documentId"));
        if (++count > 16 || !token || !domain(token) || !role(token, S("definition")) ||
            !fits(name) || !fits(id) || field(&wire, token, S("memberSelection")))
            return false;
        if (lookup) {
            if (is_value && same(name, saved(&op.reference_name))) {
                if (found || same(id, saved(&op.wanted_id)))
                    return false;
                save(&op.wanted_id, id);
                save(&op.wanted_name, name);
                found = true;
            }
            continue;
        }
        char expected[11];
        if (!is_value) {
            if (op.type_seen || op.values || !same(name, S("order000000")))
                return false;
            op.type_seen = true;
        } else {
            if (!op.type_seen || op.final_seen)
                return false;
            if (same(name, final_name)) {
                if (op.values < 2 || op.cursor.n ||
                    wire.tokens[i].next != wire.tokens[entries].next)
                    return false;
                op.final_seen = true;
            } else if (op.values == 64 || !same(name, ordinal(expected, S("order"), op.values++)))
                return false;
        }
        Member *m = &op.members[op.member_count++];
        save(&m->name, name);
        save(&m->id, id);
        m->is_value = is_value;
    }
    if (lookup) {
        if (found)
            op.stage = REFERENCE_DOCUMENT;
        else if (!op.cursor.n)
            return false;
        return true;
    }
    if (!op.cursor.n && !op.final_seen)
        return false;
    choose_member();
    return true;
}
static bool read_document(unsigned delivery) {
    if (!same(get(&wire, delivery, S("documentId")), saved(&op.wanted_id)))
        return false;
    Text content = get(&wire, delivery, S("content")), digest = get(&wire, delivery, S("sha256"));
    uint64_t size;
    if (!uint_token(&wire, field(&wire, delivery, S("decodedByteLength")), &size) || !size ||
        size > DOC || size > active[maxDecodedBytesPerExchange] ||
        content.n > active[maxEncodedBytesPerExchange] || !lower_digest(digest) ||
        !decode64(content, (unsigned)size))
        return false;
    char calculated[64];
    sha256((Text){document, (unsigned)size}, calculated);
    return same(digest, (Text){calculated, 64}) &&
           parse(&doc, document, doc_strings, (unsigned)size, active[maxDepth], active[maxNodes]) &&
           same(raw(&doc, field(&doc, 1, S("formatVersion"))), S("4")) &&
           same(get(&doc, 1, S("name")), saved(&op.wanted_name));
}
static unsigned definition(Text variant) {
    unsigned def = field(&doc, 1, S("def")), pub = field(&doc, def, S("Public"));
    unsigned body = field(&doc, pub, variant);
    return pub && body && pub == only(&doc, def, '{') && body == only(&doc, pub, '{') ? body : 0;
}
static bool reference(unsigned body) {
    unsigned token = field(&doc, body, S("Reference"));
    Text fq = str(&doc, token);
    Text mod = saved(&op.module_path);
    unsigned prefix = package_name.n + mod.n + 2;
    if (!token || token != only(&doc, body, '{') || fq.n <= prefix ||
        !same((Text){fq.p, package_name.n}, package_name) || fq.p[package_name.n] != ':' ||
        !same((Text){fq.p + package_name.n + 1, mod.n}, mod) || fq.p[prefix - 1] != '#')
        return false;
    Text name = {fq.p + prefix, fq.n - prefix};
    if (!fits(name) || same(name, final_name))
        return false;
    save(&op.reference_name, name);
    op.cursor.n = 0;
    op.stage = LOOKUP_PAGE;
    return true;
}
static bool document_step(unsigned delivery, char *bytes, unsigned *length) {
    if (!read_document(delivery))
        return false;
    if (op.stage == MEMBER_DOCUMENT && !op.members[op.member_at].is_value) {
        unsigned alias = definition(S("TypeAliasDefinition"));
        if (!alias || !empty(&doc, field(&doc, alias, S("typeParams")), '[') ||
            !same(get(&doc, alias, S("typeExp")), output_type))
            return false;
        ++op.member_at;
        choose_member();
        return true;
    }
    unsigned exp = definition(S("ExpressionBody"));
    if (!exp || !empty(&doc, field(&doc, exp, S("inputTypes")), '{') ||
        !same(get(&doc, exp, S("outputType")), output_type))
        return false;
    unsigned body = field(&doc, exp, S("body"));
    if (op.stage == MEMBER_DOCUMENT && same(saved(&op.wanted_name), final_name))
        return reference(body);
    unsigned lit = field(&doc, body, S("Literal")), s = field(&doc, lit, S("StringLiteral"));
    Text text = str(&doc, s);
    if (!lit || !s || kind(&doc, s) != '"' || lit != only(&doc, body, '{') ||
        s != only(&doc, lit, '{') || text.n >= DOC)
        return false;
    unsigned n = text.n + 1;
    uint64_t delivered;
    if (!uint_token(&wire, field(&wire, delivery, S("decodedByteLength")), &delivered))
        return false;
    if (n > active[maxArtifactChunkBytes] || delivered + n > active[maxDecodedBytesPerExchange] ||
        get(&wire, delivery, S("content")).n + 4 * ((n + 2) / 3) >
            active[maxEncodedBytesPerExchange] ||
        op.offset + n > active[maxArtifactBytes] ||
        op.total_bytes + n > active[maxTotalArtifactBytes] ||
        op.total_bytes + n > active[maxSessionDiskBytes])
        return false;
    memcpy(bytes, text.p, text.n);
    bytes[text.n] = '\n';
    *length = n;
    op.chunk_end = op.stage == REFERENCE_DOCUMENT;
    // Preserve the emitting module/path and offset until step_result has written its chunk.
    if (!op.chunk_end) {
        ++op.member_at;
        choose_member();
    }
    op.total_bytes += n;
    return true;
}
static Text request_id(char id[20]) {
    // Decimal rounds remain unique beyond the frozen guest's five exchanges.
    unsigned n = round, at = 20;
    do {
        id[--at] = '0' + n % 10;
        n /= 10;
    } while (n);
    return (Text){id + at, 20 - at};
}
static bool advance(unsigned params, char *bytes, unsigned *length) {
    uint64_t supplied_round;
    if (!round || wire.len > active[maxFrameBytes] ||
        !same(get(&wire, params, S("sessionId")), session()) ||
        !uint_token(&wire, field(&wire, params, S("round")), &supplied_round) ||
        supplied_round != round)
        return false;
    unsigned delivery = only(&wire, field(&wire, params, S("deliveries")), '[');
    char id[20];
    if (!delivery || !same(get(&wire, delivery, S("requestId")), request_id(id)) ||
        !same(get(&wire, delivery, S("snapshotId")), saved(&op.snapshot)))
        return false;
    Operation before = op;
    bool valid;
    if (op.stage == ROOT_PAGE || op.stage == MEMBER_PAGE || op.stage == LOOKUP_PAGE) {
        unsigned entries = field(&wire, delivery, S("entries"));
        if (!same(get(&wire, delivery, S("kind")), S("inventory")) || kind(&wire, entries) != '[' ||
            field(&wire, delivery, S("content")) || field(&wire, delivery, S("documentId")) ||
            field(&wire, delivery, S("sha256")) || field(&wire, delivery, S("decodedByteLength")))
            return false;
        valid = op.stage == ROOT_PAGE ? root_page(delivery, entries)
                                      : member_page(delivery, entries, op.stage == LOOKUP_PAGE);
    } else {
        if (!same(get(&wire, delivery, S("kind")), S("document")) ||
            field(&wire, delivery, S("entries")) || field(&wire, delivery, S("nextCursor")))
            return false;
        valid = document_step(delivery, bytes, length);
    }
    if (!valid || (op.stage != DONE && round >= active[maxRounds])) {
        op = before;
        *length = 0;
        return false;
    }
    ++round;
    return true;
}
static void session_result(void) {
    OUT("\"result\":{\"sessionId\":");
    quote(session());
}
static void artifact_chunk(Text bytes) {
    char digest[64], content[4 * ((DOC + 2) / 3)], path[32];
    unsigned at = 0;
    memcpy(path, "orders/", 7);
    at = 7;
    memcpy(path + at, op.module_path.bytes, op.module_path.n);
    at += op.module_path.n;
    memcpy(path + at, ".txt", 4);
    at += 4;
    sha256(bytes, digest);
    unsigned n = encode64(bytes, content);
    OUT("{\"path\":");
    quote((Text){path, at});
    OUT(",\"offset\":");
    decimal(op.offset);
    OUT(",\"decodedByteLength\":");
    decimal(bytes.n);
    OUT(",\"sha256\":");
    quote((Text){digest, 64});
    OUT(",\"content\":");
    quote((Text){content, n});
    OUT(",\"end\":");
    emit(op.chunk_end ? S("true") : S("false"));
    OUT("}");
    op.offset += bytes.n;
}
static void step_result(Text bytes) {
    session_result();
    OUT(",\"artifacts\":[");
    if (bytes.n)
        artifact_chunk(bytes);
    OUT("],\"diagnostics\":[]");
    if (bytes.n && op.chunk_end) {
        op.chunk_end = false;
        choose_module();
    }
    if (op.stage == DONE) {
        OUT(",\"state\":\"complete\"}");
        round = 0;
        return;
    }
    OUT(",\"state\":\"continue\",\"round\":");
    decimal(round);
    OUT(",\"requests\":[{\"requestId\":");
    char id[20];
    quote(request_id(id));
    if (op.stage == ROOT_PAGE || op.stage == MEMBER_PAGE || op.stage == LOOKUP_PAGE) {
        OUT(",\"kind\":\"inventory\",\"selection\":");
        quote(op.stage == ROOT_PAGE ? S("root") : saved(&op.selection));
        OUT(",\"pageSize\":16");
        Saved *cursor = op.stage == ROOT_PAGE ? &op.root_cursor : &op.cursor;
        if (cursor->n) {
            OUT(",\"cursor\":");
            quote(saved(cursor));
        }
    } else {
        OUT(",\"kind\":\"document\",\"documentId\":");
        quote(saved(&op.wanted_id));
    }
    OUT("}]}");
}
static void continuation(void) {
    step_result((Text){0});
}
static void error(Text code, Text message) {
    OUT("\"error\":{\"code\":");
    emit(code);
    OUT(",\"message\":");
    quote(message);
    OUT("}");
}
static void invalid_params(void) {
    error(S("-32602"), S("Invalid bounded generation parameters"));
}
static void dispatch(Text method, unsigned params) {
    if (phase == CLOSED) {
        error(S("-32014"), S("Invalid session state"));
        return;
    }
    if (same(method, S("morphir.initialize"))) {
        if (phase != COLD) {
            error(S("-32600"), S("Already initialized"));
            return;
        }
        unsigned versions = field(&wire, params, S("protocolVersions"));
        unsigned host = field(&wire, params, S("host"));
        if (kind(&wire, versions) != '[' || kind(&wire, field(&wire, host, S("name"))) != '"' ||
            kind(&wire, field(&wire, host, S("version"))) != '"') {
            invalid_params();
            return;
        }
        if (!includes_version(versions)) {
            error(S("-32011"), S("No supported protocol version"));
            return;
        }
        admitted = match_offer(field(&wire, params, S("modelAccess")));
        phase = READY;
        OUT("\"result\":{\"protocolVersion\":\"0.2.0-draft.2\",\"extension\":{\"id\":\"org.finos."
            "morphir.orders\","
            "\"name\":\"Orders "
            "generator\",\"version\":\"0.1.0\",\"types\":[\"backend\"]},\"capabilities\":{"
            "\"backend\":{\"targets\":[\"text\"],\"irVersions\":[\"4.0.0\"],\"generate\":false}");
        if (admitted) {
            OUT(",\"modelAccess\":");
            emit_access();
        }
        OUT("}}");
        return;
    }
    if (same(method, S("morphir.shutdown")) && phase == READY) {
        if (params && !empty(&wire, params, '{')) {
            invalid_params();
            return;
        }
        release_operation();
        phase = CLOSED;
        OUT("\"result\":{}");
        return;
    }
    const bool is_start = same(method, S("morphir.backend.generateModel.start"));
    const bool is_advance = same(method, S("morphir.backend.generateModel.advance"));
    const bool is_cancel = same(method, S("morphir.backend.generateModel.cancel"));
    if (phase == COLD && !is_start && !is_advance && !is_cancel) {
        error(S("-32014"), S("Invalid session state"));
    } else if (!is_start && !is_advance && !is_cancel) {
        error(S("-32601"), S("Unknown method"));
    } else if (!admitted) {
        error(S("-32013"), S("Bounded generation was not admitted"));
    } else if (is_start) {
        if (start(params))
            continuation();
        else
            invalid_params();
    } else if (is_advance) {
        char bytes[DOC];
        unsigned length = 0;
        if (!advance(params, bytes, &length))
            invalid_params();
        else
            step_result((Text){bytes, length});
    } else if (round && same(get(&wire, params, S("sessionId")), session())) {
        session_result();
        OUT("}");
        release_operation();
    } else {
        invalid_params();
    }
}

__attribute__((export_name("handle"))) int handle(void) {
    uint64_t n = input_length();
    if (n > FRAME)
        return 1;
    for (unsigned i = 0; i < n; ++i)
        frame[i] = (char)input_load_u8(i);
    if (!parse(&wire, frame, frame_strings, (unsigned)n, DEPTH, TOKENS) ||
        !same(get(&wire, 1, S("jsonrpc")), S("2.0")))
        return 1;
    unsigned id = field(&wire, 1, S("id"));
    // This fixture refuses a handle call on a notification. The transport must skip it.
    if (!id)
        __builtin_trap();
    if (kind(&wire, id) != '"' && kind(&wire, id) != '0')
        return 1;
    Text rpc_id = raw(&wire, id);
    if (rpc_id.n > ID_BYTES * 6 + 2)
        return 1;
    Text method = get(&wire, 1, S("method"));
    if (!method.n || (same(method, S("morphir.initialized")) || same(method, S("morphir.exit"))))
        return 1;
    reply_len = 0;
    overflow = false;
    OUT("{\"jsonrpc\":\"2.0\",\"id\":");
    emit(rpc_id);
    OUT(",");
    dispatch(method, field(&wire, 1, S("params")));
    OUT("}");
    if (overflow)
        return 1;
    uint64_t block = alloc(reply_len);
    if (!block)
        return 1;
    for (unsigned i = 0; i < reply_len; ++i)
        store_u8(block + i, (unsigned char)reply[i]);
    output_set(block, reply_len);
    return 0;
}
