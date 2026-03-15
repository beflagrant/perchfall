# frozen_string_literal: true

require "spec_helper"

RSpec.describe Perchfall::UrlValidator do
  subject(:validator) { described_class.new }

  describe "#validate!" do
    context "permitted schemes" do
      it "accepts http URLs" do
        expect { validator.validate!("http://example.com") }.not_to raise_error
      end

      it "accepts https URLs" do
        expect { validator.validate!("https://example.com/path?q=1") }.not_to raise_error
      end
    end

    context "forbidden schemes" do
      it "rejects file:// (local filesystem read)" do
        expect { validator.validate!("file:///etc/passwd") }
          .to raise_error(ArgumentError, /file/)
      end

      it "rejects ftp://" do
        expect { validator.validate!("ftp://example.com") }
          .to raise_error(ArgumentError, /ftp/)
      end

      it "rejects javascript:" do
        expect { validator.validate!("javascript:alert(1)") }
          .to raise_error(ArgumentError, /javascript/)
      end

      it "rejects data: URIs" do
        expect { validator.validate!("data:text/html,<h1>hi</h1>") }
          .to raise_error(ArgumentError, /data/)
      end

      it "rejects bare strings with no scheme" do
        expect { validator.validate!("example.com") }
          .to raise_error(ArgumentError)
      end
    end

    context "invalid URLs" do
      it "rejects strings that are not parseable URIs" do
        expect { validator.validate!("not a url at all \x00") }
          .to raise_error(ArgumentError, /Invalid URL/)
      end

      it "rejects empty string" do
        expect { validator.validate!("") }
          .to raise_error(ArgumentError)
      end
    end

    context "private/internal hostnames (A1 — literal address blocking)" do
      # These are blocked on the hostname string alone, without DNS resolution.
      # A public DNS name that resolves to a private IP is NOT blocked here;
      # that requires network-level egress filtering.

      it "rejects localhost" do
        expect { validator.validate!("http://localhost") }
          .to raise_error(ArgumentError, /internal/)
      end

      it "rejects 127.0.0.1 (IPv4 loopback)" do
        expect { validator.validate!("http://127.0.0.1") }
          .to raise_error(ArgumentError, /internal/)
      end

      it "rejects 127.x.x.x (full loopback range)" do
        expect { validator.validate!("http://127.0.0.2") }
          .to raise_error(ArgumentError, /internal/)
      end

      it "rejects ::1 (IPv6 loopback)" do
        expect { validator.validate!("http://[::1]") }
          .to raise_error(ArgumentError, /internal/)
      end

      it "rejects 169.254.169.254 (AWS instance metadata)" do
        expect { validator.validate!("http://169.254.169.254/latest/meta-data/") }
          .to raise_error(ArgumentError, /internal/)
      end

      it "rejects 169.254.x.x (full link-local range)" do
        expect { validator.validate!("http://169.254.0.1") }
          .to raise_error(ArgumentError, /internal/)
      end

      it "rejects 10.x.x.x (RFC-1918)" do
        expect { validator.validate!("http://10.0.0.1") }
          .to raise_error(ArgumentError, /internal/)
      end

      it "rejects 172.16.x.x (RFC-1918)" do
        expect { validator.validate!("http://172.16.0.1") }
          .to raise_error(ArgumentError, /internal/)
      end

      it "rejects 172.31.x.x (RFC-1918 upper bound)" do
        expect { validator.validate!("http://172.31.255.255") }
          .to raise_error(ArgumentError, /internal/)
      end

      it "accepts 172.15.x.x (just outside RFC-1918 range)" do
        expect { validator.validate!("http://172.15.0.1") }.not_to raise_error
      end

      it "accepts 172.32.x.x (just outside RFC-1918 range)" do
        expect { validator.validate!("http://172.32.0.1") }.not_to raise_error
      end

      it "rejects 192.168.x.x (RFC-1918)" do
        expect { validator.validate!("http://192.168.1.1") }
          .to raise_error(ArgumentError, /internal/)
      end

      it "rejects 0.0.0.0" do
        expect { validator.validate!("http://0.0.0.0") }
          .to raise_error(ArgumentError, /internal/)
      end
    end

    context "error message" do
      it "names the rejected scheme" do
        expect { validator.validate!("file:///etc/passwd") }
          .to raise_error(ArgumentError, /"file"/)
      end

      it "names the permitted schemes" do
        expect { validator.validate!("ftp://example.com") }
          .to raise_error(ArgumentError, /http, https/)
      end
    end
  end
end
