#!/opt/puppet/bin/ruby

# Adds the classes that are required to support all agent VM architectures
# to the "PE Master" node group via the REST API.

require 'net/https'
require 'uri'
require 'json'

# Returns an array containing the platform support classes
# that we want to add to the console.
def define_platform_classes
  platform_classes = Array.new

  platform_classes.push('pe_repo::platform::el_5_x86_64')
  platform_classes.push('pe_repo::platform::el_7_x86_64')
  platform_classes.push('pe_repo::platform::ubuntu_1404_amd64')
  platform_classes.push('pe_repo::platform::debian_7_amd64')
  platform_classes.push('pe_repo::platform::sles_11_x86_64')
  platform_classes.push('pe_repo::platform::solaris_10_i386')
  platform_classes.push('pe_repo::platform::solaris_11_i386')

  # Return the array of platform classes
  platform_classes
end

# Function: initialize_rest_api_request
#
# Description: Initializes a request to the puppet server REST API
#              Sets common properties of the request, including:
#                - host
#                - port
#                - ssl cert
#                - ssl key
#                - ssl ca cert
#
#              Returns a Net::HTTP object that is configured with these settings. 
#              This object can be used to consume the NC REST API endpoints.
#
def initialize_rest_api_request
  # Basic information required to define the REST API URL
  puppet_master_fqdn = 'master.inf.puppetlabs.demo'
  nc_rest_api_url = "https://#{puppet_master_fqdn}:4433"

  # We need to authenticate against the REST API using a certificate
  # that is whitelisted in /etc/puppetlabs/console-services/rbac-certificate-whitelist.
  # (https://docs.puppetlabs.com/pe/latest/nc_forming_requests.html#authentication)
  #
  # NOTE: The Net::HTTP class only needs the path to a ca cert file for SSL operations.
  #       However, it requires certificate objects for the client cert and key.
  cert_dir = '/etc/puppetlabs/puppet/ssl'

  # CA certificate file
  ca_cert_file = "#{cert_dir}/certs/ca.pem"

  # Whitelisted cert (use the puppet master's fqdn)
  cert_file = "#{cert_dir}/certs/#{puppet_master_fqdn}.pem"
  cert_contents = File.read(cert_file)
  cert = OpenSSL::X509::Certificate.new(cert_contents)

  # Whitelisted key (use the puppet master's fqdn)
  key_file = "#{cert_dir}/private_keys/#{puppet_master_fqdn}.pem"
  key_contents = File.read(key_file)
  key = OpenSSL::PKey::RSA.new(key_contents)

  # Build the base URI to the REST API
  uri = URI.parse(nc_rest_api_url)

  # Construct the http object with appropriate ssl properties
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true
  http.verify_mode = OpenSSL::SSL::VERIFY_PEER
  http.cert = cert
  http.key = key
  http.ca_file = ca_cert_file

  # return the http object
  http
end

# Function: get_rest_api
#
# Description: Queries a given endpoint of the REST API.
#
# Inputs: endpoint - the portion of the REST API URL that follows '/classifier-api/v1'
#                    NOTE: Not the best name, but I'm having a hard time coming up with anything better.
#         http     - the http object created by initialize_rest_api_request
def get_rest_api(endpoint, http)
  rest_api_endpoint = "/classifier-api/v1/#{endpoint}"

  # Create an HTTP GET request against the specified REST API endpoint.
  request = Net::HTTP::Get.new(rest_api_endpoint)
  # Submit the request
  response = http.request(request)
  # Return the response body (JSON containing the results of the query).
  response.body
end

# Function: post_rest_api
#
# Description: Posts data to a given endpoint of the REST API.
#
# Inputs: endpoint - the portion of the REST API URL that follows '/classifier-api/v1'
#                    NOTE: Not the best name, but I'm having a hard time coming up with anything better.
#         data     - the data to be submitted to the endpoint (in our case, a class to be added to a Node Group)
#                    NOTE: The data should be in JSON format.
#         http     - the http object created by initialize_rest_api_request
def post_rest_api(endpoint, data, http)
  rest_api_endpoint = "/classifier-api/v1/#{endpoint}"

  # Create an HTTP POST request against the specified REST API endpoint
  request = Net::HTTP::Post.new(rest_api_endpoint)
  # Set the Content-Type and data of the HTTP POST request
  request.content_type = "application/json"
  request.body = data
  # Submit the request
  response = http.request(request)
  # Return the response bosy (JSON containing the result of the POST operation)
  response.body
end

# Function name: get_class_from_production_environment
#
# Description: Queries the production environment on the PE Master for the given
#              class. If found, returns a JSON object containing the class definition.
#              If not found, returns an empty JSON object.
#
# Inputs: class_name - the fully qualified name of the class to retrieve (e.g. pe_repo::platform::el_7_x86_64)
#         settings   - the settings hash created in define_settings
#
# NOTE: A more robust way to this would be to return all classes from all environments and search the resulting
#       structure for the class we want. In this case, just searching te production environment is sufficient.
#       We only care that the master is able to manage all of the agent OSes without an seteam tarball.
#
def get_class_from_production_environment(class_name, http)
  rest_api_endpoint = "environments/production/classes/#{class_name}"
  class_json = get_rest_api(rest_api_endpoint, http)

  # Verify that something was returned from the REST API
  if class_json.empty?
    puts "Class #{class_name} not found in production environment."
    exit 1
  end

  # Verify that whatever was returned wasn't "not-found"
  class_hash = JSON.parse(class_json)
  if class_hash['kind'] == 'not-found'
    puts "Class #{class_name} not found in production environment."
    exit 1
  end

  # If we got a valid object, return it
  class_hash
