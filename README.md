
This module receives a string and transforms it by replacing
every secret reference with its actual value, retrieved from the appropriate
central secret store.

Reference syntax is :

    //@secret/<store>:<name>[:<key>]//

where :

- \<store> is the secret store to search. Today, only 'aws' is
  supported.
- \<name> is the secret name (in the store)
- \<key> is optional and must be provided when retrieving from a multi-valued secret. On AWS 
  Secrets Manager, it is optional but common practice.

Today, only AWS secrets manager is supported but others, like Hashicorp Vault, should be quite easy to add.

Note that every secret reference must be surrounded by space characters or line start/end. It means that,
if the reference is not at the beginning of a line, it must be preceded with a space character and, if
it is not at the end of a line, it must be followed by a space character.

## Use case

Let's consider a typical Terraform/Terragrunt configuration
where a git-managed file tree defines a platform, each component associated with a unique subdirectory.
For instance, everything related to the 'dev' environment of the 'myapp' application may be stored
in the 'myapp/dev' directory.

Let's say that this component/instance is configurable and its configuration parameters are contained
in a YAML file stored in the component directory. Its contents is read by terraform using code like
(terragrunt syntax) :

    locals {
        ...
        cfg = file("./app_values.yaml")
        }
        
    #----------
        
    inputs = {
        ...
        cfg     = local.cfg
    }

Here is an excerpt of the original configuration file :

    ...
    newrelic:
        license: "eu01xxf2e877c4b8997F24893ac47abNRAL"
        collector: "collector.eu01.nr-data.net"
    
    sentry:
        dsn: "https://1654891230161811352@465457211646516o.ingest.sentry.io/465457211646516"
    ...

We see that it exposes some sensitive data. This data is stored in the git repository (and history)
and that's what we want to avoid.

