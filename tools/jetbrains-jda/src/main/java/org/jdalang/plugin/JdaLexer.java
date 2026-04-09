package org.jdalang.plugin;

import com.intellij.lexer.LexerBase;
import com.intellij.psi.tree.IElementType;
import org.jetbrains.annotations.NotNull;
import org.jetbrains.annotations.Nullable;

import java.util.Set;

public class JdaLexer extends LexerBase {
    private CharSequence buffer;
    private int bufferEnd;
    private int tokenStart;
    private int tokenEnd;
    private IElementType tokenType;

    private static final Set<String> CONTROL_KEYWORDS = Set.of(
        "if", "else", "loop", "for", "match", "ret", "break", "continue", "in"
    );

    private static final Set<String> DECL_KEYWORDS = Set.of(
        "fn", "let", "mut", "const", "struct", "enum", "impl", "import", "defer"
    );

    private static final Set<String> OTHER_KEYWORDS = Set.of(
        "spawn", "own", "ref", "and", "or", "not", "asm", "volatile", "as",
        "unsafe", "pub", "use", "type", "trait", "where"
    );

    private static final Set<String> PRIMITIVE_TYPES = Set.of(
        "i8", "i16", "i32", "i64", "u8", "u16", "u32", "u64",
        "f32", "f64", "bool", "void"
    );

    private static final Set<String> BUILTIN_FUNCTIONS = Set.of(
        "syscall", "print", "assert_eq", "assert_ne", "assert_true", "assert_close",
        "f64_from_int", "f64_add", "f64_sub", "f64_mul", "f64_div", "f64_sqrt",
        "f64_neg", "f64_cmp", "f64_print",
        "tensor_new", "tensor_get", "tensor_set", "tensor_fill", "tensor_free",
        "tensor_shape", "tensor_len",
        "chan_new", "chan_send", "chan_recv", "chan_close",
        "atomic_load", "atomic_store", "atomic_cmpxchg", "atomic_fetch_add",
        "alloc_pages", "poke_byte", "call_closure"
    );

    private static final Set<String> LANG_CONSTANTS = Set.of(
        "true", "false", "none", "some", "ok", "err"
    );

    @Override
    public void start(@NotNull CharSequence buffer, int startOffset, int endOffset, int initialState) {
        this.buffer = buffer;
        this.bufferEnd = endOffset;
        this.tokenStart = startOffset;
        this.tokenEnd = startOffset;
        this.tokenType = null;
        advance();
    }

    @Override
    public int getState() {
        return 0;
    }

    @Nullable
    @Override
    public IElementType getTokenType() {
        return tokenType;
    }

    @Override
    public int getTokenStart() {
        return tokenStart;
    }

    @Override
    public int getTokenEnd() {
        return tokenEnd;
    }

