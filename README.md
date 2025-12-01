# Google Cloud Workload Identity Federation Buildkite Plugin [![Build status](https://badge.buildkite.com/480c7800bfe6ff5e72c2aae517e6d25da9c2e21b04b2de8e12.svg)](https://buildkite.com/buildkite/plugins-gcp-workload-identity-federation)

A Buildkite plugin to assume a Google Cloud service account using [workload identity federation](https://cloud.google.com/iam/docs/workload-identity-federation).

The plugin requests an OIDC token from Buildkite and uses it to a populate Google Cloud credentials file assuming you have followed the [corresponding setup on Google cloud](#google-cloud-configuration).

The path to the file is populated in `GOOGLE_APPLICATION_CREDENTIALS` for SDKs that use [Application Default Credentials](https://cloud.google.com/docs/authentication/application-default-credentials), and in `CLOUDSDK_AUTH_CREDENTIAL_FILE_OVERRIDE` for the `gcloud` CLI.

## Configuration

### `audience` (Optional, string)

- The default audience as shown on the Workload Identity Federation Provider page, without the `https:` prefix, or a custom audience that you configure.
- If not provided, the plugin will use the `GCP_WORKLOAD_IDENTITY_BUILDKITE_AUDIENCE` Buildkite secret. You must specify the secret at the pipeline or step level using the `secrets:` block.

### `gcp-project-id` (Required, string)

- The GCP project ID where the service account exists. This is used to construct the service account email address.

### `mode` (Optional, string)

- The access mode for the service account. Must be either `ro` (read-only) or `rw` (read-write). (default: `rw`)

### `claims` (list(string))

- A list of [claims to add to the requested buildkite oidc token](https://buildkite.com/docs/agent/v3/cli-oidc#claims-optional-claims). The agent currently supports requesting claims for `organization_id` and `pipeline_id`. If requested, these will include the respective buildkite organization and/or pipeline UUID claims in the token. (default: [])

### `hook` (string)

- Which [lifecycle hook phase](https://buildkite.com/docs/agent/v3/hooks#job-lifecycle-hooks) to run the plugin during. This can be either `pre-command` (default) or `environment`.

- The default is `pre-command` to ensure Buildkite secrets are available when using the `GCP_WORKLOAD_IDENTITY_BUILDKITE_AUDIENCE` secret. Use `environment` if you need credentials available earlier in the job lifecycle and are providing the audience directly in the plugin configuration.

### `lifetime` (number)

- The time (in seconds) the OIDC token will be valid for before expiry. Must be a non-negative integer. If the flag is omitted or set to 0, the API will choose a default finite lifetime. (default: 0)

### `render-command` (string)

- An installed binary that when specified, will run to process the values of `audience` and the constructed `service-account` via stdin.  This is intended to be used to render environment variables with an application such as `envsubst`. (default: '')

## Example

Add the following to your `pipeline.yml`:

```yml
steps:
  - command: |
      echo "Credentials are located at \$GOOGLE_APPLICATION_CREDENTIALS"
    plugins:
      - gcp-workload-identity-federation#v1.5.0:
          audience: "//iam.googleapis.com/projects/123456789/locations/global/workloadIdentityPools/buildkite-example-pipeline/providers/buildkite"
          gcp-project-id: "my-gcp-project"
```

The plugin will automatically construct the service account as: `<hashed-pipeline-slug>-ro@my-gcp-project.iam.gserviceaccount.com`

### Example using Buildkite secret for audience

```yml
steps:
  - command: |
      echo "Credentials are located at \$GOOGLE_APPLICATION_CREDENTIALS"
    secrets:
      - GCP_WORKLOAD_IDENTITY_BUILDKITE_AUDIENCE
    plugins:
      - gcp-workload-identity-federation#v1.5.0:
          gcp-project-id: "my-gcp-project"
```

### Example with explicit service account (backwards compatibility)

```yml
steps:
  - command: |
      echo "Credentials are located at \$GOOGLE_APPLICATION_CREDENTIALS"
    plugins:
      - gcp-workload-identity-federation#v1.5.0:
          audience: "//iam.googleapis.com/projects/123456789/locations/global/workloadIdentityPools/buildkite-example-pipeline/providers/buildkite"
          gcp-project-id: "network-dev-c10a"
```

## Usage with docker (compose) plugins

For the token to be available in the container(s) run by docker when using those plugins in the same step as this one, you will need to make sure to share the following with the containers:
* the volume `$BUILDKITE_OIDC_TMPDIR`
* the following environment variables:
   - `BUILDKITE_OIDC_TMPDIR`
   - `CLOUDSDK_AUTH_CREDENTIAL_FILE_OVERRIDE` (if using `gcloud`)
   - `GOOGLE_APPLICATION_CREDENTIALS` (if using any other gcp lib)

For example:

```yml
steps:
  - command: |
      echo "Credentials are located at \$GOOGLE_APPLICATION_CREDENTIALS or \$CLOUDSDK_AUTH_CREDENTIAL_FILE_OVERRIDE"
    plugins:
      - gcp-workload-identity-federation#v1.5.0:
          audience: "//iam.googleapis.com/projects/123456789/locations/global/workloadIdentityPools/buildkite-example-pipeline/providers/buildkite"
          gcp-project-id: "my-gcp-project"
      - docker#v5.9.0:
          image: <IMAGE>
          expand-volume-vars: true
          volumes:
            - \$BUILDKITE_OIDC_TMPDIR:/\$BUILDKITE_OIDC_TMPDIR
          environment:
            - BUILDKITE_OIDC_TMPDIR
            - CLOUDSDK_AUTH_CREDENTIAL_FILE_OVERRIDE  # if using 'gcloud'
            - GOOGLE_APPLICATION_CREDENTIALS          # if using literally any other gcp lib
```

## Google Cloud configuration

You should already have a Google Cloud project and a Service Account to assume. See [Google's documentation](https://cloud.google.com/iam/docs/workload-identity-federation-with-other-providers) for more detailed instructions for these steps.

1. Create a [Workload Identity Pool](https://console.cloud.google.com/iam-admin/workload-identity-pools).

   We recommend creating a different pool for each security boundary.

   In this example we're using `buildkite-example-pipeline`.

2. Add a provider to the pool.

   Use OpenID Connect, and give it a name like `buildkite`.

   Use `https://agent.buildkite.com` as the Issuer.

   Copy the value of the default audience or provide your own.

3. Configure provider attributes.

   Because Google limits the length of attributes to 127 characters, we suggest the following mapping:

   | Google | OIDC |
   | --- | --- |
   | `google.subject` | `"organization:" + assertion.sub.split(":")[1] + ":pipeline:" + assertion.sub.split(":")[3]` |
   | `attribute.pipeline_slug` | `assertion.pipeline_slug` |
   | `attribute.build_branch` | `assertion.build_branch` |

   With this mapping you can use a [CEL](https://github.com/google/cel-spec) expression to restrict which pipelines can assume the service account:

   ```cel
   google.subject == "organization:acme:pipeline:buildkite-example-pipeline"
   ```

4. Grant access to the service account.

5. Configure this plugin using the workload provider audience without the leading `https:`, along with your GCP project ID and access mode. The plugin will automatically construct the service account email address.

## Service Account Naming Convention

The plugin automatically constructs service account names using the following format:

```
<hashed-pipeline-slug>-<mode>@<gcp-project-id>.iam.gserviceaccount.com
```

Where:
- `<hashed-pipeline-slug>` is a SHA256 hash (first 18 characters) of the `BUILDKITE_PIPELINE_SLUG` environment variable, prefixed and suffixed with "a" to ensure valid GCP naming
- `<mode>` is the access mode you specify ("ro" for read-only or "rw" for read-write)
- `<gcp-project-id>` is your GCP project ID

Example:
```
aa1b2c3d4e5f6789012a-ro@my-gcp-project.iam.gserviceaccount.com
```

## Developing

To run testing, shellchecks and plugin linting use use `bk run` with the [Buildkite CLI](https://github.com/buildkite/cli).

```bash
bk run
```

Or if you want to run just the tests, you can use the docker [Plugin Tester](https://github.com/buildkite-plugins/buildkite-plugin-tester):

```bash
docker run --rm -ti -v "${PWD}":/plugin buildkite/plugin-tester:latest
```

## Contributing

1. Fork the repo
2. Make the changes
3. Run the tests
4. Commit and push your changes
5. Send a pull request
