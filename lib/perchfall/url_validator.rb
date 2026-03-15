# frozen_string_literal: true

require "uri"
require "ipaddr"

module Perchfall
  # Validates that a URL is safe to pass to Playwright.
  #
  # Two checks are applied in order:
  #   1. Scheme must be http or https.
  #   2. Hostname must not be a known-internal literal address.
  #
  # LIMITATION: a public DNS name that resolves to a private IP is NOT blocked.
  # Blocking post-resolution addresses requires network-level egress filtering
  # (security groups, firewall rules) and cannot be done safely here without
  # introducing a TOCTOU race between validation and Playwright's own DNS lookup.
  class UrlValidator
    PERMITTED_SCHEMES = %w[http https].freeze

    # Blocked as exact hostname strings (case-insensitive).
    BLOCKED_HOSTNAMES = %w[localhost].freeze

    # Blocked IP ranges. Any literal IPv4 or IPv6 address falling within these
    # ranges is rejected. Order does not matter; all are checked.
    BLOCKED_RANGES = [
      IPAddr.new("127.0.0.0/8"),       # IPv4 loopback
      IPAddr.new("::1"),               # IPv6 loopback
      IPAddr.new("169.254.0.0/16"),    # IPv4 link-local (incl. AWS metadata 169.254.169.254)
      IPAddr.new("fe80::/10"),         # IPv6 link-local
      IPAddr.new("10.0.0.0/8"),        # RFC-1918
      IPAddr.new("172.16.0.0/12"),     # RFC-1918
      IPAddr.new("192.168.0.0/16"),    # RFC-1918
      IPAddr.new("0.0.0.0/8"),         # unroutable
    ].freeze

    def validate!(url)
      uri = parse!(url)
      assert_permitted_scheme!(uri, url)
      assert_not_internal_host!(uri, url)
    end

    private

    def parse!(url)
      URI.parse(url)
    rescue URI::InvalidURIError
      raise ArgumentError, "Invalid URL: #{url.inspect}"
    end

    def assert_permitted_scheme!(uri, url)
      return if PERMITTED_SCHEMES.include?(uri.scheme)

      raise ArgumentError,
            "URL scheme #{uri.scheme.inspect} is not permitted. " \
            "Only #{PERMITTED_SCHEMES.join(", ")} URLs are accepted. Got: #{url.inspect}"
    end

    def assert_not_internal_host!(uri, url)
      host = uri.hostname.to_s.downcase

      if BLOCKED_HOSTNAMES.include?(host)
        raise ArgumentError, internal_error(url)
      end

      addr = parse_ip(host)
      if addr && blocked_ip?(addr)
        raise ArgumentError, internal_error(url)
      end
    end

    def parse_ip(host)
      IPAddr.new(host)
    rescue IPAddr::InvalidAddressError
      nil
    end

    def blocked_ip?(addr)
      BLOCKED_RANGES.any? { |range| range.include?(addr) }
    end

    def internal_error(url)
      "URL resolves to an internal or reserved address and is not permitted. Got: #{url.inspect}"
    end
  end
end
