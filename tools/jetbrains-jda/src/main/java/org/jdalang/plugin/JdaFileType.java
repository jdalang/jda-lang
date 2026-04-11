package org.jdalang.plugin;

import com.intellij.openapi.fileTypes.LanguageFileType;
import com.intellij.openapi.util.IconLoader;
import org.jetbrains.annotations.NotNull;
import org.jetbrains.annotations.Nullable;

import javax.swing.*;

public class JdaFileType extends LanguageFileType {
    public static final JdaFileType INSTANCE = new JdaFileType();

    private JdaFileType() {
        super(JdaLanguage.INSTANCE);
    }

    @NotNull
    @Override
    public String getName() {
        return "Jda";
    }

    @NotNull
    @Override
    public String getDescription() {
        return "Jda language file";
    }

    @NotNull
    @Override
    public String getDefaultExtension() {
        return "jda";
    }

    @Nullable
    @Override
    public Icon getIcon() {
        return IconLoader.getIcon("/icons/jda.svg", JdaFileType.class);
    }
}
