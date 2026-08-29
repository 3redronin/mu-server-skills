# Jakarta REST upload binding

Read this reference only for Mu Server resources that consume multipart uploads. Use the repository's `mu-server-jaxrs` workflow for resource construction, singleton safety, handler registration, providers, exception mapping, and general HTTP verification.

Annotate the resource method with `@Consumes(MediaType.MULTIPART_FORM_DATA)`. Mu's upload-specific `@FormParam` binding delegates to the same whole-multipart reader and has the same body ownership, blocking, total-size, temporary-storage, cleanup, and persistence lifecycle as direct `MuRequest` access.

Supported source-backed shapes are:

- `@FormParam("file") UploadedFile`: first matching upload; `null` when absent.
- `@FormParam("file") List<UploadedFile>` or `Collection<UploadedFile>`: all matching uploads; empty when absent.
- `Set<UploadedFile>` and supported `? extends UploadedFile` collection forms are accepted, but a set does not express multipart order or duplicate intent as clearly as a list.
- `@FormParam("file") File`: Mu obtains the first upload's `asFile()` representation; `null` when absent. Because decoder cleanup is request-scoped and storage mode is an implementation detail, persist explicitly instead of retaining this parameter.
- Mu Server 3 additionally supports `@FormParam("file") UploadedFile[]`; a missing field produces an empty array. Mu Server 2.4.1 does not support uploaded-file arrays.

Mu Server 3 does not implement Jakarta REST 3.1's `EntityPart` multipart API. Do not substitute `EntityPart`, `@FormParam InputStream`, or a whole-body `List<EntityPart>` for Mu's supported upload binding.

For scalar multipart text fields, Mu passes decoded attributes through ordinary `@FormParam` conversion. Collections represent repeated values. Keep missing, empty, default, and conversion behavior in focused HTTP tests rather than assuming a different Jakarta REST implementation's multipart extension.

Resource instances are application-owned singletons, so any quota tracker, staging registry, validator, or mutable service they hold must be thread-safe. Save accepted content before returning the response. If validation continues after the resource method, first persist into application-owned quarantine and pass only its server-controlled identifier to background work.

Mu Server 3 adds array binding but does not change the `UploadedFile` persistence or decoder-cleanup model found in 2.4.1. The artifact remains `io.muserver:mu-server`; preserve the version already selected by the application.
