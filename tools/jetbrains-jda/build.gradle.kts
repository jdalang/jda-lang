plugins {
    id("java")
    id("org.jetbrains.intellij") version "1.17.2"
}

group = "org.jdalang"
version = "0.1.0"

repositories {
    mavenCentral()
}

java {
    sourceCompatibility = JavaVersion.VERSION_17
    targetCompatibility = JavaVersion.VERSION_17
}

intellij {
    version.set("2024.1")
    type.set("IC") // IntelliJ IDEA Community Edition
    plugins.set(listOf())
}

tasks {
    patchPluginXml {
        sinceBuild.set("241")
        untilBuild.set("251.*")
        changeNotes.set("""
            <ul>
                <li>Initial release</li>
                <li>.jda file type recognition and syntax highlighting</li>
                <li>LSP integration via jda-lsp</li>
                <li>Bracket matching, code folding, commenting</li>
            </ul>
        """.trimIndent())
    }

    buildSearchableOptions {
        enabled = false
    }
}
