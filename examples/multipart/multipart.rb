#!/usr/bin/env ruby
# Run with: bundle exec ruby multipart/multipart.rb

require 'celluloid/current'
require 'rubygems'
require 'bundler/setup'
require 'reel'
require 'reel/request/multipart'
require 'pry'

$CELLULOID_DEBUG = true
Celluloid.logger.level = ::Logger::DEBUG

FORM = File.expand_path '../form.html', __FILE__

puts "*** Starting server on http://127.0.0.1:4567"
Reel::Server::HTTP.new('127.0.0.1', 4567) do |connection|
  connection.each_request do |request|
    p request.multipart if request.multipart?
    request.respond :ok, File.read(FORM)
  end
end

sleep
