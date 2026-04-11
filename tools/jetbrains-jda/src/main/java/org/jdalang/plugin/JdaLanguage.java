package org.jdalang.plugin;

import com.intellij.lang.Language;

public class JdaLanguage extends Language {
    public static final JdaLanguage INSTANCE = new JdaLanguage();

    private JdaLanguage() {
        super("Jda");
    }
}
