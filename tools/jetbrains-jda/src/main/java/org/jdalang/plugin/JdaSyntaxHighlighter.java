package org.jdalang.plugin;

import com.intellij.lexer.Lexer;
import com.intellij.openapi.editor.DefaultLanguageHighlighterColors;
import com.intellij.openapi.editor.HighlighterColors;
import com.intellij.openapi.editor.colors.TextAttributesKey;
import com.intellij.openapi.fileTypes.SyntaxHighlighterBase;
import com.intellij.psi.tree.IElementType;
import org.jetbrains.annotations.NotNull;

import static com.intellij.openapi.editor.colors.TextAttributesKey.createTextAttributesKey;

public class JdaSyntaxHighlighter extends SyntaxHighlighterBase {
    // Attribute keys
    public static final TextAttributesKey COMMENT =
        createTextAttributesKey("JDA_COMMENT", DefaultLanguageHighlighterColors.LINE_COMMENT);
    public static final TextAttributesKey STRING =
        createTextAttributesKey("JDA_STRING", DefaultLanguageHighlighterColors.STRING);
    public static final TextAttributesKey NUMBER =
        createTextAttributesKey("JDA_NUMBER", DefaultLanguageHighlighterColors.NUMBER);
    public static final TextAttributesKey KEYWORD =
        createTextAttributesKey("JDA_KEYWORD", DefaultLanguageHighlighterColors.KEYWORD);
    public static final TextAttributesKey TYPE =
        createTextAttributesKey("JDA_TYPE", DefaultLanguageHighlighterColors.CLASS_NAME);
    public static final TextAttributesKey BUILTIN =
        createTextAttributesKey("JDA_BUILTIN", DefaultLanguageHighlighterColors.PREDEFINED_SYMBOL);
    public static final TextAttributesKey CONSTANT =
        createTextAttributesKey("JDA_CONSTANT", DefaultLanguageHighlighterColors.CONSTANT);
    public static final TextAttributesKey OPERATOR =
        createTextAttributesKey("JDA_OPERATOR", DefaultLanguageHighlighterColors.OPERATION_SIGN);
    public static final TextAttributesKey BRACES =
        createTextAttributesKey("JDA_BRACES", DefaultLanguageHighlighterColors.BRACES);
    public static final TextAttributesKey BRACKETS =
        createTextAttributesKey("JDA_BRACKETS", DefaultLanguageHighlighterColors.BRACKETS);
    public static final TextAttributesKey PARENS =
        createTextAttributesKey("JDA_PARENS", DefaultLanguageHighlighterColors.PARENTHESES);
    public static final TextAttributesKey IDENTIFIER =
        createTextAttributesKey("JDA_IDENTIFIER", DefaultLanguageHighlighterColors.IDENTIFIER);
    public static final TextAttributesKey BAD_CHARACTER =
        createTextAttributesKey("JDA_BAD_CHARACTER", HighlighterColors.BAD_CHARACTER);

    private static final TextAttributesKey[] COMMENT_KEYS = {COMMENT};
    private static final TextAttributesKey[] STRING_KEYS = {STRING};
    private static final TextAttributesKey[] NUMBER_KEYS = {NUMBER};
    private static final TextAttributesKey[] KEYWORD_KEYS = {KEYWORD};
    private static final TextAttributesKey[] TYPE_KEYS = {TYPE};
    private static final TextAttributesKey[] BUILTIN_KEYS = {BUILTIN};
    private static final TextAttributesKey[] CONSTANT_KEYS = {CONSTANT};
    private static final TextAttributesKey[] OPERATOR_KEYS = {OPERATOR};
    private static final TextAttributesKey[] BRACE_KEYS = {BRACES};
    private static final TextAttributesKey[] BRACKET_KEYS = {BRACKETS};
    private static final TextAttributesKey[] PAREN_KEYS = {PARENS};
    private static final TextAttributesKey[] IDENTIFIER_KEYS = {IDENTIFIER};
    private static final TextAttributesKey[] BAD_KEYS = {BAD_CHARACTER};
    private static final TextAttributesKey[] EMPTY_KEYS = {};

    @NotNull
    @Override
    public Lexer getHighlightingLexer() {
        return new JdaLexer();
    }

    @Override
    public TextAttributesKey @NotNull [] getTokenHighlights(IElementType tokenType) {
        if (tokenType == JdaTokenTypes.COMMENT) return COMMENT_KEYS;
        if (tokenType == JdaTokenTypes.STRING) return STRING_KEYS;
        if (tokenType == JdaTokenTypes.NUMBER) return NUMBER_KEYS;
        if (tokenType == JdaTokenTypes.KEYWORD_CONTROL) return KEYWORD_KEYS;
        if (tokenType == JdaTokenTypes.KEYWORD_DECL) return KEYWORD_KEYS;
        if (tokenType == JdaTokenTypes.KEYWORD_OTHER) return KEYWORD_KEYS;
        if (tokenType == JdaTokenTypes.TYPE_PRIMITIVE) return TYPE_KEYS;
        if (tokenType == JdaTokenTypes.TYPE_NAME) return TYPE_KEYS;
        if (tokenType == JdaTokenTypes.BUILTIN_FN) return BUILTIN_KEYS;
        if (tokenType == JdaTokenTypes.CONSTANT_LANG) return CONSTANT_KEYS;
        if (tokenType == JdaTokenTypes.OPERATOR) return OPERATOR_KEYS;
        if (tokenType == JdaTokenTypes.LBRACE || tokenType == JdaTokenTypes.RBRACE) return BRACE_KEYS;
        if (tokenType == JdaTokenTypes.LBRACKET || tokenType == JdaTokenTypes.RBRACKET) return BRACKET_KEYS;
        if (tokenType == JdaTokenTypes.LPAREN || tokenType == JdaTokenTypes.RPAREN) return PAREN_KEYS;
        if (tokenType == JdaTokenTypes.IDENTIFIER) return IDENTIFIER_KEYS;
        if (tokenType == JdaTokenTypes.BAD_CHARACTER) return BAD_KEYS;
        return EMPTY_KEYS;
    }
}
