define resource_tree::resource (
    $type,
    $params,
    $rt_resources   = undef,
) {
  include stdlib

  if $rt_resources {
      $uniq_resources = parseyaml(template('resource_tree/resource.erb'))
      create_resources('resource_tree::resource', $uniq_resources)
  }

  # Allow arbitrary commands and nested yaml
  $parsed_params = parseyaml(template('resource_tree/param_parse.erb'))

  create_resources($type, $parsed_params)
}
