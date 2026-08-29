# Gradle setup

Use the project's existing repository, version-catalog, toolchain, and application conventions. Add exactly one direct `io.muserver:mu-server` dependency. Do not convert between Groovy and Kotlin DSL.

For a new project, use the `application` plugin so `gradle run` works. The examples use Java 17 and the offline mu-server fallback; replace both with the versions selected for the task.

## Groovy DSL

```groovy
plugins {
    id 'application'
}

repositories {
    mavenCentral()
}

java {
    toolchain {
        languageVersion = JavaLanguageVersion.of(17)
    }
}

dependencies {
    implementation 'io.muserver:mu-server:2.4.1'
}

application {
    mainClass = 'example.Main'
}
```

## Kotlin DSL

```kotlin
plugins {
    application
}

repositories {
    mavenCentral()
}

java {
    toolchain {
        languageVersion = JavaLanguageVersion.of(17)
    }
}

dependencies {
    implementation("io.muserver:mu-server:2.4.1")
}

application {
    mainClass = "example.Main"
}
```

Set the toolchain to the selected Java version. Set the dependency to the stable release resolved for the task; `2.4.1` is the offline fallback, not an instruction to downgrade or replace an existing version. Run with the existing wrapper when present, otherwise use the available Gradle installation.
