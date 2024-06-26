class resource_tree (
  Optional[Hash] $collections    = {},
  Optional[Array[String]] $apply = [],
  Optional[Hash] $default_params = {},
) {
  $allcollections = lookup('resource_tree::collections', { 'value_type' => Hash, 'merge' => 'deep', 'default_value' => $collections })
  $allapply = lookup('resource_tree::apply', { 'value_type' => Array[String], 'merge' => 'unique', 'default_value' => $apply })
  $defaults = lookup('resource_tree::default_params', { 'value_type' => Hash, 'merge' => 'deep', 'default_value' => $default_params })

  if size(intersection($allapply, keys($allcollections))) > 0 {
      $uniq_resources = parseyaml(template('resource_tree/main.erb'))
      create_resources('resource_tree::resource', $uniq_resources, {})
  }
}
