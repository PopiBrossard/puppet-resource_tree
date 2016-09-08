Resource Tree Puppet Module [![Build Status](https://travis-ci.org/jake-dog/puppet-resource_tree.svg?branch=master)](https://travis-ci.org/jake-dog/puppet-resource_tree)
===========================
A puppet swiss army knife, bridging the gap between code and configuration, making ad hoc modifications a bit more elegant.

Motivation
==========
Most modern puppet deployments are composed of puppetlabs/r10k, puppetlabs/hiera and an external node classifier.  Although the design is powerful and versioned, it doesn't leave much room for the reality of ad hoc configurations.  Often times puppet users find themselves adding a module, or editing an existing module, just to create a file or add a single package, which leads to an r10k push to every relevant environment.  The addition of a single missing resource can result in several commits, new repositories and a bunch of individual changes to production environments.

Resource Tree aims to drastically reduce the complexity of ad hoc configurations in puppet by providing a simple mechanism to define puppet resources, and relationships between those resources, entirely in hieradata.

Of course Resource Tree's capabilities extend far beyond defining individual resources, enabling users to do terrible blasphemous things to puppet.  Therefore it is highly advisable to keep Resource Tree configurations short and sweet, and avoid writing collections which would be better suited to a module.

Operating Principle
===================
Resource Tree is ideal for building simple collections of puppet resources, both user defined and [built-ins](https://docs.puppetlabs.com/references/latest/type.html), which have logical relationships to each other.

A trivial example of such a resource collection would be an `index.html` running on a standard apache server with a docroot of `/var/www/html`, requiring a total of three `file` resources, assuming that `/var` is a given.  Written briefly:

        File['/var/www']->File['/var/www/html']->File['/var/www/html/index.html']

Where the aformentioned `file` resource objects would be written in puppet code like so:

```ruby
file {
  '/var/www':
    ensure  => 'directory';
    
  '/var/www/html':
    ensure  => 'directory';
    
  '/var/www/html/index.html':
    content => 'hello world!',
    group   => 'apache',
    owner   => 'apache';
}
```

Resource Tree provides a method of building the same collection of `file` resources entirely in yaml, without creating a separate module:

```yaml
resource_tree::collections:
  'httpd_index_file': # collection
    file: # resource type
      '/var/www': # resource name
        ensure: 'directory' # resource parameter
      
      '/var/www/html': # resource name
        ensure: 'directory' # resource parameter
      
      '/var/www/html/index.html': # resource name
        content: 'hello world!' # resource parameter
        group: 'apache' # resource parameter
        owner: 'apache' # resource parameter
```

The collection would only be applied to a node if `resource_tree::apply`, an array, contains the value `httpd_index_file` in the local hiera scope.  This allows the author to have a shared set of Resource Tree collections, but only apply the desired collections to a given node.  For instance:

```yaml
resource_tree::apply:
  - httpd_index_file
```

Each resource in the tree may optionally contain an `rt_resources` parameter, where any included resources implicitly require those closer to the root of the tree.  For instance in the following example an apache configuration file and service implicitly require the httpd package:

```yaml
resource_tree::collections:
  apache:
    package:
      'httpd':
        ensure: 'installed'
        rt_resources:
          service:
            'httpd':
              ensure: 'running'
          file:
            '/etc/httpd/conf.d/status.load':
              ensure: 'present'
              owner: 'apache'
              group: 'apache'
              content: 'LoadModule status_module "modules/mod_status.so"'
              rt_notify:
                service: 'httpd'
```

Relationships between resources in the tree can also be explicitly stated using the `rt_requires` parameter, with the caveat that required resources must be declared in a Resource Tree collection.  For instance the previous example could be rewritten with explicit relationships:

```yaml
resource_tree::collections:
  apache:
    package:
      'httpd':
        ensure: 'installed'
    service:
      'httpd:
        ensure: 'running'
        rt_requires:
          - 'package-httpd'
    file:
      '/etc/httpd/conf.d/status.load':
        ensure: 'present'
        owner: 'apache'
        group: 'apache'
        content: 'LoadModule status_module "modules/mod_status.so"'
        rt_requires:
          - 'package-httpd'
        rt_notify:
          service: 'httpd'
```

Resource tree contains three special parameters for each resource:
        
+ `rt_resources` - declare additional resources which require the current resource
+ `rt_requires` - explicitly require a resource_tree resource which is not parent to the current resource
+ `rt_notify` - notify a service, mount or exec declared in the catalog when current resource changes

Advanced Usage
==============
Resource Tree provides a number of advanced features so collections can be built dynamically.  Any individual resource definition, resource collection, or collection of child resources which is a string will be evaluated as ruby code, eg.

```yaml
resource_tree::collections:
  'resource_tree_advanced_examples':
    file:
      '/tmp/thetime.txt': |
        
        # Create a file containing just the time
        { 'content' => Time.now.to_s }
      
      '/tmp/test':
        ensure: 'directory'
        rt_resources: |
        
          # Create five files in /tmp/test
          { 'file' => 
            Hash[(1..5).map {|n|
              [
                "/tmp/test/test-file-#{n}",
                { "content" => rand(500).to_s }
              ]
            }]
          }
          
    host: |
      
      # Add five host entries
      Hash[(1..5).map {|n|
        [
          "test-node-0#{n}",
          {"ip" => "192.168.1.#{n}", "ensure" => "present" }
        ]
      }]
```

Additionally individual resource parameters can be evaluated by prefixing them with `rt_eval::`, and parsed as yaml by prefixing the paramater name with `rt_parse::`.

Crazy Advanced Usage
====================
A few intrepid users have discovered interesting ways to combine Resource Tree and ruby to dynamically create resources, including querying puppetdb to find members for proxies/load-balancers.  Here are a few tricks that tip the scales for what Resource Tree can do.

#### Emulating `hiera_include('classes')`

```yaml
resource_tree::collections:
  hiera_include:
    class: |
      Hash[(scope.function_hiera_array(['classes']) - ['resource_tree']).map {|c| [c, {}] }]
```

#### Using PuppetDB to discover puppetlabs/puppetlabs-haproxy balancer members

```yaml
resource_tree::collections:
  haproxy_webservers:
    haproxy::balancermember: |
      member_ip_by_cert = scope.function_query_facts(["environment='%{environment}' and app='webserver'", [:ipaddress]])
      {
        "webservers" => {
          "listening_service" => 'webservers',
          "ports"             => '80',
          "server_names"      => member_ip_by_cert.map{|k,v| k.split(".")[0] },
          "ipaddresses"       => member_ip_by_cert.map{|k,v| v["ipaddress"] },
          "options"           => [ 'check' ]
        }
      }
```

#### Creating multiple files with templates

```yaml
config_file_template: |
  <% config = scope.function_hiera(['configs', {}]).fetch(@name[5..-1], {}) -%>
  foo=<%= config["foo"] %>
  biz=<%= config["biz"] %>

configs:
  '/etc/example/default.properties':
    foo: 'boz'
    biz: 'bar'
  '/etc/example/example.properties':
    foo: 'bar'
    biz: 'boz'

resource_tree::collections:
  apply_configs:
    file: |
      Hash[scope.function_hiera(['configs']).map {|k,v|
        [
          "#{k}",
          {
            'ensure'  => 'present',
            'owner'   => 'root',
            'group'   => 'root',
            'content' => 'rt_eval::scope.function_inline_template([scope.function_hiera(["config_file_template"])])'
          }
        ]
      }]
```
