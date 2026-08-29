# Filesystem and packaging security

Read this reference for filesystem-backed handlers, deployment reviews, file updates, or packaged-resource failures.

## Trust boundary

`fileHandler` is a static-file convenience, not an authorization or storage-isolation layer. The configured root is checked as a directory, then resource lookups use ordinary `Path.resolve`, existence, directory, and file-open operations. Normal filesystem link and permission behavior therefore applies.

Build the security boundary around that fact:

- dedicate a narrow tree to public, read-only assets;
- make the tree and its ancestors non-writable to request-handling code and untrusted deployment users;
- use least-privilege process permissions so unrelated application files are not readable;
- keep keys, configuration, source, build output, logs, backups, uploads, and tenant data outside the static tree;
- avoid links in the served tree unless their targets are intentionally public and deployment policy verifies them;
- place authorization-sensitive downloads behind an application handler that maps server-owned identifiers to approved files.

Do not treat URI normalization performed by an HTTP client, proxy, or router as proof of filesystem containment. The production path may preserve or transform URI encodings differently. Add normal integration tests at the application's ingress boundary for accepted paths, rejected malformed or ambiguous paths, nested resources, and the intended filesystem boundary. Keep the test corpus defensive and specific to the application's routing and proxy stack.

If the application needs a hard containment guarantee against a mutable or attacker-controlled tree, use a storage/design boundary that supplies it rather than relying on ResourceHandler alone—for example immutable classpath resources, a dedicated static server/object store, or an application-owned resolver with an audited canonicalization and link policy.

## Runtime updates

Filesystem metadata and content are observed at request time. A deployment that updates files in place can expose mismatched HTML and asset generations or race size/last-modified collection against content reads. Prefer versioned release directories and an atomic deployment switch, retaining referenced fingerprinted assets across the HTML cache window.

The handler does not add upload coordination, quotas, locks, malware checks, atomic writes, or authorization. Serving an upload directory turns client-controlled names and bytes into public active content and couples two different trust boundaries.

## Packaging checks

Classpath resources are discovered when the handler is built. Verify the final JAR rather than only `src/main/resources`:

1. inspect the packaged artifact for the configured classpath root and case-sensitive filenames;
2. launch from a directory where the development filesystem path does not exist;
3. fetch the root index and representative nested, MIME-sensitive, and fingerprinted assets;
4. verify missing resources and SPA fall-through;
5. rebuild/restart after classpath changes rather than expecting live discovery.

For `fileOrClasspath`, also launch once from the normal development working directory to prove the filesystem branch. The two modes should expose the same URL and header contract unless an intentional difference is documented.
