package org.jdalang.plugin;

import com.intellij.lang.ASTNode;
import com.intellij.lang.ParserDefinition;
import com.intellij.lang.PsiParser;
import com.intellij.lexer.Lexer;
import com.intellij.openapi.project.Project;
import com.intellij.psi.FileViewProvider;
import com.intellij.psi.PsiElement;
import com.intellij.psi.PsiFile;
import com.intellij.psi.tree.IFileElementType;
import com.intellij.psi.tree.TokenSet;
import org.jetbrains.annotations.NotNull;

/**
 * Minimal parser definition for Jda. Since we rely on the LSP for semantic
 * analysis, this just provides a lexer and file element type. No AST parsing.
 */
public class JdaParserDefinition implements ParserDefinition {
    public static final IFileElementType FILE = new IFileElementType(JdaLanguage.INSTANCE);

    @NotNull
    @Override
    public Lexer createLexer(Project project) {
        return new JdaLexer();
    }

    @NotNull
    @Override
    public PsiParser createParser(Project project) {
        // Dummy parser — LSP handles semantic analysis
        return (root, builder) -> {
            var marker = builder.mark();
            while (!builder.eof()) {
                builder.advanceLexer();
            }
            marker.done(root);
            return builder.getTreeBuilt();
        };
    }

    @NotNull
    @Override
    public IFileElementType getFileNodeType() {
        return FILE;
    }

    @NotNull
    @Override
    public TokenSet getCommentTokens() {
        return JdaTokenTypes.COMMENTS;
    }

    @NotNull
    @Override
    public TokenSet getStringLiteralElements() {
        return JdaTokenTypes.STRINGS;
    }

    @NotNull
    @Override
    public TokenSet getWhitespaceTokens() {
        return JdaTokenTypes.WHITESPACES;
    }

    @NotNull
    @Override
    public PsiElement createElement(ASTNode node) {
        return com.intellij.psi.impl.source.tree.PsiCoreCommentImpl.class.isAssignableFrom(node.getClass())
            ? new com.intellij.psi.impl.source.tree.LeafPsiElement(node.getElementType(), node.getText())
            : new com.intellij.psi.impl.source.tree.CompositePsiElement(node.getElementType()) {};
    }

    @Override
    public @NotNull PsiFile createFile(@NotNull FileViewProvider viewProvider) {
        return new JdaFile(viewProvider);
    }
}
