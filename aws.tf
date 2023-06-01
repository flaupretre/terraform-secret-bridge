# Retrieves secrets from AWS secrets manager

data aws_secretsmanager_secret this {
  for_each = (local.aws_is_up ? { for name in local.names.aws : name => null } : {})

  name = each.key
}

#----

data aws_secretsmanager_secret_version this {
  for_each = (local.aws_is_up ? { for name in local.names.aws : name => null } : {})

  secret_id = data.aws_secretsmanager_secret.this[each.key].id
}

#----

locals {

  aws_is_up = contains(var.stores, "aws")

  aws_map = (local.aws_is_up ? {
    for nk, secret in local.name_key_map.aws : "aws:${nk}" =>
      (secret.has_key ?
        lookup(jsondecode(data.aws_secretsmanager_secret_version.this[secret.name].secret_string)
          , secret.key, null)
        : data.aws_secretsmanager_secret_version.this[secret.name].secret_string)
  } : {})
}
