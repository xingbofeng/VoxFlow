# Secret scanning rules

The Windows release gate scans the following scopes before packaging:

- Source and configuration files under `VoxFlow.Windows/`, including tests,
  documentation, scripts, native build metadata, and workflow definitions.
- Installer and publish output before it is archived or wrapped in the EXE
  installer.
- Environment-variable assignments and token formats used by OpenAI,
  Tencent Cloud, Alibaba Cloud, and Volcengine.

The scanner may use synthetic fixtures generated in a temporary directory to
prove that each rule fires. Fixtures must not resemble an active account and
must never be committed as apparently usable credentials. A detection reports
only the file path, line number, and rule name; it never prints the matching value.

Live credentials belong only in ignored local environment state or in the
application's CurrentUser DPAPI vault. CI must not load `.env.live`, contact a
cloud provider, or require any live credential. Any detection outside a
controlled fixture blocks the release.

The no-argument source scan skips the ignored, machine-local `.env.live` files
but still scans the committed `.env.live.example` template. Paths supplied
explicitly are release inputs: every scannable file in them, including
`.env.live`, is inspected so a copied local environment file cannot silently
enter a publish or installer artifact.
