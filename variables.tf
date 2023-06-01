
# Default: activate every supported stores

variable stores {
  description = "A list of secret stores to consider"
  type = list(string)
  default = [
    "aws"
  ]
}

variable prefix {
  description = "A string to add at the beginning of every secret names"
  type = string
  default = ""
}

variable input {
  description = "A string to expand (contains secret references)"
  type = string
}
