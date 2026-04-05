package org.jdalang.plugin;

import com.intellij.extapi.psi.PsiFileBase;
import com.intellij.openapi.fileTypes.FileType;
import com.intellij.psi.FileViewProvider;
import org.jetbrains.annotations.NotNull;

public class JdaFile extends PsiFileBase {
    public JdaFile(@NotNull FileViewProvider viewProvider) {
        super(viewProvider, JdaLanguage.INSTANCE);
    }

    @NotNull
    @Override
    public FileType getFileType() {
        return JdaFileType.INSTANCE;
    }

    @Override
    public String toString() {
        return "Jda File";
    }
}
