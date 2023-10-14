# frozen_string_literal: true

require 'digest'
require 'ffi-xattr'

module Blix::WebDAV
  class FileResource < Resource

    # If this is a collection, return the child resources.
    # should this show hidden files
    def children
      Dir[file_path + '/*'].map do |path|
        child File.basename(path)
      end
    end

    # Is this resource a collection?
    def collection?
      File.directory?(file_path)
    end

    # Does this recource exist?
    def exist?
      File.exist?(file_path)
    end

    # Return the creation time.
    def creation_date
      stat.ctime
    end

    # Return the time of last modification.
    def last_modified
      stat.mtime
    end

    # Set the time of last modification.
    def last_modified=(time)
      File.utime(Time.now, time, file_path)
    end

    # Return an Etag, an unique hash value for this resource.
    def etag
      format('%x-%x-%x', stat.ino, stat.size, stat.mtime.to_i)
    end

    # Return the resource type.
    #
    # If this is a collection, return a collection element
    def resource_type
      if collection?
        Nokogiri::XML.fragment('<D:collection xmlns:D="DAV:"/>').children.first
      end
    end

    # Return the mime type of this resource.
    def content_type
      if stat.directory?
        'text/plain'
      else
        response = `mimetype -b "#{file_path}"`
        #response_array = response.split(';')
        #mime = response_array[0].to_s.strip
        mime = response.chomp.strip
        mime = 'text/plain' if mime == 'inode/x-empty'
        # mime_type(file_path, DefaultMimeTypes)
        mime
      end
    end

    # Return the size in bytes for this resource.
    def content_length
      stat.size
    end

    def set_custom_property(name, value)
      if value.nil? || value.empty?
        begin
          xattr.remove("rack-webdav:#{name}")
        rescue Errno::ENOATTR
          # If the attribute being deleted doesn't exist, just do nothing
        end
      else
        xattr["rack-webdav:#{name}"] = value
      end
    end

    def get_custom_property(name)
      value = xattr["rack-webdav:#{name}"]
      raise HTTPStatus::NotFound if value.nil?

      value
    end

    def list_custom_properties
      xattr.list.select { |a| a.start_with?('rack-webdav') }.map { |a| a.sub(/^rack-webdav:/, '') }
    end

    # HTTP GET request.
    #
    # Write the content of the resource to the response.body.
    def get
      if stat.directory?
        content = String.new
        Dir.new(file_path).each do |line|
          next if line[0] == '.' # no hidden files here please.
          #next if (line == '.') || (line == '..')
          content << line << "\n"
        end
        content
      else
        File.open(file_path)
      end
    end

    # HTTP PUT request.
    #
    # Save the content of the request.body.
    def put
      if @request.env['HTTP_CONTENT_MD5']
        content_md5_pass?(@request.env) || raise(HTTPStatus::BadRequest, 'Content-MD5 mismatch')
      end

      raise HTTPStatus::Continue if content_continue_pass?(@request.env)

      write(@request.body)
    end

    # HTTP POST request.
    #
    # Usually forbidden.
    def post
      raise HTTPStatus::Forbidden
    end

    # HTTP DELETE request.
    #
    # Delete this resource.
    def delete
      if stat.directory?
        # there could be some hidden files lurking in the directory so ensure
        # that the directory is empty first.
        Dir.new(file_path).each do |line|
          next if (line == '.') || (line == '..')
          File.unlink(File.join(file_path,line)) if line[0]=='.'
        end
        Dir.rmdir(file_path)
      else
        File.unlink(file_path)
      end
    end

    # HTTP COPY request.
    #
    # Copy this resource to given destination resource.
    def copy(dest)
      if stat.directory?
        dest.make_collection
      else
        open(file_path, 'rb') do |file|
          dest.write(file)
        end

        list_custom_properties.each do |prop|
          dest.set_custom_property(prop, get_custom_property(prop))
        end
      end
    end

    # HTTP MOVE request.
    #
    # Move this resource to given destination resource.
    def move(dest)
      copy(dest)
      delete
    end

    # HTTP MKCOL request.
    #
    # Create this resource as collection.
    def make_collection
      Dir.mkdir(file_path)
    end

    # Write to this resource from given IO.
    def write(io)
      tempfile = "#{file_path}.#{Process.pid}.#{object_id}"

      open(tempfile, 'wb') do |file|
        while part = io.read(8192)
          file << part
        end
      end

      File.rename(tempfile, file_path)
    ensure
      begin
        File.unlink(tempfile)
      rescue StandardError
        nil
      end
    end

    @@locks = {}

    def lock(token, timeout, scope = nil, type = nil, owner = nil)
      if scope && type
        # Create lock
        @@locks[token] = {
          :timeout => timeout,
          :scope => scope,
          :type => type,
          :owner => owner,
          :path => path
        }
        true
      else
        # Refresh lock
        lock = @@locks[token]
        return false unless lock

        [lock[:timeout], lock[:scope], lock[:type], lock[:owner]]
      end
    end

    def unlock(token)
      !!@@locks.delete(token)
    end

    def locked?(token, _etag = nil)
      if token.nil?
        # check parent directory match
        already_locks = @@locks.select do |_lock_token, lock|
          found = false
          Pathname.new(path).ascend do |v|
            found = lock[:path].gsub(%r{/$}, '') == v.to_s
            break if found
          end
          lock if found
        end
        !already_locks.empty?
      else
        lock_paths = @@locks.select { |_lock_token, lock| lock[:path] == path }
        exist? && @@locks.key?(token) == false && !lock_paths.empty?
      end
    end

    def other_owner_locked?(token, owner)
      return false if token.nil?
      return false if @@locks.key?(token) && owner.nil?

      other_owner = @@locks.select do |_lock_token, lock|
        lock[:path] == path
      end.select do |_lock_token, lock|
        !lock[:owner].nil? && lock[:owner] != owner
      end
      !other_owner.empty?
    end

    def locks
      @@locks
    end

    # private

    def root
      @options[:root] || raise('you need to define webdav_options :root !!')
    end

    def file_path
      File.join(root, path)
    end

    def stat
      @stat ||= File.stat(file_path)
    end

    def xattr
      @xattr ||= Xattr.new(file_path)
    end

    def content_md5_pass?(env)
      (expected = env['HTTP_CONTENT_MD5']) || (return true)

      body   = env['rack.input'].dup
      digest = Digest::MD5.new.digest(body.read)
      actual = [digest].pack('m').strip

      body.rewind

      expected == actual
    end

    def content_continue_pass?(env)
      (expected = env['HTTP_EXPECT']) || (return false)

      expected.downcase == '100-continue'
    end

  end
end
