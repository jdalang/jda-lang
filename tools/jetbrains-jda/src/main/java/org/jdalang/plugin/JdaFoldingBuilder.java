package org.jdalang.plugin;

import com.intellij.lang.ASTNode;
import com.intellij.lang.folding.FoldingBuilderEx;
import com.intellij.lang.folding.FoldingDescriptor;
import com.intellij.openapi.editor.Document;
import com.intellij.openapi.util.TextRange;
import com.intellij.psi.PsiElement;
import com.intellij.psi.util.PsiTreeUtil;
import org.jetbrains.annotations.NotNull;
import org.jetbrains.annotations.Nullable;

import java.util.ArrayList;
import java.util.List;

/**
 * Folding builder for Jda — folds brace-delimited blocks (fn bodies, struct defs, etc).
 */
public class JdaFoldingBuilder extends FoldingBuilderEx {
    @Override
    public FoldingDescriptor @NotNull [] buildFoldRegions(@NotNull PsiElement root, @NotNull Document document, boolean quick) {
        List<FoldingDescriptor> descriptors = new ArrayList<>();
        String text = document.getText();

        // Simple brace matching: find { ... } pairs spanning multiple lines
        int[] stack = new int[256];
        int depth = 0;

        for (int i = 0; i < text.length(); i++) {
            char c = text.charAt(i);
            if (c == '"') {
                // Skip strings
                i++;
                while (i < text.length()) {
                    if (text.charAt(i) == '\\') { i++; }
                    else if (text.charAt(i) == '"') break;
                    i++;
                }
                continue;
            }
            if (c == ';') {
                // Skip comments
                while (i < text.length() && text.charAt(i) != '\n') i++;
                continue;
            }
            if (c == '{') {
                if (depth < stack.length) {
                    stack[depth] = i;
                }
                depth++;
            } else if (c == '}') {
                depth--;
                if (depth >= 0 && depth < stack.length) {
                    int start = stack[depth];
                    int end = i + 1;
                    int startLine = document.getLineNumber(start);
                    int endLine = document.getLineNumber(end - 1);
                    if (endLine > startLine) {
                        descriptors.add(new FoldingDescriptor(
                            root.getNode(),
                            new TextRange(start, end)
                        ));
                    }
                }
            }
        }

        return descriptors.toArray(FoldingDescriptor.EMPTY_ARRAY);
    }

    @Nullable
    @Override
    public String getPlaceholderText(@NotNull ASTNode node) {
        return "{...}";
    }

    @Override
    public boolean isCollapsedByDefault(@NotNull ASTNode node) {
        return false;
    }
}
