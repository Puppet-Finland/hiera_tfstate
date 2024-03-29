Puppet::Functions.create_function(:hiera_tfstate) do
  require 'json'
  require 'yaml'

  dispatch :data_hash do
    param 'Hash', :options
    param 'Puppet::LookupContext', :context
  end

  def data_hash(options, context)
    context.explain { "Backend options: #{options}" }
    validate_options(options)
    validate_backend_options(options)
    raw_state = JSON.parse(load_tfstate(options))

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

  def validate_options(options)
    valid_options = ['backend', 'debug', 'no_root_module', 'region', 'bucket', 'key', 'credentials_file', 'profile', 'statefile']

    options.each do |key, _value|
      unless valid_options.include?(key)
        raise(Puppet::DataBinding::LookupError, "[hiera_tfstate] invalid option #{key}")
      end
    end
  end

  def validate_backend_options(options)
    case options['backend']
    when 'file'
      validate_file_options(options)
    when 's3'
      validate_s3_options(options)
    else
      raise Puppet::DataBinding::LookupError, "[hiera_tfstate] Test Unsupported backend: #{options['backend']}"
    end
  end

  def validate_file_options(options)
    return unless options['statefile']
    raise Puppet::DataBinding::LookupError, '[hiera_tfstate] statefile option missing!'
  end

  def validate_s3_options(options)
    required_options = ['region', 'bucket', 'key']

    required_options.each do |key|
      unless options.include?(key)
        raise "[hiera_tfstate] required option #{key} missing!"
      end
    end
  end

  def load_tfstate(options)
    load_file(options) if options['backend'] == 'file'
    download_from_s3(options) if options['backend'] == 's3'
  end

  def load_file(options)
    begin
      state_content = File.read(options['statefile'])
    rescue Errno::ENOENT
      raise "ERROR: terraform state file #{options['statefile']} not found!"
    end
    state_content
  end

  def download_from_s3(options)
    require 'aws-sdk-s3'

    aws_config = {region: options['region']}

    if options['credentials_file'].nil?
      aws_config[:profile] = options['profile'] unless options['profile'].nil?
    else
      begin
        creds = YAML.safe_load(File.read(options['credentials_file']))

        aws_config[:access_key_id] = creds['access_key_id']
        aws_config[:secret_access_key] = creds['secret_access_key']
      rescue Errno::ENOENT
        raise "ERROR: Can not read AWS credentials file in YAML format!"
      rescue TypeError => e
        raise "ERROR: Can not parse AWS credentials from file: #{e}"
      end
    end

    begin
      s3_client = Aws::S3::Client.new(aws_config)

      resp = s3_client.get_object(bucket: options['bucket'], key: options['key'])
    rescue Errno::ENOENT => e
      raise "ERROR: Can not read from AWS S3!: #{e}"
    end
    resp.body.read
  end

  def validate_terraform_version(raw_state)
    return if raw_state['terraform_version'] >= "0.13"

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
      # - module.somemodule[\"somekey\"]
      #
      mod = if resource['module'].nil?
              ''
            else
              resource['module'].gsub(/\[/,".").gsub(/[^-\.\w]/, "")
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
