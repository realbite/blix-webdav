# Blix/Rest WebDAV Server protocol implementation.

## Installation

in order to better identify mime types the `mimetype` is used:

    apt install libfile-mimeinfo-perl

    gem install blix-webdav

    require 'blix/webdav'

## Usage in Application

This gem is for use within a `Blix/Rest`  application only.

include the `Routes` Module in your controller in order to implement
the webdav protocol.


for example you could put the following in a `config.ru` file

    require 'blix/rest'
    require 'blix/webdav'

    class MyController < Blix::Rest::Controller

       include Blix::WebDAV::Routes

       before_route do |route|
         # any custom route pre-processing here... before call to webdav_routes!
       end

       # define routes

       webdav_routes :prefix=>'share',       # extra route prefix
                     :xxx=>:yyy,             # custom option
                     :root=>'/tmp/myfiles'   # resource location on filesystem

       before do
         # eg check authorisation ...
         login,password = get_basic_auth
         auth_error( "invalid" ) unless password == 'secret'
         
         webdav_params :user=>login          # pass any custom parameters here!

         # ...
       end

    end

    run Blix::Rest::Server.new

to run this example then enter at the command line :

    gem install blix-webdav
    gem install puma

    mkdir /tmp/myfiles

    echo "supported_http_methods :any" > puma.rb

    puma -p3000 -Cpuma.rb


now using this example you should be serving files from : `http://localhost:3000/share`


the available webdav options are:

    webdav_route options:

        :root               # the root on the filesystem where FileResource files are stored
        :verbose            # true/false  extended logging
        :resource_class     # a custom class to use instead of FileResource
        :prefix             # add an extra prefix to the route url

within the before hook in the controller you can add parameters to pass on to
ant custom Resource class

    webdav_params  :aaa=>:bbb


## Note on Puma

the latest version of puma does not accept all the HTTP verbs that WebDAV requires by default.
A config file directive is needed to override this:

    supported_http_methods :any