end

# Function: get_node_group_by_name
#
# Description: Queries the REST API for all node groups and extracts the
#              group whose name matches the requested name.
#
# Inputs: node_group_name - the name of the node group to return
#         settings - settings hash created in define_settings
#
# NOTE: Unlike classes, there is no way to look up a single node group by name in PE 3.7.x.
#       Instead, you must use the ID, but since this is randomly generated at the time of
#       installation, we'd have to fetch the ID by searching the entire list of groups for
#       a matching name, anyway. At that point, we may as well just return the whole group.
#
# NOTE: Shamelessly stolen from the PE 3.7 rake API functions
#       and then tweaked to work without some of the Rake API deps
#
def get_node_group_by_name(node_group_name, http)
  # Get all node groups from the REST API
  all_node_groups_json = get_rest_api('groups', http)
  all_node_groups_hash = JSON.parse(all_node_groups_json)

  # Search the list of node groups for the specified group.
  group = {}
  all_node_groups_hash.each do |g|
    if node_group_name.eql? g['name']
      group = g # found group hash in json response
      next
    end
  end

  # If we didn't find the group, something went horribly wrong.
  # Print out a message and exit.
  if group.empty?
    puts "Node group #{group_name} doesn't exist."
    exit 1
  end

  # Return the group if we found it.
  group
end


# Function: add_class_to_group
# Description: Classifies a node group with the specified class
#
# Inputs: node_group_class_hash - a hash of the form {classes => {<class_name> => <parameters_hash>} }
#                                 the class specified by <class_name> will be added to the node group
#         node_group_hash       - a hash containing the definition of a node group as retrieved from
#                                 the REST API
#         http                  - A Net::HTTP object that is configured with the necessary properties
#                                 to consume the Node Classifier REST API
def add_class_to_group(node_group_class_hash, node_group_hash, http)
  # Get the name of the class we are about to add
  class_name = node_group_class_hash['classes'].keys[0]

  # Check whether the node group is already classified with this class.
  if node_group_hash['classes'].has_key?(class_name)
    puts "Node group #{node_group_hash['name']} is already classified with class #{class_name}"
  else
    # Add the class to the node group via the REST API
    endpoint = "groups/#{node_group_hash['id']}"
    post_rest_api(endpoint, node_group_class_hash.to_json, http)
  end
end

# Function: build_node_class_hash
#
# Description: Builds a hash that is suitable for adding a class
#              to a node group from the hash that defines that class
#              in the production environment.
#
def build_node_class_hash(class_hash)
    # First, create a hash with the following structure:
    #
    # - key: The name of the class to be added to the Node Group
    # - value: The parameters to be assigned to the class (generally an empty hash)
    #
    # Example: { 'pe_repo::platform::el_7_x86_64' => {} }
    class_parameters_hash = Hash.new
    class_parameters_hash[class_hash['name']] = class_hash['parameters']

    # Now, create a node that defines a new class association with a node group.
    # This hash will have the following structure:
    #
    # - key: 'classes' (Each node group has a 'classes' key, which contains a has for each class associated with that node group)
    # - value: class_parameters_hash (The hash created above, which defines the class name and parameters to add to the node group)
    #
    # Example: { 'classes' => { 'pe_repo::platform::el_7_x86_64'  => {} } }
    node_class_hash = Hash.new
    node_class_hash['classes'] = class_parameters_hash

    # Return the newly constructed hash
    node_class_hash
end

# Function: add_platform_classes_to_pe_master_group
#
# Description:  This is the wrapper function that calls all of the others.
#               It does all of the setup, defines the classes to add,
#               gets the objects that represent the node group and classes,
#               and invokes the REST API to add the platform support classes
#               to the 'PE Master' group.
#
# NOTE: Start here to trace the operations.
#
def add_platform_classes_to_pe_master_group()
  # Initialization:
  #   1. Create an http object to be used for REST API operations
  #   2. Get the list of platform support classes that we want to add to the PE Master node group
  http = initialize_rest_api_request
  platform_classes = define_platform_classes

  # Get the 'PE Master' node group from the REST API
  node_group_hash = get_node_group_by_name('PE Master', http)

  # Add each platform support class to the 'PE Masters' node group
  platform_classes.each do |platform_class|
    # Ensure that the class that we want to add exists in the production environment.
    class_hash = get_class_from_production_environment(platform_class, http)

    # Convert this hash into one that we can add to a node group.
    node_class_hash = build_node_class_hash(class_hash)

    # Add the platform support class to the PE Master node group.
    puts "Adding #{class_hash['name']} to #{node_group_hash['name']} node group."
    add_class_to_group(node_class_hash, node_group_hash, http)
  end
end

# Execution
add_platform_classes_to_pe_master_group
