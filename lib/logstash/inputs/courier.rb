# encoding: utf-8

# Copyright 2014 Jason Woods.
#
# This file is a modification of code from Logstash Forwarder.
# Copyright 2012-2013 Jordan Sissel and contributors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

module LogStash
  module Inputs
    # Receive events over the Log Courier protocol
    class Courier < LogStash::Inputs::Base
      config_name 'courier'
      milestone 1

      default :codec, 'plain'

      # The IP address to listen on
      config :host, :validate => :string, :default => '0.0.0.0'

      # The port to listen on
      config :port, :validate => :number, :required => true

      # The transport type to use
      config :transport, :validate => :string, :default => 'tls'

      # SSL certificate to use
      config :ssl_certificate, :validate => :path

      # SSL key to use
      config :ssl_key, :validate => :path

      # SSL key passphrase to use
      config :ssl_key_passphrase, :validate => :password

      # Whether or not to verify client certificates
      config :ssl_verify, :validate => :boolean, :default => false

      # When verifying client certificates, also trust those signed by the system's default CA bundle
      config :ssl_verify_default_ca, :validate => :boolean, :default => false

      # CA certificate to use when verifying client certificates
      config :ssl_verify_ca, :validate => :path

      # Curve secret key
      config :curve_secret_key, :validate => :string

      # Max packet size
      config :max_packet_size, :validate => :number

      # The size of the internal queue for each peer
      #
      # Sent payloads will be dropped when the queue is full
      #
      # This setting should max the max_pending_payloads Log Courier
      # configuration
      config :peer_recv_queue, :validate => :number

      # Add additional fields to events that identity the peer
      #
      # This setting is only effective with the tcp and tls transports
      #
      # "peer" identifies the source host and port
      # "peer_ssl_cn" contains the client certificate hostname for TLS peers
      # using client certificates
      config :add_peer_fields, :validate => :boolean

      def register
        @logger.info('Starting courier input listener', :address => "#{@host}:#{@port}")

        options = {
          logger:                @logger,
          address:               @host,
          port:                  @port,
          transport:             @transport,
          ssl_certificate:       @ssl_certificate,
          ssl_key:               @ssl_key,
          ssl_key_passphrase:    @ssl_key_passphrase,
          ssl_verify:            @ssl_verify,
          ssl_verify_default_ca: @ssl_verify_default_ca,
          ssl_verify_ca:         @ssl_verify_ca,
          curve_secret_key:      @curve_secret_key,
          stream_factory:        CourierStreamFactory.new(@codec, output_queue)
        }

        # Honour the defaults in the LogCourier gem
        options[:max_packet_size] = @max_packet_size unless @max_packet_size.nil?
        options[:peer_recv_queue] = @peer_recv_queue unless @peer_recv_queue.nil?
        options[:add_peer_fields] = @add_peer_fields unless @add_peer_fields.nil?

        require 'log-courier/server'
        @log_courier = LogCourier::Server.new options
      end

      def run(output_queue)
        @log_courier.run do |event|
          # TODO: Implement codec flush somehow
          output_queue << event
        end
      end
    end

    class CourierStreamFactory < LogCourier::StreamFactory
      def initialize(codec_obj)
        super
        @codec_obj = codec_obj
      end

      def create_stream()
        CourierStream.new @codec_obj.clone
      end
    end

    class CourierStream < LogCourier::Stream
      def initialize(codec)
        super
        @codec = codec
      end

      def decode(event)
        if event.key?('message')
          message = event['message']
          event.delete! 'message'
        else
          message = ''
        end

        @codec.decode(message) do |decoded|
          decoded.append event
          decorate decoded
          yield decoded
        end
      end
    end
  end
end
