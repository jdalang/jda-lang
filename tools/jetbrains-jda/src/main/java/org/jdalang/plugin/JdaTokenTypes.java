package org.jdalang.plugin;

import com.intellij.psi.tree.IElementType;
import com.intellij.psi.tree.TokenSet;

public class JdaTokenTypes {
    // Token types
    public static final IElementType COMMENT = new IElementType("COMMENT", JdaLanguage.INSTANCE);
    public static final IElementType STRING = new IElementType("STRING", JdaLanguage.INSTANCE);
    public static final IElementType NUMBER = new IElementType("NUMBER", JdaLanguage.INSTANCE);
    public static final IElementType KEYWORD_CONTROL = new IElementType("KEYWORD_CONTROL", JdaLanguage.INSTANCE);
    public static final IElementType KEYWORD_DECL = new IElementType("KEYWORD_DECL", JdaLanguage.INSTANCE);
    public static final IElementType KEYWORD_OTHER = new IElementType("KEYWORD_OTHER", JdaLanguage.INSTANCE);
    public static final IElementType TYPE_PRIMITIVE = new IElementType("TYPE_PRIMITIVE", JdaLanguage.INSTANCE);
    public static final IElementType TYPE_NAME = new IElementType("TYPE_NAME", JdaLanguage.INSTANCE);
    public static final IElementType BUILTIN_FN = new IElementType("BUILTIN_FN", JdaLanguage.INSTANCE);
    public static final IElementType IDENTIFIER = new IElementType("IDENTIFIER", JdaLanguage.INSTANCE);
    public static final IElementType CONSTANT_LANG = new IElementType("CONSTANT_LANG", JdaLanguage.INSTANCE);
    public static final IElementType OPERATOR = new IElementType("OPERATOR", JdaLanguage.INSTANCE);
    public static final IElementType LBRACE = new IElementType("LBRACE", JdaLanguage.INSTANCE);
    public static final IElementType RBRACE = new IElementType("RBRACE", JdaLanguage.INSTANCE);
    public static final IElementType LBRACKET = new IElementType("LBRACKET", JdaLanguage.INSTANCE);
    public static final IElementType RBRACKET = new IElementType("RBRACKET", JdaLanguage.INSTANCE);
    public static final IElementType LPAREN = new IElementType("LPAREN", JdaLanguage.INSTANCE);
    public static final IElementType RPAREN = new IElementType("RPAREN", JdaLanguage.INSTANCE);
    public static final IElementType COMMA = new IElementType("COMMA", JdaLanguage.INSTANCE);
    public static final IElementType COLON = new IElementType("COLON", JdaLanguage.INSTANCE);
    public static final IElementType DOT = new IElementType("DOT", JdaLanguage.INSTANCE);
    public static final IElementType SEMICOLON = new IElementType("SEMICOLON", JdaLanguage.INSTANCE);
    public static final IElementType WHITESPACE = new IElementType("WHITESPACE", JdaLanguage.INSTANCE);
    public static final IElementType BAD_CHARACTER = new IElementType("BAD_CHARACTER", JdaLanguage.INSTANCE);

    // File-level element
    public static final IElementType FILE = new IElementType("FILE", JdaLanguage.INSTANCE);

    // Token sets
    public static final TokenSet COMMENTS = TokenSet.create(COMMENT);
    public static final TokenSet STRINGS = TokenSet.create(STRING);
    public static final TokenSet WHITESPACES = TokenSet.create(WHITESPACE);
}
