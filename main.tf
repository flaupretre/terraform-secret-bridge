# Format is : //@secret/<store>:<name>[:<key>]//
#

locals {

  name_key = { for store in var.stores :
    store => distinct(flatten(regexall("//@secret/${store}:([^ ]+)//", var.input)))
  }

  name_key_map = { for store in var.stores :
    store => {
      for nk in local.name_key[store] : nk => {
        name = "${var.prefix}${element(split(":", nk), 0)}"
        has_key = (length(split(":", nk)) > 1)
        key = (length(split(":", nk)) > 1) ? element(split(":", nk), 1) : null
      }
    }
  }

  names = {
    for store in var.stores :
      store => distinct([
        for item in local.name_key_map[store] : item.name
    ])
  }

  merged_maps = merge(
    local.aws_map,
    # When implemented, additional stores will come here
  )

  secret_map = { for k,v in local.merged_maps :
    ">//@secret/${k}//" => ((v == null) ? "" : ">\"${v}\"") }

  # This throws an error on secret key not existing

  errors = [
    for k,v in local.merged_maps : (v == null) ?
      file("***ERROR: '${k}' secret key not found (prefix = '${var.prefix}') ***") : null
  ]

  words = split(" ", replace(replace(">${var.input}", " ", " >"), "\n", " \n >"))

  ewords = [ for word in local.words : lookup(local.secret_map, word, word) ]

  result = substr(replace(replace(join(" ", local.ewords), " \n >", "\n"), " >", " "), 1, 100000)

}
