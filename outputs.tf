
output result {
  description = "The expanded string"
  value = local.result
  sensitive = true
}

# For sebugging only

output words {
  value = local.words
  sensitive = true
}

output ewords {
  value = local.ewords
  sensitive = true
}

output secret_map {
  value = local.secret_map
  sensitive = true
}
