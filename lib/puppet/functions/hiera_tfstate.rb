Puppet::Functions.create_function(:hiera_tfstate) do
  require 'json'
  require 'yaml'

  dispatch :data_hash do
    param 'Hash', :options
    param 'Puppet::LookupContext', :context
  end

  def data_hash(options, context)
    context.explain { "Backend options: #{options}" }
    raw_state = load_tfstate(options)
    raw_state = JSON.parse(raw_state)

    # Ensure that the state file belongs to a known good Terraform version
    validate_terraform_version(raw_state)

    # Ensure that root module can be removed from the resource paths without
    # causing unexpected behavior. Essentially require that all resources must
    # be defined inside a module when that option is enabled.
    validate_resource_paths(raw_state, options)

    # Convert the resources in the state into a format that can actually be
    # digested by Hiera lookups. The main problem with raw state files is
    # that all the resources are inside an array, so one would have to use
    # potentially volative indices to refer to the resources and their
    # attributes.
    state = convert_state(raw_state, options, context)
    state
  end

  def load_tfstate(options)
    if options['backend'] == 'file'
      load_file(options)
    elsif options['backend'] == 's3'
      download_from_s3(options)
    else
      raise Puppet::DataBinding::LookupError, "[hiera_tfstate] Unsupported backend: #{options['backend']}"
    end
  end

  def load_file(options)
    begin
      state_content = File.read(options['statefile'])
    rescue Errno::ENOENT
      raise Puppet::DataBinding::LookupError "ERROR: terraform state file #{options['statefile']} not found!"
    end
    state_content
  end

  def download_from_s3(options)
    require 'aws-sdk-s3'
    s3_client = Aws::S3::Client.new(profile: options['profile'])
    resp = s3_client.get_object(bucket: options['bucket'], key: options['key'])
    resp.body.read
  end

  def validate_terraform_version(raw_state)
    return if raw_state['terraform_version'] =~ %r{0\.13\.\d+}

    raise 'ERROR: this Hiera backend supports only Terraform 0.13.x state files.'
  end

  def validate_resource_paths(raw_state, options)
    return unless options['no_root_module']

    raw_state['resources'].each do |resource|
      unless resource['module']
        raise "Error: remove_root_module_from_path works only if all resources are in a module!')"
      end
    end
  end

  def get_module_path(mod, options)
    if options['no_root_module']
      mod.split('.').drop(2)
    else
      mod.split('.')
    end
  end

  def convert_state(raw_state, options, context)
    resources = {}
    raw_state['resources'].each do |resource|
      # Construct a Hiera-style path to the Terraform resource
      # and its attributes
      resource_path = []

      # Examples of contents of resource['module']:
      #
      # - nil (resource defined in the root module)
      # - module.somemodule
      # - module.somemodule.module.nestedmodule
      #
      mod = if resource['module'].nil?
              ''
            else
              resource['module']
            end

      module_path = get_module_path(mod, options)

      resource_path.append('tfstate')
      resource_path.append(module_path) unless module_path.empty?
      resource_path.append(resource['type'])
      resource_path.append(resource['name'])

      resource['instances'].each do |instance|
        resource_path.append(instance['index_key']) if instance['index_key']

        instance['attributes'].each do |attribute|
          resource_path.push(attribute[0])
          flattened = resource_path.flatten.join('::')
          resources[flattened] = attribute[1]
          resource_path.pop
        end
      end
    end

    context.explain { YAML.dump(resources) } if options['debug']
    resources
  end
end
