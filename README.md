# Google Cloud Workload Identity Federation Buildkite Plugin [![Build status](https://badge.buildkite.com/480c7800bfe6ff5e72c2aae517e6d25da9c2e21b04b2de8e12.svg)](https://buildkite.com/buildkite/plugins-gcp-workload-identity-federation)

A Buildkite plugin to assume a Google Cloud service account using [workload identity federation](https://cloud.google.com/iam/docs/workload-identity-federation).

The plugin requests an OIDC token from Buildkite and uses it to a populate Google Cloud credentials file.

The path to the file is populated in `GOOGLE_APPLICATION_CREDENTIALS` for SDKs that use [Application Default Credentials](https://cloud.google.com/docs/authentication/application-default-credentials), and in `CLOUDSDK_AUTH_CREDENTIAL_FILE_OVERRIDE` for the `gcloud` CLI.

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

5. Configure this plugin using the workload provider audience without the leading `https:`, and the service account email address.

## Example

Add the following to your `pipeline.yml`:

```yml
steps:
  - command: |
      echo "Credentials are located at \$GOOGLE_APPLICATION_CREDENTIALS"
    plugins:
      - gcp-workload-identity-federation#v1.1.0:
          audience: "//iam.googleapis.com/projects/123456789/locations/global/workloadIdentityPools/buildkite-example-pipeline/providers/buildkite"
          service-account: "buildkite-example-pipeline@oidc-project.iam.gserviceaccount.com"
```

## Configuration

### `audience` (Required, string)

- The default audience as shown on the Workload Identity Federation Provider page, without the `https:` prefix, or a custom audience that you configure.

### `service-account` (Required, string)

- The service account for which you want to acquire an access token.

### `lifetime` (number)

- The time (in seconds) the OIDC token will be valid for before expiry. Must be a non-negative integer. If the flag is omitted or set to 0, the API will choose a default finite lifetime. (default: 0)

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
