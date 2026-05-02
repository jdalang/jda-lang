package org.jdalang.plugin;

import com.intellij.lang.BracePair;
import com.intellij.lang.PairedBraceMatcher;
import com.intellij.psi.PsiFile;
import com.intellij.psi.tree.IElementType;
import org.jetbrains.annotations.NotNull;
import org.jetbrains.annotations.Nullable;

public class JdaBracketMatcher implements PairedBraceMatcher {
    private static final BracePair[] PAIRS = {
        new BracePair(JdaTokenTypes.LBRACE, JdaTokenTypes.RBRACE, true),
        new BracePair(JdaTokenTypes.LBRACKET, JdaTokenTypes.RBRACKET, false),
        new BracePair(JdaTokenTypes.LPAREN, JdaTokenTypes.RPAREN, false),
    };

    @Override
    public BracePair @NotNull [] getPairs() {
        return PAIRS;
    }

    @Override
    public boolean isPairedBracesAllowedBeforeType(@NotNull IElementType lbraceType, @Nullable IElementType contextType) {
        return true;
    }

    @Override
    public int getCodeConstructStart(PsiFile file, int openingBraceOffset) {
        return openingBraceOffset;
    }
}
