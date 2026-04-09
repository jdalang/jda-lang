package org.jdalang.plugin;

import com.intellij.execution.configurations.GeneralCommandLine;
import com.intellij.openapi.project.Project;
import com.intellij.openapi.vfs.VirtualFile;
import com.intellij.platform.lsp.api.LspServerSupportProvider;
import com.intellij.platform.lsp.api.ProjectWideLspServerDescriptor;
import org.jetbrains.annotations.NotNull;

import java.io.File;
import java.nio.file.Path;

/**
 * Connects to the Jda Language Server (jda-lsp.sh) for go-to-definition,
 * hover, diagnostics, and completion.
 */
public class JdaLspServerSupportProvider implements LspServerSupportProvider {
    @Override
    public void fileOpened(@NotNull Project project, @NotNull VirtualFile file, @NotNull LspServerStarter serverStarter) {
        if (file.getName().endsWith(".jda")) {
            serverStarter.ensureServerStarted(new JdaLspServerDescriptor(project));
        }
    }

    private static class JdaLspServerDescriptor extends ProjectWideLspServerDescriptor {
        JdaLspServerDescriptor(@NotNull Project project) {
            super(project, "Jda");
        }

        @NotNull
        @Override
        public GeneralCommandLine createCommandLine() {
            String lspPath = findLspScript();
            return new GeneralCommandLine(lspPath);
        }

        @Override
        public boolean isSupportedFile(@NotNull VirtualFile file) {
            return file.getName().endsWith(".jda");
        }

        private String findLspScript() {
            // 1. Check project root for tools/jda-lsp.sh
            String basePath = getProject().getBasePath();
            if (basePath != null) {
                File candidate = Path.of(basePath, "tools", "jda-lsp.sh").toFile();
                if (candidate.exists() && candidate.canExecute()) {
                    return candidate.getAbsolutePath();
                }
            }

            // 2. Check PATH for jda-lsp
            String pathEnv = System.getenv("PATH");
            if (pathEnv != null) {
                for (String dir : pathEnv.split(File.pathSeparator)) {
                    File candidate = new File(dir, "jda-lsp");
                    if (candidate.exists() && candidate.canExecute()) {
                        return candidate.getAbsolutePath();
                    }
                    candidate = new File(dir, "jda-lsp.sh");
                    if (candidate.exists() && candidate.canExecute()) {
                        return candidate.getAbsolutePath();
                    }
                }
            }

            // 3. Fallback — user must configure
            return "jda-lsp";
        }
    }
}
