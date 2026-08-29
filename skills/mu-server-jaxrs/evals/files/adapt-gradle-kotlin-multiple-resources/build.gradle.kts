plugins {
    application
}

repositories {
    mavenCentral()
}

java {
    toolchain {
        languageVersion = JavaLanguageVersion.of(11)
    }
}

dependencies {
    implementation("io.muserver:mu-server:2.4.0")
}

application {
    mainClass = "example.Main"
}