    @Override
    public void advance() {
        tokenStart = tokenEnd;
        if (tokenStart >= bufferEnd) {
            tokenType = null;
            return;
        }

        char c = buffer.charAt(tokenStart);

        // Whitespace
        if (c == ' ' || c == '\t' || c == '\n' || c == '\r') {
            tokenEnd = tokenStart + 1;
            while (tokenEnd < bufferEnd) {
                char w = buffer.charAt(tokenEnd);
                if (w != ' ' && w != '\t' && w != '\n' && w != '\r') break;
                tokenEnd++;
            }
            tokenType = JdaTokenTypes.WHITESPACE;
            return;
        }

        // Comments: ; to end of line (but ;; is also a comment)
        if (c == ';' && (tokenStart + 1 >= bufferEnd || buffer.charAt(tokenStart + 1) != '=')) {
            // Check it's not a standalone ; used as statement separator
            // In Jda, ; is always a comment start
            tokenEnd = tokenStart + 1;
            while (tokenEnd < bufferEnd && buffer.charAt(tokenEnd) != '\n') {
                tokenEnd++;
            }
            tokenType = JdaTokenTypes.COMMENT;
            return;
        }

        // Strings
        if (c == '"') {
            tokenEnd = tokenStart + 1;
            while (tokenEnd < bufferEnd) {
                char s = buffer.charAt(tokenEnd);
                if (s == '\\' && tokenEnd + 1 < bufferEnd) {
                    tokenEnd += 2; // skip escape
                    continue;
                }
                if (s == '"') {
                    tokenEnd++;
                    break;
                }
                tokenEnd++;
            }
            tokenType = JdaTokenTypes.STRING;
            return;
        }

        // Numbers: 0x, 0b, decimals
        if (Character.isDigit(c)) {
            tokenEnd = tokenStart;
            if (c == '0' && tokenEnd + 1 < bufferEnd) {
                char next = buffer.charAt(tokenEnd + 1);
                if (next == 'x' || next == 'X') {
                    tokenEnd += 2;
                    while (tokenEnd < bufferEnd && isHexDigit(buffer.charAt(tokenEnd))) tokenEnd++;
                    tokenType = JdaTokenTypes.NUMBER;
                    return;
                }
                if (next == 'b' || next == 'B') {
                    tokenEnd += 2;
                    while (tokenEnd < bufferEnd && (buffer.charAt(tokenEnd) == '0' || buffer.charAt(tokenEnd) == '1')) tokenEnd++;
                    tokenType = JdaTokenTypes.NUMBER;
                    return;
                }
            }
            while (tokenEnd < bufferEnd && Character.isDigit(buffer.charAt(tokenEnd))) tokenEnd++;
            // Check for float
            if (tokenEnd < bufferEnd && buffer.charAt(tokenEnd) == '.') {
                int dotPos = tokenEnd;
                tokenEnd++;
                if (tokenEnd < bufferEnd && Character.isDigit(buffer.charAt(tokenEnd))) {
                    while (tokenEnd < bufferEnd && Character.isDigit(buffer.charAt(tokenEnd))) tokenEnd++;
                } else {
                    tokenEnd = dotPos; // not a float, just an integer followed by dot
                }
            }
            tokenType = JdaTokenTypes.NUMBER;
            return;
        }

        // Identifiers and keywords
        if (Character.isLetter(c) || c == '_') {
            tokenEnd = tokenStart;
            while (tokenEnd < bufferEnd && isIdentChar(buffer.charAt(tokenEnd))) tokenEnd++;
            String word = buffer.subSequence(tokenStart, tokenEnd).toString();

            if (CONTROL_KEYWORDS.contains(word)) {
                tokenType = JdaTokenTypes.KEYWORD_CONTROL;
            } else if (DECL_KEYWORDS.contains(word)) {
                tokenType = JdaTokenTypes.KEYWORD_DECL;
            } else if (OTHER_KEYWORDS.contains(word)) {
                tokenType = JdaTokenTypes.KEYWORD_OTHER;
            } else if (PRIMITIVE_TYPES.contains(word)) {
                tokenType = JdaTokenTypes.TYPE_PRIMITIVE;
            } else if (BUILTIN_FUNCTIONS.contains(word)) {
                tokenType = JdaTokenTypes.BUILTIN_FN;
            } else if (LANG_CONSTANTS.contains(word)) {
                tokenType = JdaTokenTypes.CONSTANT_LANG;
            } else if (Character.isUpperCase(c)) {
                tokenType = JdaTokenTypes.TYPE_NAME;
            } else {
                tokenType = JdaTokenTypes.IDENTIFIER;
            }
            return;
        }

        // Brackets and punctuation
        tokenEnd = tokenStart + 1;
        switch (c) {
            case '{': tokenType = JdaTokenTypes.LBRACE; return;
            case '}': tokenType = JdaTokenTypes.RBRACE; return;
            case '[': tokenType = JdaTokenTypes.LBRACKET; return;
            case ']': tokenType = JdaTokenTypes.RBRACKET; return;
            case '(': tokenType = JdaTokenTypes.LPAREN; return;
            case ')': tokenType = JdaTokenTypes.RPAREN; return;
            case ',': tokenType = JdaTokenTypes.COMMA; return;
            case ':': tokenType = JdaTokenTypes.COLON; return;
            case '.': tokenType = JdaTokenTypes.DOT; return;
        }

        // Multi-char operators: ->, =>, ==, !=, <=, >=, <<, >>
        if (tokenStart + 1 < bufferEnd) {
            char next = buffer.charAt(tokenStart + 1);
            if ((c == '-' && next == '>') || (c == '=' && next == '>') ||
                (c == '=' && next == '=') || (c == '!' && next == '=') ||
                (c == '<' && next == '=') || (c == '>' && next == '=') ||
                (c == '<' && next == '<') || (c == '>' && next == '>') ||
                (c == '+' && next == '=') || (c == '-' && next == '=') ||
                (c == '*' && next == '=') || (c == '/' && next == '=')) {
                tokenEnd = tokenStart + 2;
                tokenType = JdaTokenTypes.OPERATOR;
                return;
            }
        }

        // Single-char operators
        if ("+-*/%&|^~!=<>&".indexOf(c) >= 0) {
            tokenType = JdaTokenTypes.OPERATOR;
            return;
        }

        // Anything else
        tokenType = JdaTokenTypes.BAD_CHARACTER;
    }

    @NotNull
    @Override
    public CharSequence getBufferSequence() {
        return buffer;
    }

    @Override
    public int getBufferEnd() {
        return bufferEnd;
    }

    private static boolean isIdentChar(char c) {
        return Character.isLetterOrDigit(c) || c == '_';
    }

    private static boolean isHexDigit(char c) {
        return (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F');
    }
}
