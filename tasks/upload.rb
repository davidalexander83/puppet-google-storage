#!/opt/puppetlabs/puppet/bin/ruby
# Copyright 2018 Google Inc.
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Uploads a local file to Google Cloud Storage
#
# Command line arguments: JSON object from STDIN with the following fields:
#
# - name: The name of the remote file to upload
# - type:
#     The type of the remote file (in MIME notation)
#     (default: 'application/octet-stream')
# - source: The path to a local file to upload
# - bucket: The target bucket to write the file to
# - project: The project that owns the bucket
# - credential: Path to a service account credentials file

STORAGE_ADM_SCOPES = [
  'https://www.googleapis.com/auth/devstorage.full_control'
].freeze

require 'puppet'

# We want to re-use code already written for the GCP modules
Puppet.initialize_settings

# Puppet apply does special stuff to load library code stored in modules
# but that magic is available in Bolt so we emulate it here.  We look in
# the local user's .puppetlabs directory or if running at "root" we look
# in the directory where Puppet pluginsyncs to.
libdir = if Puppet.run_mode.user?
           Dir["#{Puppet.settings[:codedir]}/modules/*/lib"]
         else
           File.path("#{Puppet.settings[:vardir]}/lib").to_a
         end
libdir << File.expand_path("#{File.dirname(__FILE__)}/../lib")
libdir.each { |l| $LOAD_PATH.unshift(l) unless $LOAD_PATH.include?(l) }

require 'google/auth/gauth_credential'
require 'google/storage/api/gstorage_object'

# Validates user input
def validate(params, arg_id, default = nil)
  arg = arg_id.id2name
  raise "Missing parameter '#{arg}' from stdin" \
    if default.nil? && !params.key?(arg)
  params.key?(arg) ? params[arg] : default
end

# Parses and validates user input
params = {}
begin
  Timeout.timeout(3) do
    params = JSON.parse(STDIN.read)
  end
rescue Timeout::Error
  puts({ status: 'failure', error: 'Cannot read JSON from stdin' }.to_json)
  exit 1
end

name = validate(params, :name)
type = validate(params, :type, 'application/octet-stream')
source = validate(params, :source)
bucket = validate(params, :bucket)
project = validate(params, :project)
credential = validate(params, :credential)

cred = Google::Auth::GAuthCredential \
       .serviceaccount_for_function(credential, STORAGE_ADM_SCOPES)
object = Google::Storage::Api::Object.new(name, bucket, project, cred)

begin
  object.upload(source, type)
  puts({ status: 'success' }.to_json)
  exit 0
rescue Puppet::Error => e
  puts({ status: 'failure', error: e }.to_json)
  exit 1
end
