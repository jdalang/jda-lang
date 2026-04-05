package org.jdalang.plugin;

import com.intellij.openapi.editor.colors.TextAttributesKey;
import com.intellij.openapi.fileTypes.SyntaxHighlighter;
import com.intellij.openapi.options.colors.AttributesDescriptor;
import com.intellij.openapi.options.colors.ColorDescriptor;
import com.intellij.openapi.options.colors.ColorSettingsPage;
import org.jetbrains.annotations.NotNull;
import org.jetbrains.annotations.Nullable;

import javax.swing.*;
import java.util.Map;

public class JdaColorSettingsPage implements ColorSettingsPage {
    private static final AttributesDescriptor[] DESCRIPTORS = {
        new AttributesDescriptor("Comment", JdaSyntaxHighlighter.COMMENT),
        new AttributesDescriptor("String", JdaSyntaxHighlighter.STRING),
        new AttributesDescriptor("Number", JdaSyntaxHighlighter.NUMBER),
        new AttributesDescriptor("Keyword", JdaSyntaxHighlighter.KEYWORD),
        new AttributesDescriptor("Type", JdaSyntaxHighlighter.TYPE),
        new AttributesDescriptor("Built-in function", JdaSyntaxHighlighter.BUILTIN),
        new AttributesDescriptor("Constant", JdaSyntaxHighlighter.CONSTANT),
        new AttributesDescriptor("Operator", JdaSyntaxHighlighter.OPERATOR),
        new AttributesDescriptor("Braces", JdaSyntaxHighlighter.BRACES),
        new AttributesDescriptor("Brackets", JdaSyntaxHighlighter.BRACKETS),
        new AttributesDescriptor("Parentheses", JdaSyntaxHighlighter.PARENS),
        new AttributesDescriptor("Identifier", JdaSyntaxHighlighter.IDENTIFIER),
    };

    @Nullable
    @Override
    public Icon getIcon() {
        return JdaFileType.INSTANCE.getIcon();
    }

    @NotNull
    @Override
    public SyntaxHighlighter getHighlighter() {
        return new JdaSyntaxHighlighter();
    }

    @NotNull
    @Override
    public String getDemoText() {
        return """
            ; Fibonacci in Jda
            const MAX = 10

            struct Point {
                x: i64
                y: i64
            }

            fn fib(n: i64) -> i64 {
                if n <= 1 { ret n }
                let a = fib(n - 1)
                let b = fib(n - 2)
                ret a + b
            }

            fn main() -> i64 {
                let result = fib(MAX)
                print("fib = ")
                print("{result}")
                print("\\n")
                ret 0
            }
            """;
    }

    @Nullable
    @Override
    public Map<String, TextAttributesKey> getAdditionalHighlightingTagToDescriptorMap() {
        return null;
    }

    @Override
    public AttributesDescriptor @NotNull [] getAttributeDescriptors() {
        return DESCRIPTORS;
    }

    @Override
    public ColorDescriptor @NotNull [] getColorDescriptors() {
        return ColorDescriptor.EMPTY_ARRAY;
    }

    @NotNull
    @Override
    public String getDisplayName() {
        return "Jda";
    }
}
