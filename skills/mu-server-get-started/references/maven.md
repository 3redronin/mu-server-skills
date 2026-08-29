# Maven setup

Use the project's existing dependency-management and property conventions. Add exactly one direct mu-server dependency:

```xml
<properties>
    <maven.compiler.release>17</maven.compiler.release>
    <mu-server.version>2.4.1</mu-server.version>
</properties>

<dependencies>
    <dependency>
        <groupId>io.muserver</groupId>
        <artifactId>mu-server</artifactId>
        <version>${mu-server.version}</version>
    </dependency>
</dependencies>
```

Set `maven.compiler.release` to the selected Java version. Set `mu-server.version` to the stable release resolved for the task; `2.4.1` above is the offline fallback, not an instruction to downgrade or replace an existing version.

For a new project, keep the POM otherwise minimal. Use the standard `src/main/java` and `src/main/resources` layout. Do not add `mu-server-rest` or a Jakarta REST API dependency for direct handlers.

Use an existing application runner when one is present. For a bare new POM, the application can be run without adding a runtime dependency:

```bash
mvn compile org.codehaus.mojo:exec-maven-plugin:3.6.3:java \
  -Dexec.mainClass=example.Main
```

Adapt the main class name to the generated package. A project that already standardizes Maven plugin versions should declare or invoke the runner according to that convention.