I initially thought it was a job for
[sealed secrets](https://github.com/bitnami-labs/sealed-secrets), but I often need to
add/modify sensitive values and, after a few days, the manual process to refresh sealed secrets
became too heavy and error-prone. In theory, it could be automated but it is not so easy to do it
in a secure way, and I rapidly gave up. Another important point is that, in their current form,
sealed secrets require manually replicating sensitive data everytime it is
modified and such human-managed synchronization is something I try to eliminate from my environment,
not to add.

So, I was looking for some sort of 'templating' system that would take a string as input
and replace every occurence of a known pattern with the appropriate
secret value retrieved from various secret stores. I also wanted the system to be flexible :
adding a new secret value to the configuration must not require more than creating the secret
in the secret store and adding a reference to the configuration file.
As I didn't find such a tool, I decided to write a terraform module for it.
And, as I am a nice guy, I am sharing it with you.

So, let's have a look to our new configuration file :

    ...
    newrelic:
      license: //@secret/aws:cfg-myapp-newrelic:license//
      collector: "collector.eu01.nr-data.net"
    
    sentry:
      dsn: //@secret/aws:cfg-myapp-sentry:dsn//
    ...

You can see that sensitive values were replaced by references delimited by '//' characters.
Each reference uniquely identifies the location where the secret value is actually stored.

About flexibility, note that we just replace what we want. In our example, 'newrelic.collector' is
not considered sensitive and remains stored in clear. This also allows a smoother migration,
creating and replacing secrets at your own pace.

You may also note that, each time a terraform plan is run, data is retrieved from its original
location, eliminating the manually-managed synchronization process you need when storing values
in clear or using sealed secrets. This makes mechanisms like automated secret rotation
much simpler to implement.

Now, adding a sensitive value becomes trivial : just create the secret in your secret store and
add a '//...//' reference where it will be replaced by its actual value.

Here is an example of some terraform code to run the expansion :

    module cfg {
      source = "git::git@github.com:flaupretre/terraform-secret-bridge.git?ref=v1.0.0"
    
      input = var.cfg
    }
    
In this case, the expanded string will be available as 'module.cfg.result'.

Note that this mechanism is especially well adapted to increase the security level of
an existing project because, when used with a structured document (yaml, json, etc), the document
structure remains unchanged, minimizing the required changes
in the code. It is especially well-suited to stop exposing sensitive data in
a Helm chart 'Values' map (when running Helm through Terraform with a 'helm_release' resource).
There, you just send the yamldecode()d expanded configuration to the chart instead of the original
map and you keep your chart code unchanged.

## Some notes about security

Please note that the present process allows to avoid exposing sensitive data in the terraform
repository, but not in the terraform state. Getting rid of sensitive data in the
terraform state or obfuscating it is a much more complex issue and out of scope here.

So, keep in mind that the 'result' output contains every secret values in clear and
is stored in the terraform state. This is your
responsibility to protect your terraform state, local or remote, from unauthorized access.

## Secret stores

### AWS Secrets Manager

This is the only store we are supporting today.

AWS secrets often contain several key/value pairs, encoded as a JSON map. If the secret you're retrieving does not contain such a map, just don't set the '[:\<key\>]'part in your reference and you will retrieve your 'PlainText' secret string as-is. 

## Using a prefix

You may set an optional prefix string when calling the module. This prefix is added at the beginning
of every secret name before retrieving it from the secret stores.

This may allow to restrict the set of secrets that may potentially be used in a configuration.
For instance, a prefix in the form 'cfg-myapp-' may be a good way to ensure that the 'myapp' application can
only access a restricted set of secrets defined for itself.

Then, our example would become :

    module cfg {
      source = "git::git@github.com:flaupretre/terraform-secret-bridge.git?ref=v1.0.0"
      
      prefix = "cfg-myapp-"
      cfg = var.cfg
    }

and :

    ...
    newrelic:
      license: //@secret/aws:newrelic:license//
      collector: "collector.eu01.nr-data.net"
    
    sentry:
      dsn: //@secret/aws:sentry:dsn//
     ...

## Errors

When your input string contains a reference to a non-existing secret, execution fails 
and you get a message saying that the secret does not exist.

When the secrets exists but the key you're referencing does not, you receive a message saying :

    │ Error: Invalid function argument
    │
    │   on .terraform/modules/cfg/main.tf line 39, in locals:
    │   39:       file("***ERROR: '${k}' secret key not found ***") : null
    │
    │ Invalid value for "path" parameter: no file exists at "***ERROR:
    │ 'aws:cfg-myapp-sonarcloud:taken' secret key not found  (prefix = 'cfg-myapp-') ***"; this function works
    │ only with files that are distributed as part of the configuration source
    │ code, so if this file will be created by a resource in this configuration
    │ you must instead obtain this result from an attribute of that resource.
    ╵
    ERRO[0020] 1 error occurred:
    * exit status 1

Here, the interesting part is 'aws:sonarcloud:taken' secret key not found' as it gives
the names of the secret store, the secret and the non-existing key.

From the message above, we can determine that :

- we are considering secrets stored in AWS Secrets Manager,
- the secret name is 'cfg-myapp-sonarcloud',
- we try to get a key named 'taken' and it does not exist.

<!-- BEGIN_TF_DOCS -->
## Requirements

No requirements.

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | n/a |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [aws_secretsmanager_secret.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/secretsmanager_secret) | data source |
| [aws_secretsmanager_secret_version.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/secretsmanager_secret_version) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_input"></a> [input](#input\_input) | A string to expand (contains secret references) | `string` | n/a | yes |
| <a name="input_prefix"></a> [prefix](#input\_prefix) | A string to add at the beginning of every secret names | `string` | `""` | no |
| <a name="input_stores"></a> [stores](#input\_stores) | A list of secret stores to consider | `list(string)` | <pre>[<br>  "aws"<br>]</pre> | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_result"></a> [result](#output\_result) | The expanded string |
<!-- END_TF_DOCS -->
