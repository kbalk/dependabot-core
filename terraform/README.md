## `dependabot-terraform`

Terraform support for [`dependabot-core`][core-repo].

### Running locally

1. Install native helpers
   ```
   $ helpers/build helpers/install-dir/terraform
   ```

2. Install Ruby dependencies
   ```
   $ bundle install
   ```

3. Run tests
   ```
   $ bundle exec rspec spec
   ```

Note:  terraform-config-inspect is expected to be found in
`/opt/go/gopath/bin`.

[core-repo]: https://github.com/dependabot/dependabot-core
