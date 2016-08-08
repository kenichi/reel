#!/usr/bin/env ruby
# Run with: bundle exec ruby multipart/multipart.rb

require 'celluloid/current'
require 'rubygems'
require 'bundler/setup'
require 'reel'
require 'reel/spy'
require 'reel/request/multipart'
require 'pry'

$CELLULOID_DEBUG = true
Celluloid.logger.level = ::Logger::DEBUG

FORM = File.expand_path '../form.html', __FILE__

puts "*** Starting server on http://127.0.0.1:4567"
Reel::Server::HTTP.new('127.0.0.1', 4567, spy: true) do |connection|
  connection.each_request do |request|
    case request.method
    when :get
      request.respond :ok, File.read(FORM)
    when :post
      if request.multipart? req.body
        request.respond :ok, "recieved: #{request.multipart.inspect}"
      else
        request.respond 400, "no file received :("
      end
    end
  end
end

sleep
